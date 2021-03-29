import CryptoSwift
import Curve25519Kit

public enum AESGCM {
    public static let gcmTagSize: UInt = 16
    public static let ivSize: UInt = 12

    public struct EncryptionResult { public let ciphertext: Data, symmetricKey: Data, ephemeralPublicKey: Data }

    public enum Error : LocalizedError {
        case keyPairGenerationFailed
        case sharedSecretGenerationFailed

        public var errorDescription: String? {
            switch self {
            case .keyPairGenerationFailed: return "Couldn't generate a key pair."
            case .sharedSecretGenerationFailed: return "Couldn't generate a shared secret."
            }
        }
    }

    /// - Note: Sync. Don't call from the main thread.
    public static func generateSymmetricKey(x25519PublicKey: Data, x25519PrivateKey: Data) throws -> Data {
        if Thread.isMainThread {
            #if DEBUG
            preconditionFailure("It's illegal to call encrypt(_:forSnode:) from the main thread.")
            #endif
        }
        guard let sharedSecret = try? Curve25519.generateSharedSecret(fromPublicKey: x25519PublicKey, privateKey: x25519PrivateKey) else {
            throw Error.sharedSecretGenerationFailed
        }
        let salt = "LOKI"
        return try Data(HMAC(key: salt.bytes, variant: .sha256).authenticate(sharedSecret.bytes))
    }
    
    /// - Note: Sync. Don't call from the main thread.
    public static func decrypt(_ ivAndCiphertext: Data, with symmetricKey: Data) throws -> Data {
        if Thread.isMainThread {
            #if DEBUG
            preconditionFailure("It's illegal to call decrypt(_:usingAESGCMWithSymmetricKey:) from the main thread.")
            #endif
        }
        let iv = ivAndCiphertext[0..<Int(ivSize)]
        let ciphertext = ivAndCiphertext[Int(ivSize)...]
        let gcm = GCM(iv: iv.bytes, tagLength: Int(gcmTagSize), mode: .combined)
        let aes = try AES(key: symmetricKey.bytes, blockMode: gcm, padding: .noPadding)
        return Data(try aes.decrypt(ciphertext.bytes))
    }

    /// - Note: Sync. Don't call from the main thread.
    public static func encrypt(_ plaintext: Data, with symmetricKey: Data) throws -> Data {
        if Thread.isMainThread {
            #if DEBUG
            preconditionFailure("It's illegal to call encrypt(_:usingAESGCMWithSymmetricKey:) from the main thread.")
            #endif
        }
        let iv = Data.getSecureRandomData(ofSize: ivSize)!
        let gcm = GCM(iv: iv.bytes, tagLength: Int(gcmTagSize), mode: .combined)
        let aes = try AES(key: symmetricKey.bytes, blockMode: gcm, padding: .noPadding)
        let ciphertext = try aes.encrypt(plaintext.bytes)
        return iv + Data(ciphertext)
    }

    /// - Note: Sync. Don't call from the main thread.
    public static func encrypt(_ plaintext: Data, for hexEncodedX25519PublicKey: String) throws -> EncryptionResult {
        if Thread.isMainThread {
            #if DEBUG
            preconditionFailure("It's illegal to call encrypt(_:forSnode:) from the main thread.")
            #endif
        }
        let x25519PublicKey = Data(hex: hexEncodedX25519PublicKey)
        let ephemeralKeyPair = Curve25519.generateKeyPair()
        let symmetricKey = try generateSymmetricKey(x25519PublicKey: x25519PublicKey, x25519PrivateKey: ephemeralKeyPair.privateKey)
        let ciphertext = try encrypt(plaintext, with: Data(symmetricKey))
        return EncryptionResult(ciphertext: ciphertext, symmetricKey: Data(symmetricKey), ephemeralPublicKey: ephemeralKeyPair.publicKey)
    }
}
