//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

/// Implementation of `SecureValueRecovery` that talks to the SVR2 server.
public class SecureValueRecovery2Impl: SecureValueRecovery {

    private let clientWrapper: SVR2ClientWrapper
    private let connectionFactory: SgxWebsocketConnectionFactory
    private let credentialStorage: SVRAuthCredentialStorage
    private let db: DB
    private let keyValueStoreFactory: KeyValueStoreFactory
    private let localStorage: SVRLocalStorage
    private let schedulers: Schedulers
    private let storageServiceManager: StorageServiceManager
    private let syncManager: SyncManagerProtocolSwift
    private let tsAccountManager: SVR.Shims.TSAccountManager
    private let twoFAManager: SVR.Shims.OWS2FAManager

    public convenience init(
        connectionFactory: SgxWebsocketConnectionFactory,
        credentialStorage: SVRAuthCredentialStorage,
        db: DB,
        keyValueStoreFactory: KeyValueStoreFactory,
        schedulers: Schedulers,
        storageServiceManager: StorageServiceManager,
        syncManager: SyncManagerProtocolSwift,
        tsAccountManager: SVR.Shims.TSAccountManager,
        twoFAManager: SVR.Shims.OWS2FAManager
    ) {
        self.init(
            clientWrapper: SVR2ClientWrapperImpl(),
            connectionFactory: connectionFactory,
            credentialStorage: credentialStorage,
            db: db,
            keyValueStoreFactory: keyValueStoreFactory,
            schedulers: schedulers,
            storageServiceManager: storageServiceManager,
            syncManager: syncManager,
            tsAccountManager: tsAccountManager,
            twoFAManager: twoFAManager
        )
    }

    private let scheduler: Scheduler

    internal init(
        clientWrapper: SVR2ClientWrapper,
        connectionFactory: SgxWebsocketConnectionFactory,
        credentialStorage: SVRAuthCredentialStorage,
        db: DB,
        keyValueStoreFactory: KeyValueStoreFactory,
        schedulers: Schedulers,
        storageServiceManager: StorageServiceManager,
        syncManager: SyncManagerProtocolSwift,
        tsAccountManager: SVR.Shims.TSAccountManager,
        twoFAManager: SVR.Shims.OWS2FAManager
    ) {
        self.clientWrapper = clientWrapper
        self.connectionFactory = connectionFactory
        self.credentialStorage = credentialStorage
        self.db = db
        self.keyValueStoreFactory = keyValueStoreFactory
        self.localStorage = SVRLocalStorage(keyValueStoreFactory: keyValueStoreFactory)
        self.schedulers = schedulers
        self.storageServiceManager = storageServiceManager
        self.syncManager = syncManager
        self.tsAccountManager = tsAccountManager
        self.twoFAManager = twoFAManager

        self.scheduler = schedulers.queue(label: "org.signal.svr2", qos: .userInitiated)
    }

    public func warmCaches() {
        fatalError("Unimplemented!")
    }

    // MARK: - Key Existence

    public func hasMasterKey(transaction: DBReadTransaction) -> Bool {
        return localStorage.getMasterKey(transaction) != nil
    }

    public func hasBackedUpMasterKey(transaction: DBReadTransaction) -> Bool {
        return localStorage.getIsMasterKeyBackedUp(transaction)
    }

    public func setMasterKeyBackedUp(_ value: Bool, transaction: DBWriteTransaction) {
        localStorage.setIsMasterKeyBackedUp(value, transaction)
    }

    public func useDeviceLocalMasterKey(authedAccount: AuthedAccount, transaction: DBWriteTransaction) {
        setLocalDataAndSyncStorageServiceIfNeeded(
            masterKey: Cryptography.generateRandomBytes(SVR.masterKeyLengthBytes),
            isMasterKeyBackedUp: false,
            pinType: .alphanumeric,
            encodedPINVerificationString: nil,
            mrEnclaveStringValue: nil,
            authedAccount: authedAccount,
            transaction: transaction
        )
        // Disable the PIN locally.
        twoFAManager.markDisabled(transaction: transaction)

        // Wipe credentials; they're now useless.
        credentialStorage.removeSVR2CredentialsForCurrentUser(transaction)

        // TODO: wipe tokens and any in progress SVR backups; they're now useless.

        // We should update account attributes so we wipe the reglock and
        // reg recovery password.
        tsAccountManager.scheduleAccountAttributesUpdate(authedAccount: authedAccount, transaction: transaction)
    }

    // MARK: - PIN Management

    public func currentPinType(transaction: DBReadTransaction) -> SVR.PinType? {
        return localStorage.getPinType(transaction)
    }

    public func verifyPin(_ pin: String, resultHandler: @escaping (Bool) -> Void) {
        // Kick off to a background thread to do expensive cryptography operations.
        schedulers.global().async { [schedulers, localStorage, db] in
            var isValid = false
            defer {
                schedulers.main.async { resultHandler(isValid) }
            }

            guard let encodedVerificationString = db.read(block: { tx in
                localStorage.getEncodedPINVerificationString(tx)
            }) else {
                owsFailDebug("Attempted to verify pin locally when we don't have a verification string")
                return
            }

            isValid = SVRUtil.verifyPIN(pin: pin, againstEncodedPINVerificationString: encodedVerificationString)
        }
    }

    // MARK: - Key Management

    public func acquireRegistrationLockForNewNumber(with pin: String, and auth: SVRAuthCredential) -> Promise<String> {
        fatalError("Unimplemented!")
    }

    public func generateAndBackupKeys(pin: String, authMethod: SVR.AuthMethod, rotateMasterKey: Bool) -> Promise<Void> {
        return firstly(on: scheduler) { [weak self] () -> Promise<Void> in
            guard let self else {
                return .init(error: SVR.SVRError.assertion)
            }
            let masterKey: Data = {
                if !rotateMasterKey, let masterKey = self.db.read(block: { tx in self.localStorage.getMasterKey(tx) }) {
                    return masterKey
                }
                return self.generateMasterKey()
            }()
            return self.doBackupAndExpose(pin: pin, masterKey: masterKey, authMethod: authMethod)
        }
    }

    public func restoreKeysAndBackup(pin: String, authMethod: SVR.AuthMethod) -> Guarantee<SVR.RestoreKeysResult> {
        fatalError("Unimplemented!")
    }

    public func deleteKeys() -> Promise<Void> {
        fatalError("Unimplemented!")
    }

    public func clearKeys(transaction: DBWriteTransaction) {
        // TODO: wipe tokens and any in progress SVR backups
        localStorage.clearKeys(transaction)
    }

    // MARK: - Master Key Encryption

    public func encrypt(
        keyType: SVR.DerivedKey,
        data: Data,
        transaction: DBReadTransaction
    ) -> SVR.ApplyDerivedKeyResult {
        guard let keyData = self.data(for: keyType, transaction: transaction) else {
            return .masterKeyMissing
        }
        do {
            return .success(try Aes256GcmEncryptedData.encrypt(data, key: keyData.rawData).concatenate())
        } catch let error {
            return .cryptographyError(error)
        }
    }

    public func decrypt(
        keyType: SVR.DerivedKey,
        encryptedData: Data,
        transaction: DBReadTransaction
    ) -> SVR.ApplyDerivedKeyResult {
        guard let keyData = self.data(for: keyType, transaction: transaction) else {
            return .masterKeyMissing
        }
        do {
            return .success(try Aes256GcmEncryptedData(concatenated: encryptedData).decrypt(key: keyData.rawData))
        } catch let error {
            return .cryptographyError(error)
        }
    }

    public func storeSyncedStorageServiceKey(data: Data?, authedAccount: AuthedAccount, transaction: DBWriteTransaction) {
        localStorage.setSyncedStorageServiceKey(data, transaction)

        // Trigger a re-fetch of the storage manifest, our keys have changed
        if data != nil {
            storageServiceManager.restoreOrCreateManifestIfNecessary(authedAccount: authedAccount)
        }
    }

    // MARK: - Value Derivation

    public func data(for key: SVR.DerivedKey, transaction: DBReadTransaction) -> SVR.DerivedKeyData? {
        // If we are a linked device, we don't have the master key. But we might
        // have the storage service derived key in local storage, which we got from
        // a sync message. Check for that first.
        if key == .storageService, let data = localStorage.getSyncedStorageServiceKey(transaction) {
            return SVR.DerivedKeyData(data, .storageService)
        }

        guard let rootKeyData = rootKeyData(for: key, transaction: transaction) else {
            return nil
        }
        return SVR.DerivedKeyData(key.derivedData(from: rootKeyData), key)
    }

    public func isKeyAvailable(_ key: SVR.DerivedKey, transaction: DBReadTransaction) -> Bool {
        return data(for: key, transaction: transaction) != nil
    }

    // MARK: - Backup/Expose Request

    private lazy var kvStore = keyValueStoreFactory.keyValueStore(collection: "SecureValueRecovery2Impl")

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
        let rawPinType: Int
        let encodedPINVerificationString: String
        // If we make a backup to one mrenclave, then update the mrenclave,
        // we are safe to drop it and start again with a backup to the new
        // mrenclave.
        let mrEnclaveStringValue: String

        func matches(
            pin: String,
            mrEnclave: MrEnclave
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

        var pinType: SVR.PinType {
            return SVR.PinType(rawValue: rawPinType) ?? .alphanumeric
        }
    }

    private static let inProgressBackupKey = "InProgressBackup"

    private func getInProgressBackup(_ tx: DBReadTransaction) throws -> InProgressBackup? {
        return try kvStore.getCodableValue(forKey: Self.inProgressBackupKey, transaction: tx)
    }

    private func setInProgressBackup(_ value: InProgressBackup, _ tx: DBWriteTransaction) throws {
        try kvStore.setCodable(optional: value, key: Self.inProgressBackupKey, transaction: tx)
    }

    private func clearInProgressBackup(_ tx: DBWriteTransaction) {
        kvStore.removeValue(forKey: Self.inProgressBackupKey, transaction: tx)
    }

    private func doBackupAndExpose(
        pin: String,
        masterKey: Data,
        authMethod: SVR.AuthMethod
    ) -> Promise<Void> {
        let config = SVR2WebsocketConfigurator(authMethod: authMethod)
        return makeHandshakeAndOpenConnection(config)
            .then(on: scheduler) { [weak self] connection -> Promise<Void> in
                guard let self else {
                    return .init(error: SVR.SVRError.assertion)
                }

                let weakSelf = Weak(value: self)
                func continueWithExpose(backup: InProgressBackup) -> Promise<Void> {
                    guard let self = weakSelf.value else {
                        return .init(error: SVR.SVRError.assertion)
                    }
                    return self
                        .performExposeRequest(
                            backup: backup,
                            authedAccount: authMethod.authedAccount,
                            connection: connection
                        )
                        .then(on: self.schedulers.sync) { result -> Promise<Void> in
                            switch result {
                            case .success:
                                return .value(())
                            case .serverError, .networkError, .unretainedError, .localPersistenceError:
                                return .init(error: SVR.SVRError.assertion)
                            }
                        }
                }

                func startFreshBackupExpose() -> Promise<Void> {
                    return self
                        .performBackupRequest(
                            pin: pin,
                            masterKey: masterKey,
                            mrEnclave: config.mrenclave,
                            connection: connection
                        )
                        .then(on: self.scheduler) { (backupResult: BackupResult) -> Promise<Void> in
                            switch backupResult {
                            case .serverError, .networkError, .localPersistenceError, .localEncryptionError, .unretainedError:
                                return .init(error: SVR.SVRError.assertion)
                            case .success(let inProgressBackup):
                                return continueWithExpose(backup: inProgressBackup)
                            }
                        }
                }

                // Check if we had an in flight backup.
                let inProgressBackup: InProgressBackup?
                do {
                    inProgressBackup = try self.db.read(block: self.getInProgressBackup)
                } catch {
                    // If we fail to decode, something has gone wrong locally. But we can
                    // treat this like if we never had a backup; after all the user may uninstall,
                    // reinstall, and do a backup again with the same PIN. This, like that, is
                    // a local-only trigger.
                    Logger.error("Failed to decode in progress backup state")
                    inProgressBackup = nil
                }
                if let inProgressBackup {
                    if inProgressBackup.matches(pin: pin, mrEnclave: config.mrenclave) {
                        // Continue the backup from where we left off.
                        return continueWithExpose(backup: inProgressBackup)
                    } else {
                        // We had an in flight backup, but for a different PIN.
                        // If its expose hasn't started, it should stop itself.
                        Logger.info("Cancelling in progress backup because master key changed")
                        return startFreshBackupExpose()
                    }
                } else {
                    return startFreshBackupExpose()
                }

            }
    }

    private enum BackupResult {
        case success(InProgressBackup)
        case localEncryptionError
        case localPersistenceError
        case networkError
        case serverError
        case unretainedError
    }

    private func performBackupRequest(
        pin: String,
        masterKey: Data,
        mrEnclave: MrEnclave,
        connection: WebsocketConnection
    ) -> Guarantee<BackupResult> {
        guard
            let normalizedPinData = SVRUtil.normalizePin(pin).data(using: .utf8),
            let encodedPINVerificationString = try? SVRUtil.deriveEncodedPINVerificationString(pin: pin),
            let usernameData = connection.auth.username.data(using: .utf8)
        else {
            return .value(.localEncryptionError)
        }
        let pinHashResult: SVR2.PinHashResult
        do {
            pinHashResult = try connection.hashPinAndEncryptMasterKey(
                wrapper: clientWrapper,
                utf8Pin: normalizedPinData,
                utf8Username: usernameData,
                masterKey: masterKey
            )
        } catch {
            return .value(.localEncryptionError)
        }

        var backupRequest = SVR2Proto_BackupRequest()
        backupRequest.maxTries = SVR.maximumKeyAttempts
        backupRequest.pin = pinHashResult.accessKey
        backupRequest.data = pinHashResult.encryptedMasterKey

        var request = SVR2Proto_Request()
        request.backup = backupRequest

        return connection.sendRequestAndReadResponse(request, unretainedError: .unretainedError) { [weak self] makeRequest in
            guard let self else {
                return .value(.unretainedError)
            }
            return makeRequest().map(on: self.scheduler) { [weak self] (response: SVR2Proto_Response) -> BackupResult in
                guard let self else {
                    return .unretainedError
                }
                guard response.hasBackup else {
                    return .serverError
                }
                switch response.backup.status {
                case .ok:
                    let inProgressBackup = InProgressBackup(
                        masterKey: masterKey,
                        encryptedMasterKey: pinHashResult.encryptedMasterKey,
                        rawPinType: SVR.PinType(forPin: pin).rawValue,
                        encodedPINVerificationString: encodedPINVerificationString,
                        mrEnclaveStringValue: mrEnclave.stringValue
                    )
                    do {
                        // Write the in progress state to disk; we want to continue
                        // from here and not redo the backup request.
                        try self.db.write { tx in
                            try self.setInProgressBackup(inProgressBackup, tx)
                        }
                    } catch {
                        return .localPersistenceError
                    }
                    return .success(inProgressBackup)
                case .UNRECOGNIZED, .unset:
                    return .serverError
                }
            }
            .recover(on: self.schedulers.sync) { error in
                if error.isNetworkFailureOrTimeout {
                    return .value(.networkError)
                } else {
                    return .value(.serverError)
                }
            }
        }
    }

    private enum ExposeResult {
        case success
        case localPersistenceError
        case networkError
        case serverError
        case unretainedError
    }

    private func performExposeRequest(
        backup: InProgressBackup,
        authedAccount: AuthedAccount,
        connection: WebsocketConnection
    ) -> Guarantee<ExposeResult> {
        var exposeRequest = SVR2Proto_ExposeRequest()
        exposeRequest.data = backup.encryptedMasterKey
        var request = SVR2Proto_Request()
        request.expose = exposeRequest
        return connection.sendRequestAndReadResponse(request, unretainedError: .unretainedError) { [weak self] makeRequest in
            guard let self else {
                return .value(.unretainedError)
            }
            // Check that the backup is still the latest before we actually
            // issue the request.
            let currentBackup: InProgressBackup?
            do {
                currentBackup = try self.db.read { return try self.getInProgressBackup($0) }
            } catch {
                return .value(.localPersistenceError)
            }
            if let currentBackup, backup.matches(currentBackup).negated {
                // This expose is out of date. But its fine to let the caller
                // think it was a success; the backup that took its place
                // is now in charge and this one is done and shouldn't be repeated.
                return .value(.success)
            }
            return makeRequest().map(on: self.scheduler) { [weak self] (response) -> ExposeResult in
                guard let self else {
                    return .unretainedError
                }
                guard response.hasExpose else {
                    return .serverError
                }
                switch response.expose.status {
                case .ok:
                    self.db.write { tx in
                        self.clearInProgressBackup(tx)
                        self.setLocalDataAndSyncStorageServiceIfNeeded(
                            masterKey: backup.masterKey,
                            isMasterKeyBackedUp: true,
                            pinType: backup.pinType,
                            encodedPINVerificationString: backup.encodedPINVerificationString,
                            mrEnclaveStringValue: backup.mrEnclaveStringValue,
                            authedAccount: authedAccount,
                            transaction: tx
                        )
                    }
                    return .success
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
                    Logger.error("Got error response when exposing on SVR2 server; something has gone horribly wrong.")
                    return .serverError
                case .UNRECOGNIZED, .unset:
                    return .serverError
                }
            }
            .recover(on: self.schedulers.sync) { error in
                if error.isNetworkFailureOrTimeout {
                    return .value(.networkError)
                } else {
                    return .value(.serverError)
                }
            }
        }
    }

    // MARK: - Opening websocket

    /// A connection that manages its own lifecycle and executes all requests in serial.
    ///
    /// In general, we open a connection, make a few requests, and close it.
    /// 1) We ensure all requests happen in serial; if a second request comes in before the first
    ///   has goten a response, we make it wait for the response (and all response handling)
    ///   before continuing.
    /// 2) Instead of managing the open/close in our request creation code, we do that here:
    ///   we keep track of how many requests are going out, decrement when they finish,
    ///   and close the connection when there are none left.
    private class WebsocketConnection {
        private let connection: SgxWebsocketConnection<SVR2WebsocketConfigurator>
        private let scheduler: Scheduler
        private let onDisconnect: () -> Void

        var auth: RemoteAttestation.Auth { connection.auth }

        init(
            connection: SgxWebsocketConnection<SVR2WebsocketConfigurator>,
            scheduler: Scheduler,
            onDisconnect: @escaping () -> Void
        ) {
            self.connection = connection
            self.scheduler = scheduler
            self.onDisconnect = onDisconnect
        }

        private var requestQueue = [() -> Promise<Void>]()
        private var isMakingRequest = false

        private func startNextRequestIfPossible() {
            guard !isMakingRequest else {
                return
            }
            if requestQueue.isEmpty {
                self.scheduleDisconnectIfNeeded()
                return
            }
            let nextRequest = requestQueue.removeFirst()
            self.isMakingRequest = true
            nextRequest().ensure(on: scheduler) { [weak self] in
                self?.isMakingRequest = false
                self?.startNextRequestIfPossible()
            }.cauterize()
        }

        /// Should only be called from the scheduler's queue.
        /// - Parameter handler: Called once all previously enqueued requests have gotten a response
        ///  AND executed the contents of their handlers. Anything you want done before another request
        ///  starts should happen before the resolution of the promise returned by this handler.
        func sendRequestAndReadResponse<T>(
            _ request: SVR2Proto_Request,
            unretainedError: T,
            handler: @escaping (() -> Promise<SVR2Proto_Response>) -> Guarantee<T>
        ) -> Guarantee<T> {
            let (returnedGuarantee, returnedFuture) = Guarantee<T>.pending()
            requestQueue.append({ [weak self] () -> Promise<Void> in
                guard let self else {
                    returnedFuture.resolve(unretainedError)
                    return .init(error: SVR.SVRError.assertion)
                }
                let guarantee = handler({ self.connection.sendRequestAndReadResponse(request) })
                returnedFuture.resolve(on: self.scheduler, with: guarantee)
                return guarantee.asVoid(on: SyncScheduler())
            })
            startNextRequestIfPossible()
            return returnedGuarantee
        }

        private func scheduleDisconnectIfNeeded() {
            // Give a little leeway to start another request, after
            // which if nothing is happening we can close the connection.
            self.scheduler.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                if self?.requestQueue.isEmpty == true {
                    self?.disconnect()
                }
            }
        }

        private var isDisconnected = false

        private func disconnect() {
            guard !isDisconnected else {
                return
            }
            isDisconnected = true
            connection.disconnect()
            onDisconnect()
        }

        deinit {
            disconnect()
        }

        func hashPinAndEncryptMasterKey(
            wrapper: SVR2ClientWrapper,
            utf8Pin: Data,
            utf8Username: Data,
            masterKey: Data
        ) throws -> SVR2.PinHashResult {
            try wrapper.hashPinAndEncryptMasterKey(
                connection: connection,
                utf8Pin: utf8Pin,
                utf8Username: utf8Username,
                masterKey: masterKey
            )
        }
    }

    /// Maps from mrenclave string to open connection.
    /// A single connection makes all requests in serial; the next isn't made until we get a response.
    private var openConnectionByMrEnclaveString: [String: WebsocketConnection] = [:]

    private lazy var openConnectionChainedPromise = ChainedPromise<WebsocketConnection?>(initialValue: nil, scheduler: scheduler)

    private func makeHandshakeAndOpenConnection(_ config: SVR2WebsocketConfigurator) -> Promise<WebsocketConnection> {
        var innerError: Error = SVR.SVRError.assertion
        return openConnectionChainedPromise.enqueue(recoverValue: nil) { [weak self] (_: WebsocketConnection?) -> Promise<WebsocketConnection?> in
            guard let self else {
                return .init(error: SVR.SVRError.assertion)
            }
            if let openConnection = self.openConnectionByMrEnclaveString[config.mrenclave.stringValue] {
                return .value(openConnection)
            }
            return self.connectionFactory
                .connectAndPerformHandshake(
                    configurator: config,
                    on: self.scheduler
                )
                .then(on: self.scheduler) { [weak self] connection -> Promise<WebsocketConnection?> in
                    guard let self else {
                        return .init(error: SVR.SVRError.assertion)
                    }
                    let connection = WebsocketConnection(
                        connection: connection,
                        scheduler: self.scheduler,
                        onDisconnect: { [weak self] in
                            self?.openConnectionByMrEnclaveString[config.mrenclave.stringValue] = nil
                        }
                    )
                    self.openConnectionByMrEnclaveString[config.mrenclave.stringValue] = connection
                    return .value(connection)
                }
                .recover(on: self.schedulers.sync) { error -> Promise<WebsocketConnection?> in
                    innerError = error
                    return .init(error: error)
                }
        }.then(on: schedulers.sync) { connection -> Promise<WebsocketConnection> in
            if let connection {
                return .value(connection)
            } else {
                return .init(error: innerError)
            }
        }
    }

    // MARK: - Master key generation

    func generateMasterKey() -> Data {
        return Cryptography.generateRandomBytes(SVR.masterKeyLengthBytes)
    }

    // MARK: - Local key storage helpers

    private func rootKeyData(for key: SVR.DerivedKey, transaction: DBReadTransaction) -> Data? {
        switch key {
        case .storageServiceManifest, .storageServiceRecord:
            // StorageService manifest and record keys are derived from
            // the root storageService key, which itself is derived from
            // the svr master key.
            // Linked devices have the storage service key but not the master key,
            // so try that first before doing the double derivation from the master key.
            if let storageServiceData = localStorage.getSyncedStorageServiceKey(transaction) {
                return storageServiceData
            } else if let masterKey = localStorage.getMasterKey(transaction) {
                return SVR.DerivedKey.storageService.derivedData(from: masterKey)
            } else {
                return nil
            }
        case .storageService, .registrationLock, .registrationRecoveryPassword:
            // Most keys derive directly from the master key.
            return localStorage.getMasterKey(transaction)
        }
    }

    private func setLocalDataAndSyncStorageServiceIfNeeded(
        masterKey: Data,
        isMasterKeyBackedUp: Bool,
        pinType: SVR.PinType,
        encodedPINVerificationString: String?,
        mrEnclaveStringValue: String?,
        authedAccount: AuthedAccount,
        transaction: DBWriteTransaction
    ) {
        let masterKeyChanged = masterKey != localStorage.getMasterKey(transaction)
        if masterKeyChanged {
            localStorage.setMasterKey(masterKey, transaction)
        }
        if isMasterKeyBackedUp != localStorage.getIsMasterKeyBackedUp(transaction) {
            localStorage.setIsMasterKeyBackedUp(isMasterKeyBackedUp, transaction)
        }
        if pinType != localStorage.getPinType(transaction) {
            localStorage.setPinType(pinType, transaction)
        }
        if encodedPINVerificationString != localStorage.getEncodedPINVerificationString(transaction) {
            localStorage.setEncodedPINVerificationString(encodedPINVerificationString, transaction)
        }
        if mrEnclaveStringValue != localStorage.getSVR2MrEnclaveStringValue(transaction) {
            localStorage.setSVR2MrEnclaveStringValue(mrEnclaveStringValue, transaction)
        }

        // Only continue if we didn't previously have a master key or our master key has changed
        guard masterKeyChanged, tsAccountManager.isRegisteredAndReady(transaction: transaction) else { return }

        // Trigger a re-creation of the storage manifest, our keys have changed
        storageServiceManager.resetLocalData(transaction: transaction)

        // If the app is ready start that restoration.
        guard AppReadiness.isAppReady else { return }

        storageServiceManager.restoreOrCreateManifestIfNecessary(authedAccount: authedAccount)

        let syncManager = self.syncManager
        storageServiceManager.waitForPendingRestores().observe { _ in
            // Sync our new keys with linked devices, but wait until the storage
            // service restore is done. That way we avoid the linked device getting
            // the new keys first, failing to decrypt old storage service data,
            // and asking for new keys even though thats not the problem.
            // We don't wanna miss sending one of these, though, so go ahead and send it
            // even if it fails. In any scenario it should eventually recover once
            // both storage service and the linked device have the latest stuff.
            syncManager.sendKeysSyncMessage()
        }
    }
}

fileprivate extension SVR.AuthMethod {

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
