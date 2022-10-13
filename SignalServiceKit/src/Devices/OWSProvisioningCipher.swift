//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CommonCrypto
import LibSignalClient

public class OWSProvisioningCipher: NSObject {
    // Local errors for logging purposes only.
    // FIXME: If we start propagating errors out of encrypt(_:), we'll want to revisit this.
    private enum Error: Swift.Error {
        case unexpectedLengthForInitializationVector
        case dataIsTooLongToEncrypt
        case encryptionFailed
        case macComputationFailed
    }

    private static let cipherKeyLength: Int = 32
    private static let macKeyLength: Int = 32

    private let theirPublicKeyData: Data
    private let ourKeyPair: IdentityKeyPair
    private let initializationVector: Data

    @objc
    public convenience init(theirPublicKey: Data) {
        self.init(
            theirPublicKey: theirPublicKey,
            ourKeyPair: IdentityKeyPair.generate(),
            initializationVector: Cryptography.generateRandomBytes(UInt(kCCBlockSizeAES128)))
    }

    #if TESTABLE_BUILD
    @objc
    private convenience init(theirPublicKey: Data, ourKeyPair: ECKeyPair, initializationVector: Data) {
        self.init(
            theirPublicKey: theirPublicKey,
            ourKeyPair: ourKeyPair.identityKeyPair,
            initializationVector: initializationVector)
    }
    #endif

    private init(theirPublicKey: Data, ourKeyPair: IdentityKeyPair, initializationVector: Data) {
        self.theirPublicKeyData = theirPublicKey
        self.ourKeyPair = ourKeyPair
        self.initializationVector = initializationVector
    }

    public var ourPublicKey: PublicKey { self.ourKeyPair.publicKey }

    // FIXME: propagate errors from here instead of just returning nil.
    // This means auditing all of the places we throw OR deciding it's okay to throw arbitrary errors.
    @objc
    public func encrypt(_ data: Data) -> Data? {
        do {
            let theirPublicKey = try! ECPublicKey(keyData: theirPublicKeyData).key
            let sharedSecret = self.ourKeyPair.privateKey.keyAgreement(with: theirPublicKey)

            let infoData = ProvisioningCipher.messageInfo
            let derivedSecret: [UInt8] = try infoData.utf8.withContiguousStorageIfAvailable {
                let totalLength = Self.cipherKeyLength + Self.macKeyLength
                return try hkdf(outputLength: totalLength, inputKeyMaterial: sharedSecret, salt: [], info: $0)
            }!
            let cipherKey = derivedSecret[0..<Self.cipherKeyLength]
            let macKey = derivedSecret[Self.cipherKeyLength...]
            owsAssertDebug(macKey.count == Self.macKeyLength)

            let cipherText = try self.encrypt(data, key: cipherKey)

            let version: UInt8 = 1
            var message: Data = Data()
            message.append(version)
            message.append(cipherText)

            let mac = try self.mac(forMessage: message, key: macKey)
            message.append(mac)
            return message

        } catch {
            owsFailDebug("error: \(error)")
            return nil
        }
    }

    private func encrypt(_ data: Data, key: ArraySlice<UInt8>) throws -> Data {
        guard initializationVector.count == kCCBlockSizeAES128 else {
            // FIXME: This can only occur during testing; should it be non-recoverable?
            throw Error.unexpectedLengthForInitializationVector
        }

        guard data.count < Int.max - (kCCBlockSizeAES128 + initializationVector.count) else {
            throw Error.dataIsTooLongToEncrypt
        }

        let ciphertextBufferSize = data.count + kCCBlockSizeAES128

        var ciphertextData = Data(count: ciphertextBufferSize)

        var bytesEncrypted = 0
        let cryptStatus: CCCryptorStatus = key.withUnsafeBytes { keyBytes in
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
            throw Error.encryptionFailed
        }

        // message format is (iv || ciphertext)
        return initializationVector + ciphertextData.prefix(bytesEncrypted)
    }

    private func mac(forMessage message: Data, key: ArraySlice<UInt8>) throws -> Data {
        guard let mac = Cryptography.computeSHA256HMAC(message, key: Data(key)) else {
            throw Error.macComputationFailed
        }
        return mac
    }
}
