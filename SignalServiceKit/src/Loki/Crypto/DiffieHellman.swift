import CryptoSwift
import Curve25519Kit

public enum DiffieHellman {
    
    public static let ivLength: Int32 = 16;
    
    public static func encrypt(_ plainTextData: Data, using symmetricKey: Data) throws -> Data {
        let iv = Randomness.generateRandomBytes(ivLength)!
        let ivBytes = [UInt8](iv)
        let symmetricKeyBytes = [UInt8](symmetricKey)
        let messageBytes = [UInt8](plainTextData)
        let blockMode = CBC(iv: ivBytes)
        let aes = try AES(key: symmetricKeyBytes, blockMode: blockMode)
        let cipherText = try aes.encrypt(messageBytes)
        let ivAndCipher = ivBytes + cipherText
        return Data(bytes: ivAndCipher, count: ivAndCipher.count)
    }
    
    public static func encrypt(_ plainTextData: Data, publicKey: Data, privateKey: Data) throws -> Data {
        let symmetricKey = try Curve25519.generateSharedSecret(fromPublicKey: publicKey, privateKey: privateKey)
        return try encrypt(plainTextData, using: symmetricKey)
    }
    
    public static func decrypt(_ encryptedData: Data, using symmetricKey: Data) throws -> Data {
        let symmetricKeyBytes = [UInt8](symmetricKey)
        let ivBytes = [UInt8](encryptedData[..<ivLength])
        let cipherBytes = [UInt8](encryptedData[ivLength...])
        let blockMode = CBC(iv: ivBytes)
        let aes = try AES(key: symmetricKeyBytes, blockMode: blockMode)
        let decrypted = try aes.decrypt(cipherBytes)
        return Data(bytes: decrypted, count: decrypted.count)
    }
    
    public static func decrypt(_ encryptedData: Data, publicKey: Data, privateKey: Data) throws -> Data {
        let symmetricKey = try Curve25519.generateSharedSecret(fromPublicKey: publicKey, privateKey: privateKey)
        return try decrypt(encryptedData, using: symmetricKey)
    }
}
