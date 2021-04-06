//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

import SignalClient
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
        return ECPublicKey(secondaryDeviceKeyPair.publicKey)
    }

    let secondaryDeviceKeyPair: IdentityKeyPair
    init(secondaryDeviceKeyPair: IdentityKeyPair) {
        self.secondaryDeviceKeyPair = secondaryDeviceKeyPair
    }

    public class func generate() -> ProvisioningCipher {
        return ProvisioningCipher(secondaryDeviceKeyPair: IdentityKeyPair.generate())
    }

    internal class var messageInfo: String {
        return "TextSecure Provisioning Message"
    }

    // MARK: 

    public func decrypt(envelope: ProvisioningProtoProvisionEnvelope) throws -> ProvisionMessage {
        let primaryDeviceEphemeralPublicKey = try PublicKey(envelope.publicKey)
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

        let agreement = secondaryDeviceKeyPair.privateKey.keyAgreement(
            with: primaryDeviceEphemeralPublicKey)

        let keyBytes = try Self.messageInfo.utf8.withContiguousStorageIfAvailable {
            try hkdf(outputLength: 64, version: 3, inputKeyMaterial: agreement, salt: [], info: $0)
        }!

        let cipherKey = Array(keyBytes[0..<32])
        let macKey = keyBytes[32..<64]

        guard let ourHMAC = Cryptography.computeSHA256HMAC(Data(messageToAuthenticate), key: Data(macKey)) else {
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

        let identityKeyPair = try IdentityKeyPair(publicKey: PublicKey(proto.identityKeyPublic),
                                                  privateKey: PrivateKey(proto.identityKeyPrivate))
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
                                identityKeyPair: ECKeyPair(identityKeyPair),
                                profileKey: profileKey,
                                areReadReceiptsEnabled: areReadReceiptsEnabled,
                                primaryUserAgent: primaryUserAgent,
                                provisioningCode: provisioningCode,
                                provisioningVersion: provisioningVersion)
    }
}
