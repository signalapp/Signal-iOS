//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class SMKUDAccessKey: NSObject {

    @objc
    public static let kUDAccessKeyLength: Int = 16

    @objc
    public let keyData: Data

    @objc
    public init(profileKey: Data) throws {
        guard let aesGcmKey = OWSAES256Key(data: profileKey) else {
            throw SMKError.assertionError(description: "Profile key is not valid AES GCM key.")
        }

        // We derive the "ud access key" from the private key by encrypting zeroes.
        let emptyPlaintextLength = 16
        let emptyPlaintext = Data(count: Int(emptyPlaintextLength))
        let initializationVector = Data(count: Int(kAESGCM256_IVLength))
        guard let keyData = Cryptography.encryptAESGCM(plainTextData: emptyPlaintext,
                                                initializationVector: initializationVector,
                                                additionalAuthenticatedData: nil,
                                                key: aesGcmKey) else {
                                                    throw SMKError.assertionError(description: "Could not derive UD access key from profile key.")
        }
        guard keyData.ciphertext.count == SMKUDAccessKey.kUDAccessKeyLength else {
            throw SMKError.assertionError(description: "\(SMKUDAccessKey.logTag) key has invalid length")
        }

        self.keyData = keyData.ciphertext
    }

    @objc
    public init(randomKeyData: ()) {
        self.keyData = Randomness.generateRandomBytes(Int32(SMKUDAccessKey.kUDAccessKeyLength))
    }

    // MARK:

    override public func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? SMKUDAccessKey else { return false }
        return self.keyData == other.keyData
    }
}
