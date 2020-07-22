//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

import SignalMetadataKit
import PromiseKit
import CommonCrypto

public struct ProvisionMessage {
    public let uuid: UUID?
    public let phoneNumber: String
    public let identityKeyPair: ECKeyPair
    public let profileKey: OWSAES256Key
    public let areReadReceiptsEnabled: Bool?
    public let primaryUserAgent: String?
    public let provisioningCode: String
    public let provisioningVersion: UInt32?
}

public enum ProvisioningError: Error {
    case invalidProvisionMessage(_ description: String)
}

public class ProvisioningCipher {

    public var secondaryDevicePublicKey: ECPublicKey {
        return try! secondaryDeviceKeyPair.ecPublicKey()
    }

    let secondaryDeviceKeyPair: ECKeyPair
    init(secondaryDeviceKeyPair: ECKeyPair) {
        self.secondaryDeviceKeyPair = secondaryDeviceKeyPair
    }

    public class func generate() -> ProvisioningCipher {
        return ProvisioningCipher(secondaryDeviceKeyPair: Curve25519.generateKeyPair())
    }

    // MARK: 

    public func decrypt(envelope: ProvisioningProtoProvisionEnvelope) throws -> ProvisionMessage {
        let primaryDeviceEphemeralPublicKey = try ECPublicKey(serializedKeyData: envelope.publicKey)
        let bytes = [UInt8](envelope.body)

        let versionLength = 1
        let ivLength = 16
        let macLength = 32
        let provisionMessageLength = bytes.count - versionLength - ivLength - macLength
        guard provisionMessageLength > 0 else {
            throw ProvisioningError.invalidProvisionMessage("provisioning message too short.")
        }

        let version = bytes[0]
        guard version == 1 else {
            throw ProvisioningError.invalidProvisionMessage("Unexpected version on provisioing message: \(bytes[0])")
        }

        let iv = Array(bytes[1..<17])
        let theirMac = bytes.suffix(32)
        let messageToAuthenticate = bytes[0..<(bytes.count - 32)]
        let ciphertext = Array(bytes[17..<(bytes.count - 32)])
        let agreement = try Curve25519.generateSharedSecret(fromPublicKey: primaryDeviceEphemeralPublicKey.keyData,
                                                            privateKey: try secondaryDeviceKeyPair.ecPrivateKey().keyData)

        let info = "TextSecure Provisioning Message".data(using: .utf8)!
        let salt = Data([UInt8](repeating: 0, count: 32))
        let keys = try HKDFKit.deriveKey(agreement, info: info, salt: salt, outputSize: 64)
        let keyBytes = [UInt8](keys)

        let cipherKey = Array(keyBytes[0..<32])
        let macKey = keyBytes[32..<64]

        guard let ourHMAC = Cryptography.computeSHA256HMAC(Data(messageToAuthenticate), withHMACKey: Data(macKey)) else {
            throw OWSAssertionError("ourHMAC was unexpectedly nil")
        }

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

        let plaintext = Data(plaintextBuffer.prefix(upTo: bytesDecrypted))
        let proto = try ProvisioningProtoProvisionMessage(serializedData: plaintext)

        let identityKeyPair = try ECKeyPair(serializedPublicKeyData: proto.identityKeyPublic, privateKeyData: proto.identityKeyPrivate)
        guard let profileKey = OWSAES256Key(data: proto.profileKey) else {
            throw ProvisioningError.invalidProvisionMessage("invalid profileKey - count: \(proto.profileKey.count)")
        }
        let areReadReceiptsEnabled = proto.hasReadReceipts ? proto.readReceipts : nil
        let primaryUserAgent = proto.hasUserAgent ? proto.userAgent : nil
        let provisioningCode = proto.provisioningCode
        let provisioningVersion = proto.hasProvisioningVersion ? proto.provisioningVersion : nil

        guard let phoneNumber = proto.number, phoneNumber.count > 1 else {
            throw ProvisioningError.invalidProvisionMessage("missing number from provisioning message")
        }

        let uuid: UUID? = try {
            guard proto.hasUuid, let uuidString = proto.uuid else { return nil }
            guard let uuid = UUID(uuidString: uuidString) else {
                throw ProvisioningError.invalidProvisionMessage("invalid uuid from provisioning message")
            }
            return uuid
        }()

        return ProvisionMessage(uuid: uuid,
                                phoneNumber: phoneNumber,
                                identityKeyPair: identityKeyPair,
                                profileKey: profileKey,
                                areReadReceiptsEnabled: areReadReceiptsEnabled,
                                primaryUserAgent: primaryUserAgent,
                                provisioningCode: provisioningCode,
                                provisioningVersion: provisioningVersion)
    }
}

private extension ECKeyPair {
    convenience init(serializedPublicKeyData: Data, privateKeyData: Data) throws {
        let publicKey = try (serializedPublicKeyData as NSData).removeKeyType() as Data
        try self.init(publicKeyData: publicKey, privateKeyData: privateKeyData)
    }
}
