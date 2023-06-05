//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalCoreKit

public class KeyBackupServiceImpl: SecureValueRecovery {

    // MARK: - Init

    private let appContext: AppContext
    private let accountManager: SVR.Shims.TSAccountManager
    private let credentialStorage: SVRAuthCredentialStorage
    private let db: DB
    private let keyValueStoreFactory: KeyValueStoreFactory
    private let legacyStateManager: LegacyKbsStateManager
    private let localStorage: SVRLocalStorage
    private let remoteAttestation: SVR.Shims.RemoteAttestation
    private let schedulers: Schedulers
    private let signalService: OWSSignalServiceProtocol
    private let storageServiceManager: StorageServiceManager
    private let syncManager: SyncManagerProtocolSwift
    private let tsConstants: TSConstantsProtocol
    private let twoFAManager: SVR.Shims.OWS2FAManager

    public init(
        accountManager: SVR.Shims.TSAccountManager,
        appContext: AppContext,
        credentialStorage: SVRAuthCredentialStorage,
        databaseStorage: DB,
        keyValueStoreFactory: KeyValueStoreFactory,
        remoteAttestation: SVR.Shims.RemoteAttestation,
        schedulers: Schedulers,
        signalService: OWSSignalServiceProtocol,
        storageServiceManager: StorageServiceManager,
        syncManager: SyncManagerProtocolSwift,
        tsConstants: TSConstantsProtocol,
        twoFAManager: SVR.Shims.OWS2FAManager
    ) {
        self.accountManager = accountManager
        self.appContext = appContext
        self.credentialStorage = credentialStorage
        self.db = databaseStorage
        self.keyValueStoreFactory = keyValueStoreFactory
        self.legacyStateManager = LegacyKbsStateManager(keyValueStoreFactory: keyValueStoreFactory)
        self.localStorage = SVRLocalStorage(keyValueStoreFactory: keyValueStoreFactory)
        self.remoteAttestation = remoteAttestation
        self.schedulers = schedulers
        self.signalService = signalService
        self.storageServiceManager = storageServiceManager
        self.syncManager = syncManager
        self.tsConstants = tsConstants
        self.twoFAManager = twoFAManager
    }

    // MARK: - Pin Management

    private var currentEnclave: KeyBackupEnclave { return tsConstants.keyBackupEnclave }

    public func hasBackedUpMasterKey(transaction: DBReadTransaction) -> Bool {
        return getOrLoadState(transaction: transaction).isMasterKeyBackedUp
    }

    public func hasMasterKey(transaction: DBReadTransaction) -> Bool {
        return getOrLoadState(transaction: transaction).masterKey != nil
    }

    public func currentPinType(transaction: DBReadTransaction) -> SVR.PinType? {
        return getOrLoadState(transaction: transaction).pinType
    }

    /// Indicates whether your pin is valid when compared to your stored keys.
    /// This is a local verification and does not make any requests to the KBS.
    public func verifyPin(_ pin: String, resultHandler: @escaping (Bool) -> Void) {
        schedulers.global().async { [schedulers] in
            var isValid = false
            defer {
                schedulers.main.async { resultHandler(isValid) }
            }

            guard let encodedVerificationString = self.getOrLoadStateWithSneakyTransaction().encodedVerificationString else {
                owsFailDebug("Attempted to verify pin locally when we don't have a verification string")
                return
            }

            isValid = SVRUtil.verifyPIN(pin: pin, againstEncodedPINVerificationString: encodedVerificationString)
        }
    }

    // When changing number, we need to verify the PIN against the new number's KBS
    // record in order to generate a registration lock token. It's important that this
    // happens without touching any of the state we maintain around our account.
    public func acquireRegistrationLockForNewNumber(with pin: String, and auth: SVRAuthCredential) -> Promise<String> {
        // When restoring your backup we want to check the current enclave first,
        // and then fallback to previous enclaves if the current enclave has no
        // record of you. It's important that these are ordered from neweset enclave
        // to oldest enclave, so we start with the newest enclave and then progressively
        // check older enclaves.
        let enclavesToCheck = [TSConstants.keyBackupEnclave] + TSConstants.keyBackupPreviousEnclaves
        return acquireRegistrationLockForNewNumber(pin: pin, auth: auth, enclavesToCheck: enclavesToCheck)
    }

    private func acquireRegistrationLockForNewNumber(
        pin: String,
        auth: SVRAuthCredential,
        enclavesToCheck: [KeyBackupEnclave]
    ) -> Promise<String> {
        guard let enclave = enclavesToCheck.first else {
            owsFailDebug("Unexpectedly tried to acquire registration lock with no specified enclaves")
            return Promise(error: SVR.SVRError.assertion)
        }
        return acquireRegistrationLockForNewNumber(
            pin: pin,
            auth: auth,
            enclave: enclave
        ).recover { error -> Promise<String> in
            if case SVR.SVRError.backupMissing = error, enclavesToCheck.count > 1 {
                // There's no backup on this enclave, but we have more enclaves we can try.
                return self.acquireRegistrationLockForNewNumber(pin: pin, auth: auth, enclavesToCheck: Array(enclavesToCheck.dropFirst()))
            }

            throw error
        }
    }

    private func acquireRegistrationLockForNewNumber(
        pin: String,
        auth: SVRAuthCredential,
        enclave: KeyBackupEnclave
    ) -> Promise<String> {
        Logger.info("Attempting to acquire registration lock from enclave \(enclave.name)")

        return restoreKeys(
            pin: pin,
            auth: auth.kbsAuthMethod,
            enclave: enclave,
            ignoreCachedToken: true
        ).map(on: schedulers.global()) { restoredKeys -> String in
            guard let registrationLockToken = SVR.DerivedKey.registrationLock.derivedData(from: restoredKeys.masterKey)?.hexadecimalString else {
                owsFailDebug("Failed to derive registration lock token")
                throw SVR.SVRError.assertion
            }
            return registrationLockToken
        }.recover(on: schedulers.global()) { error -> Promise<String> in
            owsAssertDebug(error is SVR.SVRError, "Unexpectedly surfacing a non KBS error \(error)")
            throw error
        }
    }

    public func restoreKeys(pin: String, authMethod: SVR.AuthMethod) -> Guarantee<SVR.RestoreKeysResult> {
        // When restoring your backup we want to check the current enclave first,
        // and then fallback to previous enclaves if the current enclave has no
        // record of you. It's important that these are ordered from newest enclave
        // to oldest enclave, so we start with the newest enclave and then progressively
        // check older enclaves.
        let enclavesToCheck = [TSConstants.keyBackupEnclave] + TSConstants.keyBackupPreviousEnclaves
        guard let authMethod = authMethod.kbs else {
            return .value(.genericError(SVR.SVRError.assertion))
        }
        return restoreKeys(pin: pin, auth: authMethod, enclavesToCheck: enclavesToCheck)
    }

    public func restoreKeysAndBackup(pin: String, authMethod: SVR.AuthMethod) -> Guarantee<SVR.RestoreKeysResult> {
        // When restoring your backup we want to check the current enclave first,
        // and then fallback to previous enclaves if the current enclave has no
        // record of you. It's important that these are ordered from newest enclave
        // to oldest enclave, so we start with the newest enclave and then progressively
        // check older enclaves.
        let enclavesToCheck = [TSConstants.keyBackupEnclave] + TSConstants.keyBackupPreviousEnclaves
        guard let authMethod = authMethod.kbs else {
            return .value(.genericError(SVR.SVRError.assertion))
        }
        return restoreKeysAndBackup(pin: pin, auth: authMethod, enclavesToCheck: enclavesToCheck)
    }

    /// An auth credential is needed to talk to the KBS server.
    /// This defines how we should get that auth credential
    public indirect enum AuthMethod: Equatable {
        /// Explicitly provide an auth credential to use directly with KBS.
        /// note: if it fails, will fall back to the backup or implicit if unset.
        case kbsAuth(KBSAuthCredential, backup: AuthMethod?)
        /// Get an SVR auth credential from the chat server first with the
        /// provided credentials, then use it to talk to the SVR server.
        case chatServerAuth(AuthedAccount)
        /// Use whatever SVR auth credential we have cached; if unavailable or
        /// if invalid, falls back to getting a SVR auth credential from the chat server
        /// with the chat server auth credentials we have cached.
        case implicit
    }

    private func restoreKeys(
        pin: String,
        auth: AuthMethod,
        enclavesToCheck: [KeyBackupEnclave]
    ) -> Guarantee<SVR.RestoreKeysResult> {
        guard let enclave = enclavesToCheck.first else {
            owsFailDebug("Unexpectedly tried to restore keys with no specified enclaves")
            return .value(.genericError(SVR.SVRError.assertion))
        }
        return restoreKeys(
            pin: pin,
            auth: auth,
            enclave: enclave
        ).map(on: schedulers.sync) { restoredKeys -> SVR.RestoreKeysResult in
            let encodedVerificationString = try SVRUtil.deriveEncodedPINVerificationString(pin: pin)

            // We successfully stored the new keys in KBS, save them in the database.
            // We record the enclave we restored from since we aren't backing up right now;
            // eventually it should migrate to the newest enclave (if this isn't the newest).
            self.db.write { transaction in
                self.store(
                    masterKey: restoredKeys.masterKey,
                    isMasterKeyBackedUp: true,
                    pinType: SVR.PinType(forPin: pin),
                    encodedVerificationString: encodedVerificationString,
                    enclaveName: enclave.name,
                    authedAccount: auth.authedAccount,
                    transaction: transaction
                )
            }
            return .success
        }.recover(on: schedulers.sync) { error -> Guarantee<SVR.RestoreKeysResult> in
            if error.isNetworkConnectivityFailure {
                return .value(.networkError(error))
            }
            guard let kbsError = error as? SVR.SVRError else {
                owsFailDebug("Unexpectedly surfacing a non KBS error \(error)")
                return .value(.genericError(error))
            }

            switch kbsError {
            case .assertion:
                return .value(.genericError(error))
            case .invalidPin(let remainingAttempts):
                return .value(.invalidPin(remainingAttempts: remainingAttempts))
            case .backupMissing:
                return .value(.backupMissing)
            }
        }
    }

    private func restoreKeysAndBackup(
        pin: String,
        auth: AuthMethod,
        enclavesToCheck: [KeyBackupEnclave]
    ) -> Guarantee<SVR.RestoreKeysResult> {
        guard let enclave = enclavesToCheck.first else {
            owsFailDebug("Unexpectedly tried to restore keys with no specified enclaves")
            return .value(.genericError(SVR.SVRError.assertion))
        }
        return restoreKeysAndBackup(
            pin: pin,
            auth: auth,
            enclave: enclave
        ).then(on: schedulers.sync) { result -> Guarantee<SVR.RestoreKeysResult> in
            switch result {
            case .success, .invalidPin, .networkError, .genericError:
                return .value(result)
            case .backupMissing:
                if enclavesToCheck.count > 1 {
                    // There's no backup on this enclave, but we have more enclaves we can try.
                    return self.restoreKeysAndBackup(pin: pin, auth: auth, enclavesToCheck: Array(enclavesToCheck.dropFirst()))
                } else {
                    return .value(result)
                }
            }
        }
    }

    private func restoreKeysAndBackup(
        pin: String,
        auth: AuthMethod,
        enclave: KeyBackupEnclave
    ) -> Guarantee<SVR.RestoreKeysResult> {
        Logger.info("Attempting KBS restore from enclave \(enclave.name)")

        return restoreKeys(
            pin: pin,
            auth: auth,
            enclave: enclave
        ).then { restoredKeys in
            // Backup our keys again, even though we just fetched them.
            // This resets the number of remaining attempts. We always
            // backup to the current enclave, even if we restored from
            // a previous enclave.
            return self.backupKeyRequest(
                accessKey: restoredKeys.accessKey,
                encryptedMasterKey: restoredKeys.encryptedMasterKey,
                enclave: self.currentEnclave,
                auth: auth
            ).map { ($0, restoredKeys.masterKey) }
        }.done(on: schedulers.global()) { response, masterKey in
            guard let status = response.status else {
                owsFailDebug("KBS backup is missing status")
                throw SVR.SVRError.assertion
            }

            guard let tokenData = response.token else {
                owsFailDebug("KBS restore is missing token")
                throw SVR.SVRError.assertion
            }

            // We should always receive a new token to use on our next request.
            // Since the backup request is always for the current enclave, the
            // token is also always for the current enclave.
            try self.updateNextToken(
                data: tokenData,
                enclaveName: self.currentEnclave.name
            )

            switch status {
            case .alreadyExists:
                // If we receive already exists, this means our backup has expired and
                // been replaced. In normal circumstances this should never happen.
                owsFailDebug("Received ALREADY_EXISTS response from KBS")
                throw SVR.SVRError.assertion
            case .notYetValid:
                owsFailDebug("the server thinks we provided a `validFrom` in the future")
                throw SVR.SVRError.assertion
            case .ok:
                let encodedVerificationString = try SVRUtil.deriveEncodedPINVerificationString(pin: pin)

                // We successfully stored the new keys in KBS, save them in the database.
                // Since the backup request is always for the current enclave, we want to
                // record the current enclave's name.
                self.db.write { transaction in
                    self.store(
                        masterKey: masterKey,
                        isMasterKeyBackedUp: true,
                        pinType: SVR.PinType(forPin: pin),
                        encodedVerificationString: encodedVerificationString,
                        enclaveName: self.currentEnclave.name,
                        authedAccount: auth.authedAccount,
                        transaction: transaction
                    )
                }
            }
        }.then(on: schedulers.sync) { () -> Promise<Void> in
            // If we restored from an enclave that's not the current enclave,
            // we need to delete the keys from the old enclave.
            guard enclave != self.currentEnclave else { return Promise.value(()) }
            Logger.info("Deleting restored keys from old enclave")
            return self.deleteKeyRequest(
                auth: auth,
                enclave: enclave
            ).done { _ in
                Logger.info("Successfully deleted keys from previous enclave")
            }.recover { error in
                owsFailDebug("Failed to delete keys from previous enclave \(error)")
                throw error
            }
        }.map(on: schedulers.sync) {
            return .success
        }
        .recover(on: schedulers.global()) { error -> Guarantee<SVR.RestoreKeysResult> in
            if error.isNetworkConnectivityFailure {
                return .value(.networkError(error))
            }
            guard let kbsError = error as? SVR.SVRError else {
                owsFailDebug("Unexpectedly surfacing a non KBS error \(error)")
                return .value(.genericError(error))
            }

            switch kbsError {
            case .assertion:
                return .value(.genericError(error))
            case .invalidPin(let remainingAttempts):
                return .value(.invalidPin(remainingAttempts: remainingAttempts))
            case .backupMissing:
                return .value(.backupMissing)
            }
        }
    }

    private struct RestoredKeys {
        let masterKey: Data
        let encryptedMasterKey: Data
        let accessKey: Data
    }

    private func restoreKeys(
        pin: String,
        auth: AuthMethod,
        enclave: KeyBackupEnclave,
        ignoreCachedToken: Bool = false
    ) -> Promise<RestoredKeys> {
        fetchBackupId(
            auth: auth,
            enclave: enclave,
            ignoreCachedToken: ignoreCachedToken
        ).map(on: schedulers.global()) { backupId in
            return try SVRUtil.deriveSVR1EncryptionKeyAndAccessKey(pin: pin, backupId: backupId)
        }.then { encryptionKey, accessKey in
            self.restoreKeyRequest(
                accessKey: accessKey,
                enclave: enclave,
                auth: auth,
                ignoreCachedToken: ignoreCachedToken
            ).map { ($0, encryptionKey, accessKey) }
        }.map(on: schedulers.global()) { response, encryptionKey, accessKey -> RestoredKeys in
            guard let status = response.status else {
                owsFailDebug("KBS restore is missing status")
                throw SVR.SVRError.assertion
            }

            // As long as the backup exists we should always receive a
            // new token to use on our next request. Store it now.
            if !ignoreCachedToken, status != .missing {
                guard let tokenData = response.token else {
                    owsFailDebug("KBS restore is missing token")
                    throw SVR.SVRError.assertion
                }

                try self.updateNextToken(
                    data: tokenData,
                    tries: response.tries,
                    enclaveName: enclave.name
                )
            }

            switch status {
            case .tokenMismatch:
                // the given token has already been spent. we'll use the new token
                // on the next attempt.
                owsFailDebug("attempted restore with spent token")
                self.db.write(block: self.clearNextToken(transaction:))
                throw SVR.SVRError.assertion
            case .pinMismatch:
                throw SVR.SVRError.invalidPin(remainingAttempts: response.tries)
            case .missing:
                throw SVR.SVRError.backupMissing
            case .notYetValid:
                owsFailDebug("the server thinks we provided a `validFrom` in the future")
                throw SVR.SVRError.assertion
            case .ok:
                guard let encryptedMasterKey = response.data else {
                    owsFailDebug("Failed to extract encryptedMasterKey from successful KBS restore response")
                    throw SVR.SVRError.assertion
                }

                let masterKey = try self.decryptMasterKey(encryptedMasterKey, encryptionKey: encryptionKey)

                return RestoredKeys(masterKey: masterKey, encryptedMasterKey: encryptedMasterKey, accessKey: accessKey)
            }
        }
    }

    public func generateAndBackupKeys(
        pin: String,
        authMethod: SVR.AuthMethod,
        rotateMasterKey: Bool
    ) -> Promise<Void> {
        return generateAndBackupKeys(pin: pin, authMethod: authMethod, masterKey: {
            if rotateMasterKey { return self.generateMasterKey() }
            return self.getOrLoadStateWithSneakyTransaction().masterKey ?? self.generateMasterKey()
        }())
    }

    internal func generateAndBackupKeys(
        pin: String,
        authMethod: SVR.AuthMethod,
        masterKey: @escaping @autoclosure () -> Data
    ) -> Promise<Void> {
        guard let authMethod = authMethod.kbs else {
            return Promise.init(error: SVR.SVRError.assertion)
        }
        return fetchBackupId(
            auth: authMethod,
            enclave: currentEnclave
        ).map(on: schedulers.global()) { backupId -> (Data, Data, Data) in
            let masterKey: Data = masterKey()
            let (encryptionKey, accessKey) = try SVRUtil.deriveSVR1EncryptionKeyAndAccessKey(pin: pin, backupId: backupId)
            let encryptedMasterKey = try self.encryptMasterKey(masterKey, encryptionKey: encryptionKey)

            return (masterKey, encryptedMasterKey, accessKey)
        }.then { masterKey, encryptedMasterKey, accessKey -> Promise<(KeyBackupProtoBackupResponse, Data)> in
            self.backupKeyRequest(
                accessKey: accessKey,
                encryptedMasterKey: encryptedMasterKey,
                enclave: self.currentEnclave,
                auth: authMethod
            ).map { ($0, masterKey) }
        }.done(on: schedulers.global()) { response, masterKey in
            guard let status = response.status else {
                owsFailDebug("KBS backup is missing status")
                throw SVR.SVRError.assertion
            }

            guard let tokenData = response.token else {
                owsFailDebug("KBS restore is missing token")
                throw SVR.SVRError.assertion
            }

            // We should always receive a new token to use on our next request. Store it now.
            try self.updateNextToken(
                data: tokenData,
                enclaveName: self.currentEnclave.name
            )

            switch status {
            case .alreadyExists:
                // the given token has already been spent. we'll use the new token
                // on the next attempt.
                owsFailDebug("attempted restore with spent token")
                throw SVR.SVRError.assertion
            case .notYetValid:
                owsFailDebug("the server thinks we provided a `validFrom` in the future")
                throw SVR.SVRError.assertion
            case .ok:
                let encodedVerificationString = try SVRUtil.deriveEncodedPINVerificationString(pin: pin)

                // We successfully stored the new keys in KBS, save them in the database
                self.db.write { transaction in
                    self.store(
                        masterKey: masterKey,
                        isMasterKeyBackedUp: true,
                        pinType: SVR.PinType(forPin: pin),
                        encodedVerificationString: encodedVerificationString,
                        enclaveName: self.currentEnclave.name,
                        authedAccount: authMethod.authedAccount,
                        transaction: transaction
                    )
                }
            }
        }.recover(on: schedulers.global()) { error in
            Logger.error("recording backupKeyRequest errored: \(error)")

            self.db.write { transaction in
                self.legacyStateManager.setHasBackupKeyRequestFailed(true, transaction: transaction)
            }

            guard let kbsError = error as? SVR.SVRError else {
                Logger.error("Surfacing a non KBS error: \(error)")
                throw error
            }

            throw kbsError
        }
    }

    public func objc_deleteKeys() -> AnyPromise {
        return AnyPromise(deleteKeys())
    }

    /// Remove the keys locally from the device and from the KBS,
    /// they will not be able to be restored.
    public func deleteKeys() -> Promise<Void> {
        return deleteKeyRequest(auth: .implicit, enclave: currentEnclave).ensure {
            // Even if the request to delete our keys from KBS failed,
            // purge them from the database.
            self.db.write { self.clearKeys(transaction: $0) }
        }.asVoid()
    }

    // MARK: - Master Key Encryption

    private func dataToDeriveFrom(for key: SVR.DerivedKey, transaction: DBReadTransaction) -> Data? {
        switch key {
        case .storageServiceManifest, .storageServiceRecord:
            return self.data(for: .storageService, transaction: transaction)?.rawData
        default:
            // Most keys derive directly from the master key.
            // Only a few exceptions derive from another derived key.
            guard let masterKey = getOrLoadState(transaction: transaction).masterKey else { return nil }
            return masterKey
        }
    }

    public func data(for key: SVR.DerivedKey, transaction: DBReadTransaction) -> SVR.DerivedKeyData? {
        // If we have this derived key stored in the database, use it.
        // This should only happen if we're a linked device and received
        // the derived key via a sync message, since we won't know about
        // the master key.
        let isPrimaryDevice = accountManager.isPrimaryDevice(transaction: transaction)
        if (!isPrimaryDevice || appContext.isRunningTests),
            let cachedData = getOrLoadState(transaction: transaction).syncedDerivedKeys[key] {
            return SVR.DerivedKeyData(cachedData, key)
        }

        guard let dataToDeriveFrom = dataToDeriveFrom(for: key, transaction: transaction) else {
            return nil
        }

        return SVR.DerivedKeyData(key.derivedData(from: dataToDeriveFrom), key)
    }

    public func isKeyAvailable(_ key: SVR.DerivedKey, transaction: DBReadTransaction) -> Bool {
        return data(for: key, transaction: transaction) != nil
    }

    public func encrypt(
        keyType: SVR.DerivedKey,
        data: Data,
        transaction: DBReadTransaction
    ) -> SVR.ApplyDerivedKeyResult {
        guard let keyData = self.data(for: keyType, transaction: transaction) else {
            owsFailDebug("missing derived key \(keyType)")
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
            owsFailDebug("missing derived key \(keyType)")
            return .masterKeyMissing
        }
        do {
            return .success(try Aes256GcmEncryptedData(concatenated: encryptedData).decrypt(key: keyData.rawData))
        } catch let error {
            return .cryptographyError(error)
        }
    }

    // MARK: - Master Key Management

    private func assertIsOnBackgroundQueue() {
        guard !CurrentAppContext().isRunningTests else { return }
        AssertNotOnMainThread()
    }

    func generateMasterKey() -> Data {
        assertIsOnBackgroundQueue()

        return Cryptography.generateRandomBytes(SVR.masterKeyLengthBytes)
    }

    func encryptMasterKey(_ masterKey: Data, encryptionKey: Data) throws -> Data {
        assertIsOnBackgroundQueue()

        guard masterKey.count == SVR.masterKeyLengthBytes else { throw SVR.SVRError.assertion }
        guard encryptionKey.count == 32 else { throw SVR.SVRError.assertion }

        let (iv, cipherText) = try Cryptography.encryptSHA256HMACSIV(data: masterKey, key: encryptionKey)

        guard iv.count == 16 else { throw SVR.SVRError.assertion }
        guard cipherText.count == 32 else { throw SVR.SVRError.assertion }

        return iv + cipherText
    }

    func decryptMasterKey(_ ivAndCipher: Data, encryptionKey: Data) throws -> Data {
        assertIsOnBackgroundQueue()

        guard ivAndCipher.count == 48 else { throw SVR.SVRError.assertion }

        let masterKey = try Cryptography.decryptSHA256HMACSIV(
            iv: ivAndCipher[0...15],
            cipherText: ivAndCipher[16...47],
            key: encryptionKey
        )

        guard masterKey.count == SVR.masterKeyLengthBytes else { throw SVR.SVRError.assertion }

        return masterKey
    }

    // MARK: - State

    private let cacheQueue = DispatchQueue(label: "org.signal.key-backup-service")

    private var cachedState: State?
    private struct State {
        let masterKey: Data?
        let pinType: SVR.PinType?
        let encodedVerificationString: String?
        let isMasterKeyBackedUp: Bool
        let syncedDerivedKeys: [SVR.DerivedKey: Data]
        let enclaveName: String?

        init(localStorage: SVRLocalStorage, transaction: DBReadTransaction) {
            masterKey = localStorage.getMasterKey(transaction)
            pinType = localStorage.getPinType(transaction)
            encodedVerificationString = localStorage.getEncodedPINVerificationString(transaction)
            isMasterKeyBackedUp = localStorage.getIsMasterKeyBackedUp(transaction)
            if let storageServiceKey = localStorage.getSyncedStorageServiceKey(transaction) {
                syncedDerivedKeys = [.storageService: storageServiceKey]
            } else {
                syncedDerivedKeys = [:]
            }
            enclaveName = localStorage.getSVR1EnclaveName(transaction)
        }
    }

    private func getOrLoadState(transaction: DBReadTransaction) -> State {
        if let cachedState = cacheQueue.sync(execute: { cachedState }) { return cachedState }
        return loadState(transaction: transaction)
    }

    private func getOrLoadStateWithSneakyTransaction() -> State {
        if let cachedState = cacheQueue.sync(execute: { cachedState }) { return cachedState }
        return db.read { loadState(transaction: $0) }
    }

    @discardableResult
    private func loadState(transaction: DBReadTransaction) -> State {
        let state = State(localStorage: localStorage, transaction: transaction)
        cacheQueue.sync { cachedState = state }
        return state
    }

    private func reloadState(transaction: DBReadTransaction) {
        _ = loadState(transaction: transaction)
    }

    public func warmCaches() {
        owsAssertDebug(GRDBSchemaMigrator.areMigrationsComplete)

        let state = getOrLoadStateWithSneakyTransaction()
        migrateEnclavesIfNecessary(state: state)
    }

    private func migrateEnclavesIfNecessary(state: State) {
        let (isRegisteredAndReady, pinCode) = db.read {
            return (
                accountManager.isRegisteredAndReady(transaction: $0),
                self.twoFAManager.pinCode(transaction: $0)
            )
        }
        guard
            state.enclaveName != currentEnclave.name,
            state.masterKey != nil,
            isRegisteredAndReady
        else {
            return
        }
        guard state.isMasterKeyBackedUp else {
            Logger.warn("Can't migrate KBS enclave because pins are not enabled.")
            return
        }
        guard let pin = pinCode else {
            owsFailDebug("Can't migrate KBS enclave because local pin is missing")
            return
        }

        Logger.info("Migrating from KBS enclave \(String(describing: state.enclaveName)) to \(currentEnclave.name)")

        generateAndBackupKeys(
            pin: pin,
            authMethod: .implicit,
            rotateMasterKey: false
        ).then { () -> Promise<Void> in
            guard let previousEnclave = TSConstants.keyBackupPreviousEnclaves.first(where: { $0.name == state.enclaveName }) else {
                // This can happen in legitimate cases, for example the user waited so
                // long to update to an app that supports the new enclave, that the old
                // enclave is no longer supported. In practice, this should be very rare.
                Logger.warn("Can't identify previous enclave, skipping delete")
                return Promise.value(())
            }

            return self.deleteKeyRequest(auth: .implicit, enclave: previousEnclave).asVoid().recover { error in
                // We ignore errors from the delete key request, because the migration was
                // successful. Most likely, this will happen because the old enclave is no
                // longer passing attestation. We just do our best to try and clean up.
                owsFailDebug("Failed to delete keys from previous enclave during migration \(error)")
            }
        }.done {
            Logger.info("Successfully migrated KBS enclave")
        }.catch { error in
            owsFailDebug("Failed to migrate KBS enclave \(error)")
        }
    }

    /// Removes the KBS keys locally from the device, they can still be
    /// restored from the server if you know the pin.
    public func clearKeys(transaction: DBWriteTransaction) {
        clearNextToken(transaction: transaction)
        localStorage.clearKeys(transaction)
        reloadState(transaction: transaction)
    }

    internal func store(
        masterKey: Data,
        isMasterKeyBackedUp: Bool,
        pinType: SVR.PinType,
        encodedVerificationString: String?,
        enclaveName: String?,
        authedAccount: AuthedAccount,
        transaction: DBWriteTransaction
    ) {
        owsAssertDebug(accountManager.isPrimaryDevice(transaction: transaction))

        let previousState = getOrLoadState(transaction: transaction)

        guard masterKey != previousState.masterKey
            || isMasterKeyBackedUp != previousState.isMasterKeyBackedUp
            || pinType != previousState.pinType
            || encodedVerificationString != previousState.encodedVerificationString else { return }

        if masterKey != previousState.masterKey {
            localStorage.setMasterKey(masterKey, transaction)
        }
        if isMasterKeyBackedUp != previousState.isMasterKeyBackedUp {
            localStorage.setIsMasterKeyBackedUp(isMasterKeyBackedUp, transaction)
        }
        if pinType != previousState.pinType {
            localStorage.setPinType(pinType, transaction)
        }
        if encodedVerificationString != previousState.encodedVerificationString {
            localStorage.setEncodedPINVerificationString(encodedVerificationString, transaction)
        }
        if enclaveName != previousState.enclaveName {
            localStorage.setSVR1EnclaveName(enclaveName, transaction)
        }

        // Clear failed status
        legacyStateManager.setHasBackupKeyRequestFailed(false, transaction: transaction)

        reloadState(transaction: transaction)

        // Only continue if we didn't previously have a master key or our master key has changed
        guard masterKey != previousState.masterKey, accountManager.isRegisteredAndReady(transaction: transaction) else { return }

        // Trigger a re-creation of the storage manifest, our keys have changed
        storageServiceManager.resetLocalData(transaction: transaction)

        // If the app is ready start that restoration.
        guard AppReadiness.isAppReady else { return }

        // TODO: These two things happen asynchronously and definitely race with each other.
        storageServiceManager.restoreOrCreateManifestIfNecessary(authedAccount: authedAccount)

        // Sync our new keys with linked devices.
        syncManager.sendKeysSyncMessage()
    }

    public func storeSyncedStorageServiceKey(
        data: Data?,
        authedAccount: AuthedAccount,
        transaction: DBWriteTransaction
    ) {
        guard !accountManager.isPrimaryDevice(transaction: transaction) || appContext.isRunningTests else {
            return owsFailDebug("primary device should never store synced keys")
        }

        localStorage.setSyncedStorageServiceKey(data, transaction)

        reloadState(transaction: transaction)

        // Trigger a re-fetch of the storage manifest, our keys have changed
        if data != nil {
            storageServiceManager.restoreOrCreateManifestIfNecessary(authedAccount: authedAccount)
        }
    }

    public func useDeviceLocalMasterKey(
        authedAccount: AuthedAccount,
        transaction: DBWriteTransaction
    ) {
        store(
            masterKey: generateMasterKey(),
            isMasterKeyBackedUp: false,
            pinType: .alphanumeric,
            encodedVerificationString: nil,
            enclaveName: nil,
            authedAccount: authedAccount,
            transaction: transaction
        )

        twoFAManager.markDisabled(transaction: transaction)
    }

    // MARK: - Requests

    private func enclaveRequest<RequestType: KBSRequestOption>(
        auth: AuthMethod,
        enclave: KeyBackupEnclave,
        ignoreCachedToken: Bool = false,
        requestOptionBuilder: @escaping (Token) throws -> RequestType
    ) -> Promise<RequestType.ResponseOptionType> {
        return performRemoteAttestation(
            auth: auth,
            enclave: enclave
        ).then { [schedulers] remoteAttestation -> Promise<RequestType.ResponseOptionType> in
            firstly {
                self.fetchToken(for: remoteAttestation, ignoreCachedToken: ignoreCachedToken)
            }.then(on: schedulers.global()) { tokenResponse -> Promise<HTTPResponse> in
                let requestOption = try requestOptionBuilder(tokenResponse)
                let requestBuilder = KeyBackupProtoRequest.builder()
                requestOption.set(on: requestBuilder)
                let kbRequestData = try requestBuilder.buildSerializedData()

                let encryptionResult = try Aes256GcmEncryptedData.encrypt(
                    kbRequestData,
                    key: remoteAttestation.keys.clientKey.keyData,
                    associatedData: remoteAttestation.requestId
                )

                let request = OWSRequestFactory.kbsEnclaveRequest(
                    withRequestId: remoteAttestation.requestId,
                    data: encryptionResult.ciphertext,
                    cryptIv: encryptionResult.nonce,
                    cryptMac: encryptionResult.authenticationTag,
                    enclaveName: remoteAttestation.enclaveName,
                    authUsername: remoteAttestation.auth.username,
                    authPassword: remoteAttestation.auth.password,
                    cookies: remoteAttestation.cookies,
                    requestType: RequestType.stringRepresentation
                )
                let urlSession = self.signalService.urlSessionForKBS()
                guard let requestUrl = request.url else {
                    owsFailDebug("Missing requestUrl.")
                    throw OWSHTTPError.missingRequest
                }
                return firstly {
                    urlSession.promiseForTSRequest(request)
                }.recover(on: schedulers.global()) { error -> Promise<HTTPResponse> in
                    // OWSUrlSession should only throw OWSHTTPError or OWSAssertionError.
                    if let httpError = error as? OWSHTTPError {
                        throw httpError
                    } else {
                        owsFailDebug("Unexpected error: \(error)")
                        throw OWSHTTPError.invalidRequest(requestUrl: requestUrl)
                    }
                }
            }.map(on: schedulers.global()) { (response: HTTPResponse) in
                guard let json = response.responseBodyJson else {
                    owsFailDebug("Missing or invalid JSON.")
                    throw SVR.SVRError.assertion
                }
                guard let parser = ParamParser(responseObject: json) else {
                    owsFailDebug("Failed to parse response object")
                    throw SVR.SVRError.assertion
                }

                let data = try parser.requiredBase64EncodedData(key: "data")
                guard data.count > 0 else {
                    owsFailDebug("data is invalid")
                    throw SVR.SVRError.assertion
                }

                let iv = try parser.requiredBase64EncodedData(key: "iv")
                let mac = try parser.requiredBase64EncodedData(key: "mac")

                let encryptionResult: Data
                do {
                    let encryptedData = Aes256GcmEncryptedData(nonce: iv, ciphertext: data, authenticationTag: mac)
                    encryptionResult = try encryptedData.decrypt(key: remoteAttestation.keys.serverKey.keyData)
                } catch {
                    owsFailDebug("failed to decrypt KBS response \(error)")
                    throw SVR.SVRError.assertion
                }

                let kbResponse = try KeyBackupProtoResponse(serializedData: encryptionResult)

                guard let typedResponse = RequestType.responseOption(from: kbResponse) else {
                    owsFailDebug("missing KBS response object")
                    throw SVR.SVRError.assertion
                }

                return typedResponse
            }
        }
    }

    private func backupKeyRequest(
        accessKey: Data,
        encryptedMasterKey: Data,
        enclave: KeyBackupEnclave,
        auth: AuthMethod
    ) -> Promise<KeyBackupProtoBackupResponse> {
        return enclaveRequest(auth: auth, enclave: enclave) { token -> KeyBackupProtoBackupRequest in
            guard let serviceId = Data.data(fromHex: enclave.serviceId) else {
                owsFailDebug("failed to encode service id")
                throw SVR.SVRError.assertion
            }

            let backupRequestBuilder = KeyBackupProtoBackupRequest.builder()
            backupRequestBuilder.setData(encryptedMasterKey)
            backupRequestBuilder.setPin(accessKey)
            backupRequestBuilder.setToken(token.data)
            backupRequestBuilder.setBackupID(token.backupId)
            backupRequestBuilder.setTries(SVR.maximumKeyAttempts)
            backupRequestBuilder.setServiceID(serviceId)

            // number of seconds since unix epoch after which this request should be valid
            // Always set to the client's clock time, minus 24 hours to account for inaccurate clocks
            backupRequestBuilder.setValidFrom(UInt64(Date().addingTimeInterval(-kDayInterval).timeIntervalSince1970))

            do {
                return try backupRequestBuilder.build()
            } catch {
                owsFailDebug("failed to build backup request")
                throw SVR.SVRError.assertion
            }
        }
    }

    private func restoreKeyRequest(
        accessKey: Data,
        enclave: KeyBackupEnclave,
        auth: AuthMethod,
        ignoreCachedToken: Bool = false
    ) -> Promise<KeyBackupProtoRestoreResponse> {
        return enclaveRequest(auth: auth, enclave: enclave, ignoreCachedToken: ignoreCachedToken) { token -> KeyBackupProtoRestoreRequest in
            guard let serviceId = Data.data(fromHex: enclave.serviceId) else {
                owsFailDebug("failed to encode service id")
                throw SVR.SVRError.assertion
            }

            let restoreRequestBuilder = KeyBackupProtoRestoreRequest.builder()
            restoreRequestBuilder.setPin(accessKey)
            restoreRequestBuilder.setToken(token.data)
            restoreRequestBuilder.setBackupID(token.backupId)
            restoreRequestBuilder.setServiceID(serviceId)

            // number of seconds since unix epoch after which this request should be valid
            // Always set to the client's clock time, minus 24 hours to account for inaccurate clocks
            restoreRequestBuilder.setValidFrom(UInt64(Date().addingTimeInterval(-kDayInterval).timeIntervalSince1970))

            do {
                return try restoreRequestBuilder.build()
            } catch {
                owsFailDebug("failed to build restore request")
                throw SVR.SVRError.assertion
            }
        }
    }

    private func deleteKeyRequest(
        auth: AuthMethod,
        enclave: KeyBackupEnclave
    ) -> Promise<KeyBackupProtoDeleteResponse> {
        return enclaveRequest(auth: auth, enclave: enclave) { token -> KeyBackupProtoDeleteRequest in
            guard let serviceId = Data.data(fromHex: enclave.serviceId) else {
                owsFailDebug("failed to encode service id")
                throw SVR.SVRError.assertion
            }

            let deleteRequestBuilder = KeyBackupProtoDeleteRequest.builder()
            deleteRequestBuilder.setBackupID(token.backupId)
            deleteRequestBuilder.setServiceID(serviceId)

            do {
                return try deleteRequestBuilder.build()
            } catch {
                owsFailDebug("failed to build delete request")
                throw SVR.SVRError.assertion
            }
        }
    }

    // MARK: - Token

    public var tokenStore: KeyValueStore {
        return keyValueStoreFactory.keyValueStore(collection: "kOWSKeyBackupService_Token")
    }

    private struct Token {

        static var backupIdKey: String { "backupIdKey" }
        static var dataKey: String { "dataKey" }
        static var triesKey: String { "triesKey" }
        static var enclaveNameKey: String { "enclaveNameKey" }

        let backupId: Data
        let data: Data
        let tries: UInt32
        let enclaveName: String

        init(backupId: Data, data: Data, tries: UInt32, enclaveName: String) throws {
            guard backupId.count == 32 else {
                owsFailDebug("invalid backupId")
                throw SVR.SVRError.assertion
            }
            self.backupId = backupId

            guard data.count == 32 else {
                owsFailDebug("invalid token data")
                throw SVR.SVRError.assertion
            }
            self.data = data

            self.tries = tries
            self.enclaveName = enclaveName
        }

        init(responseObject: Any?, enclaveName: String) throws {
            guard let paramParser = ParamParser(responseObject: responseObject) else {
                owsFailDebug("Unexpectedly missing response object")
                throw SVR.SVRError.assertion
            }

            let backupId = try paramParser.requiredBase64EncodedData(key: "backupId")
            let data = try paramParser.requiredBase64EncodedData(key: "token")
            let tries: UInt32 = try paramParser.required(key: "tries")

            try self.init(backupId: backupId, data: data, tries: tries, enclaveName: enclaveName)
        }
    }

    /// Update the token to use for the next enclave request.
    /// If backupId or tries are nil, attempts to use the previously known value.
    /// If we don't have a cached value (we've never stored a token before), an error is thrown.
    @discardableResult
    private func updateNextToken(backupId: Data? = nil, data: Data, tries: UInt32? = nil, enclaveName: String) throws -> Token {
        guard let backupId = backupId ?? db.read(block: { transaction in
            tokenStore.getData(Token.backupIdKey, transaction: transaction)
        }) else {
            owsFailDebug("missing backupId")
            throw SVR.SVRError.assertion
        }

        guard let tries = tries ?? db.read(block: { transaction in
            tokenStore.getUInt32(Token.triesKey, transaction: transaction)
        }) else {
            owsFailDebug("missing tries")
            throw SVR.SVRError.assertion
        }

        let token = try Token(backupId: backupId, data: data, tries: tries, enclaveName: enclaveName)
        recordAsCurrentToken(token)
        return token
    }

    /// Update the token to use for the next enclave request.
    @discardableResult
    private func updateNextToken(responseObject: Any?, enclaveName: String) throws -> Token {
        let token = try Token(responseObject: responseObject, enclaveName: enclaveName)
        recordAsCurrentToken(token)
        return token
    }

    private func clearNextToken(transaction: DBWriteTransaction) {
        tokenStore.setData(nil, key: Token.backupIdKey, transaction: transaction)
        tokenStore.setData(nil, key: Token.dataKey, transaction: transaction)
        tokenStore.setObject(nil, key: Token.triesKey, transaction: transaction)
        tokenStore.setObject(nil, key: Token.enclaveNameKey, transaction: transaction)
    }

    /// The token to use when making the next enclave request.
    private func nextToken(enclaveName: String) -> Token? {
        return db.read { transaction in
            // If the cached token is for another enclave, we can't use it. This
            // can happen when migrating from one enclave to another.
            guard tokenStore.getString(Token.enclaveNameKey, transaction: transaction) == enclaveName else {
                return nil
            }

            guard
                let backupId = tokenStore.getData(Token.backupIdKey, transaction: transaction),
                let data = tokenStore.getData(Token.dataKey, transaction: transaction),
                let tries = tokenStore.getUInt32(Token.triesKey, transaction: transaction)
            else {
                return nil
            }

            do {
                return try Token(backupId: backupId, data: data, tries: tries, enclaveName: enclaveName)
            } catch {
                // This should never happen, but if for some reason our stored token gets
                // corrupted we'll return nil which will trigger us to fetch a fresh one
                // from the enclave.
                owsFailDebug("unexpectedly failed to initialize token with error: \(error)")
                return nil
            }
        }
    }

    private func recordAsCurrentToken(_ token: Token) {
        db.write { transaction in
            tokenStore.setData(token.backupId, key: Token.backupIdKey, transaction: transaction)
            tokenStore.setData(token.data, key: Token.dataKey, transaction: transaction)
            tokenStore.setUInt32(token.tries, key: Token.triesKey, transaction: transaction)
            tokenStore.setString(token.enclaveName, key: Token.enclaveNameKey, transaction: transaction)
        }
    }

    private func fetchBackupId(auth: AuthMethod, enclave: KeyBackupEnclave, ignoreCachedToken: Bool = false) -> Promise<Data> {
        if !ignoreCachedToken, let currentToken = nextToken(
            enclaveName: enclave.name
        ) { return Promise.value(currentToken.backupId) }

        return performRemoteAttestation(
            auth: auth,
            enclave: enclave
        ).then { remoteAttestation in
            self.fetchToken(for: remoteAttestation, ignoreCachedToken: ignoreCachedToken).map { $0.backupId }
        }
    }

    private func fetchToken(for remoteAttestation: RemoteAttestation, ignoreCachedToken: Bool) -> Promise<Token> {
        // If we already have a token stored, we need to use it before fetching another.
        // We only stop using this token once the enclave informs us it is spent.
        if !ignoreCachedToken, let currentToken = nextToken(
            enclaveName: remoteAttestation.enclaveName
        ) { return Promise.value(currentToken) }

        // Fetch a new token

        let request = OWSRequestFactory.kbsEnclaveTokenRequest(
            withEnclaveName: remoteAttestation.enclaveName,
            authUsername: remoteAttestation.auth.username,
            authPassword: remoteAttestation.auth.password,
            cookies: remoteAttestation.cookies
        )

        return firstly { () -> Promise<HTTPResponse> in
            let urlSession = self.signalService.urlSessionForKBS()
            guard let requestUrl = request.url else {
                owsFailDebug("Missing requestUrl.")
                throw OWSHTTPError.missingRequest
            }
            return firstly {
                urlSession.promiseForTSRequest(request)
            }.recover(on: schedulers.global()) { error -> Promise<HTTPResponse> in
                // OWSUrlSession should only throw OWSHTTPError or OWSAssertionError.
                if let httpError = error as? OWSHTTPError {
                    throw httpError
                } else {
                    owsFailDebug("Unexpected error: \(error)")
                    throw OWSHTTPError.invalidRequest(requestUrl: requestUrl)
                }
            }
        }.map(on: schedulers.global()) { response in
            guard let json = response.responseBodyJson else {
                throw OWSAssertionError("Missing or invalid JSON.")
            }

            let token = try Token(responseObject: json, enclaveName: remoteAttestation.enclaveName)
            if !ignoreCachedToken { self.recordAsCurrentToken(token) }
            return token
        }
    }

    // MARK: Auth

    /// Calls `RemoteAttestation.performForKeyBackup(auth: enclave:)` with either the provided credential,
    /// or any we have stored locally.
    /// Stores the resulting credential to disk for reuse in the future.
    internal func performRemoteAttestation(auth: AuthMethod, enclave: KeyBackupEnclave) -> Promise<RemoteAttestation> {
        let authMethod: RemoteAttestation.KeyBackupAuthMethod
        var backupAuthMethod: RemoteAttestation.KeyBackupAuthMethod?
        let implicitAuthMethod: RemoteAttestation.KeyBackupAuthMethod
        var kbsAuth: KBSAuthCredential?
        let cachedKbsAuth: KBSAuthCredential? = self.db.read(block: { credentialStorage.getAuthCredentialForCurrentUser($0) })

        if let cachedKbsAuth {
            backupAuthMethod = .chatServerImplicitCredentials
            implicitAuthMethod = .kbsAuth(cachedKbsAuth.credential)
            kbsAuth = cachedKbsAuth
        } else {
            backupAuthMethod = nil
            implicitAuthMethod = .chatServerImplicitCredentials
        }

        switch auth {
        case let .kbsAuth(kBSAuthCredential, backup):
            authMethod = .kbsAuth(kBSAuthCredential.credential)
            kbsAuth = kBSAuthCredential
            switch backup {
            case .kbsAuth(let backupCredential, _):
                backupAuthMethod = .kbsAuth(backupCredential.credential)
            case let .chatServerAuth(authedAccount):
                backupAuthMethod = .chatServer(authedAccount.chatServiceAuth)
            case .none, .implicit:
                if kbsAuth == cachedKbsAuth {
                    backupAuthMethod = .chatServerImplicitCredentials
                } else {
                    backupAuthMethod = implicitAuthMethod
                }
            }
        case let .chatServerAuth(authedAccount):
            authMethod = .chatServer(authedAccount.chatServiceAuth)
        case .implicit:
            authMethod = implicitAuthMethod
        }
        return remoteAttestation
            .performForKeyBackup(
                authMethod: authMethod,
                enclave: enclave
            )
            .recover(on: schedulers.sync) { [credentialStorage, remoteAttestation, db] error in
                Logger.warn("KBS attestation failed, rotating auth credential.")
                // If we fail for any reason, be aggressive and clear our auth
                // credential and retry so we fetch a new one. It's cheap to do so.
                if let kbsAuth {
                    db.asyncWrite { credentialStorage.deleteInvalidCredentials([kbsAuth], $0) }
                }
                if let backupAuthMethod {
                    return remoteAttestation.performForKeyBackup(
                        authMethod: backupAuthMethod,
                        enclave: enclave
                    )
                } else {
                    return Promise(error: error)
                }
            }
            .map(on: schedulers.sync) { [credentialStorage, db] attestation in
                let credential = attestation.auth
                db.write { credentialStorage.storeAuthCredentialForCurrentUsername(KBSAuthCredential(credential: credential), $0) }
                return attestation
            }
    }
}
// MARK: -

private protocol KBSRequestOption {
    associatedtype ResponseOptionType
    static func responseOption(from response: KeyBackupProtoResponse) -> ResponseOptionType?
    func set(on builder: KeyBackupProtoRequestBuilder)

    static var stringRepresentation: String { get }
}

extension KeyBackupProtoBackupRequest: KBSRequestOption {
    typealias ResponseOptionType = KeyBackupProtoBackupResponse
    static func responseOption(from response: KeyBackupProtoResponse) -> ResponseOptionType? {
        return response.backup
    }
    func set(on builder: KeyBackupProtoRequestBuilder) {
        builder.setBackup(self)
    }
    static var stringRepresentation: String { "backup" }
}
extension KeyBackupProtoRestoreRequest: KBSRequestOption {
    typealias ResponseOptionType = KeyBackupProtoRestoreResponse
    static func responseOption(from response: KeyBackupProtoResponse) -> ResponseOptionType? {
        return response.restore
    }
    func set(on builder: KeyBackupProtoRequestBuilder) {
        builder.setRestore(self)
    }
    static var stringRepresentation: String { "restore" }
}
extension KeyBackupProtoDeleteRequest: KBSRequestOption {
    typealias ResponseOptionType = KeyBackupProtoDeleteResponse
    static func responseOption(from response: KeyBackupProtoResponse) -> ResponseOptionType? {
        return response.delete
    }
    func set(on builder: KeyBackupProtoRequestBuilder) {
        builder.setDelete(self)
    }
    static var stringRepresentation: String { "delete" }
}

extension KeyBackupServiceImpl.AuthMethod {

    var authedAccount: AuthedAccount {
        switch self {
        case .kbsAuth(_, let backup):
            return backup?.authedAccount ?? .implicit()
        case .chatServerAuth(let chatServiceAuth):
            return chatServiceAuth
        case .implicit:
            return .implicit()
        }
    }
}

extension SVR.AuthMethod {

    var kbs: KeyBackupServiceImpl.AuthMethod? {
        switch self {
        case .svrAuth(let someSVRAuthCredential, let backup):
            switch someSVRAuthCredential {
            case .kbsOnly(let kBSAuthCredential):
                return .kbsAuth(kBSAuthCredential, backup: backup?.kbs)
            case .svr2Only:
                // We explicitly opted to svr2 only, don't try
                // the backup (its probably a chat service auth credential).
                return nil
            case .both(let kBSAuthCredential, _):
                return .kbsAuth(kBSAuthCredential, backup: backup?.kbs)
            }
        case .chatServerAuth(let authedAccount):
            return .chatServerAuth(authedAccount)
        case .implicit:
            return .implicit
        }
    }
}

extension SVRAuthCredential {

    var kbsAuthMethod: KeyBackupServiceImpl.AuthMethod {
        guard let kbs else {
            return .implicit
        }
        return .kbsAuth(kbs, backup: nil)
    }
}
