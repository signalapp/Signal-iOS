import CryptoSwift
import Curve25519Kit

private extension String {

    // Convert hex string to Data
    fileprivate var hexData: Data {
        var hex = self
        var data = Data()
        while(hex.count > 0) {
            let subIndex = hex.index(hex.startIndex, offsetBy: 2)
            let c = String(hex[..<subIndex])
            hex = String(hex[subIndex...])
            var ch: UInt32 = 0
            Scanner(string: c).scanHexInt32(&ch)
            var char = UInt8(ch)
            data.append(&char, count: 1)
        }
        return data
    }
}

/// A fallback session cipher which uses the the recipients public key to encrypt data
@objc public final class FallBackSessionCipher : NSObject {
    // The pubkey hex string of the recipient
    private let recipientId: String
    // The identity manager
    private let identityKeyStore: OWSIdentityManager

    // The length of the iv
    private let ivLength: Int32 = 16;
    
    // The pubkey representation of the hex id
    private lazy var recipientPubKey: Data = {
        var recipientId = self.recipientId
        
        // We need to check here if the id is prefix with '05'
        // We only need to do this if the length is 66
        if (recipientId.count == 66 && recipientId.hasPrefix("05")) {
            recipientId = recipientId.substring(from: 2)
        }

        return recipientId.hexData
    }()
    
    // Our identity key
    private lazy var userIdentityKeyPair: ECKeyPair? = identityKeyStore.identityKeyPair()
    
    // A symmetric key used for encryption and decryption
    private lazy var symmetricKey: Data? = {
        guard let userIdentityKeyPair = userIdentityKeyPair else { return nil }
        
        return try? Curve25519.generateSharedSecret(fromPublicKey: recipientPubKey, privateKey: userIdentityKeyPair.privateKey)
    }()
    
    /// Create a FallBackSessionCipher.
    /// This is a very basic cipher and should only be used in special cases such as Friend Requests.
    ///
    /// - Parameters:
    ///   - recipientId: The pubkey string of the recipient
    ///   - identityKeyStore: The identity manager
    @objc public init(recipientId: String, identityKeyStore: OWSIdentityManager) {
        self.recipientId = recipientId
        self.identityKeyStore = identityKeyStore
        super.init()
    }
    
    /// Encrypt a message
    ///
    /// - Parameter message: The message to encrypt
    /// - Returns: The encypted message or `nil` if it failed
    @objc public func encrypt(message: Data) -> Data? {
        guard let symmetricKey = symmetricKey else { return nil }
        do {
            return try DiffieHellman.encrypt(message, using: symmetricKey)
        } catch {
            Logger.warn("FallBackSessionCipher: Failed to encrypt message")
            return nil
        }
    }
    
    /// Decrypt a message
    ///
    /// - Parameter message: The message to decrypt
    /// - Returns: The decrypted message or `nil` if it failed
    @objc public func decrypt(message: Data) -> Data? {
        guard let symmetricKey = symmetricKey else { return nil }
        do {
            return try DiffieHellman.decrypt(message, using: symmetricKey)
        } catch {
            Logger.warn("FallBackSessionCipher: Failed to decrypt message")
            return nil
        }
    }
}
