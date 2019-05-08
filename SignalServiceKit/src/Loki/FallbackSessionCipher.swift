import Curve25519Kit
import CryptoSwift

private extension String {
    // Convert hex string to Data
    var hexData: Data {
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

/// A fallback session cipher which uses the the recipients pubkey to encrypt data
@objc public final class FallBackSessionCipher: NSObject {
    
    // The length of the iv
    private let ivLength: Int32 = 16;
    
    // The pubkey hex string of the recipient
    private let recipientId: String
    
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
    
    // The identity manager
    private let identityKeyStore: OWSIdentityManager
    
    // Our identity key
    private lazy var myIdentityKeyPair: ECKeyPair? = {
        return identityKeyStore.identityKeyPair()
    }()
    
    /// Creare a FallBackSessionCipher.
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
    /// - Returns: The encypted message or nil if it failed
    @objc public func encrypt(message: Data) -> Data? {
        do {
            let myIdentityKeyPair = self.myIdentityKeyPair!
            let symmetricKey = try Curve25519.generateSharedSecret(fromPublicKey: recipientPubKey, privateKey: myIdentityKeyPair.privateKey)
            return try diffieHellmanEncrypt(message: message, symmetricKey: symmetricKey)
        } catch {
            Logger.warn("FallBackSessionCipher: Failed to encrypt message")
            return nil
        }
    }
    
    // Encypt the message with the symmetric key and a 16 bit iv
    private func diffieHellmanEncrypt(message: Data, symmetricKey: Data) throws -> Data {
        let iv = Randomness.generateRandomBytes(ivLength)!
        let ivBytes = [UInt8](iv)
        
        let symmetricKeyBytes = [UInt8](symmetricKey)
        let messageBytes = [UInt8](message)
        
        let blockMode = CBC(iv: ivBytes)
        let aes = try AES(key: symmetricKeyBytes, blockMode: blockMode)
        let cipherText = try aes.encrypt(messageBytes)
        let ivAndCipher = ivBytes + cipherText
        return Data(bytes: ivAndCipher, count: ivAndCipher.count)
    }
}
