import CryptoSwift
import PromiseKit

extension OnionRequestAPI {

    internal typealias EncryptionResult = (ciphertext: Data, symmetricKey: Data, ephemeralPublicKey: Data)

    /// Returns `size` bytes of random data generated using the default random number generator. See
    /// [SecRandomCopyBytes](https://developer.apple.com/documentation/security/1399291-secrandomcopybytes) for more information.
    private static func getRandomData(ofSize size: UInt) throws -> Data {
        var data = Data(count: Int(size))
        let result = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, Int(size), $0.baseAddress!) }
        guard result == errSecSuccess else { throw Error.randomDataGenerationFailed }
        return data
    }

    /// - Note: Sync. Don't call from the main thread.
    private static func encrypt(_ plaintext: Data, usingAESGCMWithSymmetricKey symmetricKey: Data) throws -> Data {
        guard !Thread.isMainThread else { preconditionFailure("It's illegal to call encryptUsingAESGCM(symmetricKey:plainText:) from the main thread.") }
        let ivSize: UInt = 12
        let iv = try getRandomData(ofSize: ivSize)
        let gcmTagLength: UInt = 128
        let gcm = GCM(iv: iv.bytes, tagLength: Int(gcmTagLength), mode: .combined)
        let aes = try AES(key: symmetricKey.bytes, blockMode: gcm, padding: .noPadding)
        let ciphertext = try aes.encrypt(plaintext.bytes)
        return Data(bytes: ciphertext)
    }

    /// - Note: Sync. Don't call from the main thread.
    private static func encrypt(_ plaintext: Data, forSnode snode: LokiAPITarget) throws -> EncryptionResult {
        guard !Thread.isMainThread else { preconditionFailure("It's illegal to call encrypt(_:forSnode:) from the main thread.") }
        guard let hexEncodedSnodeX25519PublicKey = snode.publicKeySet?.x25519Key else { throw Error.snodePublicKeySetMissing }
        let snodeX25519PublicKey = Data(hex: hexEncodedSnodeX25519PublicKey)
        let ephemeralKeyPair = Curve25519.generateKeyPair()
        let ephemeralSharedSecret = try Curve25519.generateSharedSecret(fromPublicKey: snodeX25519PublicKey, privateKey: ephemeralKeyPair.privateKey)
        let password = "LOKI"
        let key = try HKDF(password: password.bytes, variant: .sha256).calculate()
        let symmetricKey = try HMAC(key: key, variant: .sha256).authenticate(ephemeralSharedSecret.bytes)
        let ciphertext = try encrypt(plaintext, usingAESGCMWithSymmetricKey: Data(bytes: symmetricKey))
        return (ciphertext, Data(bytes: symmetricKey), ephemeralKeyPair.publicKey)
    }

    /// Encrypts `payload` for `snode` and returns the result. Use this to build the core of an onion request.
    internal static func encrypt(_ payload: Data, forTargetSnode snode: LokiAPITarget) -> Promise<EncryptionResult> {
        let (promise, seal) = Promise<EncryptionResult>.pending()
        workQueue.async {
            let parameters: JSON = [ "body" : payload ]
            do {
                let plaintext = try JSONSerialization.data(withJSONObject: parameters, options: [])
                let result = try encrypt(plaintext, forSnode: snode)
                seal.fulfill(result)
            } catch (let error) {
                seal.reject(error)
            }
        }
        return promise
    }

    /// Encrypts the previous encryption result (i.e. that of the hop after this one) for the given hop. Use this to build the layers of an onion request.
    internal static func encryptHop(from snode1: LokiAPITarget, to snode2: LokiAPITarget, using previousEncryptionResult: EncryptionResult) -> Promise<EncryptionResult> {
        let (promise, seal) = Promise<EncryptionResult>.pending()
        workQueue.async {
            let parameters: JSON = [
                "ciphertext" : previousEncryptionResult.ciphertext.base64EncodedString(),
                "ephemeral_key" : previousEncryptionResult.ephemeralPublicKey.toHexString(),
                "destination" : snode2.publicKeySet!.ed25519Key
            ]
            do {
                let plaintext = try JSONSerialization.data(withJSONObject: parameters, options: [])
                let result = try encrypt(plaintext, forSnode: snode1)
                seal.fulfill(result)
            } catch (let error) {
                seal.reject(error)
            }
        }
        return promise
    }
}
