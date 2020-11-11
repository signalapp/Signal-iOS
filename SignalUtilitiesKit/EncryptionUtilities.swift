import CryptoSwift

internal typealias EncryptionResult = (ciphertext: Data, symmetricKey: Data, ephemeralPublicKey: Data)

enum EncryptionUtilities {
    internal static let gcmTagSize: UInt = 16
    internal static let ivSize: UInt = 12

    /// - Note: Sync. Don't call from the main thread.
    internal static func encrypt(_ plaintext: Data, usingAESGCMWithSymmetricKey symmetricKey: Data) throws -> Data {
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
    internal static func encrypt(_ plaintext: Data, using hexEncodedX25519PublicKey: String) throws -> EncryptionResult {
        if Thread.isMainThread {
            #if DEBUG
            preconditionFailure("It's illegal to call encrypt(_:forSnode:) from the main thread.")
            #endif
        }
        let x25519PublicKey = Data(hex: hexEncodedX25519PublicKey)
        let ephemeralKeyPair = Curve25519.generateKeyPair()
        let ephemeralSharedSecret = try! Curve25519.generateSharedSecret(fromPublicKey: x25519PublicKey, privateKey: ephemeralKeyPair.privateKey)
        let salt = "LOKI"
        let symmetricKey = try HMAC(key: salt.bytes, variant: .sha256).authenticate(ephemeralSharedSecret.bytes)
        let ciphertext = try encrypt(plaintext, usingAESGCMWithSymmetricKey: Data(bytes: symmetricKey))
        return (ciphertext, Data(bytes: symmetricKey), ephemeralKeyPair.publicKey)
    }
}
