//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

/// Implementation of `SecureValueRecovery` that talks to the SVR2 server.
public class SecureValueRecovery2Impl: SecureValueRecovery {

    private let pinHasher: any SVR2PinHasher
    private let connectionFactory: SgxWebsocketConnectionFactory
    private let credentialStorage: SVRAuthCredentialStorage
    private let db: any DB
    private let accountKeyStore: AccountKeyStore
    private let localStorage: SVRLocalStorage
    private let storageServiceManager: StorageServiceManager
    private let tsConstants: TSConstantsProtocol
    private let twoFAManager: SVR2.Shims.OWS2FAManager

    init(
        connectionFactory: SgxWebsocketConnectionFactory,
        credentialStorage: SVRAuthCredentialStorage,
        db: any DB,
        accountKeyStore: AccountKeyStore,
        pinHasher: any SVR2PinHasher,
        storageServiceManager: StorageServiceManager,
        svrLocalStorage: SVRLocalStorage,
        tsConstants: TSConstantsProtocol,
        twoFAManager: SVR2.Shims.OWS2FAManager,
    ) {
        self.connectionFactory = connectionFactory
        self.credentialStorage = credentialStorage
        self.db = db
        self.accountKeyStore = accountKeyStore
        self.localStorage = svrLocalStorage
        self.pinHasher = pinHasher
        self.storageServiceManager = storageServiceManager
        self.tsConstants = tsConstants
        self.twoFAManager = twoFAManager
    }

    // MARK: - Periodic Backups

    public func refreshCredentialsIfNecessary() async throws {
        let hasBackedUp = self.db.read { tx in self.hasBackedUpMasterKey(transaction: tx) }
        guard hasBackedUp else {
            // If we've never backed up, don't refresh periodically. (If we eventually
            // perform a backup, we'll cache those credential after fetching them.)
            return
        }
        // Force refresh a credential, even if we have one cached, to ensure we
        // have a fresh credential to back up.
        let credential = try await RemoteAttestation.authForSVR2(chatServiceAuth: .implicit())
        await db.awaitableWrite { tx in
            credentialStorage.storeAuthCredentialForCurrentUsername(
                SVR2AuthCredential(credential: credential),
                tx,
            )
        }
    }

    // MARK: - Key Existence

    public func hasMasterKey(transaction: DBReadTransaction) -> Bool {
        return accountKeyStore.getMasterKey(tx: transaction) != nil
    }

    public func hasBackedUpMasterKey(transaction: DBReadTransaction) -> Bool {
        return localStorage.getIsMasterKeyBackedUp(transaction)
    }

    // MARK: - Key Management

    private let backupQueue = ConcurrentTaskQueue(concurrentLimit: 1)

    public func backupMasterKey(pin: String, masterKey: MasterKey, force: Bool, authMethod: SVR.AuthMethod) async throws {
        Logger.info("")
        try await backupQueue.run {
            try await doBackupAndExpose(pin: pin, masterKey: masterKey, force: force, authMethod: authMethod)
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

    private let kvStore = KeyValueStore(collection: "SecureValueRecovery2Impl")

    /// We must be careful to never repeat a backup request after sending an
    /// expose request for the first time. We must do this even if the
    /// connection dies and we lose the response to the expose request.
    /// After we get a success response from a backup request, we create and
    /// persist one of these to track that we've started making expose requests,
    /// and we only ever make expose requests from then on until:
    /// 1. The user chooses a different PIN (we will make a new backup request)
    /// 2. The user rotates their master key (we will make a new backup request)
    /// 3. We roll out a new enclave (we will make a new backup request)
    /// 3. The user disables their PIN (we will make a delete request)
    private struct CompletedBackup: Codable {
        let masterKey: Data
        let encryptedMasterKey: Data
        let encodedPINVerificationString: String
        var isExposed: Bool

        func matches(pin: String, masterKey: MasterKey) -> Bool {
            return (
                SVRUtil.verifyPIN(pin: pin, againstEncodedPINVerificationString: self.encodedPINVerificationString)
                    && masterKey.rawData.ows_constantTimeIsEqual(to: self.masterKey),
            )
        }
    }

    private func getCompletedBackup(forEnclave enclave: MrEnclave, tx: DBReadTransaction) -> CompletedBackup? {
        do {
            return try localStorage.completedBackupStore.getCodableValue(forKey: enclave.stringValue, transaction: tx)
        } catch {
            // If we fail to decode, something has gone wrong locally. But we can
            // treat this like if we never had a backup; after all the user may uninstall,
            // reinstall, and do a backup again with the same PIN. This, like that, is
            // a local-only trigger.
            Logger.error("couldn't decode CompletedBackup")
            return nil
        }
    }

    private func setCompletedBackup(_ value: CompletedBackup, forEnclave enclave: MrEnclave, tx: DBWriteTransaction) {
        failIfThrows {
            try localStorage.completedBackupStore.setCodable(optional: value, key: enclave.stringValue, transaction: tx)
        }
    }

    private func removeCompletedBackup(forEnclave enclave: String, tx: DBWriteTransaction) {
        localStorage.completedBackupStore.removeValue(forKey: enclave, transaction: tx)
    }

    private func doBackupAndExpose(
        pin: String,
        masterKey: MasterKey,
        force: Bool,
        authMethod: SVR2.AuthMethod,
    ) async throws {
        let mrEnclave = tsConstants.svr2Enclave

        let priorBackup = self.db.read { tx in self.getCompletedBackup(forEnclave: mrEnclave, tx: tx) }

        let priorMatchingBackup: CompletedBackup?
        if force {
            // We're forcing a backup, so *nothing* matches.
            priorMatchingBackup = nil
        } else if let priorBackup, priorBackup.matches(pin: pin, masterKey: masterKey) {
            // We're trying to back up what's already backed up.
            priorMatchingBackup = priorBackup
        } else {
            priorMatchingBackup = nil
        }

        if let priorMatchingBackup, priorMatchingBackup.isExposed {
            return
        }

        let config = SVR2WebsocketConfigurator(mrenclave: mrEnclave, authMethod: authMethod)

        let connection = try await makeHandshakeAndOpenConnection(config)
        defer { connection.disconnect(code: .normalClosure) }

        Logger.info("Connection open; beginning backup/expose")

        // After this point, we might have data stored in this enclave. (For
        // example, the network may drop before we receive the response.) Store
        // this enclave so that we eventually clean it up.
        await self.db.awaitableWrite { tx in
            self.addEnclaveToPotentiallyDeleteFrom(mrEnclave, tx)
        }

        var completedBackup: CompletedBackup
        if let priorMatchingBackup {
            // We already completed a backup for this (pin, masterKey, enclave) triple,
            // so we only want to perform an expose.
            Logger.warn("Skipping backup that was already completed")
            completedBackup = priorMatchingBackup
        } else {
            // We don't have a backup, or we're trying to back up something else, or
            // we're trying to back up to somewhere else; start fresh in these cases.
            completedBackup = try await self.performBackupRequest(
                pin: pin,
                masterKey: masterKey,
                connection: connection,
            )
            await self.db.awaitableWrite { tx in
                // Write that we've finished to disk; we never want to repeat the prior
                // request after we start sending expose requests.
                self.setCompletedBackup(completedBackup, forEnclave: mrEnclave, tx: tx)
            }
        }

        // This must be true because it's checked earlier for existing backups and
        // starts out false for new backups.
        owsPrecondition(!completedBackup.isExposed)

        try await self.performExposeRequest(
            backup: completedBackup,
            authedAccount: authMethod.authedAccount,
            connection: connection,
        )
        completedBackup.isExposed = true

        await self.db.awaitableWrite { tx in
            self.setCompletedBackup(completedBackup, forEnclave: mrEnclave, tx: tx)
        }
    }

    private func performBackupRequest(
        pin: String,
        masterKey: MasterKey,
        connection: SgxWebsocketConnection<SVR2WebsocketConfigurator>,
    ) async throws -> CompletedBackup {
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
            return CompletedBackup(
                masterKey: masterKey.rawData,
                encryptedMasterKey: encryptedMasterKey,
                encodedPINVerificationString: encodedPINVerificationString,
                isExposed: false,
            )
        case .UNRECOGNIZED, .unset:
            throw OWSGenericError("backup status response unknown")
        }
    }

    private func performExposeRequest(
        backup: CompletedBackup,
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
            // any CompletedBackup state around so that retries just retry the expose.
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
        await db.awaitableWrite { tx in
            // If send a request to delete this, it may be deleted even if we don't get
            // back a response (e.g., the connection fails, the app exits). By clearing
            // this now, we ensure resiliency for new backups after these edge cases.
            removeCompletedBackup(forEnclave: mrEnclave.stringValue, tx: tx)
        }
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

    private static let enclavesToPotentiallyDeleteFromKey = "OldEnclavesToDeleteFrom"

    private func getEnclavesToPotentiallyDeleteFrom(_ tx: DBReadTransaction) -> Set<String> {
        // This is decoding a Set<String>. It won't actually ever fail, so just eat up errors.
        let enclaveStrings: Set<String> = (try? kvStore.getCodableValue(
            forKey: Self.enclavesToPotentiallyDeleteFromKey,
            transaction: tx,
        )) ?? Set()
        return enclaveStrings
    }

    private func addEnclaveToPotentiallyDeleteFrom(_ enclave: MrEnclave, _ tx: DBWriteTransaction) {
        // This is (en/de)coding a Set<String>. It won't actually ever fail, so just eat up errors.
        var enclaveStrings: Set<String> = (try? kvStore.getCodableValue(
            forKey: Self.enclavesToPotentiallyDeleteFromKey,
            transaction: tx,
        )) ?? Set()
        enclaveStrings.insert(enclave.stringValue)
        try? kvStore.setCodable(enclaveStrings, key: Self.enclavesToPotentiallyDeleteFromKey, transaction: tx)
    }

    private func markEnclaveDeleted(_ enclave: String, _ tx: DBWriteTransaction) {
        // This is (en/de)coding a Set<String>. It won't actually ever fail, so just eat up errors.
        var enclaveStrings: Set<String> = (try? kvStore.getCodableValue(
            forKey: Self.enclavesToPotentiallyDeleteFromKey,
            transaction: tx,
        )) ?? Set()
        enclaveStrings.remove(enclave)
        try? kvStore.setCodable(enclaveStrings, key: Self.enclavesToPotentiallyDeleteFromKey, transaction: tx)
    }

    private func wipeObsoleteEnclaves(allEnclaves: some Sequence<MrEnclave>, enclavesToKeep: Int) async throws {
        var firstError: (any Error)?
        var potentialEnclaves = db.read(block: { tx in self.getEnclavesToPotentiallyDeleteFrom(tx) })
        for keptEnclave in allEnclaves.prefix(enclavesToKeep) {
            potentialEnclaves.remove(keptEnclave.stringValue)
        }
        for obsoleteEnclave in allEnclaves.dropFirst(enclavesToKeep) {
            guard potentialEnclaves.remove(obsoleteEnclave.stringValue) != nil else {
                continue
            }
            Logger.info("wiping enclave: \(obsoleteEnclave)")
            do {
                try await self.doDelete(mrEnclave: obsoleteEnclave, authMethod: .implicit)
                await db.awaitableWrite { tx in
                    markEnclaveDeleted(obsoleteEnclave.stringValue, tx)
                }
            } catch {
                Logger.warn("couldn't wipe enclave; may retry eventually: \(error)")
                firstError = firstError ?? error
            }
        }
        for unknownEnclave in potentialEnclaves {
            Logger.warn("pruning unknown enclave: \(unknownEnclave)")
            await db.awaitableWrite { tx in
                removeCompletedBackup(forEnclave: unknownEnclave, tx: tx)
                markEnclaveDeleted(unknownEnclave, tx)
            }
        }
        if let firstError {
            throw firstError
        }
    }

    // MARK: - Migrations

    public func refreshBackupIfNecessary() async throws {
        try await backupQueue.run {
            let pin = db.read(block: twoFAManager.pinCode(transaction:))

            if let pin {
                let masterKey = db.read(block: accountKeyStore.getMasterKey(tx:))
                if let masterKey {
                    // If a backup isn't needed, this returns a success immediately.
                    try await doBackupAndExpose(pin: pin, masterKey: masterKey, force: false, authMethod: .implicit)
                } else {
                    Logger.warn("can't back up master key without master key")
                }
            }

            let allEnclaves = [tsConstants.svr2Enclave] + tsConstants.svr2PreviousEnclaves
            // If we don't have a PIN, we shouldn't keep any enclaves.
            let enclavesToKeep = pin == nil ? 0 : 1

            // Require backups (i.e., migrations) to succeed before deleting from old
            // enclaves to ensure we're always backed up to at least one enclave.
            try await wipeObsoleteEnclaves(allEnclaves: allEnclaves, enclavesToKeep: enclavesToKeep)
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
