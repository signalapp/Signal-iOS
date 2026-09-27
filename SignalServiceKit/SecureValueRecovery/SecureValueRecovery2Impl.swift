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
        let shouldBeBackedUp = self.db.read { tx in self.twoFAManager.shouldMasterKeyBeBackedUp(tx: tx) }
        guard shouldBeBackedUp else {
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

    public func backUpMasterKey(pin: String, masterKey: MasterKey, authMethod: SVR.AuthMethod) async throws {
        Logger.info("")
        try await backupQueue.runWithThrowingTask {
            try await doBackupAndExpose(pin: pin, masterKey: masterKey, authMethod: authMethod)
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
        authedAccount: AuthedAccount,
        tx: DBWriteTransaction,
    ) {
        Logger.info("")
        accountKeyStore.setMediaRootBackupKey(provisioningMessage.mrbk, tx: tx)
        accountKeyStore.setAccountEntropyPool(provisioningMessage.aep, tx: tx)
        accountKeyStore.setWaitingForKeysSyncMessage(false, tx: tx)
    }

    public func storeKeys(
        fromKeysSyncMessage syncMessage: SSKProtoSyncMessageKeys,
        authedAccount: AuthedAccount,
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
                    authedAccount: authedAccount,
                    masterKeySource: .implicit,
                )
            }
        }
    }

    // MARK: - Backup/Expose Request

    /// We must be careful to never repeat a backup request after sending an
    /// expose request for the first time. We must do this even if the
    /// connection dies and we lose the response to the expose request. After we
    /// get a success response from a backup request, we set isBackedUp to true
    /// to track that we've started making expose requests, and we only ever
    /// make expose requests from then on until:
    /// 1. The user chooses a different PIN (we will make a new backup request)
    /// 2. The user rotates their master key (we will make a new backup request)
    /// 3. We roll out a new enclave (we will make a new backup request)
    /// 3. The user disables their PIN (we will make a delete request)
    private struct BackupAttempt: Codable {
        let masterKey: Data
        let encryptedMasterKey: Data
        let encodedPINVerificationString: String
        // TODO: Make non-Optional when MrEnclave ced8217b26228e4b210c985786999d095c4958a94faf37b14acaf25c4cbb02a4 doesn't exist.
        var isBackedUp: Bool?
        var isBackedUpOrDefault: Bool { isBackedUp ?? true }
        var isExposed: Bool

        func matches(pin: String, masterKey: MasterKey) -> Bool {
            return (
                SVRUtil.verifyPIN(pin: pin, againstEncodedPINVerificationString: self.encodedPINVerificationString)
                    && masterKey.rawData.ows_constantTimeIsEqual(to: self.masterKey),
            )
        }
    }

    private func getBackupAttempt(forEnclave enclave: MrEnclave, tx: DBReadTransaction) -> BackupAttempt? {
        do {
            return try localStorage.backupAttemptStore.getCodableValue(forKey: enclave.stringValue, transaction: tx)
        } catch {
            // If we fail to decode, something has gone wrong locally. But we can
            // treat this like if we never had a backup; after all the user may uninstall,
            // reinstall, and do a backup again with the same PIN. This, like that, is
            // a local-only trigger.
            Logger.error("couldn't decode BackupAttempt")
            return nil
        }
    }

    private func setBackupAttempt(_ value: BackupAttempt, forEnclave enclave: MrEnclave, tx: DBWriteTransaction) {
        failIfThrows {
            try localStorage.backupAttemptStore.setCodable(optional: value, key: enclave.stringValue, transaction: tx)
        }
    }

    private func removeBackupAttempt(forEnclave enclave: String, tx: DBWriteTransaction) {
        localStorage.backupAttemptStore.removeValue(forKey: enclave, transaction: tx)
    }

    public func invalidateBackupAttemptForEveryEnclave(tx: DBWriteTransaction) {
        for enclave in tsConstants.svr2Enclaves {
            invalidateBackupAttempt(forEnclave: enclave, tx: tx)
        }
    }

    private func invalidateBackupAttempt(forEnclave enclave: MrEnclave, tx: DBWriteTransaction) {
        let invalidBackupAttempt = BackupAttempt(
            masterKey: Data(),
            encryptedMasterKey: Data(),
            encodedPINVerificationString: "",
            isBackedUp: false,
            isExposed: false,
        )
        setBackupAttempt(invalidBackupAttempt, forEnclave: enclave, tx: tx)
    }

    private func doBackupAndExpose(
        pin: String,
        masterKey: MasterKey,
        authMethod: SVR2.AuthMethod,
    ) async throws {
        for enclave in tsConstants.svr2Enclaves.prefix(tsConstants.activeSvr2EnclaveCount) {
            try await _doBackupAndExpose(
                pin: pin,
                masterKey: masterKey,
                mrEnclave: enclave,
                authMethod: authMethod,
            )
        }
    }

    private func _doBackupAndExpose(
        pin: String,
        masterKey: MasterKey,
        mrEnclave: MrEnclave,
        authMethod: SVR2.AuthMethod,
    ) async throws {
        let priorBackup = self.db.read { tx in self.getBackupAttempt(forEnclave: mrEnclave, tx: tx) }

        let priorMatchingBackup: BackupAttempt?
        if
            let priorBackup,
            priorBackup.isBackedUpOrDefault,
            priorBackup.matches(pin: pin, masterKey: masterKey)
        {
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

        var backupAttempt: BackupAttempt
        if let priorMatchingBackup {
            // We already completed a backup for this (pin, masterKey, enclave) triple,
            // so we only want to perform an expose.
            Logger.warn("Skipping backup that was already completed")
            backupAttempt = priorMatchingBackup
        } else {
            // We don't have a backup, or we're trying to back up something else, or
            // we're trying to back up to somewhere else, or we're not sure if we have
            // a backup; we must start fresh in these cases.
            let pinVerifier = try SVRUtil.deriveEncodedPINVerificationString(pin: pin)
            let pinHash = try hashPin(pin, forConnection: connection)
            let encryptedMasterKey = try pinHash.encryptMasterKey(masterKey.rawData)
            backupAttempt = BackupAttempt(
                masterKey: masterKey.rawData,
                encryptedMasterKey: encryptedMasterKey,
                encodedPINVerificationString: pinVerifier,
                isBackedUp: false,
                isExposed: false,
            )
            await self.db.awaitableWrite { tx in
                self.setBackupAttempt(backupAttempt, forEnclave: mrEnclave, tx: tx)
            }
            // After this point, we might have data stored in this enclave, but we're
            // not confident about that until the end of this method. (For example,
            // requests may be applied to the enclave but have their responses lost due
            // to network failures.) The prior line stored this enclave in an
            // unresolved state so that we eventually complete a backup (or delete it
            // if the user disables their PIN). This ensures eventual consistency.
            try await self.performBackupRequest(
                backup: backupAttempt,
                accessKey: pinHash.accessKey,
                connection: connection,
            )
            backupAttempt.isBackedUp = true
            await self.db.awaitableWrite { tx in
                // Write that we've finished to disk; we never want to repeat the prior
                // request after we start sending expose requests.
                self.setBackupAttempt(backupAttempt, forEnclave: mrEnclave, tx: tx)
            }
        }

        // This must be true because it's checked earlier for existing backups and
        // starts out false for new backups.
        owsPrecondition(!backupAttempt.isExposed)

        try await self.performExposeRequest(
            backup: backupAttempt,
            connection: connection,
        )
        backupAttempt.isExposed = true

        await self.db.awaitableWrite { tx in
            self.setBackupAttempt(backupAttempt, forEnclave: mrEnclave, tx: tx)
        }
    }

    private func performBackupRequest(
        backup: BackupAttempt,
        accessKey: Data,
        connection: SgxWebsocketConnection<SVR2WebsocketConfigurator>,
    ) async throws {
        Logger.info("Performing backup")

        var backupRequest = SVR2Proto_BackupRequest()
        backupRequest.maxTries = SVR.maximumKeyAttempts
        backupRequest.pin = accessKey
        backupRequest.data = backup.encryptedMasterKey

        var request = SVR2Proto_Request()
        request.backup = backupRequest

        let response = try await connection.sendRequestAndReadResponse(request)
        guard response.hasBackup else {
            throw OWSGenericError("backup missing from server response")
        }
        switch response.backup.status {
        case .ok:
            Logger.info("Backup success!")
        case .UNRECOGNIZED, .unset:
            throw OWSGenericError("backup status response unknown")
        }
    }

    private func performExposeRequest(
        backup: BackupAttempt,
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
        } catch WebSocketError.httpError(statusCode: 404, retryAfter: _) {
            Logger.warn("skipping restore for non-existent enclave")
            return .backupMissing
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
            // a response (e.g., the connection fails, the app exits). By invalidating
            // this now, we ensure resiliency for new backups after these edge cases.
            invalidateBackupAttempt(forEnclave: mrEnclave, tx: tx)
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

    // Partially deprecated
    private let potentialEnclavesStore = NewKeyValueStore(collection: "SVR.Potential")

    private func getEnclavesToPotentiallyDeleteFrom(_ tx: DBReadTransaction) -> Set<String> {
        let modernEnclaves = localStorage.backupAttemptStore.allKeys(transaction: tx)
        // When this fails, legacy enclaves have been torn down, and we don't need
        // to delete anything from them. We should delete `legacyEnclaves` (and
        // DELETE its contents) at that point in time.
        assert({
            let migrationEnclaves = Set([
                // Production
                "ced8217b26228e4b210c985786999d095c4958a94faf37b14acaf25c4cbb02a4",
                "1240acbd4aa26974184844c8a46b1022d3957ac8a76c1fd8f5b1a15141ee0708",
                "29cd63c87bea751e3bfd0fbd401279192e2e5c99948b4ee9437eafc4968355fb",

                // Staging
                "3c699f4975aaa3d172c0aad042f94f031b2b03e10b9c19a45116a01693d83302",
                "97f151f6ed078edbbfd72fa9cae694dcc08353f1f5e8d9ccd79a971b10ffc535",
                "a75542d82da9f6914a1e31f8a7407053b99cc99a0e7291d8fbd394253e19b036",
            ])
            let allEnclaves = TSConstants.svr2Enclaves
            let shouldUseLegacyEnclaves = !migrationEnclaves.isDisjoint(with: allEnclaves.lazy.map(\.stringValue))
            return shouldUseLegacyEnclaves
        }())
        let legacyEnclaves = potentialEnclavesStore.fetchKeys(tx: tx)
        return Set(legacyEnclaves + modernEnclaves)
    }

    private func markEnclaveDeleted(_ enclave: String, _ tx: DBWriteTransaction) {
        removeBackupAttempt(forEnclave: enclave, tx: tx)
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
            } catch WebSocketError.httpError(statusCode: 404, retryAfter: _) {
                // The enclave doesn't exist.
                Logger.warn("skipping wipe for non-existent enclave")
            } catch {
                Logger.warn("couldn't wipe enclave; may retry eventually: \(error)")
                firstError = firstError ?? error
                continue
            }
            await db.awaitableWrite { tx in
                markEnclaveDeleted(obsoleteEnclave.stringValue, tx)
            }
        }
        for unknownEnclave in potentialEnclaves {
            Logger.warn("pruning unknown enclave: \(unknownEnclave)")
            await db.awaitableWrite { tx in
                markEnclaveDeleted(unknownEnclave, tx)
            }
        }
        if let firstError {
            throw firstError
        }
    }

    // MARK: - Migrations

    public func refreshBackupIfNecessary() async throws {
        try await backupQueue.runWithThrowingTask {
            let pin = db.read(block: twoFAManager.pinCode(transaction:))

            if let pin {
                let aep = db.read { tx in accountKeyStore.getAccountEntropyPool(tx: tx) }
                if let aep {
                    // If a backup isn't needed, this returns a success immediately.
                    try await doBackupAndExpose(pin: pin, masterKey: aep.getMasterKey(), authMethod: .implicit)
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

        return try await connectionQueue.runWithThrowingTask {
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
                    Logger.warn("couldn't open web socket: \(error)")
                    if case WebSocketError.httpError(statusCode: 401, retryAfter: _) = error {
                        // If the credential isn't valid, clear it out and try with a backup.
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
            return backup?.authedAccount ?? .implicit
        case .chatServerAuth(let authedAccount):
            return authedAccount
        case .implicit:
            return .implicit
        }
    }
}
