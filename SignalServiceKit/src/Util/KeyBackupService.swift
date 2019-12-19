//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import CommonCrypto

@objc(OWSKeyBackupService)
public class KeyBackupService: NSObject {
    public enum KBSError: Error {
        case assertion
        case invalidPin(triesRemaining: UInt32)
        case backupMissing
    }

    // PRAGMA MARK: - Depdendencies
    static var networkManager: TSNetworkManager {
        return TSNetworkManager.shared()
    }

    static var databaseStorage: SDSDatabaseStorage {
        return .shared
    }

    static var tsAccountManager: TSAccountManager {
        return .sharedInstance()
    }

    static var storageServiceManager: StorageServiceManagerProtocol {
        return SSKEnvironment.shared.storageServiceManager
    }

    static var syncManager: SyncManagerProtocol {
        return SSKEnvironment.shared.syncManager
    }

    // PRAGMA MARK: - Pin Management

    // TODO: Decide what we want this to be
    static let maximumKeyAttempts: UInt32 = 10

    /// Indicates whether or not we have a local copy of your keys to verify your pin
    @objc
    public static var hasLocalKeys: Bool {
        return cacheQueue.sync { cachedMasterKey != nil && cachedPinKey2 != nil }
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

            guard hasLocalKeys else {
                owsFailDebug("Attempted to verify pin locally when we don't have KBS keys")
                return
            }

            guard let masterKey = cacheQueue.sync(execute: { cachedMasterKey }) else {
                owsFailDebug("unexpectedly missing master key")
                return
            }

            guard let pinKey2 = cacheQueue.sync(execute: { cachedPinKey2 }) else {
                owsFailDebug("unexpectedly missing pinKey2")
                return
            }

            guard let stretchedPin = deriveStretchedPin(from: pin) else {
                owsFailDebug("failed to derive stretched pin")
                return
            }

            guard let pinKey1 = derivePinKey1(from: stretchedPin) else {
                owsFailDebug("failed to derive pinKey1")
                return
            }

            isValid = masterKey == deriveMasterKey(from: pinKey1, and: pinKey2)
        }
    }

    @objc(restoreKeysWithPin:)
    static func objc_RestoreKeys(with pin: String) -> AnyPromise {
        return AnyPromise(restoreKeys(with: pin))
    }

    /// Loads the users key, if any, from the KBS into the database.
    public static func restoreKeys(with pin: String, and auth: RemoteAttestationAuth? = nil) -> Promise<Void> {
        return DispatchQueue.global().async(.promise) { () -> (Data, Data) in
            guard let stretchedPin = self.deriveStretchedPin(from: pin) else {
                owsFailDebug("failed to derive stretched pin")
                throw KBSError.assertion
            }

            guard let pinKey1 = derivePinKey1(from: stretchedPin) else {
                owsFailDebug("failed to derive stretched pin")
                throw KBSError.assertion
            }

            return (stretchedPin, pinKey1)
        }.then { stretchedPin, pinKey1 in
            restoreKeyRequest(stretchedPin: stretchedPin, with: auth).map { ($0, stretchedPin, pinKey1) }
        }.then { response, stretchedPin, pinKey1 in
            DispatchQueue.global().async(.promise) { () -> (Data, Data, Data) in
                guard let status = response.status else {
                    owsFailDebug("KBS restore is missing status")
                    throw KBSError.assertion
                }

                // As long as the backup exists we should always receive a
                // new token to use on our next request. Store it now.
                if status != .missing {
                    guard let tokenData = response.token else {
                        owsFailDebug("KBS restore is missing token")
                        throw KBSError.assertion
                    }

                    try Token.updateNext(data: tokenData, tries: response.tries)
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
                    guard let pinKey2 = response.data else {
                        owsFailDebug("Failed to extract key from successful KBS restore response")
                        throw KBSError.assertion
                    }

                    guard let masterKey = deriveMasterKey(from: pinKey1, and: pinKey2) else {
                        throw KBSError.assertion
                    }

                    return (masterKey, stretchedPin, pinKey2)
                }
            }
        }.then { masterKey, stretchedPin, pinKey2 in
            // Backup our keys again, even though we just fetched them.
            // This resets the number of remaining attempts.
            backupKeyRequest(stretchedPin: stretchedPin, keyData: pinKey2, and: auth).map { ($0, masterKey, pinKey2) }
        }.done { response, masterKey, pinKey2 in
            guard let status = response.status else {
                owsFailDebug("KBS backup is missing status")
                throw KBSError.assertion
            }

            guard let tokenData = response.token else {
                owsFailDebug("KBS restore is missing token")
                throw KBSError.assertion
            }

            // We should always receive a new token to use on our next request.
            try Token.updateNext(data: tokenData)

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
                // We successfully stored the new keys in KBS, save them in the database
                databaseStorage.write { transaction in
                    store(masterKey, pinKey2: pinKey2, transaction: transaction)
                }
            }
        }.recover { error in
            guard let kbsError = error as? KBSError else {
                owsFailDebug("Unexpectedly surfacing a non KBS error \(error)")
                throw error
            }

            throw kbsError
        }
    }

    @objc(generateAndBackupKeysWithPin:)
    static func objc_generateAndBackupKeys(with pin: String) -> AnyPromise {
        return AnyPromise(generateAndBackupKeys(with: pin))
    }

    /// Generates a new master key for the given pin, backs it up to the KBS,
    /// and stores it locally in the database.
    public static func generateAndBackupKeys(with pin: String) -> Promise<Void> {
        return DispatchQueue.global().async(.promise) { () -> (Data, Data, Data) in
            guard let stretchedPin = deriveStretchedPin(from: pin) else {
                owsFailDebug("failed to derive stretched pin")
                throw KBSError.assertion
            }

            guard let pinKey1 = derivePinKey1(from: stretchedPin) else {
                owsFailDebug("failed to derive pinKey1")
                throw KBSError.assertion
            }

            let pinKey2 = generatePinKey2().keyData

            guard let masterKey = deriveMasterKey(from: pinKey1, and: pinKey2) else {
                owsFailDebug("failed to derive master key")
                throw KBSError.assertion
            }

            return (stretchedPin, pinKey2, masterKey)
        }.then { stretchedPin, pinKey2, masterKey in
            backupKeyRequest(stretchedPin: stretchedPin, keyData: pinKey2).map { ($0, pinKey2, masterKey) }
        }.done { response, pinKey2, masterKey in
            guard let status = response.status else {
                owsFailDebug("KBS backup is missing status")
                throw KBSError.assertion
            }

            guard let tokenData = response.token else {
                owsFailDebug("KBS restore is missing token")
                throw KBSError.assertion
            }

            // We should always receive a new token to use on our next request. Store it now.
            try Token.updateNext(data: tokenData)

            switch status {
            case .alreadyExists:
                // the given token has already been spent. we'll use the new token
                // on the next attempt.
                owsFailDebug("attempted restore with spent token")
            case .notYetValid:
                owsFailDebug("the server thinks we provided a `validFrom` in the future")
                throw KBSError.assertion
            case .ok:
                // We successfully stored the new keys in KBS, save them in the database
                databaseStorage.write { transaction in
                    store(masterKey, pinKey2: pinKey2, transaction: transaction)
                }
            }
        }.recover { error in
            guard let kbsError = error as? KBSError else {
                owsFailDebug("Unexpectedly surfacing a non KBS error: \(error)")
                throw error
            }

            throw kbsError
        }
    }

    @objc(deleteKeys)
    static func objc_deleteKeys() -> AnyPromise {
        return AnyPromise(deleteKeys())
    }

    /// Remove the keys locally from the device and from the KBS,
    /// they will not be able to be restored.
    public static func deleteKeys() -> Promise<Void> {
        return deleteKeyRequest().ensure {
            // Even if the request to delete our keys from KBS failed,
            // purge them from the database.
            databaseStorage.write { clearKeys(transaction: $0) }
        }.done { _ in
            // The next token is no longer valid, as it pertains to
            // a deleted backup. Clear it out so we fetch a fresh one.
            Token.clearNext()
        }
    }

    // PRAGMA MARK: - Crypto

    public enum DerivedKey: String, CaseIterable {
        case storageService = "Storage Service Encryption"
        case registrationLock = "Registration Lock"

        public var data: Data? {
            // If we have this derived key stored in the database, use it.
            // This should only happen if we're a linked device and received
            // the derived key via a sync message, since we won't know about
            // the master key.
            if tsAccountManager.isPrimaryDevice,
                let cachedData = cacheQueue.sync(execute: { cachedSyncedDerivedKeys[self] }) {
                return cachedData
            }

            guard let masterKey = cacheQueue.sync(execute: { cachedMasterKey }) else {
                return nil
            }

            guard let data = rawValue.data(using: .utf8) else {
                owsFailDebug("Failed to encode data")
                return nil
            }

            return Cryptography.computeSHA256HMAC(data, withHMACKey: masterKey)
        }

        public var isAvailable: Bool { return data != nil }
    }

    public static func encrypt(keyType: DerivedKey, data: Data) throws -> Data {
        guard let keyData = keyType.data, let key = OWSAES256Key(data: keyData) else {
            owsFailDebug("missing derived key \(keyType)")
            throw KBSError.assertion
        }

        // TODO: Maybe rename this since it's no longer profile specific
        guard let encryptedData = Cryptography.encryptAESGCMProfileData(plainTextData: data, key: key) else {
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

        // TODO: Maybe rename this since it's no longer profile specific
        guard let data = Cryptography.decryptAESGCMProfileData(encryptedData: encryptedData, key: key) else {
            owsFailDebug("failed to decrypt data")
            throw KBSError.assertion
        }

        return data
    }

    private static func assertIsOnBackgroundQueue() {
        assertOnQueue(DispatchQueue.global())
    }

    private static func deriveStretchedPin(from pin: String) -> Data? {
        if !CurrentAppContext().isRunningTests {
            assertIsOnBackgroundQueue()
        }

        guard let pinData = pin.ensureArabicNumerals.data(using: .utf8) else {
            owsFailDebug("Failed to encode pin data")
            return nil
        }

        guard let saltData = "nosalt".data(using: .utf8) else {
            owsFailDebug("Failed to encode salt data")
            return nil
        }

        return Cryptography.pbkdf2Derivation(password: pinData, salt: saltData, iterations: 20000, outputLength: 32)
    }

    private static func derivePinKey1(from stretchedPin: Data) -> Data? {
        if !CurrentAppContext().isRunningTests {
            assertIsOnBackgroundQueue()
        }

        guard let data = "Master Key Encryption".data(using: .utf8) else {
            owsFailDebug("Failed to encode data")
            return nil
        }
        return Cryptography.computeSHA256HMAC(data, withHMACKey: stretchedPin)
    }

    private static func generatePinKey2() -> OWSAES256Key {
        assertIsOnBackgroundQueue()

        return OWSAES256Key.generateRandom()
    }

    private static func deriveMasterKey(from pinKey1: Data, and pinKey2: Data) -> Data? {
        if !CurrentAppContext().isRunningTests {
            assertIsOnBackgroundQueue()
        }

        return Cryptography.computeSHA256HMAC(pinKey2, withHMACKey: pinKey1)
    }

    @objc
    static func deriveRegistrationLockToken() -> String? {
        return DerivedKey.registrationLock.data?.hexadecimalString
    }

    @objc
    static func deriveKBSAccessKey(from stretchedPin: Data) -> Data? {
        assertIsOnBackgroundQueue()

        guard let data = "KBS Access Key".data(using: .utf8) else {
            owsFailDebug("Failed to encode data")
            return nil
        }

        return Cryptography.computeSHA256HMAC(data, withHMACKey: stretchedPin)
    }

    // PRAGMA MARK: - Key Storage

    public static var keyValueStore: SDSKeyValueStore {
        return SDSKeyValueStore(collection: "kOWSKeyBackupService_Keys")
    }

    private static let masterKeyIdentifer = "masterKey"
    private static let pinKey2Identifer = "pinKey2"
    private static let cacheQueue = DispatchQueue(label: "org.signal.KeyBackupService")

    @objc
    public static func warmCaches() {
        var masterKey: Data?
        var pinKey2: Data?

        var syncedDerivedKeys = [DerivedKey: Data]()

        databaseStorage.read { transaction in
            masterKey = keyValueStore.getData(masterKeyIdentifer, transaction: transaction)
            pinKey2 = keyValueStore.getData(pinKey2Identifer, transaction: transaction)

            for type in DerivedKey.allCases {
                syncedDerivedKeys[type] = keyValueStore.getData(type.rawValue, transaction: transaction)
            }
        }

        cacheQueue.sync {
            cachedMasterKey = masterKey
            cachedPinKey2 = pinKey2
            cachedSyncedDerivedKeys = syncedDerivedKeys
        }
    }

    /// Removes the KBS keys locally from the device, they can still be
    /// restored from the server if you know the pin.
    @objc
    public static func clearKeys(transaction: SDSAnyWriteTransaction) {
        keyValueStore.removeAll(transaction: transaction)
        cacheQueue.sync {
            cachedMasterKey = nil
            cachedPinKey2 = nil
        }
    }

    // Should only be interacted with on the serial cache queue
    // Always contains an in memory reference to our current masterKey
    private static var cachedMasterKey: Data?
    // Always contains an in memory reference to our current pinKey2
    private static var cachedPinKey2: Data?
    // Always contains an in memory reference to our received derived keys
    static var cachedSyncedDerivedKeys = [DerivedKey: Data]()

    private static func store(_ masterKey: Data, pinKey2: Data, transaction: SDSAnyWriteTransaction) {
        guard masterKey != cachedMasterKey || pinKey2 != cachedPinKey2 else { return }

        keyValueStore.setData(masterKey, key: masterKeyIdentifer, transaction: transaction)
        keyValueStore.setData(pinKey2, key: pinKey2Identifer, transaction: transaction)

        cacheQueue.sync {
            cachedMasterKey = masterKey
            cachedPinKey2 = pinKey2
        }

        // Trigger a re-creation of the storage manifest, our keys have changed
        storageServiceManager.restoreOrCreateManifestIfNecessary()

        if tsAccountManager.isRegisteredAndReady {
            // Sync our new keys with linked devices.
            syncManager.sendKeysSyncMessage()
        }
    }

    public static func storeSyncedKey(type: DerivedKey, data: Data?, transaction: SDSAnyWriteTransaction) {
        guard !tsAccountManager.isPrimaryDevice else {
            return owsFailDebug("primary device should never store synced keys")
        }

        keyValueStore.setData(data, key: type.rawValue, transaction: transaction)
        cacheQueue.sync { cachedSyncedDerivedKeys[type] = data }

        // Trigger a re-fetch of the storage manifest, our keys have changed
        if type == .storageService {
            storageServiceManager.restoreOrCreateManifestIfNecessary()
        }
    }

    // PRAGMA MARK: - Requests

    private static func enclaveRequest<RequestType: KBSRequestOption>(
        with auth: RemoteAttestationAuth? = nil,
        and requestOptionBuilder: @escaping (Token) throws -> RequestType
    ) -> Promise<RequestType.ResponseOptionType> {
        return RemoteAttestation.makePromise(for: .keyBackup, with: auth).then { remoteAttestation in
            fetchToken(for: remoteAttestation).map { ($0, remoteAttestation) }
        }.map(on: DispatchQueue.global()) { tokenResponse, remoteAttestation -> (TSRequest, RemoteAttestation) in
            let requestOption = try requestOptionBuilder(tokenResponse)
            let requestBuilder = KeyBackupProtoRequest.builder()
            requestOption.set(on: requestBuilder)
            let kbRequestData = try requestBuilder.buildSerializedData()

            guard let encryptionResult = Cryptography.encryptAESGCM(
                plainTextData: kbRequestData,
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
                cookies: remoteAttestation.cookies
            )

            return (request, remoteAttestation)
        }.then { request, remoteAttestation in
            networkManager.makePromise(request: request).map { ($0.responseObject, remoteAttestation) }
        }.map(on: DispatchQueue.global()) { responseObject, remoteAttestation in
            guard let parser = ParamParser(responseObject: responseObject) else {
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

            let kbResponse = try KeyBackupProtoResponse.parseData(encryptionResult)

            guard let typedResponse = RequestType.responseOption(from: kbResponse) else {
                owsFailDebug("missing KBS response object")
                throw KBSError.assertion
            }

            return typedResponse
        }
    }

    private static func backupKeyRequest(stretchedPin: Data, keyData: Data, and auth: RemoteAttestationAuth? = nil) -> Promise<KeyBackupProtoBackupResponse> {
        return enclaveRequest(with: auth) { token -> KeyBackupProtoBackupRequest in
            guard let kbsAccessKey = deriveKBSAccessKey(from: stretchedPin) else {
                owsFailDebug("failed to dervive KBS Access key")
                throw KBSError.assertion
            }

            guard let serviceId = Data.data(fromHex: TSConstants.keyBackupServiceId) else {
                owsFailDebug("failed to encode service id")
                throw KBSError.assertion
            }

            let backupRequestBuilder = KeyBackupProtoBackupRequest.builder()
            backupRequestBuilder.setData(keyData)
            backupRequestBuilder.setPin(kbsAccessKey)
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

    private static func restoreKeyRequest(stretchedPin: Data, with auth: RemoteAttestationAuth? = nil) -> Promise<KeyBackupProtoRestoreResponse> {
        return enclaveRequest(with: auth) { token -> KeyBackupProtoRestoreRequest in
            guard let kbsAccessKey = deriveKBSAccessKey(from: stretchedPin) else {
                owsFailDebug("failed to dervive KBS Access key")
                throw KBSError.assertion
            }

            guard let serviceId = Data.data(fromHex: TSConstants.keyBackupServiceId) else {
                owsFailDebug("failed to encode service id")
                throw KBSError.assertion
            }

            let restoreRequestBuilder = KeyBackupProtoRestoreRequest.builder()
            restoreRequestBuilder.setPin(kbsAccessKey)
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

    private static func deleteKeyRequest() -> Promise<KeyBackupProtoDeleteResponse> {
        return enclaveRequest { token -> KeyBackupProtoDeleteRequest in
            guard let serviceId = Data.data(fromHex: TSConstants.keyBackupServiceId) else {
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

    // PRAGMA MARK: - Token

    public static var tokenStore: SDSKeyValueStore {
        return SDSKeyValueStore(collection: "kOWSKeyBackupService_Token")
    }

    private struct Token {
        private static var keyValueStore: SDSKeyValueStore {
            return KeyBackupService.tokenStore
        }

        private static let backupIdKey = "backupIdKey"
        private static let dataKey = "dataKey"
        private static let triesKey = "triesKey"

        let backupId: Data
        let data: Data
        let tries: UInt32

        private init(backupId: Data, data: Data, tries: UInt32) throws {
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
        }

        /// Update the token to use for the next enclave request.
        /// If backupId or tries are nil, attempts to use the previously known value.
        /// If we don't have a cached value (we've never stored a token before), an error is thrown.
        @discardableResult
        static func updateNext(backupId: Data? = nil, data: Data, tries: UInt32? = nil) throws -> Token {
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

            let token = try Token(backupId: backupId, data: data, tries: tries)
            token.recordAsCurrent()
            return token
        }

        /// Update the token to use for the next enclave request.
        @discardableResult
        static func updateNext(responseObject: Any?) throws -> Token {
            guard let paramParser = ParamParser(responseObject: responseObject) else {
                owsFailDebug("Unexpectedly missing response object")
                throw KBSError.assertion
            }

            let backupId = try paramParser.requiredBase64EncodedData(key: "backupId")
            let data = try paramParser.requiredBase64EncodedData(key: "token")
            let tries: UInt32 = try paramParser.required(key: "tries")

            let token = try Token(backupId: backupId, data: data, tries: tries)
            token.recordAsCurrent()
            return token
        }

        static func clearNext() {
            databaseStorage.write { transaction in
                keyValueStore.setData(nil, key: backupIdKey, transaction: transaction)
                keyValueStore.setData(nil, key: dataKey, transaction: transaction)
                keyValueStore.setObject(nil, key: triesKey, transaction: transaction)
            }
        }

        /// The token to use when making the next enclave request.
        static var next: Token? {
            return databaseStorage.read { transaction in
                guard let backupId = keyValueStore.getData(backupIdKey, transaction: transaction),
                    let data = keyValueStore.getData(dataKey, transaction: transaction),
                    let tries = keyValueStore.getUInt32(triesKey, transaction: transaction) else {
                        return nil
                }

                do {
                    return try Token(backupId: backupId, data: data, tries: tries)
                } catch {
                    // This should never happen, but if for some reason our stored token gets
                    // corrupted we'll return nil which will trigger us to fetch a fresh one
                    // from the enclave.
                    owsFailDebug("unexpectedly failed to initialize token with error: \(error)")
                    return nil
                }
            }
        }

        private func recordAsCurrent() {
            databaseStorage.write { transaction in
                Token.keyValueStore.setData(self.backupId, key: Token.backupIdKey, transaction: transaction)
                Token.keyValueStore.setData(self.data, key: Token.dataKey, transaction: transaction)
                Token.keyValueStore.setUInt32(self.tries, key: Token.triesKey, transaction: transaction)
            }
        }
    }

    private static func fetchToken(for remoteAttestation: RemoteAttestation) -> Promise<Token> {
        // If we already have a token stored, we need to use it before fetching another.
        // We only stop using this token once the enclave informs us it is spent.
        if let currentToken = Token.next { return Promise.value(currentToken) }

        // Fetch a new token

        let request = OWSRequestFactory.kbsEnclaveTokenRequest(
            withEnclaveName: remoteAttestation.enclaveName,
            authUsername: remoteAttestation.auth.username,
            authPassword: remoteAttestation.auth.password,
            cookies: remoteAttestation.cookies
        )

        return networkManager.makePromise(request: request).map(on: DispatchQueue.global()) { _, responseObject in
            try Token.updateNext(responseObject: responseObject)
        }
    }
}

// PRAGMA MARK: -

extension RemoteAttestation {
    static func makePromise(for service: RemoteAttestationService, with auth: RemoteAttestationAuth? = nil) -> Promise<RemoteAttestation> {
        return Promise { resolver in
            perform(for: service, auth: auth, success: {
                resolver.fulfill($0)
            }, failure: {
                resolver.reject($0)
            })
        }
    }
}

// PRAGMA MARK: -

private protocol KBSRequestOption {
    associatedtype ResponseOptionType
    static func responseOption(from response: KeyBackupProtoResponse) -> ResponseOptionType?
    func set(on builder: KeyBackupProtoRequest.KeyBackupProtoRequestBuilder)
}

extension KeyBackupProtoBackupRequest: KBSRequestOption {
    typealias ResponseOptionType = KeyBackupProtoBackupResponse
    static func responseOption(from response: KeyBackupProtoResponse) -> ResponseOptionType? {
        return response.backup
    }
    func set(on builder: KeyBackupProtoRequest.KeyBackupProtoRequestBuilder) {
        builder.setBackup(self)
    }
}
extension KeyBackupProtoRestoreRequest: KBSRequestOption {
    typealias ResponseOptionType = KeyBackupProtoRestoreResponse
    static func responseOption(from response: KeyBackupProtoResponse) -> ResponseOptionType? {
        return response.restore
    }
    func set(on builder: KeyBackupProtoRequest.KeyBackupProtoRequestBuilder) {
        builder.setRestore(self)
    }
}
extension KeyBackupProtoDeleteRequest: KBSRequestOption {
    typealias ResponseOptionType = KeyBackupProtoDeleteResponse
    static func responseOption(from response: KeyBackupProtoResponse) -> ResponseOptionType? {
        return response.delete
    }
    func set(on builder: KeyBackupProtoRequest.KeyBackupProtoRequestBuilder) {
        builder.setDelete(self)
    }
}
