//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

/// Implementation of `SecureValueRecovery` that talks to the SVR2 server.
public class SecureValueRecovery2Impl: SecureValueRecovery {

    private let appContext: SVR2.Shims.AppContext
    private let appReadiness: AppReadiness
    private let appVersion: AppVersion
    private let pinHasher: any SVR2PinHasher
    private let connectionFactory: SgxWebsocketConnectionFactory
    private let credentialStorage: SVRAuthCredentialStorage
    private let db: any DB
    private let accountKeyStore: AccountKeyStore
    private let localStorage: SVRLocalStorage
    private let storageServiceManager: StorageServiceManager
    private let tsAccountManager: TSAccountManager
    private let tsConstants: TSConstantsProtocol
    private let twoFAManager: SVR2.Shims.OWS2FAManager

    init(
        appContext: SVR2.Shims.AppContext,
        appReadiness: AppReadiness,
        appVersion: AppVersion,
        connectionFactory: SgxWebsocketConnectionFactory,
        credentialStorage: SVRAuthCredentialStorage,
        db: any DB,
        accountKeyStore: AccountKeyStore,
        pinHasher: any SVR2PinHasher,
        storageServiceManager: StorageServiceManager,
        svrLocalStorage: SVRLocalStorage,
        tsAccountManager: TSAccountManager,
        tsConstants: TSConstantsProtocol,
        twoFAManager: SVR2.Shims.OWS2FAManager,
    ) {
        self.appContext = appContext
        self.appReadiness = appReadiness
        self.appVersion = appVersion
        self.connectionFactory = connectionFactory
        self.credentialStorage = credentialStorage
        self.db = db
        self.accountKeyStore = accountKeyStore
        self.localStorage = svrLocalStorage
        self.pinHasher = pinHasher
        self.storageServiceManager = storageServiceManager
        self.tsAccountManager = tsAccountManager
        self.tsConstants = tsConstants
        self.twoFAManager = twoFAManager
    }

    @MainActor
    public func warmCaches() {
        if self.appContext.isMainApp {

            // Never migrate in the NSE or extensions.
            Task { @MainActor in
                try await performStartupMigrationsIfNecessary()
                self.refreshCredentialsAndBackupIfNecessary()
            }
        }
    }

    @MainActor
    private func refreshCredentialsAndBackupIfNecessary() {
        appReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            Task {
                await self.periodicRefreshCredentialIfNecessary()
                try await self.backupMasterKeyIfNecessary()
            }
        }
    }

    // MARK: - Periodic Backups

    private static let periodicCredentialRefreshAppVersionKey = "periodicCredentialRefreshAppVersion"

    private func getNeedsCredentialRefreshBasedOnVersion(tx: DBReadTransaction) -> Bool {
        guard
            let lastAppVersion = self.kvStore.getString(
                Self.periodicCredentialRefreshAppVersionKey,
                transaction: tx,
            )
        else {
            return true
        }
        return lastAppVersion != appVersion.currentAppVersion
    }

    private func didRefreshCredentialInCurrentVersion(tx: DBWriteTransaction) {
        self.kvStore.setString(
            appVersion.currentAppVersion,
            key: Self.periodicCredentialRefreshAppVersionKey,
            transaction: tx,
        )
    }

    @MainActor
    private func periodicRefreshCredentialIfNecessary() async {
        let needsRefresh = self.db.read { tx -> Bool in
            guard self.tsAccountManager.registrationState(tx: tx).isRegistered else {
                // Only refresh if registered.
                return false
            }
            guard self.hasBackedUpMasterKey(transaction: tx) else {
                // If we've never backed up, don't refresh periodically.
                return false
            }
            return self.getNeedsCredentialRefreshBasedOnVersion(tx: tx)
        }
        guard needsRefresh else {
            return
        }
        // Force refresh a credential, even if we have one cached, to ensure we
        // have a fresh credential to back up.
        Logger.info("Refreshing auth credential for periodic backup")
        do {
            let credential = try await RemoteAttestation.authForSVR2(chatServiceAuth: .implicit())
            Logger.info("Storing refreshed credential")
            db.write { tx in
                credentialStorage.storeAuthCredentialForCurrentUsername(
                    SVR2AuthCredential(credential: credential),
                    tx,
                )
                didRefreshCredentialInCurrentVersion(tx: tx)
            }
        } catch {
            Logger.warn("Unable to fetch auth credential")
        }
    }

    // MARK: - Key Existence

    public func hasMasterKey(transaction: DBReadTransaction) -> Bool {
        return accountKeyStore.getMasterKey(tx: transaction) != nil
    }

    public func hasBackedUpMasterKey(transaction: DBReadTransaction) -> Bool {
        return localStorage.getIsMasterKeyBackedUp(transaction)
    }

    // MARK: -

    /// Takes SVR-related actions when the master key changes, such as updating
    /// local state and updating remote SVR state.
    ///
    /// - Parameter disablePIN
    /// If `true`, wipes local state related to the PIN; no remote actions are
    /// taken, since the master key the PIN protects is being updated anyway.
    public func handleMasterKeyUpdated(
        newMasterKey: MasterKey,
        disablePIN: Bool,
        tx transaction: DBWriteTransaction,
    ) {
        // clearInProgressBackup will clear any in progress backup state.
        // This will prevent us continuing any in progress backups/exposes.
        clearInProgressBackup(tx: transaction)

        updateLocalSVRState(
            isMasterKeyBackedUp: localStorage.getIsMasterKeyBackedUp(transaction),
            mrEnclaveStringValue: nil,
            transaction: transaction,
        )

        if disablePIN {
            Logger.info("Disabling PIN.")

            // Disable the PIN locally.
            twoFAManager.markDisabled(transaction: transaction)
            // Wipe credentials; they're now useless.
            credentialStorage.removeSVR2CredentialsForCurrentUser(transaction)
        } else if let pin = twoFAManager.pinCode(transaction: transaction) {
            Logger.info("Scheduling master key backup with PIN.")

            // Record that the master key needs to be backed up.
            localStorage.setNeedsMasterKeyBackup(true, transaction)
            transaction.addSyncCompletion {
                Task { _ = try await self.backupMasterKey(pin: pin, masterKey: newMasterKey, authMethod: .implicit) }
            }
        }
    }

    // MARK: - Key Management

    private let backupQueue = ConcurrentTaskQueue(concurrentLimit: 1)

    public func backupMasterKey(pin: String, masterKey: MasterKey, authMethod: SVR.AuthMethod) async throws -> MasterKey {
        Logger.info("")
        return try await backupQueue.run {
            return try await doBackupAndExpose(pin: pin, masterKey: masterKey, authMethod: authMethod)
        }
    }

    public func restoreKeys(pin: String, authMethod: SVR.AuthMethod) async -> SVR.RestoreKeysResult {
        Logger.info("")
        // When we restore, we remember which enclave it was from. On some future app startup, we check
        // this enclave, and migrate to a new one if available. This code path relies on that happening
        // asynchronously.
        do {
            return try await doRestore(pin: pin, authMethod: authMethod).asSVRResult
        } catch {
            // [Err] TODO: Expose these directly to the caller.
            if error.isNetworkFailureOrTimeout {
                return .networkError(error)
            }
            return .genericError(error)
        }
    }

    public func clearKeys(transaction: DBWriteTransaction) {
        Logger.info("")
        // This will prevent us continuing any in progress backups/exposes.
        // If either are in flight, they will no-op when they get a response
        // and see no in progress backup state.
        clearInProgressBackup(tx: transaction)
        localStorage.clearSVRKeys(transaction)
    }

    public func storeKeys(
        fromProvisioningMessage provisioningMessage: LinkingProvisioningMessage,
        authedDevice: AuthedDevice,
        tx: DBWriteTransaction,
    ) throws(SVR.KeysError) {
        Logger.info("")
        accountKeyStore.setMediaRootBackupKey(provisioningMessage.mrbk, tx: tx)

        switch provisioningMessage.rootKey {
        case .accountEntropyPool(let aep):
            accountKeyStore.setAccountEntropyPool(aep, tx: tx)
        case .masterKey(let masterKey):
            accountKeyStore.setMasterKey(masterKey, tx: tx)
        }
    }

    public func storeKeys(
        fromKeysSyncMessage syncMessage: SSKProtoSyncMessageKeys,
        authedDevice: AuthedDevice,
        tx: DBWriteTransaction,
    ) throws(SVR.KeysError) {
        Logger.info("")

        if
            let mrbkBytes = syncMessage.mediaRootBackupKey,
            let backupKey = try? BackupKey(contents: mrbkBytes)
        {
            accountKeyStore.setMediaRootBackupKey(MediaRootBackupKey(backupKey: backupKey), tx: tx)
        } else {
            throw SVR.KeysError.missingOrInvalidMRBK
        }

        var keyChanged = false

        let oldAep = accountKeyStore.getAccountEntropyPool(tx: tx)
        do {
            if let aep = try syncMessage.accountEntropyPool.map({ try AccountEntropyPool(key: $0) }) {
                accountKeyStore.setAccountEntropyPool(aep, tx: tx)
            }
        } catch {
            owsFailDebug("Error setting AEP")
        }
        let newAep = accountKeyStore.getAccountEntropyPool(tx: tx)
        keyChanged = (oldAep != newAep)

        if newAep == nil {
            let oldMasterKey = accountKeyStore.getMasterKey(tx: tx)?.rawData
            do {
                if let masterKey = try syncMessage.master.map({ try MasterKey(data: $0) }) {
                    accountKeyStore.setMasterKey(masterKey, tx: tx)
                }
            } catch {
                throw SVR.KeysError.missingMasterKey
            }
            let newMasterKey = accountKeyStore.getMasterKey(tx: tx)?.rawData
            keyChanged = (oldMasterKey != newMasterKey)
        }

        // Trigger a re-fetch of the storage manifest if our keys have changed
        if keyChanged {
            storageServiceManager.restoreOrCreateManifestIfNecessary(
                authedDevice: authedDevice,
                masterKeySource: .implicit,
            )
        }
    }

    // MARK: - Backup/Expose Request

    private lazy var kvStore = KeyValueStore(collection: "SecureValueRecovery2Impl")

    /// We must be careful to never repeat a backup request when an expose request fails, or
    /// even if an expose request was made. Once we get a success response from a backup
    /// request, we create and persist one of these to track that, and only ever make expose
    /// requests from then on until either:
    /// 1. The expose requests succeeeds (we are done backing up and can wipe this)
    /// 2. The user chooses a different PIN (we will make a new backup request)
    /// 3. The user wipes SVR2 backups
    private struct InProgressBackup: Codable, Equatable {
        let masterKey: Data
        let encryptedMasterKey: Data
        // TODO: Remove.
        let rawPinType: Int
        let encodedPINVerificationString: String
        // If we make a backup to one mrenclave, then update the mrenclave,
        // we are safe to drop it and start again with a backup to the new
        // mrenclave.
        let mrEnclaveStringValue: String

        func matches(
            pin: String,
            mrEnclave: MrEnclave,
        ) -> Bool {
            if !SVRUtil.verifyPIN(pin: pin, againstEncodedPINVerificationString: self.encodedPINVerificationString) {
                return false
            }
            if mrEnclave.stringValue != self.mrEnclaveStringValue {
                return false
            }
            return true
        }

        func matches(_ other: InProgressBackup) -> Bool {
            return self == other
        }
    }

    private static let inProgressBackupKey = "InProgressBackup"

    private func getInProgressBackup(tx: DBReadTransaction) throws -> InProgressBackup? {
        return try kvStore.getCodableValue(forKey: Self.inProgressBackupKey, transaction: tx)
    }

    private func setInProgressBackup(_ value: InProgressBackup, tx: DBWriteTransaction) {
        failIfThrows {
            try kvStore.setCodable(optional: value, key: Self.inProgressBackupKey, transaction: tx)
        }
    }

    private func clearInProgressBackup(tx: DBWriteTransaction) {
        kvStore.removeValue(forKey: Self.inProgressBackupKey, transaction: tx)
    }

    private func doBackupAndExpose(
        pin: String,
        masterKey: MasterKey,
        authMethod: SVR2.AuthMethod,
    ) async throws -> MasterKey {
        let config = SVR2WebsocketConfigurator(mrenclave: tsConstants.svr2Enclave, authMethod: authMethod)

        let connection = try await makeHandshakeAndOpenConnection(config)
        defer { connection.disconnect(code: .normalClosure) }

        Logger.info("Connection open; beginning backup/expose")

        // Check if we had an in flight backup.
        let inProgressBackup: InProgressBackup?
        do {
            inProgressBackup = try self.db.read(block: self.getInProgressBackup(tx:))
        } catch {
            // If we fail to decode, something has gone wrong locally. But we can
            // treat this like if we never had a backup; after all the user may uninstall,
            // reinstall, and do a backup again with the same PIN. This, like that, is
            // a local-only trigger.
            Logger.error("Failed to decode in progress backup state")
            inProgressBackup = nil
        }

        let completedInProgressBackup: InProgressBackup
        if let inProgressBackup, inProgressBackup.matches(pin: pin, mrEnclave: config.mrenclave) {
            // Continue the backup from where we left off.
            Logger.warn("Skipping backup that was already completed")
            completedInProgressBackup = inProgressBackup
        } else {
            // We don't have a backup, or we're trying to back up something else; start
            // fresh in both cases.
            completedInProgressBackup = try await self.performBackupRequest(
                pin: pin,
                masterKey: masterKey,
                mrEnclave: config.mrenclave,
                connection: connection,
            )
            // Write the in progress state to disk; we want to continue
            // from here and not redo the backup request.
            await self.db.awaitableWrite { tx in
                self.setInProgressBackup(completedInProgressBackup, tx: tx)
            }
        }

        try await self.performExposeRequest(
            backup: completedInProgressBackup,
            authedAccount: authMethod.authedAccount,
            connection: connection,
        )

        try await self.db.awaitableWrite { tx in
            guard let persistedBackup = try self.getInProgressBackup(tx: tx), persistedBackup.matches(completedInProgressBackup) else {
                Logger.info("Backup state changed while expose ongoing; throwing away results")
                return
            }
            self.localStorage.setNeedsMasterKeyBackup(false, tx)
            self.clearInProgressBackup(tx: tx)
            self.updateLocalSVRState(
                isMasterKeyBackedUp: true,
                mrEnclaveStringValue: completedInProgressBackup.mrEnclaveStringValue,
                transaction: tx,
            )
        }

        return try MasterKey(data: completedInProgressBackup.masterKey)
    }

    private func performBackupRequest(
        pin: String,
        masterKey: MasterKey,
        mrEnclave: MrEnclave,
        connection: SgxWebsocketConnection<SVR2WebsocketConfigurator>,
    ) async throws -> InProgressBackup {
        Logger.info("Performing backup")
        let encodedPINVerificationString = try SVRUtil.deriveEncodedPINVerificationString(pin: pin)

        let pinHash = try hashPin(pin, forConnection: connection)
        let encryptedMasterKey = try pinHash.encryptMasterKey(masterKey.rawData)

        var backupRequest = SVR2Proto_BackupRequest()
        backupRequest.maxTries = SVR.maximumKeyAttempts
        backupRequest.pin = pinHash.accessKey
        backupRequest.data = encryptedMasterKey

        var request = SVR2Proto_Request()
        request.backup = backupRequest

        let response = try await connection.sendRequestAndReadResponse(request)
        guard response.hasBackup else {
            throw OWSGenericError("backup missing from server response")
        }
        switch response.backup.status {
        case .ok:
            Logger.info("Backup success!")
            return InProgressBackup(
                masterKey: masterKey.rawData,
                encryptedMasterKey: encryptedMasterKey,
                rawPinType: 0,
                encodedPINVerificationString: encodedPINVerificationString,
                mrEnclaveStringValue: mrEnclave.stringValue,
            )
        case .UNRECOGNIZED, .unset:
            throw OWSGenericError("backup status response unknown")
        }
    }

    private func performExposeRequest(
        backup: InProgressBackup,
        authedAccount: AuthedAccount,
        connection: SgxWebsocketConnection<SVR2WebsocketConfigurator>,
    ) async throws {
        var exposeRequest = SVR2Proto_ExposeRequest()
        exposeRequest.data = backup.encryptedMasterKey
        var request = SVR2Proto_Request()
        request.expose = exposeRequest
        Logger.info("Issuing expose request")
        let response = try await connection.sendRequestAndReadResponse(request)
        guard response.hasExpose else {
            throw OWSGenericError("expose missing from server response")
        }
        switch response.expose.status {
        case .ok:
            Logger.info("Expose success!")
        case .error:
            // Every expose is a pair with a backup request. For it to fail,
            // one of three things happened:
            // 1. The local client sent a second backup, invalidating the one
            // this expose is paired with.
            // 2. A second client has sent its own backup, invalidating the
            // backup this expose is paired with.
            // 3. The server is misbehaving and reporting an error.
            //
            // 1 should be impossible; this class enforces serial execution to
            // prevent this. It is developer error if it does.
            //
            // 2 is impossible; only a primary device does backups, and if there
            // were another primary this one would be deregistered and its
            // auth credentials invalidated.
            //
            // 3 could be a legitimate server error or a compromised server; in either
            // case we do NOT want to make another backup; report a failure but keep
            // any InProgressBackup state around so that retries just retry the expose.
            // This prevents any possibility of repeated PIN guessing by a compromised server.
            throw OWSGenericError("Got error response when exposing on SVR2 server; something has gone horribly wrong.")
        case .UNRECOGNIZED, .unset:
            throw OWSGenericError("expose status response unknown")
        }
    }

    // MARK: - Restore Request

    private enum RestoreResult {
        case success(masterKey: MasterKey, mrEnclave: MrEnclave)
        case invalidPin(remainingAttempts: UInt32)
        case backupMissing

        var asSVRResult: SVR.RestoreKeysResult {
            switch self {
            case .success(let masterKey, _):
                return .success(masterKey)
            case .backupMissing:
                return .backupMissing
            case .invalidPin(let remainingAttempts):
                return .invalidPin(remainingAttempts: remainingAttempts)
            }
        }
    }

    private func doRestore(
        pin: String,
        authMethod: SVR2.AuthMethod,
    ) async throws -> RestoreResult {
        let enclavesToTry = [tsConstants.svr2Enclave] + tsConstants.svr2PreviousEnclaves
        for enclave in enclavesToTry {
            let enclaveResult = try await self.doRestoreForSpecificEnclave(
                pin: pin,
                mrEnclave: enclave,
                authMethod: authMethod,
            )
            switch enclaveResult {
            case .backupMissing:
                // Only if we get an explicit backup missing result
                // from the server, try prior enclaves.
                // This works because we always wipe old enclaves when
                // we know about newer ones, so the only reason we'd have
                // anything in an old enclave is that we haven't migrated yet.
                // Once we migrate, we wipe the old one.
                continue
            case .success, .invalidPin:
                return enclaveResult
            }
        }
        // If we reach the end, there's no backup.
        return .backupMissing
    }

    private func doRestoreForSpecificEnclave(
        pin: String,
        mrEnclave: MrEnclave,
        authMethod: SVR2.AuthMethod,
    ) async throws -> RestoreResult {
        let config = SVR2WebsocketConfigurator(mrenclave: mrEnclave, authMethod: authMethod)
        do {
            let connection = try await makeHandshakeAndOpenConnection(config)
            defer { connection.disconnect(code: .normalClosure) }
            Logger.info("Connection open; making restore request")
            return try await self.performRestoreRequest(
                mrEnclave: mrEnclave,
                pin: pin,
                connection: connection,
                authedAccount: authMethod.authedAccount,
            )
        }
    }

    private func performRestoreRequest(
        mrEnclave: MrEnclave,
        pin: String,
        connection: SgxWebsocketConnection<SVR2WebsocketConfigurator>,
        authedAccount: AuthedAccount,
    ) async throws -> RestoreResult {
        let pinHash = try hashPin(pin, forConnection: connection)

        var restoreRequest = SVR2Proto_RestoreRequest()
        restoreRequest.pin = pinHash.accessKey
        var request = SVR2Proto_Request()
        request.restore = restoreRequest
        let response = try await connection.sendRequestAndReadResponse(request)
        guard response.hasRestore else {
            throw OWSGenericError("restore missing in server response")
        }
        switch response.restore.status {
        case .unset, .UNRECOGNIZED:
            throw OWSGenericError("restore status response unknown")
        case .missing:
            Logger.info("restore response: backup missing")
            return .backupMissing
        case .pinMismatch:
            Logger.info("restore response: invalid pin")
            return .invalidPin(remainingAttempts: response.restore.tries)
        case .ok:
            Logger.info("Restore success!")
            let encryptedMasterKey = response.restore.data
            let masterKeyData = try pinHash.decryptMasterKey(encryptedMasterKey)
            let masterKey = try MasterKey(data: masterKeyData)
            await self.db.awaitableWrite { tx in
                self.updateLocalSVRState(
                    isMasterKeyBackedUp: true,
                    mrEnclaveStringValue: mrEnclave.stringValue,
                    transaction: tx,
                )
            }
            return .success(masterKey: masterKey, mrEnclave: mrEnclave)
        }
    }

    // MARK: - Delete Request

    private func doDelete(
        mrEnclave: MrEnclave,
        authMethod: SVR2.AuthMethod,
    ) async throws {
        let config = SVR2WebsocketConfigurator(mrenclave: mrEnclave, authMethod: authMethod)
        let connection = try await makeHandshakeAndOpenConnection(config)
        defer { connection.disconnect(code: .normalClosure) }
        return try await self.performDeleteRequest(
            mrEnclave: mrEnclave,
            connection: connection,
            authedAccount: authMethod.authedAccount,
        )
    }

    private func performDeleteRequest(
        mrEnclave: MrEnclave,
        connection: SgxWebsocketConnection<SVR2WebsocketConfigurator>,
        authedAccount: AuthedAccount,
    ) async throws {
        var request = SVR2Proto_Request()
        request.delete = SVR2Proto_DeleteRequest()
        let response = try await connection.sendRequestAndReadResponse(request)
        guard response.hasDelete else {
            throw OWSGenericError("delete missing in server response")
        }
        Logger.info("Delete success!")
    }

    // MARK: Durable deletes

    private static let oldEnclavesToDeleteFromKey = "OldEnclavesToDeleteFrom"

    private func getOldEnclavesToDeleteFrom(_ tx: DBReadTransaction) -> [MrEnclave] {
        // This is decoding a Set<String>. It won't actually ever fail, so just eat up errors.
        let enclaveStrings: Set<String>? = try? kvStore.getCodableValue(
            forKey: Self.oldEnclavesToDeleteFromKey,
            transaction: tx,
        )
        guard var enclaveStrings else {
            return []
        }
        var enclavesToDeleteFrom = [MrEnclave]()
        for enclave in tsConstants.svr2PreviousEnclaves {
            if enclaveStrings.remove(enclave.stringValue) != nil {
                enclavesToDeleteFrom.append(enclave)
            }
        }
        return enclavesToDeleteFrom
    }

    private func addOldEnclaveToDeleteFrom(_ enclave: MrEnclave, _ tx: DBWriteTransaction) {
        // This is (en/de)coding a Set<String>. It won't actually ever fail, so just eat up errors.
        var enclaveStrings: Set<String> = (try? kvStore.getCodableValue(
            forKey: Self.oldEnclavesToDeleteFromKey,
            transaction: tx,
        )) ?? Set()
        enclaveStrings.insert(enclave.stringValue)
        cleanUpForgottenEnclaves(in: &enclaveStrings)
        try? kvStore.setCodable(enclaveStrings, key: Self.oldEnclavesToDeleteFromKey, transaction: tx)
    }

    private func markOldEnclaveDeleted(_ enclave: MrEnclave, _ tx: DBWriteTransaction) {
        // This is (en/de)coding a Set<String>. It won't actually ever fail, so just eat up errors.
        var enclaveStrings: Set<String> = (try? kvStore.getCodableValue(
            forKey: Self.oldEnclavesToDeleteFromKey,
            transaction: tx,
        )) ?? Set()
        enclaveStrings.remove(enclave.stringValue)
        cleanUpForgottenEnclaves(in: &enclaveStrings)
        try? kvStore.setCodable(enclaveStrings, key: Self.oldEnclavesToDeleteFromKey, transaction: tx)
    }

    private func cleanUpForgottenEnclaves(in enclaveStrings: inout Set<String>) {
        let knownEnclaves = Set(tsConstants.svr2PreviousEnclaves.map(\.stringValue))
        enclaveStrings.formIntersection(knownEnclaves)
    }

    private func wipeOldEnclavesIfNeeded(auth: SVR2.AuthMethod) async {
        let (isRegistered, enclavesToDeleteFrom) = db.read { tx in
            return (
                self.tsAccountManager.registrationState(tx: tx).isRegistered,
                self.getOldEnclavesToDeleteFrom(tx),
            )
        }
        guard isRegistered else {
            return
        }
        for enclave in enclavesToDeleteFrom {
            Logger.info("Wiping old enclave: \(enclave.stringValue)")
            do {
                try await self.doDelete(mrEnclave: enclave, authMethod: auth)
                await db.awaitableWrite { tx in
                    markOldEnclaveDeleted(enclave, tx)
                }
            } catch {
                Logger.warn("couldn't wipe old enclave; may retry eventually: \(error)")
            }
        }
    }

    // MARK: - Migrations

    public func performStartupMigrationsIfNecessary() async throws {
        // Require migrations to succeed before we check for old stuff
        // to wipe, because migrations add old stuff to be wiped.
        // If a migration isn't needed, this returns a success immediately.
        try await migrateEnclavesIfNecessary()
        await wipeOldEnclavesIfNeeded(auth: .implicit)
    }

    private func backupMasterKeyIfNecessary() async throws {
        try await backupQueue.run {
            try await _backupMasterKeyIfNecessary()
        }
    }

    private func _backupMasterKeyIfNecessary() async throws {
        let (
            currentPIN,
            backupRequested,
            masterKey,
        ) = db.read { tx in
            (
                twoFAManager.pinCode(transaction: tx),
                localStorage.getNeedsMasterKeyBackup(tx),
                accountKeyStore.getMasterKey(tx: tx),
            )
        }
        if
            let currentPIN,
            let masterKey,
            backupRequested
        {
            _ = try await doBackupAndExpose(pin: currentPIN, masterKey: masterKey, authMethod: .implicit)
        } else {
            if masterKey != nil, currentPIN == nil {
                Logger.warn("Cannot backup master key without PIN")
            } else if masterKey == nil, currentPIN != nil {
                Logger.warn("Skipping backup due missing master key")
            }
        }
    }

    /// If there is a newer enclave than the one we most recently backed up to, backs up known
    /// master key data to it instead, marking the old enclave for deletion.
    /// If there is no migration needed, returns a success promise immediately.
    private func migrateEnclavesIfNecessary() async throws {
        try await backupQueue.run {
            try await _migrateEnclavesIfNecessary()
        }
    }

    private func _migrateEnclavesIfNecessary() async throws {
        let values = db.read { tx -> (String, String, MasterKey)? in
            guard
                self.tsAccountManager.registrationState(tx: tx).isRegisteredPrimaryDevice,
                let masterKey = self.accountKeyStore.getMasterKey(tx: tx),
                let pin = self.twoFAManager.pinCode(transaction: tx)
            else {
                // Need to be registered with a master key and PIN to migrate.
                Logger.info("Not migrating; local state not ready")
                return nil
            }
            let currentEnclaveString = self.tsConstants.svr2Enclave.stringValue
            let oldSVR2EnclaveString = self.localStorage.getSVR2MrEnclaveStringValue(tx)

            guard self.localStorage.getIsMasterKeyBackedUp(tx) else {
                // "isMasterKeyBackedUp" is shared between svr2 and kbs; if its
                // false that means we had no backups to begin with and therefore
                // should not back up to any new enclave.
                Logger.info("Not migrating; no previous backups.")
                return nil
            }

            if
                let oldSVR2EnclaveString,
                oldSVR2EnclaveString != currentEnclaveString
            {
                // We are backed up to an svr2 enclave that isn't the current one.
                Logger.info("Migrating from old svr2 enclave")
                return (oldSVR2EnclaveString, pin, masterKey)
            }

            return nil
        }
        guard let (oldSVR2EnclaveString, pin, masterKey) = values else {
            // No migration needed.
            return
        }

        Logger.info("Migrating SVR2 Enclaves")
        do {
            _ = try await self.doBackupAndExpose(pin: pin, masterKey: masterKey, authMethod: .implicit)
            Logger.info("Successfully migrated SVR2 enclave")
        } catch {
            owsFailDebug("Failed to migrate SVR2 enclave")
            throw error
        }

        let backedUpEnclave = self.tsConstants.svr2PreviousEnclaves.first(where: {
            $0.stringValue == oldSVR2EnclaveString
        })
        if let backedUpEnclave {
            Logger.info("Adding old enclave to be deleted")
            // Strictly speaking, this happens in a separate transaction from when we mark the
            // backup/expose complete. But no matter what this is best effort; the client
            // can be uninstalled before it gets a chance to delete the old backup, for example.
            await self.db.awaitableWrite { tx in
                self.addOldEnclaveToDeleteFrom(backedUpEnclave, tx)
            }
            // We start wiping any old enclaves right after doing this migration,
            // no need to kick it off here.
        }
    }

    // MARK: - Opening websocket

    func hashPin(
        _ pin: String,
        forConnection connection: SgxWebsocketConnection<SVR2WebsocketConfigurator>,
    ) throws -> SVR2PinHash {
        return try pinHasher.hashPin(
            normalizedPin: SVRUtil.normalizePin(pin),
            username: connection.auth.username,
            mrEnclave: connection.mrEnclave,
        )
    }

    private let connectionQueue = ConcurrentTaskQueue(concurrentLimit: 1)

    private func makeHandshakeAndOpenConnection(_ config: SVR2WebsocketConfigurator) async throws -> SgxWebsocketConnection<SVR2WebsocketConfigurator> {
        // Update the auth method with cached credentials if we have them.
        switch config.authMethod {
        case .svrAuth, .chatServerAuth:
            // If we explicitly want to use some credential, use that.
            break
        case .implicit:
            // If implicit, use any cached values.
            if let cachedCredential: SVR2AuthCredential = db.read(block: credentialStorage.getAuthCredentialForCurrentUser) {
                config.authMethod = .svrAuth(cachedCredential, backup: .implicit)
            }
        }

        return try await connectionQueue.run {
            while true {
                Logger.info("Opening new connection")
                do {
                    let sgxConnection = try await self.connectionFactory.connectAndPerformHandshake(configurator: config)
                    let knownGoodAuthCredential = sgxConnection.auth
                    // If we were able to open a connection, that means the auth used is valid
                    // and we should cache it.
                    await self.db.awaitableWrite { tx in
                        self.credentialStorage.storeAuthCredentialForCurrentUsername(
                            SVR2AuthCredential(credential: knownGoodAuthCredential),
                            tx,
                        )
                    }
                    return sgxConnection
                } catch {
                    Logger.error("Failed to open websocket connection and complete handshake")

                    // if we fail to connect for any reason, assume the credential we tried to use was bad.
                    // clear it out, and if we have a backup, try again with that.
                    switch config.authMethod {
                    case .svrAuth(let attemptedCredential, let backup):
                        await self.db.awaitableWrite { tx in
                            self.credentialStorage.deleteInvalidCredentials([attemptedCredential].compacted(), tx)
                        }
                        if let backup {
                            config.authMethod = backup
                            continue
                        }
                    case .chatServerAuth, .implicit:
                        break
                    }

                    throw error
                }
            }
        }
    }

    // MARK: - Local key storage helpers

    private func updateLocalSVRState(
        isMasterKeyBackedUp: Bool,
        mrEnclaveStringValue: String?,
        transaction: DBWriteTransaction,
    ) {
        if isMasterKeyBackedUp != localStorage.getIsMasterKeyBackedUp(transaction) {
            localStorage.setIsMasterKeyBackedUp(isMasterKeyBackedUp, transaction)
        }
        if mrEnclaveStringValue != localStorage.getSVR2MrEnclaveStringValue(transaction) {
            localStorage.setSVR2MrEnclaveStringValue(mrEnclaveStringValue, transaction)
        }
    }
}

private extension SVR2.AuthMethod {

    var authedAccount: AuthedAccount {
        switch self {
        case .svrAuth(_, let backup):
            return backup?.authedAccount ?? .implicit()
        case .chatServerAuth(let authedAccount):
            return authedAccount
        case .implicit:
            return .implicit()
        }
    }
}
