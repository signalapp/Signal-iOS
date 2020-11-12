import CryptoSwift
import Curve25519Kit
import SessionUtilitiesKit

/// A fallback session cipher which uses the the recipient's public key to encrypt data.
@objc public final class FallBackSessionCipher : NSObject {
    /// The hex encoded public key of the recipient.
    private let recipientPublicKey: String
    private let privateKey: Data?
    private let ivSize: Int32 = 16

    private lazy var recipientPublicKeyAsData: Data = {
        var recipientPublicKey = self.recipientPublicKey
        if recipientPublicKey.count == 66 && recipientPublicKey.hasPrefix("05") {
            let index = recipientPublicKey.index(recipientPublicKey.startIndex, offsetBy: 2)
            recipientPublicKey = recipientPublicKey.substring(from: index)
        }
        return Data(hex: recipientPublicKey)
    }()

    private lazy var symmetricKey: Data? = {
        guard let privateKey = privateKey else { return nil }
        return try? Curve25519.generateSharedSecret(fromPublicKey: recipientPublicKeyAsData, privateKey: privateKey)
    }()
    
    @objc public init(recipientPublicKey: String, privateKey: Data?) {
        self.recipientPublicKey = recipientPublicKey
        self.privateKey = privateKey
        super.init()
    }

    @objc public func encrypt(_ plaintext: Data) -> Data? {
        guard let symmetricKey = symmetricKey else { return nil }
        do {
            return try DiffieHellman.encrypt(plaintext, using: symmetricKey)
        } catch {
            SNLog("Couldn't encrypt message using fallback session cipher due to error: \(error).")
            return nil
        }
    }

    @objc public func decrypt(_ ivAndCiphertext: Data) -> Data? {
        guard let symmetricKey = symmetricKey else { return nil }
        do {
            return try DiffieHellman.decrypt(ivAndCiphertext, using: symmetricKey)
        } catch {
            SNLog("Couldn't decrypt message using fallback session cipher due to error: \(error).")
            return nil
        }
    }
}
