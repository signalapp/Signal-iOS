import CryptoSwift

enum DecryptionUtilities {

    /// - Note: Sync. Don't call from the main thread.
    internal static func decrypt(_ ivAndCiphertext: Data, usingAESGCMWithSymmetricKey symmetricKey: Data) throws -> Data {
        if Thread.isMainThread {
            #if DEBUG
            preconditionFailure("It's illegal to call decrypt(_:usingAESGCMWithSymmetricKey:) from the main thread.")
            #endif
        }
        let iv = ivAndCiphertext[0..<Int(EncryptionUtilities.ivSize)]
        let ciphertext = ivAndCiphertext[Int(EncryptionUtilities.ivSize)...]
        let gcm = GCM(iv: iv.bytes, tagLength: Int(EncryptionUtilities.gcmTagSize), mode: .combined)
        let aes = try AES(key: symmetricKey.bytes, blockMode: gcm, padding: .noPadding)
        return Data(try aes.decrypt(ciphertext.bytes))
    }
}
