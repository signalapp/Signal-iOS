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
        static let version: UInt8 = 1
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
        initializationVector: Data? = nil,
    ) {
        self.ourKeyPair = ourKeyPair
        self.initializationVector = initializationVector ?? Randomness.generateRandomBytes(UInt(kCCBlockSizeAES128))
    }

    public func encrypt(_ data: Data, theirPublicKey: PublicKey) throws -> Data {
        let sharedSecret = self.ourKeyPair.privateKey.keyAgreement(with: theirPublicKey)

        let infoData = Constants.info
        let totalLength = Constants.cipherKeyLength + Constants.macKeyLength
        let derivedSecret = try infoData.utf8.withContiguousStorageIfAvailable {
            return try hkdf(outputLength: totalLength, inputKeyMaterial: sharedSecret, salt: [], info: $0)
        }!
        owsPrecondition(derivedSecret.count == totalLength)
        let cipherKey = derivedSecret.prefix(Constants.cipherKeyLength)
        let macKey = derivedSecret.dropFirst(Constants.cipherKeyLength)
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
                            keyBytes.baseAddress,
                            keyBytes.count,
                            ivBytes.baseAddress,
                            dataBytes.baseAddress,
                            dataBytes.count,
                            ciphertextBytes.baseAddress,
                            ciphertextBytes.count,
                            &bytesEncrypted,
                        )
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

    public func decrypt(data bytes: Data, theirPublicKey: PublicKey) throws -> Data {
        var bytes = bytes

        let versionLength = 1
        let ivLength = 16
        let macLength = 32

        let theirMac = bytes.suffix(macLength)
        bytes = bytes.dropLast(macLength)

        let messageToAuthenticate = bytes

        let version = bytes.first
        bytes = bytes.dropFirst(versionLength)

        let initializationVector = bytes.prefix(ivLength)
        bytes = bytes.dropFirst(ivLength)

        let ciphertext = bytes

        guard let version, initializationVector.count == ivLength, theirMac.count == macLength, !ciphertext.isEmpty else {
            throw ProvisioningError.invalidProvisionMessage("provisioning message too short.")
        }

        guard version == Constants.version else {
            throw ProvisioningError.invalidProvisionMessage("Unexpected version on provisioning message: \(version)")
        }

        let agreement = ourKeyPair.privateKey.keyAgreement(with: theirPublicKey)

        let keyBytes = try Constants.info.utf8.withContiguousStorageIfAvailable {
            try hkdf(outputLength: 64, inputKeyMaterial: agreement, salt: [], info: $0)
        }!

        owsPrecondition(keyBytes.count == 64)
        let cipherKey = keyBytes.prefix(32)
        let macKey = keyBytes.dropFirst(32).prefix(32)

        let ourHMAC = Data(HMAC<SHA256>.authenticationCode(for: messageToAuthenticate, using: .init(data: macKey)))
        guard ourHMAC.ows_constantTimeIsEqual(to: theirMac) else {
            throw ProvisioningError.invalidProvisionMessage("mac mismatch")
        }

        var bytesDecrypted: size_t = 0
        var plaintextData = Data(count: ciphertext.count)
        let cryptStatus = cipherKey.withUnsafeBytes { keyBytes in
            initializationVector.withUnsafeBytes { ivBytes in
                ciphertext.withUnsafeBytes { ciphertextBytes in
                    plaintextData.withUnsafeMutableBytes { dataBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES128),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress,
                            keyBytes.count,
                            ivBytes.baseAddress,
                            ciphertextBytes.baseAddress,
                            ciphertextBytes.count,
                            dataBytes.baseAddress,
                            dataBytes.count,
                            &bytesDecrypted,
                        )
                    }
                }
            }
        }

        guard cryptStatus == kCCSuccess else {
            throw OWSAssertionError("failure with cryptStatus: \(cryptStatus)")
        }

        return plaintextData.prefix(bytesDecrypted)
    }
}
