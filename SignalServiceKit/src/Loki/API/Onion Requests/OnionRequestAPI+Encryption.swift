import CryptoSwift
import PromiseKit

extension OnionRequestAPI {
    internal static let gcmTagSize: UInt = 16
    internal static let ivSize: UInt = 12

    internal typealias EncryptionResult = (ciphertext: Data, symmetricKey: Data, ephemeralPublicKey: Data)

    /// - Note: Sync. Don't call from the main thread.
    private static func encrypt(_ plaintext: Data, usingAESGCMWithSymmetricKey symmetricKey: Data) throws -> Data {
        guard !Thread.isMainThread else { preconditionFailure("It's illegal to call encrypt(_:usingAESGCMWithSymmetricKey:) from the main thread.") }
        guard let iv = Data.getSecureRandomData(ofSize: ivSize) else { throw Error.randomDataGenerationFailed }
        let gcm = GCM(iv: iv.bytes, tagLength: Int(gcmTagSize), mode: .combined)
        let aes = try AES(key: symmetricKey.bytes, blockMode: gcm, padding: .noPadding)
        let ciphertext = try aes.encrypt(plaintext.bytes)
        return iv + Data(bytes: ciphertext)
    }

    /// - Note: Sync. Don't call from the main thread.
    private static func encrypt(_ plaintext: Data, forSnode snode: LokiAPITarget) throws -> EncryptionResult {
        guard !Thread.isMainThread else { preconditionFailure("It's illegal to call encrypt(_:forSnode:) from the main thread.") }
        guard let hexEncodedSnodeX25519PublicKey = snode.publicKeySet?.x25519Key else { throw Error.snodePublicKeySetMissing }
        let snodeX25519PublicKey = Data(hex: hexEncodedSnodeX25519PublicKey)
        let ephemeralKeyPair = Curve25519.generateKeyPair()
        let ephemeralSharedSecret = try Curve25519.generateSharedSecret(fromPublicKey: snodeX25519PublicKey, privateKey: ephemeralKeyPair.privateKey)
        let salt = "LOKI"
        let symmetricKey = try HMAC(key: salt.bytes, variant: .sha256).authenticate(ephemeralSharedSecret.bytes)
        let ciphertext = try encrypt(plaintext, usingAESGCMWithSymmetricKey: Data(bytes: symmetricKey))
        return (ciphertext, Data(bytes: symmetricKey), ephemeralKeyPair.publicKey)
    }

    /// Encrypts `payload` for `snode` and returns the result. Use this to build the core of an onion request.
    internal static func encrypt(_ payload: JSON, forTargetSnode snode: LokiAPITarget) -> Promise<EncryptionResult> {
        let (promise, seal) = Promise<EncryptionResult>.pending()
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                guard JSONSerialization.isValidJSONObject(payload) else { return seal.reject(HTTP.Error.invalidJSON) }
                let payloadAsData = try JSONSerialization.data(withJSONObject: payload, options: [ .fragmentsAllowed ])
                let payloadAsString = String(data: payloadAsData, encoding: .utf8)! // Snodes only accept this as a string
                let wrapper: JSON = [ "body" : payloadAsString, "headers" : "" ]
                guard JSONSerialization.isValidJSONObject(wrapper) else { return seal.reject(HTTP.Error.invalidJSON) }
                let plaintext = try JSONSerialization.data(withJSONObject: wrapper, options: [ .fragmentsAllowed ])
                let result = try encrypt(plaintext, forSnode: snode)
                seal.fulfill(result)
            } catch (let error) {
                seal.reject(error)
            }
        }
        return promise
    }

    /// Encrypts the previous encryption result (i.e. that of the hop after this one) for this hop. Use this to build the layers of an onion request.
    internal static func encryptHop(from lhs: LokiAPITarget, to rhs: LokiAPITarget, using previousEncryptionResult: EncryptionResult) -> Promise<EncryptionResult> {
        let (promise, seal) = Promise<EncryptionResult>.pending()
        DispatchQueue.global(qos: .userInitiated).async {
            let parameters: JSON = [
                "ciphertext" : previousEncryptionResult.ciphertext.base64EncodedString(),
                "ephemeral_key" : previousEncryptionResult.ephemeralPublicKey.toHexString(),
                "destination" : rhs.publicKeySet!.ed25519Key
            ]
            do {
                guard JSONSerialization.isValidJSONObject(parameters) else { return seal.reject(HTTP.Error.invalidJSON) }
                let plaintext = try JSONSerialization.data(withJSONObject: parameters, options: [ .fragmentsAllowed ])
                let result = try encrypt(plaintext, forSnode: lhs)
                seal.fulfill(result)
            } catch (let error) {
                seal.reject(error)
            }
        }
        return promise
    }
}
