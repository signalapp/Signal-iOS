//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import Curve25519Kit

@objc
public enum DeviceNameError: Int, Error {
    case assertionFailure
}

@objc
public class DeviceNames: NSObject {
    // Never instantiate this class.
    private override init() {}

    @objc
    public class func encryptDeviceName(plaintext: String,
                                        identityKeyPair: ECKeyPair) throws -> Data {

        guard let plaintextData = plaintext.data(using: .utf8) else {
            owsFail("Could not convert text to UTF-8.")
        }

        let ephemeralKeyPair = Curve25519.generateKeyPair()

        // master_secret = ECDH(ephemeral_private, identity_public).
        let masterSecret: Data
        do {
            masterSecret = try Curve25519.generateSharedSecret(fromPublicKey: identityKeyPair.publicKey,
                                                                     privateKey: ephemeralKeyPair.privateKey)
        } catch {
            Logger.error("Could not generate shared secret: \(error)")
            throw error
        }

        // synthetic_iv = HmacSHA256(key=HmacSHA256(key=master_secret, input=“auth”), input=plaintext)[0:16]
        guard let syntheticIVInput = "auth".data(using: .utf8) else {
            owsFail("Could not convert text to UTF-8.")
        }
        guard let syntheticIVKey = Cryptography.computeSHA256HMAC(syntheticIVInput, withHMACKey: masterSecret) else {
            owsFailDebug("Could not compute synthetic IV key.")
            throw DeviceNameError.assertionFailure
        }
        let ivLength: UInt = 16
        guard let syntheticIV = Cryptography.truncatedSHA256HMAC(plaintextData, withHMACKey: syntheticIVKey, truncation: ivLength) else {
            owsFailDebug("Could not compute synthetic IV.")
            throw DeviceNameError.assertionFailure
        }

        // cipher_key = HmacSHA256(key=HmacSHA256(key=master_secret, “cipher”), input=synthetic_iv)
        guard let cipherKeyInput = "cipher".data(using: .utf8) else {
            owsFail("Could not convert text to UTF-8.")
        }
        guard let cipherKeyKey = Cryptography.computeSHA256HMAC(cipherKeyInput, withHMACKey: masterSecret) else {
            owsFailDebug("Could not compute cipher key key.")
            throw DeviceNameError.assertionFailure
        }
        guard let cipherKey = Cryptography.computeSHA256HMAC(syntheticIV, withHMACKey: cipherKeyKey) else {
            owsFailDebug("Could not compute cipher key.")
            throw DeviceNameError.assertionFailure
        }

        // cipher_text = AES-CTR(key=cipher_key, input=plaintext, counter=0)
        //
        // TODO: Is this right?
        let cipherTextIV = Data(count: Int(kAES256CTR_IVLength))
        guard let cipherTextKey = OWSAES256Key(data: cipherKey) else {
            owsFailDebug("Invalid cipher key.")
            throw DeviceNameError.assertionFailure
        }
        guard let cipherText: AES256CTREncryptionResult = Cryptography.encryptAESCTR(plaintextData: plaintextData, initializationVector: cipherTextIV, key: cipherTextKey) else {
            owsFailDebug("Could not compute cipher text.")
            throw DeviceNameError.assertionFailure
        }

        let protoBuilder = SignalIOSProtoDeviceName.builder(ephemeralPublic: ephemeralKeyPair.publicKey,
                                                            syntheticIv: syntheticIV,
                                                            ciphertext: cipherText.ciphertext)
        let protoData = try protoBuilder.buildSerializedData()

        let protoDataBase64 = protoData.base64EncodedData()

        return protoDataBase64
    }
}
