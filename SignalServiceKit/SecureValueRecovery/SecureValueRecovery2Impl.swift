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
    private let credentialManager: SVRAuthCredentialManager
    private let db: any DB
    private let accountKeyStore: AccountKeyStore
    private let localStorage: SVRLocalStorage
    private let remoteAttestationAuthFetcher: RemoteAttestationAuthFetcher
    private let storageServiceManager: StorageServiceManager
    private let tsConstants: TSConstantsProtocol
    private let twoFAManager: SVR2.Shims.OWS2FAManager

    init(
        connectionFactory: SgxWebsocketConnectionFactory,
        credentialManager: SVRAuthCredentialManager,
        db: any DB,
        accountKeyStore: AccountKeyStore,
        pinHasher: any SVR2PinHasher,
        remoteAttestationAuthFetcher: RemoteAttestationAuthFetcher,
        storageServiceManager: StorageServiceManager,
        svrLocalStorage: SVRLocalStorage,
        tsConstants: TSConstantsProtocol,
        twoFAManager: SVR2.Shims.OWS2FAManager,
    ) {
        self.connectionFactory = connectionFactory
        self.credentialManager = credentialManager
        self.db = db
        self.accountKeyStore = accountKeyStore
        self.localStorage = svrLocalStorage
        self.pinHasher = pinHasher
        self.remoteAttestationAuthFetcher = remoteAttestationAuthFetcher
        self.storageServiceManager = storageServiceManager
        self.tsConstants = tsConstants
        self.twoFAManager = twoFAManager
    }

    // MARK: - Periodic Backups

    public func refreshCredentialsIfNecessary() async throws {
        let hasBackedUp = self.db.read { tx in self.localStorage.isMasterKeyBackedUp(tx: tx) }
        guard hasBackedUp else {
            // If we've never backed up, don't refresh periodically. (If we eventually
            // perform a backup, we'll cache those credential after fetching them.)
            return
        }
        // Force refresh a credential, even if we have one cached, to ensure we
        // have a fresh credential to back up.
        let credential = try await remoteAttestationAuthFetcher.fetchAuth(
            forService: .svr2,
            chatServiceAuth: .implicit(),
        )
        await db.awaitableWrite { tx in
            credentialManager.storeAuthCredentialForCurrentUsername(
                SVR2AuthCredential(credential: credential),
                tx,
            )
        }
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
    ) {
        Logger.info("")
        accountKeyStore.setMediaRootBackupKey(provisioningMessage.mrbk, tx: tx)
        accountKeyStore.setAccountEntropyPool(provisioningMessage.aep, tx: tx)
        accountKeyStore.setWaitingForKeysSyncMessage(false, tx: tx)
    }

    public func storeKeys(
        fromKeysSyncMessage syncMessage: SSKProtoSyncMessageKeys,
        authedDevice: AuthedDevice,
        tx: DBWriteTransaction,
    ) throws(SVR.KeysError) {
        Logger.info("")

        let newMrbk = syncMessage.mediaRootBackupKey.flatMap({ try? BackupKey(contents: $0) })
        guard let newMrbk else {
            throw SVR.KeysError.missingMrbk
        }
        accountKeyStore.setMediaRootBackupKey(MediaRootBackupKey(backupKey: newMrbk), tx: tx)

        let newAep = syncMessage.accountEntropyPool.flatMap({ try? AccountEntropyPool(key: $0) })
        guard let newAep else {
            throw SVR.KeysError.missingAep
        }
        var shouldRestore = false
        if newAep != accountKeyStore.getAccountEntropyPool(tx: tx) {
            accountKeyStore.setAccountEntropyPool(newAep, tx: tx)
            shouldRestore = true
        }
        if accountKeyStore.isWaitingForKeysSyncMessage(tx: tx) {
            accountKeyStore.setWaitingForKeysSyncMessage(false, tx: tx)
            shouldRestore = true
        }
        if shouldRestore {
            // Trigger a re-fetch of the storage manifest if our keys have changed or
            // if we've gotten a key that we requested.
            tx.addSyncCompletion { [storageServiceManager] in
                storageServiceManager.restoreOrCreateManifestIfNecessary(
                    authedDevice: authedDevice,
                    masterKeySource: .implicit,
                )
            }
        }
    }

    // MARK: - Backup/Expose Request

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
        for enclave in tsConstants.svr2Enclaves.prefix(tsConstants.activeSvr2EnclaveCount) {
            try await _doBackupAndExpose(
                pin: pin,
                masterKey: masterKey,
                force: force,
                mrEnclave: enclave,
                authMethod: authMethod,
            )
        }
    }

    private func _doBackupAndExpose(
        pin: String,
        masterKey: MasterKey,
        force: Bool,
        mrEnclave: MrEnclave,
        authMethod: SVR2.AuthMethod,
    ) async throws {
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

        let config = SVR2WebsocketConfigurator(
            mrenclave: mrEnclave,
            authMethod: authMethod,
            remoteAttestationAuthFetcher: remoteAttestationAuthFetcher,
        )

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
            Logger.warn("Expose error; continuing anyways")
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
        for enclave in tsConstants.svr2Enclaves {
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
        let config = SVR2WebsocketConfigurator(
            mrenclave: mrEnclave,
            authMethod: authMethod,
            remoteAttestationAuthFetcher: remoteAttestationAuthFetcher,
        )
        do {
            let connection = try await makeHandshakeAndOpenConnection(config)
            defer { connection.disconnect(code: .normalClosure) }
            Logger.info("Connection open; making restore request")
            return try await self.performRestoreRequest(
                mrEnclave: mrEnclave,
                pin: pin,
                connection: connection,
            )
        }
    }

    private func performRestoreRequest(
        mrEnclave: MrEnclave,
        pin: String,
        connection: SgxWebsocketConnection<SVR2WebsocketConfigurator>,
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
        let config = SVR2WebsocketConfigurator(
            mrenclave: mrEnclave,
            authMethod: authMethod,
            remoteAttestationAuthFetcher: remoteAttestationAuthFetcher,
        )
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
        )
    }

    private func performDeleteRequest(
        mrEnclave: MrEnclave,
        connection: SgxWebsocketConnection<SVR2WebsocketConfigurator>,
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

    private let potentialEnclavesStore = NewKeyValueStore(collection: "SVR.Potential")

    private func getEnclavesToPotentiallyDeleteFrom(_ tx: DBReadTransaction) -> Set<String> {
        return Set(potentialEnclavesStore.fetchKeys(tx: tx))
    }

    private func addEnclaveToPotentiallyDeleteFrom(_ enclave: MrEnclave, _ tx: DBWriteTransaction) {
        potentialEnclavesStore.writeValue(Data(), forKey: enclave.stringValue, tx: tx)
    }

    private func markEnclaveDeleted(_ enclave: String, _ tx: DBWriteTransaction) {
        potentialEnclavesStore.removeValue(forKey: enclave, tx: tx)
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
                let aep = db.read { tx in accountKeyStore.getAccountEntropyPool(tx: tx) }
                if let aep {
                    // If a backup isn't needed, this returns a success immediately.
                    try await doBackupAndExpose(pin: pin, masterKey: aep.getMasterKey(), force: false, authMethod: .implicit)
                } else {
                    Logger.warn("can't back up master key without master key")
                }
            }

            let allEnclaves = tsConstants.svr2Enclaves
            // If we don't have a PIN, we shouldn't keep any enclaves.
            let enclavesToKeep = pin == nil ? 0 : tsConstants.activeSvr2EnclaveCount

            // Require backups (i.e., migrations) to succeed before deleting from old
            // enclaves to ensure we're always backed up to at least one enclave.
            try await wipeObsoleteEnclaves(allEnclaves: allEnclaves, enclavesToKeep: enclavesToKeep)

            if pin == nil {
                let anyCredential = db.read { tx in
                    return credentialManager.getAuthCredentialForCurrentUser(tx)
                }
                if anyCredential != nil {
                    await db.awaitableWrite { tx in
                        credentialManager.removeSVR2CredentialsForCurrentUser(tx)
                    }
                }
            }
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
            if let cachedCredential: SVR2AuthCredential = db.read(block: credentialManager.getAuthCredentialForCurrentUser) {
                config.authMethod = .svrAuth(cachedCredential, backup: .implicit)
            }
        }

        return try await connectionQueue.run {
            while true {
                Logger.info("Opening new connection")
                do {
                    let sgxConnection = try await self.connectionFactory.connectAndPerformHandshake(configurator: config)
                    let knownGoodAuthCredential = sgxConnection.auth
                    if case .implicit = config.authMethod {
                        // If we opened a connection with a credential we fetched, we believe it's
                        // valid. If the credential was fetched implicitly, then we also believe it
                        // belongs to the current account, so we should cache it.
                        await self.db.awaitableWrite { tx in
                            self.credentialManager.storeAuthCredentialForCurrentUsername(
                                SVR2AuthCredential(credential: knownGoodAuthCredential),
                                tx,
                            )
                        }
                    }
                    return sgxConnection
                } catch {
                    Logger.error("Failed to open websocket connection and complete handshake")

                    // if we fail to connect for any reason, assume the credential we tried to use was bad.
                    // clear it out, and if we have a backup, try again with that.
                    switch config.authMethod {
                    case .svrAuth(let attemptedCredential, let backup):
                        await self.db.awaitableWrite { tx in
                            self.credentialManager.deleteInvalidCredentials([attemptedCredential].compacted(), tx)
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
