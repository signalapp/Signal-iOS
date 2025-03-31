//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public struct RegistrationProvisioningEnvelope {

    public let body: Data
    public let publicKey: Data

    public init(serializedData: Data) throws {
        let proto = try RegistrationProtos_RegistrationProvisionEnvelope(serializedBytes: serializedData)
        self.body = proto.body
        self.publicKey = proto.publicKey
    }
}

public struct RegistrationProvisioningMessage {

    public enum Platform {
        case ios
        case android
    }
    public enum BackupTier {
        case free
        case paid
    }

    public let accountEntropyPool: AccountEntropyPool
    public let aci: Aci
    public let phoneNumber: E164
    public let pin: String?
    public let platform: Platform
    public let tier: BackupTier?
    public let backupTimestamp: UInt64?
    public let backupSizeBytes: UInt64?
    public let restoreMethodToken: String?

    public init(
        accountEntropyPool: AccountEntropyPool,
        aci: Aci,
        phoneNumber: E164,
        pin: String?,
        tier: BackupTier?,
        backupTimestamp: UInt64?,
        backupSizeBytes: UInt64?,
        restoreMethodToken: String?
    ) {
        self.platform = .ios
        self.accountEntropyPool = accountEntropyPool
        self.aci = aci
        self.phoneNumber = phoneNumber
        self.pin = pin
        self.tier = tier
        self.backupTimestamp = backupTimestamp
        self.backupSizeBytes = backupSizeBytes
        self.restoreMethodToken = restoreMethodToken
    }

    public init(plaintext: Data) throws {
        let proto = try RegistrationProtos_RegistrationProvisionMessage(serializedBytes: plaintext)

        guard
            let accountEntropyPool = proto.accountEntropyPool.nilIfEmpty,
            let aep = try? AccountEntropyPool(key: accountEntropyPool)
        else {
            throw ProvisioningError.invalidProvisionMessage("missing master key from provisioning message")
        }
        self.accountEntropyPool = aep

        self.aci = try Aci.parseFrom(serviceIdBinary: proto.aci)

        guard let e164 = E164(proto.e164) else {
            throw ProvisioningError.invalidProvisionMessage("missing number from provisioning message")
        }
        self.phoneNumber = e164

        self.pin = proto.pin

        self.platform = proto.platform == .android ? .android : .ios

        self.tier = proto.tier == .paid ? .paid : .free
        self.backupTimestamp = proto.backupTimestampMs
        self.backupSizeBytes = proto.backupSizeBytes

        self.restoreMethodToken = proto.restoreMethodToken
    }

    public func buildEncryptedMessageBody(theirPublicKey: PublicKey) throws -> Data {
        var messageBuilder = RegistrationProtos_RegistrationProvisionMessage()

        messageBuilder.accountEntropyPool = accountEntropyPool.rawData
        messageBuilder.aci = aci.serviceIdBinary.asData
        messageBuilder.e164 = phoneNumber.stringValue
        if let pin {
            messageBuilder.pin = pin
        }

        messageBuilder.platform = .ios

        // TODO: [Backups] Check backups are enabled before populating this
        if let tier {
            let protoTier: RegistrationProtos_RegistrationProvisionMessage.Tier
            switch tier {
            case .free: protoTier = .free
            case .paid: protoTier = .paid
            }
            messageBuilder.tier = protoTier
        }

        if let backupTimestamp {
            messageBuilder.backupTimestampMs = backupTimestamp
        }
        if let backupSizeBytes {
            messageBuilder.backupSizeBytes = backupSizeBytes
        }

        let plainTextMessage = try messageBuilder.serializedData()

        let ourKeyPair = IdentityKeyPair.generate()
        let cipher = ProvisioningCipher(ourKeyPair: ourKeyPair)
        let encryptedMessage: Data
        do {
            encryptedMessage = try cipher.encrypt(plainTextMessage, theirPublicKey: theirPublicKey)
        } catch {
            throw OWSAssertionError("Failed to encrypt registration provisioning message")
        }

        var envelopeBuilder = RegistrationProtos_RegistrationProvisionEnvelope()
        envelopeBuilder.publicKey = ourKeyPair.publicKey.serialize().asData
        envelopeBuilder.body = encryptedMessage

        return try envelopeBuilder.serializedData()
    }
}
