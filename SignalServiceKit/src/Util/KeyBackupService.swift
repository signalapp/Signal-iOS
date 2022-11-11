//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalArgon2
import SignalCoreKit

@objc(OWSKeyBackupService)
public class KeyBackupService: NSObject {
    public enum KBSError: Error, Equatable {
        case assertion
        case invalidPin(triesRemaining: UInt32)
        case backupMissing
    }

    public enum PinType: Int {
        case numeric = 1
        case alphanumeric = 2

        public init(forPin pin: String) {
            let normalizedPin = KeyBackupService.normalizePin(pin)
            self = normalizedPin.digitsOnly() == normalizedPin ? .numeric : .alphanumeric
        }
    }

    // MARK: - Pin Management

    static let maximumKeyAttempts: UInt32 = 10

    /// Indicates whether or not we have a master key locally
    @objc
    public static var hasMasterKey: Bool {
        return getOrLoadStateWithSneakyTransaction().masterKey != nil
    }

    public static var currentEnclave: KeyBackupEnclave { return TSConstants.keyBackupEnclave }

    /// Indicates whether or not we have a master key stored in KBS
    @objc
    public static var hasBackedUpMasterKey: Bool {
        return getOrLoadStateWithSneakyTransaction().isMasterKeyBackedUp
    }

    public static func hasMasterKey(transaction: SDSAnyReadTransaction) -> Bool {
        return getOrLoadState(transaction: transaction).masterKey != nil
    }

    public static var currentPinType: PinType? {
        return getOrLoadStateWithSneakyTransaction().pinType
    }

    /// Indicates whether your pin is valid when compared to your stored keys.
    /// This is a local verification and does not make any requests to the KBS.
    @objc
    public static func verifyPin(_ pin: String, resultHandler: @escaping (Bool) -> Void) {
        DispatchQueue.global().async {
            var isValid = false
            defer {
                DispatchQueue.main.async { resultHandler(isValid) }
            }

            guard let encodedVerificationString = getOrLoadStateWithSneakyTransaction().encodedVerificationString else {
                owsFailDebug("Attempted to verify pin locally when we don't have a verification string")
                return
            }

            guard let pinData = normalizePin(pin).data(using: .utf8) else {
                owsFailDebug("failed to determine pin data")
                return
            }

            do {
                isValid = try Argon2.verify(encoded: encodedVerificationString, password: pinData, variant: .i)
            } catch {
                owsFailDebug("Failed to validate encodedVerificationString with error: \(error)")
            }
        }
    }

    // When changing number, we need to verify the PIN against the new number's KBS
    // record in order to generate a registration lock token. It's important that this
    // happens without touching any of the state we maintain around our account.
    public static func acquireRegistrationLockForNewNumber(with pin: String, and auth: RemoteAttestation.Auth) -> Promise<String> {
        // When restoring your backup we want to check the current enclave first,
        // and then fallback to previous enclaves if the current enclave has no
        // record of you. It's important that these are ordered from neweset enclave
        // to oldest enclave, so we start with the newest enclave and then progressively
        // check older enclaves.
        let enclavesToCheck = [TSConstants.keyBackupEnclave] + TSConstants.keyBackupPreviousEnclaves
        return acquireRegistrationLockForNewNumber(pin: pin, auth: auth, enclavesToCheck: enclavesToCheck)
    }

    private static func acquireRegistrationLockForNewNumber(
        pin: String,
        auth: RemoteAttestation.Auth,
        enclavesToCheck: [KeyBackupEnclave]
    ) -> Promise<String> {
        guard let enclave = enclavesToCheck.first else {
            owsFailDebug("Unexpectedly tried to acquire registration lock with no specified enclaves")
            return Promise(error: KBSError.assertion)
        }
        return acquireRegistrationLockForNewNumber(
            pin: pin,
            auth: auth,
            enclave: enclave
        ).recover { error -> Promise<String> in
            if case KBSError.backupMissing = error, enclavesToCheck.count > 1 {
                // There's no backup on this enclave, but we have more enclaves we can try.
                return acquireRegistrationLockForNewNumber(pin: pin, auth: auth, enclavesToCheck: Array(enclavesToCheck.dropFirst()))
            }

            throw error
        }
    }

    private static func acquireRegistrationLockForNewNumber(
        pin: String,
        auth: RemoteAttestation.Auth,
        enclave: KeyBackupEnclave
    ) -> Promise<String> {
        Logger.info("Attempting to acquire registration lock from enclave \(enclave.name)")

        return restoreKeys(
            pin: pin,
            auth: auth,
            enclave: enclave,
            ignoreCachedToken: true
        ).map(on: .global()) { restoredKeys -> String in
            guard let registrationLockToken = DerivedKey.registrationLock.derivedData(from: restoredKeys.masterKey)?.hexadecimalString else {
                owsFailDebug("Failed to derive registration lock token")
                throw KBSError.assertion
            }
            return registrationLockToken
        }.recover(on: .global()) { error -> Promise<String> in
            owsAssertDebug(error is KBSError, "Unexpectedly surfacing a non KBS error \(error)")
            throw error
        }
    }

    @objc(restoreKeysAndBackupWithPin:)
    static func objc_RestoreKeysAndBackup(with pin: String) -> AnyPromise {
        return AnyPromise(restoreKeysAndBackup(with: pin))
    }

    /// Loads the users key, if any, from the KBS into the database.
    public static func restoreKeysAndBackup(with pin: String, and auth: RemoteAttestation.Auth? = nil) -> Promise<Void> {
        // When restoring your backup we want to check the current enclave first,
        // and then fallback to previous enclaves if the current enclave has no
        // record of you. It's important that these are ordered from neweset enclave
        // to oldest enclave, so we start with the newest enclave and then progressively
        // check older enclaves.
        let enclavesToCheck = [TSConstants.keyBackupEnclave] + TSConstants.keyBackupPreviousEnclaves
        return restoreKeysAndBackup(pin: pin, auth: auth, enclavesToCheck: enclavesToCheck)
    }

    private static func restoreKeysAndBackup(
        pin: String,
        auth: RemoteAttestation.Auth?,
        enclavesToCheck: [KeyBackupEnclave]
    ) -> Promise<Void> {
        guard let enclave = enclavesToCheck.first else {
            owsFailDebug("Unexpectedly tried to restore keys with no specified enclaves")
            return Promise(error: KBSError.assertion)
        }
        return restoreKeysAndBackup(
            pin: pin,
            auth: auth,
            enclave: enclave
        ).recover { error -> Promise<Void> in
            if let error = error as? KBSError, error == .backupMissing, enclavesToCheck.count > 1 {
                // There's no backup on this enclave, but we have more enclaves we can try.
                return restoreKeysAndBackup(pin: pin, auth: auth, enclavesToCheck: Array(enclavesToCheck.dropFirst()))
            }

            throw error
        }
    }

    private static func restoreKeysAndBackup(
        pin: String,
        auth: RemoteAttestation.Auth?,
        enclave: KeyBackupEnclave
    ) -> Promise<Void> {
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
            return backupKeyRequest(
                accessKey: restoredKeys.accessKey,
                encryptedMasterKey: restoredKeys.encryptedMasterKey,
                enclave: currentEnclave,
                auth: auth
            ).map { ($0, restoredKeys.masterKey) }
        }.done(on: .global()) { response, masterKey in
            guard let status = response.status else {
                owsFailDebug("KBS backup is missing status")
                throw KBSError.assertion
            }

            guard let tokenData = response.token else {
                owsFailDebug("KBS restore is missing token")
                throw KBSError.assertion
            }

            // We should always receive a new token to use on our next request.
            // Since the backup request is always for the current enclave, the
            // token is also always for the current enclave.
            try Token.updateNext(
                data: tokenData,
                enclaveName: currentEnclave.name
            )

            switch status {
            case .alreadyExists:
                // If we receive already exists, this means our backup has expired and
                // been replaced. In normal circumstances this should never happen.
                owsFailDebug("Received ALREADY_EXISTS response from KBS")
                throw KBSError.assertion
            case .notYetValid:
                owsFailDebug("the server thinks we provided a `validFrom` in the future")
                throw KBSError.assertion
            case .ok:
                let encodedVerificationString = try deriveEncodedVerificationString(pin: pin)

                // We successfully stored the new keys in KBS, save them in the database.
                // Since the backup request is always for the current enclave, we want to
                // record the current enclave's name.
                databaseStorage.write { transaction in
                    store(
                        masterKey: masterKey,
                        isMasterKeyBackedUp: true,
                        pinType: PinType(forPin: pin),
                        encodedVerificationString: encodedVerificationString,
                        enclaveName: currentEnclave.name,
                        transaction: transaction
                    )
                }
            }
        }.then { () -> Promise<Void> in
            // If we restored from an enclave that's not the current enclave,
            // we need to delete the keys from the old enclave.
            guard enclave != currentEnclave else { return Promise.value(()) }
            Logger.info("Deleting restored keys from old enclave")
            return deleteKeyRequest(
                enclave: enclave
            ).done { _ in
                Logger.info("Successfully deleted keys from previous enclave")
            }.recover { error in
                owsFailDebug("Failed to delete keys from previous enclave \(error)")
                throw error
            }
        }.recover(on: .global()) { error in
            guard let kbsError = error as? KBSError else {
                owsFailDebug("Unexpectedly surfacing a non KBS error \(error)")
                throw error
            }

            throw kbsError
        }
    }

    private struct RestoredKeys {
        let masterKey: Data
        let encryptedMasterKey: Data
        let accessKey: Data
    }

    private static func restoreKeys(
        pin: String,
        auth: RemoteAttestation.Auth?,
        enclave: KeyBackupEnclave,
        ignoreCachedToken: Bool = false
    ) -> Promise<RestoredKeys> {
        fetchBackupId(
            auth: auth,
            enclave: enclave,
            ignoreCachedToken: ignoreCachedToken
        ).map(on: .global()) { backupId in
            return try deriveEncryptionKeyAndAccessKey(pin: pin, backupId: backupId)
        }.then { encryptionKey, accessKey in
            restoreKeyRequest(
                accessKey: accessKey,
                enclave: enclave,
                auth: auth,
                ignoreCachedToken: ignoreCachedToken
            ).map { ($0, encryptionKey, accessKey) }
        }.map(on: .global()) { response, encryptionKey, accessKey -> RestoredKeys in
            guard let status = response.status else {
                owsFailDebug("KBS restore is missing status")
                throw KBSError.assertion
            }

            // As long as the backup exists we should always receive a
            // new token to use on our next request. Store it now.
            if !ignoreCachedToken, status != .missing {
                guard let tokenData = response.token else {
                    owsFailDebug("KBS restore is missing token")
                    throw KBSError.assertion
                }

                try Token.updateNext(
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
                throw KBSError.assertion
            case .pinMismatch:
                throw KBSError.invalidPin(triesRemaining: response.tries)
            case .missing:
                throw KBSError.backupMissing
            case .notYetValid:
                owsFailDebug("the server thinks we provided a `validFrom` in the future")
                throw KBSError.assertion
            case .ok:
                guard let encryptedMasterKey = response.data else {
                    owsFailDebug("Failed to extract encryptedMasterKey from successful KBS restore response")
                    throw KBSError.assertion
                }

                let masterKey = try decryptMasterKey(encryptedMasterKey, encryptionKey: encryptionKey)

                return RestoredKeys(masterKey: masterKey, encryptedMasterKey: encryptedMasterKey, accessKey: accessKey)
            }
        }
    }

    @objc(generateAndBackupKeysWithPin:rotateMasterKey:)
    @available(swift, obsoleted: 1.0)
    static func generateAndBackupKeys(with pin: String, rotateMasterKey: Bool) -> AnyPromise {
        return AnyPromise(generateAndBackupKeys(with: pin, rotateMasterKey: rotateMasterKey))
    }

    /// Backs up the user's master key to KBS and stores it locally in the database.
    /// If the user doesn't have a master key already a new one is generated.
    public static func generateAndBackupKeys(with pin: String, rotateMasterKey: Bool) -> Promise<Void> {
        return fetchBackupId(
            auth: nil,
            enclave: currentEnclave
        ).map(on: .global()) { backupId -> (Data, Data, Data) in
            let masterKey: Data = {
                if rotateMasterKey { return generateMasterKey() }
                return getOrLoadStateWithSneakyTransaction().masterKey ?? generateMasterKey()
            }()
            let (encryptionKey, accessKey) = try deriveEncryptionKeyAndAccessKey(pin: pin, backupId: backupId)
            let encryptedMasterKey = try encryptMasterKey(masterKey, encryptionKey: encryptionKey)

            return (masterKey, encryptedMasterKey, accessKey)
        }.then { masterKey, encryptedMasterKey, accessKey -> Promise<(KeyBackupProtoBackupResponse, Data)> in
            backupKeyRequest(
                accessKey: accessKey,
                encryptedMasterKey: encryptedMasterKey,
                enclave: currentEnclave
            ).map { ($0, masterKey) }
        }.done(on: .global()) { response, masterKey in
            guard let status = response.status else {
                owsFailDebug("KBS backup is missing status")
                throw KBSError.assertion
            }

            guard let tokenData = response.token else {
                owsFailDebug("KBS restore is missing token")
                throw KBSError.assertion
            }

            // We should always receive a new token to use on our next request. Store it now.
            try Token.updateNext(
                data: tokenData,
                enclaveName: currentEnclave.name
            )

            switch status {
            case .alreadyExists:
                // the given token has already been spent. we'll use the new token
                // on the next attempt.
                owsFailDebug("attempted restore with spent token")
                throw KBSError.assertion
            case .notYetValid:
                owsFailDebug("the server thinks we provided a `validFrom` in the future")
                throw KBSError.assertion
            case .ok:
                let encodedVerificationString = try deriveEncodedVerificationString(pin: pin)

                // We successfully stored the new keys in KBS, save them in the database
                databaseStorage.write { transaction in
                    store(
                        masterKey: masterKey,
                        isMasterKeyBackedUp: true,
                        pinType: PinType(forPin: pin),
                        encodedVerificationString: encodedVerificationString,
                        enclaveName: currentEnclave.name,
                        transaction: transaction
                    )
                }
            }
        }.recover(on: .global()) { error in
            Logger.error("recording backupKeyRequest errored: \(error)")

            databaseStorage.write { transaction in
                keyValueStore.setBool(true, key: hasBackupKeyRequestFailedIdentifier, transaction: transaction)

                reloadState(transaction: transaction)
            }

            guard let kbsError = error as? KBSError else {
                owsFailDebug("Unexpectedly surfacing a non KBS error: \(error)")
                throw error
            }

            throw kbsError
        }
    }

    @objc(deleteKeys)
    public static func objc_deleteKeys() -> AnyPromise {
        return AnyPromise(deleteKeys())
    }

    /// Remove the keys locally from the device and from the KBS,
    /// they will not be able to be restored.
    public static func deleteKeys() -> Promise<Void> {
        return deleteKeyRequest(enclave: currentEnclave).ensure {
            // Even if the request to delete our keys from KBS failed,
            // purge them from the database.
            databaseStorage.write { clearKeys(transaction: $0) }
        }.asVoid()
    }

    // MARK: - Master Key Encryption

    public enum DerivedKey: Hashable {
        case registrationLock
        case storageService

        case storageServiceManifest(version: UInt64)
        case storageServiceRecord(identifier: StorageService.StorageIdentifier)

        var rawValue: String {
            switch self {
            case .registrationLock:
                return "Registration Lock"
            case .storageService:
                return "Storage Service Encryption"
            case .storageServiceManifest(let version):
                return "Manifest_\(version)"
            case .storageServiceRecord(let identifier):
                return "Item_\(identifier.data.base64EncodedString())"
            }
        }

        static var syncableKeys: [DerivedKey] {
            return [
                .storageService
            ]
        }

        private var dataToDeriveFrom: Data? {
            switch self {
            case .storageServiceManifest, .storageServiceRecord:
                return DerivedKey.storageService.data
            default:
                // Most keys derive directly from the master key.
                // Only a few exceptions derive from another derived key.
                guard let masterKey = getOrLoadStateWithSneakyTransaction().masterKey else { return nil }
                return masterKey
            }
        }

        public var data: Data? {
            // If we have this derived key stored in the database, use it.
            // This should only happen if we're a linked device and received
            // the derived key via a sync message, since we won't know about
            // the master key.
            if (!tsAccountManager.isPrimaryDevice || CurrentAppContext().isRunningTests),
                let cachedData = getOrLoadStateWithSneakyTransaction().syncedDerivedKeys[self] {
                return cachedData
            }

            guard let dataToDeriveFrom = dataToDeriveFrom else {
                return nil
            }

            return derivedData(from: dataToDeriveFrom)
        }

        public func derivedData(from dataToDeriveFrom: Data) -> Data? {
            guard let data = rawValue.data(using: .utf8) else {
                owsFailDebug("Failed to encode data")
                return nil
            }

            return Cryptography.computeSHA256HMAC(data, key: dataToDeriveFrom)
        }

        public var isAvailable: Bool { return data != nil }
    }

    public static func encrypt(keyType: DerivedKey, data: Data) throws -> Data {
        guard let keyData = keyType.data, let key = OWSAES256Key(data: keyData) else {
            owsFailDebug("missing derived key \(keyType)")
            throw KBSError.assertion
        }

        guard let encryptedData = Cryptography.encryptAESGCMWithDataAndConcatenateResults(
            plainTextData: data,
            initializationVectorLength: kAESGCM256_DefaultIVLength,
            key: key
        ) else {
            owsFailDebug("Failed to encrypt data")
            throw KBSError.assertion
        }

        return encryptedData
    }

    public static func decrypt(keyType: DerivedKey, encryptedData: Data) throws -> Data {
        guard let keyData = keyType.data, let key = OWSAES256Key(data: keyData) else {
            owsFailDebug("missing derived key \(keyType)")
            throw KBSError.assertion
        }

        guard let data = Cryptography.decryptAESGCMConcatenatedData(
            encryptedData: encryptedData,
            initializationVectorLength: kAESGCM256_DefaultIVLength,
            key: key
        ) else {
            Logger.error("failed to decrypt data")
            throw KBSError.assertion
        }

        return data
    }

    @objc
    public static func deriveRegistrationLockToken() -> String? {
        return DerivedKey.registrationLock.data?.hexadecimalString
    }

    // MARK: - Master Key Management

    private static func assertIsOnBackgroundQueue() {
        guard !CurrentAppContext().isRunningTests else { return }
        AssertNotOnMainThread()
    }

    static func deriveEncryptionKeyAndAccessKey(pin: String, backupId: Data) throws -> (encryptionKey: Data, accessKey: Data) {
        assertIsOnBackgroundQueue()

        guard let pinData = normalizePin(pin).data(using: .utf8) else { throw KBSError.assertion }
        guard backupId.count == 32 else { throw KBSError.assertion }

        let (rawHash, _) = try Argon2.hash(
            iterations: 32,
            memoryInKiB: 1024 * 16, // 16MiB
            threads: 1,
            password: pinData,
            salt: backupId,
            desiredLength: 64,
            variant: .id,
            version: .v13
        )

        return (encryptionKey: rawHash[0...31], accessKey: rawHash[32...63])
    }

    static func deriveEncodedVerificationString(pin: String, salt: Data = Cryptography.generateRandomBytes(16)) throws -> String {
        assertIsOnBackgroundQueue()

        guard let pinData = normalizePin(pin).data(using: .utf8) else { throw KBSError.assertion }
        guard salt.count == 16 else { throw KBSError.assertion }

        let (_, encodedString) = try Argon2.hash(
            iterations: 64,
            memoryInKiB: 512,
            threads: 1,
            password: pinData,
            salt: salt,
            desiredLength: 32,
            variant: .i,
            version: .v13
        )

        return encodedString
    }

    @objc
    public static func normalizePin(_ pin: String) -> String {
        // Trim leading and trailing whitespace
        var normalizedPin = pin.ows_stripped()

        // If this pin contains only numerals, ensure they are arabic numerals.
        if pin.digitsOnly() == normalizedPin { normalizedPin = normalizedPin.ensureArabicNumerals }

        // NFKD unicode normalization.
        return normalizedPin.decomposedStringWithCompatibilityMapping
    }

    static func generateMasterKey() -> Data {
        assertIsOnBackgroundQueue()

        return Cryptography.generateRandomBytes(32)
    }

    static func encryptMasterKey(_ masterKey: Data, encryptionKey: Data) throws -> Data {
        assertIsOnBackgroundQueue()

        guard masterKey.count == 32 else { throw KBSError.assertion }
        guard encryptionKey.count == 32 else { throw KBSError.assertion }

        let (iv, cipherText) = try Cryptography.encryptSHA256HMACSIV(data: masterKey, key: encryptionKey)

        guard iv.count == 16 else { throw KBSError.assertion }
        guard cipherText.count == 32 else { throw KBSError.assertion }

        return iv + cipherText
    }

    static func decryptMasterKey(_ ivAndCipher: Data, encryptionKey: Data) throws -> Data {
        assertIsOnBackgroundQueue()

        guard ivAndCipher.count == 48 else { throw KBSError.assertion }

        let masterKey = try Cryptography.decryptSHA256HMACSIV(
            iv: ivAndCipher[0...15],
            cipherText: ivAndCipher[16...47],
            key: encryptionKey
        )

        guard masterKey.count == 32 else { throw KBSError.assertion }

        return masterKey
    }

    // MARK: - State

    public static var keyValueStore: SDSKeyValueStore {
        return SDSKeyValueStore(collection: "kOWSKeyBackupService_Keys")
    }

    private static let masterKeyIdentifer = "masterKey"
    private static let pinTypeIdentifier = "pinType"
    private static let encodedVerificationStringIdentifier = "encodedVerificationString"
    private static let hasBackupKeyRequestFailedIdentifier = "hasBackupKeyRequestFailed"
    private static let hasPendingRestorationIdentifier = "hasPendingRestoration"
    private static let isMasterKeyBackedUpIdentifer = "isMasterKeyBackedUp"
    private static let enclaveNameIdentifier = "enclaveName"
    private static let cacheQueue = DispatchQueue(label: "org.signal.KeyBackupService")

    private static var cachedState: State?
    private struct State {
        let masterKey: Data?
        let pinType: PinType?
        let encodedVerificationString: String?
        let hasBackupKeyRequestFailed: Bool
        let hasPendingRestoration: Bool
        let isMasterKeyBackedUp: Bool
        let syncedDerivedKeys: [DerivedKey: Data]
        let enclaveName: String?

        init(transaction: SDSAnyReadTransaction) {
            masterKey = keyValueStore.getData(masterKeyIdentifer, transaction: transaction)

            if let rawPinType = keyValueStore.getInt(pinTypeIdentifier, transaction: transaction) {
                pinType = PinType(rawValue: rawPinType)
            } else {
                pinType = nil
            }

            encodedVerificationString = keyValueStore.getString(
                encodedVerificationStringIdentifier,
                transaction: transaction
            )

            hasBackupKeyRequestFailed = keyValueStore.getBool(
                hasBackupKeyRequestFailedIdentifier,
                defaultValue: false,
                transaction: transaction
            )

            hasPendingRestoration = keyValueStore.getBool(
                hasPendingRestorationIdentifier,
                defaultValue: false,
                transaction: transaction
            )

            isMasterKeyBackedUp = keyValueStore.getBool(
                isMasterKeyBackedUpIdentifer,
                defaultValue: false,
                transaction: transaction
            )

            var syncedDerivedKeys = [DerivedKey: Data]()
            for type in DerivedKey.syncableKeys {
                syncedDerivedKeys[type] = keyValueStore.getData(type.rawValue, transaction: transaction)
            }
            self.syncedDerivedKeys = syncedDerivedKeys

            enclaveName = keyValueStore.getString(enclaveNameIdentifier, transaction: transaction)
        }
    }

    private static func getOrLoadState(transaction: SDSAnyReadTransaction) -> State {
        if let cachedState = cacheQueue.sync(execute: { cachedState }) { return cachedState }
        return loadState(transaction: transaction)
    }

    private static func getOrLoadStateWithSneakyTransaction() -> State {
        if let cachedState = cacheQueue.sync(execute: { cachedState }) { return cachedState }
        return databaseStorage.read { loadState(transaction: $0) }
    }

    @discardableResult
    private static func loadState(transaction: SDSAnyReadTransaction) -> State {
        let state = State(transaction: transaction)
        cacheQueue.sync { cachedState = state }
        return state
    }

    private static func reloadState(transaction: SDSAnyReadTransaction) {
        _ = loadState(transaction: transaction)
    }

    @objc
    public static func warmCaches() {
        owsAssertDebug(GRDBSchemaMigrator.areMigrationsComplete)

        let state = getOrLoadStateWithSneakyTransaction()
        migrateEnclavesIfNecessary(state: state)
    }

    private static func migrateEnclavesIfNecessary(state: State) {
        guard state.enclaveName != currentEnclave.name,
            state.masterKey != nil,
            tsAccountManager.isRegisteredAndReady else { return }
        guard state.isMasterKeyBackedUp else {
            Logger.warn("Can't migrate KBS enclave because pins are not enabled.")
            return
        }
        guard let pin = OWS2FAManager.shared.pinCode else {
            owsFailDebug("Can't migrate KBS enclave because local pin is missing")
            return
        }

        Logger.info("Migrating from KBS enclave \(String(describing: state.enclaveName)) to \(currentEnclave.name)")

        generateAndBackupKeys(
            with: pin,
            rotateMasterKey: false
        ).then { () -> Promise<Void> in
            guard let previousEnclave = TSConstants.keyBackupPreviousEnclaves.first(where: { $0.name == state.enclaveName }) else {
                // This can happen in legitimate cases, for example the user waited so
                // long to update to an app that supports the new enclave, that the old
                // enclave is no longer supported. In practice, this should be very rare.
                Logger.warn("Can't identify previous enclave, skipping delete")
                return Promise.value(())
            }

            return deleteKeyRequest(enclave: previousEnclave).asVoid().recover { error in
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
    @objc
    public static func clearKeys(transaction: SDSAnyWriteTransaction) {
        Token.clearNext(transaction: transaction)

        keyValueStore.removeValues(forKeys: [
            masterKeyIdentifer,
            isMasterKeyBackedUpIdentifer,
            pinTypeIdentifier,
            encodedVerificationStringIdentifier
        ], transaction: transaction)

        for type in DerivedKey.syncableKeys {
            keyValueStore.removeValue(forKey: type.rawValue, transaction: transaction)
        }

        reloadState(transaction: transaction)
    }

    static func store(
        masterKey: Data,
        isMasterKeyBackedUp: Bool,
        pinType: PinType,
        encodedVerificationString: String,
        enclaveName: String,
        transaction: SDSAnyWriteTransaction
    ) {
        owsAssertDebug(tsAccountManager.isPrimaryDevice)

        let previousState = getOrLoadState(transaction: transaction)

        guard masterKey != previousState.masterKey
            || isMasterKeyBackedUp != previousState.isMasterKeyBackedUp
            || pinType != previousState.pinType
            || encodedVerificationString != previousState.encodedVerificationString else { return }

        keyValueStore.setData(
            masterKey,
            key: masterKeyIdentifer,
            transaction: transaction
        )

        keyValueStore.setBool(
            isMasterKeyBackedUp,
            key: isMasterKeyBackedUpIdentifer,
            transaction: transaction
        )

        keyValueStore.setInt(
            pinType.rawValue,
            key: pinTypeIdentifier,
            transaction: transaction
        )

        keyValueStore.setString(
            encodedVerificationString,
            key: encodedVerificationStringIdentifier,
            transaction: transaction
        )

        keyValueStore.setString(
            enclaveName,
            key: enclaveNameIdentifier,
            transaction: transaction
        )

        // Clear failed status
        keyValueStore.setBool(
            false,
            key: hasBackupKeyRequestFailedIdentifier,
            transaction: transaction
        )

        reloadState(transaction: transaction)

        // Only continue if we didn't previously have a master key or our master key has changed
        guard masterKey != previousState.masterKey, tsAccountManager.isRegisteredAndReady else { return }

        // Trigger a re-creation of the storage manifest, our keys have changed
        storageServiceManager.resetLocalData(transaction: transaction)

        // If the app is ready start that restoration.
        guard AppReadiness.isAppReady else { return }

        storageServiceManager.restoreOrCreateManifestIfNecessary()

        // Sync our new keys with linked devices.
        syncManager.sendKeysSyncMessage()
    }

    public static func storeSyncedKey(type: DerivedKey, data: Data?, transaction: SDSAnyWriteTransaction) {
        guard !tsAccountManager.isPrimaryDevice || CurrentAppContext().isRunningTests else {
            return owsFailDebug("primary device should never store synced keys")
        }

        guard DerivedKey.syncableKeys.contains(type) else {
            return owsFailDebug("tried to store a non-syncable key")
        }

        keyValueStore.setData(data, key: type.rawValue, transaction: transaction)

        reloadState(transaction: transaction)

        // Trigger a re-fetch of the storage manifest, our keys have changed
        if type == .storageService, data != nil {
            storageServiceManager.restoreOrCreateManifestIfNecessary()
        }
    }

    public static func hasBackupKeyRequestFailed(transaction: SDSAnyReadTransaction) -> Bool {
        getOrLoadState(transaction: transaction).hasBackupKeyRequestFailed
    }

    public static func hasPendingRestoration(transaction: SDSAnyReadTransaction) -> Bool {
        getOrLoadState(transaction: transaction).hasPendingRestoration
    }

    public static func recordPendingRestoration(transaction: SDSAnyWriteTransaction) {
        keyValueStore.setBool(true, key: hasPendingRestorationIdentifier, transaction: transaction)

        reloadState(transaction: transaction)
    }

    public static func clearPendingRestoration(transaction: SDSAnyWriteTransaction) {
        keyValueStore.removeValue(forKey: hasPendingRestorationIdentifier, transaction: transaction)

        reloadState(transaction: transaction)
    }

    public static func setMasterKeyBackedUp(_ value: Bool, transaction: SDSAnyWriteTransaction) {
        keyValueStore.setBool(value, key: isMasterKeyBackedUpIdentifer, transaction: transaction)

        reloadState(transaction: transaction)
    }

    public static func useDeviceLocalMasterKey(transaction: SDSAnyWriteTransaction) {
        store(
            masterKey: generateMasterKey(),
            isMasterKeyBackedUp: false,
            pinType: .alphanumeric,
            encodedVerificationString: "",
            enclaveName: "",
            transaction: transaction
        )

        OWS2FAManager.shared.markDisabled(transaction: transaction)
    }

    // MARK: - Requests

    private static func enclaveRequest<RequestType: KBSRequestOption>(
        auth: RemoteAttestation.Auth? = nil,
        enclave: KeyBackupEnclave,
        ignoreCachedToken: Bool = false,
        requestOptionBuilder: @escaping (Token) throws -> RequestType
    ) -> Promise<RequestType.ResponseOptionType> {
        return RemoteAttestation.performForKeyBackup(
            auth: auth,
            enclave: enclave
        ).then { remoteAttestation -> Promise<RequestType.ResponseOptionType> in
            firstly {
                fetchToken(for: remoteAttestation, ignoreCachedToken: ignoreCachedToken)
            }.then(on: .global()) { tokenResponse -> Promise<HTTPResponse> in
                let requestOption = try requestOptionBuilder(tokenResponse)
                let requestBuilder = KeyBackupProtoRequest.builder()
                requestOption.set(on: requestBuilder)
                let kbRequestData = try requestBuilder.buildSerializedData()

                guard let encryptionResult = Cryptography.encryptAESGCM(
                    plainTextData: kbRequestData,
                    initializationVectorLength: kAESGCM256_DefaultIVLength,
                    additionalAuthenticatedData: remoteAttestation.requestId,
                    key: remoteAttestation.keys.clientKey
                ) else {
                    owsFailDebug("Failed to encrypt request data")
                    throw KBSError.assertion
                }

                let request = OWSRequestFactory.kbsEnclaveRequest(
                    withRequestId: remoteAttestation.requestId,
                    data: encryptionResult.ciphertext,
                    cryptIv: encryptionResult.initializationVector,
                    cryptMac: encryptionResult.authTag,
                    enclaveName: remoteAttestation.enclaveName,
                    authUsername: remoteAttestation.auth.username,
                    authPassword: remoteAttestation.auth.password,
                    cookies: remoteAttestation.cookies,
                    requestType: RequestType.stringRepresentation
                )
                let urlSession = Self.signalService.urlSessionForKBS()
                guard let requestUrl = request.url else {
                    owsFailDebug("Missing requestUrl.")
                    let url: URL = urlSession.baseUrl ?? URL(string: TSConstants.keyBackupURL)!
                    throw OWSHTTPError.missingRequest(requestUrl: url)
                }
                return firstly {
                    urlSession.promiseForTSRequest(request)
                }.recover(on: .global()) { error -> Promise<HTTPResponse> in
                    // OWSUrlSession should only throw OWSHTTPError or OWSAssertionError.
                    if let httpError = error as? OWSHTTPError {
                        throw httpError
                    } else {
                        owsFailDebug("Unexpected error: \(error)")
                        throw OWSHTTPError.invalidRequest(requestUrl: requestUrl)
                    }
                }
            }.map(on: .global()) { (response: HTTPResponse) in
                guard let json = response.responseBodyJson else {
                    owsFailDebug("Missing or invalid JSON.")
                    throw KBSError.assertion
                }
                guard let parser = ParamParser(responseObject: json) else {
                    owsFailDebug("Failed to parse response object")
                    throw KBSError.assertion
                }

                let data = try parser.requiredBase64EncodedData(key: "data")
                guard data.count > 0 else {
                    owsFailDebug("data is invalid")
                    throw KBSError.assertion
                }

                let iv = try parser.requiredBase64EncodedData(key: "iv")
                guard iv.count == 12 else {
                    owsFailDebug("iv is invalid")
                    throw KBSError.assertion
                }

                let mac = try parser.requiredBase64EncodedData(key: "mac")
                guard mac.count == 16 else {
                    owsFailDebug("mac is invalid")
                    throw KBSError.assertion
                }

                guard let encryptionResult = Cryptography.decryptAESGCM(
                    withInitializationVector: iv,
                    ciphertext: data,
                    additionalAuthenticatedData: nil,
                    authTag: mac,
                    key: remoteAttestation.keys.serverKey
                ) else {
                    owsFailDebug("failed to decrypt KBS response")
                    throw KBSError.assertion
                }

                let kbResponse = try KeyBackupProtoResponse(serializedData: encryptionResult)

                guard let typedResponse = RequestType.responseOption(from: kbResponse) else {
                    owsFailDebug("missing KBS response object")
                    throw KBSError.assertion
                }

                return typedResponse
            }
        }
    }

    private static func backupKeyRequest(
        accessKey: Data,
        encryptedMasterKey: Data,
        enclave: KeyBackupEnclave,
        auth: RemoteAttestation.Auth? = nil
    ) -> Promise<KeyBackupProtoBackupResponse> {
        return enclaveRequest(auth: auth, enclave: enclave) { token -> KeyBackupProtoBackupRequest in
            guard let serviceId = Data.data(fromHex: enclave.serviceId) else {
                owsFailDebug("failed to encode service id")
                throw KBSError.assertion
            }

            let backupRequestBuilder = KeyBackupProtoBackupRequest.builder()
            backupRequestBuilder.setData(encryptedMasterKey)
            backupRequestBuilder.setPin(accessKey)
            backupRequestBuilder.setToken(token.data)
            backupRequestBuilder.setBackupID(token.backupId)
            backupRequestBuilder.setTries(maximumKeyAttempts)
            backupRequestBuilder.setServiceID(serviceId)

            // number of seconds since unix epoch after which this request should be valid
            // Always set to the client's clock time, minus 24 hours to account for inaccurate clocks
            backupRequestBuilder.setValidFrom(UInt64(Date().addingTimeInterval(-kDayInterval).timeIntervalSince1970))

            do {
                return try backupRequestBuilder.build()
            } catch {
                owsFailDebug("failed to build backup request")
                throw KBSError.assertion
            }
        }
    }

    private static func restoreKeyRequest(
        accessKey: Data,
        enclave: KeyBackupEnclave,
        auth: RemoteAttestation.Auth? = nil,
        ignoreCachedToken: Bool = false
    ) -> Promise<KeyBackupProtoRestoreResponse> {
        return enclaveRequest(auth: auth, enclave: enclave, ignoreCachedToken: ignoreCachedToken) { token -> KeyBackupProtoRestoreRequest in
            guard let serviceId = Data.data(fromHex: enclave.serviceId) else {
                owsFailDebug("failed to encode service id")
                throw KBSError.assertion
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
                throw KBSError.assertion
            }
        }
    }

    private static func deleteKeyRequest(enclave: KeyBackupEnclave) -> Promise<KeyBackupProtoDeleteResponse> {
        return enclaveRequest(enclave: enclave) { token -> KeyBackupProtoDeleteRequest in
            guard let serviceId = Data.data(fromHex: enclave.serviceId) else {
                owsFailDebug("failed to encode service id")
                throw KBSError.assertion
            }

            let deleteRequestBuilder = KeyBackupProtoDeleteRequest.builder()
            deleteRequestBuilder.setBackupID(token.backupId)
            deleteRequestBuilder.setServiceID(serviceId)

            do {
                return try deleteRequestBuilder.build()
            } catch {
                owsFailDebug("failed to build delete request")
                throw KBSError.assertion
            }
        }
    }

    // MARK: - Token

    public static var tokenStore: SDSKeyValueStore {
        return SDSKeyValueStore(collection: "kOWSKeyBackupService_Token")
    }

    private struct Token {
        private static var keyValueStore: SDSKeyValueStore {
            return KeyBackupService.tokenStore
        }

        private static var backupIdKey: String { "backupIdKey" }
        private static var dataKey: String { "dataKey" }
        private static var triesKey: String { "triesKey" }
        private static var enclaveNameKey: String { "enclaveNameKey" }

        let backupId: Data
        let data: Data
        let tries: UInt32
        let enclaveName: String

        private init(backupId: Data, data: Data, tries: UInt32, enclaveName: String) throws {
            guard backupId.count == 32 else {
                owsFailDebug("invalid backupId")
                throw KBSError.assertion
            }
            self.backupId = backupId

            guard data.count == 32 else {
                owsFailDebug("invalid token data")
                throw KBSError.assertion
            }
            self.data = data

            self.tries = tries
            self.enclaveName = enclaveName
        }

        /// Update the token to use for the next enclave request.
        /// If backupId or tries are nil, attempts to use the previously known value.
        /// If we don't have a cached value (we've never stored a token before), an error is thrown.
        @discardableResult
        static func updateNext(backupId: Data? = nil, data: Data, tries: UInt32? = nil, enclaveName: String) throws -> Token {
            guard let backupId = backupId ?? databaseStorage.read(block: { transaction in
                keyValueStore.getData(backupIdKey, transaction: transaction)
            }) else {
                owsFailDebug("missing backupId")
                throw KBSError.assertion
            }

            guard let tries = tries ?? databaseStorage.read(block: { transaction in
                keyValueStore.getUInt32(triesKey, transaction: transaction)
            }) else {
                owsFailDebug("missing tries")
                throw KBSError.assertion
            }

            let token = try Token(backupId: backupId, data: data, tries: tries, enclaveName: enclaveName)
            token.recordAsCurrent()
            return token
        }

        /// Update the token to use for the next enclave request.
        @discardableResult
        static func updateNext(responseObject: Any?, enclaveName: String) throws -> Token {
            let token = try Token(responseObject: responseObject, enclaveName: enclaveName)
            token.recordAsCurrent()
            return token
        }

        init(responseObject: Any?, enclaveName: String) throws {
            guard let paramParser = ParamParser(responseObject: responseObject) else {
                owsFailDebug("Unexpectedly missing response object")
                throw KBSError.assertion
            }

            let backupId = try paramParser.requiredBase64EncodedData(key: "backupId")
            let data = try paramParser.requiredBase64EncodedData(key: "token")
            let tries: UInt32 = try paramParser.required(key: "tries")

            try self.init(backupId: backupId, data: data, tries: tries, enclaveName: enclaveName)
        }

        static func clearNext() {
            databaseStorage.write { clearNext(transaction: $0) }
        }

        static func clearNext(transaction: SDSAnyWriteTransaction) {
            keyValueStore.setData(nil, key: backupIdKey, transaction: transaction)
            keyValueStore.setData(nil, key: dataKey, transaction: transaction)
            keyValueStore.setObject(nil, key: triesKey, transaction: transaction)
            keyValueStore.setObject(nil, key: enclaveNameKey, transaction: transaction)
        }

        /// The token to use when making the next enclave request.
        static func next(enclaveName: String) -> Token? {
            return databaseStorage.read { transaction in
                // If the cached token is for another enclave, we can't use it. This
                // can happen when migrating from one enclave to another.
                guard keyValueStore.getString(enclaveNameKey, transaction: transaction) == enclaveName else {
                    return nil
                }

                guard let backupId = keyValueStore.getData(backupIdKey, transaction: transaction),
                    let data = keyValueStore.getData(dataKey, transaction: transaction),
                    let tries = keyValueStore.getUInt32(triesKey, transaction: transaction) else {
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

        func recordAsCurrent() {
            databaseStorage.write { transaction in
                Token.keyValueStore.setData(self.backupId, key: Token.backupIdKey, transaction: transaction)
                Token.keyValueStore.setData(self.data, key: Token.dataKey, transaction: transaction)
                Token.keyValueStore.setUInt32(self.tries, key: Token.triesKey, transaction: transaction)
                Token.keyValueStore.setString(self.enclaveName, key: Token.enclaveNameKey, transaction: transaction)
            }
        }
    }

    private static func fetchBackupId(auth: RemoteAttestation.Auth?, enclave: KeyBackupEnclave, ignoreCachedToken: Bool = false) -> Promise<Data> {
        if !ignoreCachedToken, let currentToken = Token.next(
            enclaveName: enclave.name
        ) { return Promise.value(currentToken.backupId) }

        return RemoteAttestation.performForKeyBackup(
            auth: auth,
            enclave: enclave
        ).then { remoteAttestation in
            fetchToken(for: remoteAttestation, ignoreCachedToken: ignoreCachedToken).map { $0.backupId }
        }
    }

    private static func fetchToken(for remoteAttestation: RemoteAttestation, ignoreCachedToken: Bool) -> Promise<Token> {
        // If we already have a token stored, we need to use it before fetching another.
        // We only stop using this token once the enclave informs us it is spent.
        if !ignoreCachedToken, let currentToken = Token.next(
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
            let urlSession = Self.signalService.urlSessionForKBS()
            guard let requestUrl = request.url else {
                owsFailDebug("Missing requestUrl.")
                let url: URL = urlSession.baseUrl ?? URL(string: TSConstants.keyBackupURL)!
                throw OWSHTTPError.missingRequest(requestUrl: url)
            }
            return firstly {
                urlSession.promiseForTSRequest(request)
            }.recover(on: .global()) { error -> Promise<HTTPResponse> in
                // OWSUrlSession should only throw OWSHTTPError or OWSAssertionError.
                if let httpError = error as? OWSHTTPError {
                    throw httpError
                } else {
                    owsFailDebug("Unexpected error: \(error)")
                    throw OWSHTTPError.invalidRequest(requestUrl: requestUrl)
                }
            }
        }.map(on: .global()) { response in
            guard let json = response.responseBodyJson else {
                throw OWSAssertionError("Missing or invalid JSON.")
            }

            let token = try Token(responseObject: json, enclaveName: remoteAttestation.enclaveName)
            if !ignoreCachedToken { token.recordAsCurrent() }
            return token
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
