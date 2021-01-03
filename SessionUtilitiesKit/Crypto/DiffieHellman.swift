import CryptoSwift
import Curve25519Kit

public final class DiffieHellman : NSObject {
    public static let ivSize: UInt = 16

    public enum Error : LocalizedError {
        case decryptionFailed
        case sharedSecretGenerationFailed

        public var errorDescription: String {
            switch self {
            case .decryptionFailed: return "Couldn't decrypt data"
            case .sharedSecretGenerationFailed: return "Couldn't generate a shared secret."
            }
        }
    }
    
    private override init() { }

    public static func encrypt(_ plaintext: Data, using symmetricKey: Data) throws -> Data {
        let iv = Data.getSecureRandomData(ofSize: ivSize)!
        let cbc = CBC(iv: iv.bytes)
        let aes = try AES(key: symmetricKey.bytes, blockMode: cbc)
        let ciphertext = try aes.encrypt(plaintext.bytes)
        let ivAndCiphertext = iv.bytes + ciphertext
        return Data(ivAndCiphertext)
    }
    
    public static func encrypt(_ plaintext: Data, publicKey: Data, privateKey: Data) throws -> Data {
        guard let symmetricKey = try? Curve25519.generateSharedSecret(fromPublicKey: publicKey, privateKey: privateKey) else { throw Error.sharedSecretGenerationFailed }
        return try encrypt(plaintext, using: symmetricKey)
    }
    
    public static func decrypt(_ ivAndCiphertext: Data, using symmetricKey: Data) throws -> Data {
        guard ivAndCiphertext.count >= ivSize else { throw Error.decryptionFailed }
        let iv = ivAndCiphertext[..<ivSize]
        let ciphertext = ivAndCiphertext[ivSize...]
        let cbc = CBC(iv: iv.bytes)
        let aes = try AES(key: symmetricKey.bytes, blockMode: cbc)
        let plaintext = try aes.decrypt(ciphertext.bytes)
        return Data(plaintext)
    }
    
    public static func decrypt(_ ivAndCiphertext: Data, publicKey: Data, privateKey: Data) throws -> Data {
        guard let symmetricKey = try? Curve25519.generateSharedSecret(fromPublicKey: publicKey, privateKey: privateKey) else { throw Error.sharedSecretGenerationFailed }
        return try decrypt(ivAndCiphertext, using: symmetricKey)
    }
}
