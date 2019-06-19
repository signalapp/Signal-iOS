//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import CommonCrypto

@objc(OWSKeyBackupService)
public class KeyBackupService: NSObject {
    enum KBSError: Error {
        case assertion
        case invalidPin(triesRemaining: UInt32)
        case backupMissing
    }

    // PRAGMA MARK: - Depdendencies
    static var networkManager: TSNetworkManager {
        return TSNetworkManager.shared()
    }

    static var keychainStorage: SSKKeychainStorage {
        return CurrentAppContext().keychainStorage()
    }

    // PRAGMA MARK: - Pin Management

    // TODO: Decide what we want this to be
    static let maximumKeyAttempts: UInt32 = 10

    /// Indicates whether or not we have a local copy of your keys to verify your pin
    @objc
    public static var hasLocalKeys: Bool {
        return storedMasterKey != nil && storedPinKey2 != nil
    }

    /// Indicates whether your pin is valid when compared to your stored keys.
    /// This is a local verification and does not make any requests to the KBS.
    public static func verifyPin(_ pin: String, resultHandler: @escaping (Bool) -> Void) {
        cryptoQueue.async {
            var isValid = false
            defer {
                DispatchQueue.main.async { resultHandler(isValid) }
            }

            guard hasLocalKeys else {
                owsFailDebug("Attempted to verify pin locally when we don't have KBS keys")
                return
            }

            guard let masterKey = storedMasterKey else {
                owsFailDebug("unexpectedly missing master key")
                return
            }

            guard let pinKey2 = storedPinKey2 else {
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

    /// Loads the users key, if any, from the KBS into the keychain.
    public static func restoreKeys(with pin: String, and auth: RemoteAttestationAuth? = nil) -> Promise<Void> {
        return cryptoQueue.async(.promise) { () -> (Data, Data) in
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
            cryptoQueue.async(.promise) { () -> (Data, Data, Data) in
                guard let status = response.status else {
                    owsFailDebug("KBS restore is missing status")
                    throw KBSError.assertion
                }

                switch status {
                case .nonceMismatch:
                    // the given nonce is outdated;
                    // TODO: the request should be retried with new nonce value
                    owsFailDebug("attempted restore with expired nonce")
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

            switch status {
            case .nonceMismatch:
                // the given nonce is outdated;
                // TODO: the request should be retried with new nonce value
                owsFailDebug("attempted backup with expired nonce")
                throw KBSError.assertion
            case .notYetValid:
                owsFailDebug("the server thinks we provided a `validFrom` in the future")
                throw KBSError.assertion
            case .ok:
                // We successfully stored the new keys in KBS, save them in the keychain
                storePinKey2(pinKey2)
                storeMasterKey(masterKey)
            }
        }
    }

    @objc(generateAndBackupKeysWithPin:)
    static func objc_generateAndBackupKeys(with pin: String) -> AnyPromise {
        return AnyPromise(generateAndBackupKeys(with: pin))
    }

    /// Generates a new master key for the given pin, backs it up to the KBS,
    /// and stores it locally in the keychain.
    public static func generateAndBackupKeys(with pin: String) -> Promise<Void> {
        return cryptoQueue.async(.promise) { () -> (Data, Data, Data) in
            guard let stretchedPin = deriveStretchedPin(from: pin) else {
                owsFailDebug("failed to derive stretched pin")
                throw KBSError.assertion
            }

            guard let pinKey1 = derivePinKey1(from: stretchedPin) else {
                owsFailDebug("failed to derive pinKey1")
                throw KBSError.assertion
            }

            let pinKey2 = generatePinKey2()

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

            switch status {
            case .nonceMismatch:
                // the given nonce is outdated;
                // TODO: the request should be retried with new nonce value
                owsFailDebug("attempted backup with expired nonce")
                throw KBSError.assertion
            case .notYetValid:
                owsFailDebug("the server thinks we provided a `validFrom` in the future")
                throw KBSError.assertion
            case .ok:
                // We successfully stored the new keys in KBS, save them in the keychain
                storePinKey2(pinKey2)
                storeMasterKey(masterKey)
            }
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
            // purge them from the keychain.
            clearKeychain()
        }.asVoid()
    }

    // PRAGMA MARK: - Crypto

    private static let cryptoQueue = DispatchQueue(label: "KeyBackupServiceQueue")

    private static func assertIsOnCryptoQueue() {
        assertOnQueue(cryptoQueue)
    }

    private static func deriveStretchedPin(from pin: String) -> Data? {
        assertIsOnCryptoQueue()

        guard let pinData = pin.data(using: .utf8) else {
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
        assertIsOnCryptoQueue()

        guard let data = "Master Key Encryption".data(using: .utf8) else {
            owsFailDebug("Failed to encode data")
            return nil
        }
        return Cryptography.computeSHA256HMAC(data, withHMACKey: stretchedPin)
    }

    private static func generatePinKey2() -> Data {
        assertIsOnCryptoQueue()

        return OWSAES256Key.generateRandom().keyData
    }

    private static func deriveMasterKey(from pinKey1: Data, and pinKey2: Data) -> Data? {
        assertIsOnCryptoQueue()

        return Cryptography.computeSHA256HMAC(pinKey2, withHMACKey: pinKey1)
    }

    @objc
    static func deriveRegistrationLockToken() -> String? {
        guard let masterKey = storedMasterKey else {
            return nil
        }

        guard let data = "Registration Lock".data(using: .utf8) else {
            return nil
        }

        return Cryptography.computeSHA256HMAC(data, withHMACKey: masterKey)?.hexadecimalString
    }

    // PRAGMA MARK: - Keychain

    private static let keychainService = "OWSKeyBackup"
    private static let masterKeyKeychainIdentifer = "KBSMasterKey"
    private static let pinKey2KeychainIdentifer = "KBSPinKey2"

    // We want this data to persist across devices an app installs to allow
    // backup restoration.
    private static let keychainAccessType = kSecAttrAccessibleAfterFirstUnlock

    /// Removes the KBS keys locally from the device, they can still be
    /// restored from the server if you know the pin.
    @objc
    public static func clearKeychain() {
        clearMasterKey()
        clearPinKey2()
    }

    private static var storedMasterKey: Data? {
        return try? CurrentAppContext().keychainStorage().data(
            forService: keychainService,
            key: masterKeyKeychainIdentifer
        )
    }

    private static func storeMasterKey(_ masterKey: Data) {
        try? keychainStorage.set(data: masterKey, service: keychainService, key: masterKeyKeychainIdentifer)
    }

    private static func clearMasterKey() {
        try? keychainStorage.remove(service: keychainService, key: masterKeyKeychainIdentifer)
    }

    private static var storedPinKey2: Data? {
        return try? keychainStorage.data(forService: keychainService, key: pinKey2KeychainIdentifer)
    }

    private static func storePinKey2(_ pinKey2: Data) {
        try? keychainStorage.set(data: pinKey2, service: keychainService, key: pinKey2KeychainIdentifer)
    }

    private static func clearPinKey2() {
        try? keychainStorage.remove(service: keychainService, key: pinKey2KeychainIdentifer)
    }

    // PRAGMA MARK: - Requests

    private static func enclaveRequest<RequestType: KBSRequestBody>(
        with auth: RemoteAttestationAuth? = nil,
        and kbRequestBuilder: @escaping (NonceResponse) throws -> RequestType
    ) -> Promise<RequestType.ResponseType> {
        return RemoteAttestation.makePromise(for: .keyBackup, with: auth).then { remoteAttestation in
            fetchNonce(for: remoteAttestation).map { ($0, remoteAttestation) }
        }.map { nonce, remoteAttestation -> (TSRequest, RemoteAttestation) in
            let kbRequest = try kbRequestBuilder(nonce)
            let requestBuilder = KeyBackupProtoRequest.builder()
            kbRequest.setRequest(on: requestBuilder)
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
                enclaveId: remoteAttestation.enclaveId,
                authUsername: remoteAttestation.auth.username,
                authPassword: remoteAttestation.auth.password,
                cookies: remoteAttestation.cookies
            )

            return (request, remoteAttestation)
        }.then { request, remoteAttestation in
            networkManager.makePromise(request: request).map { ($0.responseObject, remoteAttestation) }
        }.map { responseObject, remoteAttestation in
            guard let parser = ParamParser(responseObject: responseObject) else {
                owsFailDebug("Failed to parse response object")
                throw KBSError.assertion
            }

            let data = try parser.requiredBase64EncodedData(key: "data")
            let iv = try parser.requiredBase64EncodedData(key: "iv")
            let mac = try parser.requiredBase64EncodedData(key: "mac")

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

            guard let kbResponse = try? KeyBackupProtoResponse.parseData(encryptionResult) else {
                owsFailDebug("failed to parse KBS response data")
                throw KBSError.assertion
            }

            guard let typedResponse = RequestType.response(from: kbResponse) else {
                owsFailDebug("missing KBS response object")
                throw KBSError.assertion
            }

            return typedResponse
        }
    }

    private static func backupKeyRequest(stretchedPin: Data, keyData: Data, and auth: RemoteAttestationAuth? = nil) -> Promise<KeyBackupProtoBackupResponse> {
        return enclaveRequest(with: auth) { nonce -> KeyBackupProtoBackupRequest in
            let backupRequestBuilder = KeyBackupProtoBackupRequest.builder()
            backupRequestBuilder.setData(keyData)
            backupRequestBuilder.setPin(stretchedPin)
            backupRequestBuilder.setNonce(nonce.nonce)
            backupRequestBuilder.setBackupID(nonce.backupId)
            backupRequestBuilder.setTries(maximumKeyAttempts)

            // number of seconds since unix epoch after which this request should be valid
            // Always set to the client's clock time, minus 24 hours to account for inaccurate clocks
            backupRequestBuilder.setValidFrom(UInt64(Date().addingTimeInterval(-kDayInterval).timeIntervalSince1970))

            return try backupRequestBuilder.build()
        }
    }

    private static func restoreKeyRequest(stretchedPin: Data, with auth: RemoteAttestationAuth? = nil) -> Promise<KeyBackupProtoRestoreResponse> {
        return enclaveRequest(with: auth) { nonce -> KeyBackupProtoRestoreRequest in
            let restoreRequestBuilder = KeyBackupProtoRestoreRequest.builder()
            restoreRequestBuilder.setPin(stretchedPin)
            restoreRequestBuilder.setNonce(nonce.nonce)
            restoreRequestBuilder.setBackupID(nonce.backupId)

            // number of seconds since unix epoch after which this request should be valid
            // Always set to the client's clock time, minus 24 hours to account for inaccurate clocks
            restoreRequestBuilder.setValidFrom(UInt64(Date().addingTimeInterval(-kDayInterval).timeIntervalSince1970))

            return try restoreRequestBuilder.build()
        }
    }

    private static func deleteKeyRequest() -> Promise<KeyBackupProtoDeleteResponse> {
        return enclaveRequest { nonce -> KeyBackupProtoDeleteRequest in
            let deleteRequestBuilder = KeyBackupProtoDeleteRequest.builder()
            deleteRequestBuilder.setBackupID(nonce.backupId)

            return try deleteRequestBuilder.build()
        }
    }

    // PRAGMA MARK: - Nonce

    private struct NonceResponse {
        let backupId: Data
        let nonce: Data
        let tries: Int

        static func parse(json: Dictionary<String, Any>) -> NonceResponse? {
            guard let backupIdString = json["backupId"] as? String,
                let backupId = Data(base64Encoded: backupIdString),
                let nonceString = json["nonce"] as? String,
                let nonce = Data(base64Encoded: nonceString),
                let tries = json["tries"] as? Int else { return nil }
            return NonceResponse(
                backupId: backupId,
                nonce: nonce,
                tries: tries
            )
        }
    }

    private static func fetchNonce(for remoteAttestation: RemoteAttestation) -> Promise<NonceResponse> {
        let request = OWSRequestFactory.kbsEnclaveNonceRequest(
            withEnclaveId: remoteAttestation.enclaveId,
            authUsername: remoteAttestation.auth.username,
            authPassword: remoteAttestation.auth.password,
            cookies: remoteAttestation.cookies
        )

        return networkManager.makePromise(request: request).map { _, responseObject in
            guard let response = responseObject as? [String: Any],
                let nonceResponse = NonceResponse.parse(json: response) else {
                    owsFailDebug("failed to parse KBS nonce response json")
                    throw KBSError.assertion
            }

            return nonceResponse
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

private protocol KBSRequestBody {
    associatedtype ResponseType
    static func response(from response: KeyBackupProtoResponse) -> ResponseType?
    func setRequest(on builder: KeyBackupProtoRequest.KeyBackupProtoRequestBuilder)
}

extension KeyBackupProtoBackupRequest: KBSRequestBody {
    typealias ResponseType = KeyBackupProtoBackupResponse
    static func response(from response: KeyBackupProtoResponse) -> ResponseType? {
        return response.backup
    }
    func setRequest(on builder: KeyBackupProtoRequest.KeyBackupProtoRequestBuilder) {
        builder.setBackup(self)
    }
}
extension KeyBackupProtoRestoreRequest: KBSRequestBody {
    typealias ResponseType = KeyBackupProtoRestoreResponse
    static func response(from response: KeyBackupProtoResponse) -> ResponseType? {
        return response.restore
    }
    func setRequest(on builder: KeyBackupProtoRequest.KeyBackupProtoRequestBuilder) {
        builder.setRestore(self)
    }
}
extension KeyBackupProtoDeleteRequest: KBSRequestBody {
    typealias ResponseType = KeyBackupProtoDeleteResponse
    static func response(from response: KeyBackupProtoResponse) -> ResponseType? {
        return response.delete
    }
    func setRequest(on builder: KeyBackupProtoRequest.KeyBackupProtoRequestBuilder) {
        builder.setDelete(self)
    }
}
