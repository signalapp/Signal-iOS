//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CommonCrypto
import CryptoKit
public import LibSignalClient

public enum ProvisioningError: Error {
    case invalidProvisionMessage(_ description: String)
}

public class ProvisioningCipher {

    private enum Constants {
        static let cipherKeyLength: Int = 32
        static let macKeyLength: Int = 32
        static let info: String = "TextSecure Provisioning Message"
    }

    private let ourKeyPair: IdentityKeyPair
    private let initializationVector: Data

    public var ourPublicKey: PublicKey {
        return ourKeyPair.publicKey
    }

    public init(
        ourKeyPair: IdentityKeyPair = IdentityKeyPair.generate(),
        initializationVector: Data? = nil
    ) {
        self.ourKeyPair = ourKeyPair
        self.initializationVector = initializationVector ?? Randomness.generateRandomBytes(UInt(kCCBlockSizeAES128))
    }

    public func encrypt(_ data: Data, theirPublicKey: PublicKey) throws -> Data {
        let sharedSecret = self.ourKeyPair.privateKey.keyAgreement(with: theirPublicKey)

        let infoData = Constants.info
        let derivedSecret: [UInt8] = try infoData.utf8.withContiguousStorageIfAvailable {
            let totalLength = Constants.cipherKeyLength + Constants.macKeyLength
            return try hkdf(outputLength: totalLength, inputKeyMaterial: sharedSecret, salt: [], info: $0)
        }!
        let cipherKey = derivedSecret[0..<Constants.cipherKeyLength]
        let macKey = derivedSecret[Constants.cipherKeyLength...]
        owsAssertDebug(macKey.count == Constants.macKeyLength)

        guard data.count < Int.max - (kCCBlockSizeAES128 + initializationVector.count) else {
            throw ProvisioningError.invalidProvisionMessage("data too long to encrypt.")
        }

        let ciphertextBufferSize = data.count + kCCBlockSizeAES128

        var ciphertextData = Data(count: ciphertextBufferSize)

        var bytesEncrypted = 0
        let cryptStatus: CCCryptorStatus = cipherKey.withUnsafeBytes { keyBytes in
            initializationVector.withUnsafeBytes { ivBytes in
                data.withUnsafeBytes { dataBytes in
                    ciphertextData.withUnsafeMutableBytes { ciphertextBytes in
                        let status = CCCrypt(
                            CCOperation(kCCEncrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress, keyBytes.count,
                            ivBytes.baseAddress,
                            dataBytes.baseAddress, dataBytes.count,
                            ciphertextBytes.baseAddress, ciphertextBytes.count,
                            &bytesEncrypted)
                        return status
                    }
                }
            }
        }

        guard cryptStatus == kCCSuccess else {
            throw ProvisioningError.invalidProvisionMessage("failure with status \(cryptStatus)")
        }

        // message format is (iv || ciphertext)
        let cipherText = initializationVector + ciphertextData.prefix(bytesEncrypted)

        let version: UInt8 = 1
        var message: Data = Data()
        message.append(version)
        message.append(cipherText)

        let mac = Data(HMAC<SHA256>.authenticationCode(for: message, using: .init(data: macKey)))
        message.append(mac)
        return message
    }

    public func decrypt(data: Data, theirPublicKey: PublicKey) throws -> Data {
        let bytes = [UInt8](data)

        let versionLength = 1
        let ivLength = 16
        let macLength = 32
        let provisionMessageLength = bytes.count - versionLength - ivLength - macLength
        guard provisionMessageLength > 0 else {
            throw ProvisioningError.invalidProvisionMessage("provisioning message too short.")
        }

        let version = bytes[0]
        guard version == 1 else {
            throw ProvisioningError.invalidProvisionMessage("Unexpected version on provisioning message: \(bytes[0])")
        }

        let iv = Array(bytes[1..<17])
        let theirMac = bytes.suffix(32)
        let messageToAuthenticate = bytes[0..<(bytes.count - 32)]
        let ciphertext = Array(bytes[17..<(bytes.count - 32)])

        let agreement = ourKeyPair.privateKey.keyAgreement(with: theirPublicKey)

        let keyBytes = try Constants.info.utf8.withContiguousStorageIfAvailable {
            try hkdf(outputLength: 64, inputKeyMaterial: agreement, salt: [], info: $0)
        }!

        let cipherKey = Array(keyBytes[0..<32])
        let macKey = keyBytes[32..<64]

        let ourHMAC = Data(HMAC<SHA256>.authenticationCode(for: messageToAuthenticate, using: .init(data: macKey)))
        guard ourHMAC.ows_constantTimeIsEqual(to: Data(theirMac)) else {
            throw ProvisioningError.invalidProvisionMessage("mac mismatch")
        }

        var bytesDecrypted: size_t = 0
        var plaintextBuffer: [UInt8] = [UInt8].init(repeating: 0, count: ciphertext.count + kCCBlockSizeAES128)
        let cryptStatus = CCCrypt(CCOperation(kCCDecrypt),
                                  CCAlgorithm(kCCAlgorithmAES128),
                                  CCOptions(kCCOptionPKCS7Padding),
                                  cipherKey,
                                  cipherKey.count,
                                  iv,
                                  ciphertext,
                                  ciphertext.count,
                                  &plaintextBuffer,
                                  plaintextBuffer.count,
                                  &bytesDecrypted)

        guard cryptStatus == kCCSuccess else {
            throw OWSAssertionError("failure with cryptStatus: \(cryptStatus)")
        }

        return Data(plaintextBuffer.prefix(upTo: bytesDecrypted))
    }
}
