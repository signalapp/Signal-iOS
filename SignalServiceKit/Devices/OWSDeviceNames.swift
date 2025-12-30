//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CryptoKit
import Foundation
public import LibSignalClient

public enum OWSDeviceNameError: Error {
    case assertionFailure
    case invalidInput
    case cryptError(_ description: String)
}

public enum OWSDeviceNames {

    private static let syntheticIVLength = 16

    public static func encryptDeviceName(plaintext: String, identityKeyPair: IdentityKeyPair) throws -> Data {
        let plaintextData = Data(plaintext.utf8)

        let ephemeralKeyPair = IdentityKeyPair.generate()

        // master_secret = ECDH(ephemeral_private, identity_public).
        let masterSecret = ephemeralKeyPair.privateKey.keyAgreement(with: identityKeyPair.publicKey)

        // synthetic_iv = HmacSHA256(key=HmacSHA256(key=master_secret, input=“auth”), input=plaintext)[0:16]
        let syntheticIV = computeSyntheticIV(masterSecret: masterSecret, plaintextData: plaintextData)

        // cipher_key = HmacSHA256(key=HmacSHA256(key=master_secret, “cipher”), input=synthetic_iv)
        let cipherKey = computeCipherKey(masterSecret: masterSecret, syntheticIV: syntheticIV)

        // cipher_text = AES-CTR(key=cipher_key, input=plaintext, counter=0)
        var ciphertext = plaintextData
        // An all-zeros IV corresponds to an AES CTR counter of zero.
        try Aes256Ctr32.process(&ciphertext, key: cipherKey, nonce: Data(count: Aes256Ctr32.nonceLength))

        let protoBuilder = SignalIOSProtoDeviceName.builder(
            ephemeralPublic: ephemeralKeyPair.publicKey.serialize(),
            syntheticIv: syntheticIV,
            ciphertext: ciphertext,
        )
        return try protoBuilder.buildSerializedData()
    }

    private static func computeSyntheticIV(masterSecret: Data, plaintextData: Data) -> Data {
        // synthetic_iv = HmacSHA256(key=HmacSHA256(key=master_secret, input=“auth”), input=plaintext)[0:16]
        let syntheticIVInput = Data("auth".utf8)
        let syntheticIVKey = Data(HMAC<SHA256>.authenticationCode(for: syntheticIVInput, using: .init(data: masterSecret)))
        let syntheticIV = Data(HMAC<SHA256>.authenticationCode(for: plaintextData, using: .init(data: syntheticIVKey)).prefix(syntheticIVLength))
        return syntheticIV
    }

    private static func computeCipherKey(masterSecret: Data, syntheticIV: Data) -> Data {
        // cipher_key = HmacSHA256(key=HmacSHA256(key=master_secret, “cipher”), input=synthetic_iv)
        let cipherKeyInput = Data("cipher".utf8)
        let cipherKeyKey = Data(HMAC<SHA256>.authenticationCode(for: cipherKeyInput, using: .init(data: masterSecret)))
        let cipherKey = Data(HMAC<SHA256>.authenticationCode(for: syntheticIV, using: .init(data: cipherKeyKey)))
        return cipherKey
    }

    public static func decryptDeviceName(base64String: String, identityKeyPair: IdentityKeyPair) throws -> String {

        guard let protoData = Data(base64Encoded: base64String) else {
            // Not necessarily an error; might be a legacy device name.
            throw OWSDeviceNameError.invalidInput
        }

        return try decryptDeviceName(protoData: protoData, identityKeyPair: identityKeyPair)
    }

    public static func decryptDeviceName(protoData: Data, identityKeyPair: IdentityKeyPair) throws -> String {

        let proto: SignalIOSProtoDeviceName
        do {
            proto = try SignalIOSProtoDeviceName(serializedData: protoData)
        } catch {
            // Not necessarily an error; might be a legacy device name.
            Logger.error("failed to parse proto")
            throw OWSDeviceNameError.invalidInput
        }

        let ephemeralPublicData = proto.ephemeralPublic
        let receivedSyntheticIV = proto.syntheticIv
        let ciphertext = proto.ciphertext

        let ephemeralPublic: PublicKey
        do {
            ephemeralPublic = try PublicKey(ephemeralPublicData)
        } catch {
            owsFailDebug("failed to remove key type")
            throw OWSDeviceNameError.invalidInput
        }

        guard receivedSyntheticIV.count == syntheticIVLength else {
            owsFailDebug("Invalid synthetic IV.")
            throw OWSDeviceNameError.assertionFailure
        }
        guard ciphertext.count > 0 else {
            owsFailDebug("Invalid cipher text.")
            throw OWSDeviceNameError.assertionFailure
        }

        // master_secret = ECDH(identity_private, ephemeral_public)
        let masterSecret = identityKeyPair.privateKey.keyAgreement(with: ephemeralPublic)

        // cipher_key = HmacSHA256(key=HmacSHA256(key=master_secret, input=“cipher”), input=synthetic_iv)
        let cipherKey = computeCipherKey(masterSecret: masterSecret, syntheticIV: receivedSyntheticIV)

        // plaintext = AES-CTR(key=cipher_key, input=ciphertext, counter=0)
        var plaintextData = ciphertext
        // An all-zeros IV corresponds to an AES CTR counter of zero.
        try Aes256Ctr32.process(&plaintextData, key: cipherKey, nonce: Data(count: Aes256Ctr32.nonceLength))

        // Verify the synthetic IV was correct.
        // constant_time_compare(HmacSHA256(key=HmacSHA256(key=master_secret, input=”auth”), input=plaintext)[0:16], synthetic_iv) == true
        let computedSyntheticIV = computeSyntheticIV(masterSecret: masterSecret, plaintextData: plaintextData)
        guard receivedSyntheticIV.ows_constantTimeIsEqual(to: computedSyntheticIV) else {
            throw OWSDeviceNameError.cryptError("Synthetic IV did not match.")
        }

        guard let plaintext = String(bytes: plaintextData, encoding: .utf8) else {
            owsFailDebug("Invalid plaintext.")
            throw OWSDeviceNameError.invalidInput
        }

        return plaintext
    }
}
