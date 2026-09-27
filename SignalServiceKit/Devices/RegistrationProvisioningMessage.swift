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

    public enum Capability: String {
        case wifiaware = "wifiaware"
    }

    /// Wraps state that's only available for accounts with phone numbers.
    public struct PhoneNumberState {
        public let phoneNumber: E164
        public let pniIdentityKeyPair: IdentityKeyPair

        public init(phoneNumber: E164, pniIdentityKeyPair: IdentityKeyPair) {
            self.phoneNumber = phoneNumber
            self.pniIdentityKeyPair = pniIdentityKeyPair
        }
    }

    public enum Platform {
        case ios
        case android
    }

    public enum BackupTier: Equatable {
        case free
        case paid
    }

    public let aci: Aci
    public let aciIdentityKeyPair: IdentityKeyPair
    public let phoneNumberState: PhoneNumberState
    public let accountEntropyPool: AccountEntropyPool
    public let pin: String?
    public let platform: Platform
    public let tier: BackupTier?
    public let backupVersion: UInt64?
    public let backupTimestamp: UInt64?
    public let backupSizeBytes: UInt64?
    public let restoreMethodToken: String?
    public let lastBackupForwardSecrecyToken: LibSignalClient.BackupForwardSecrecyToken?
    public let nextBackupSecretData: BackupNonce.NextSecretMetadata?
    public let capabilites: [Capability]

    public init(
        aci: Aci,
        aciIdentityKeyPair: IdentityKeyPair,
        phoneNumberState: PhoneNumberState,
        accountEntropyPool: AccountEntropyPool,
        pin: String?,
        tier: BackupTier?,
        backupVersion: UInt64?,
        backupTimestamp: UInt64?,
        backupSizeBytes: UInt64?,
        restoreMethodToken: String?,
        lastBackupForwardSecrecyToken: LibSignalClient.BackupForwardSecrecyToken?,
        nextBackupSecretData: BackupNonce.NextSecretMetadata?,
        capabilites: [Capability],
    ) {
        self.platform = .ios
        self.accountEntropyPool = accountEntropyPool
        self.aci = aci
        self.aciIdentityKeyPair = aciIdentityKeyPair
        self.phoneNumberState = phoneNumberState
        self.pin = pin
        self.tier = tier
        self.backupVersion = backupVersion
        self.backupTimestamp = backupTimestamp
        self.backupSizeBytes = backupSizeBytes
        self.restoreMethodToken = restoreMethodToken
        self.lastBackupForwardSecrecyToken = lastBackupForwardSecrecyToken
        self.nextBackupSecretData = nextBackupSecretData
        self.capabilites = capabilites
    }

    public init(_ proto: RegistrationProtos_RegistrationProvisionMessage) throws {
        self.aciIdentityKeyPair = try IdentityKeyPair(
            publicKey: PublicKey(proto.aciIdentityKeyPublic),
            privateKey: PrivateKey(proto.aciIdentityKeyPrivate),
        )

        let pniIdentityKeyPair = try IdentityKeyPair(
            publicKey: PublicKey(proto.pniIdentityKeyPublic),
            privateKey: PrivateKey(proto.pniIdentityKeyPrivate),
        )

        self.accountEntropyPool = try AccountEntropyPool(key: proto.accountEntropyPool)

        self.aci = try Aci.parseFrom(serviceIdBinary: proto.aci)

        guard let phoneNumber = E164(proto.e164) else {
            throw OWSGenericError("missing number from provisioning message")
        }
        self.phoneNumberState = PhoneNumberState(
            phoneNumber: phoneNumber,
            pniIdentityKeyPair: pniIdentityKeyPair,
        )

        self.pin = proto.pin

        self.platform = proto.platform == .android ? .android : .ios

        self.tier = proto.tier == .paid ? .paid : .free
        self.backupVersion = proto.backupVersion
        self.backupTimestamp = proto.backupTimestampMs
        self.backupSizeBytes = proto.backupSizeBytes

        self.restoreMethodToken = proto.restoreMethodToken

        self.capabilites = proto.capabilities.compactMap { Capability(rawValue: $0) }

        if let data = proto.lastBackupForwardSecrecyToken.nilIfEmpty {
            self.lastBackupForwardSecrecyToken = try LibSignalClient.BackupForwardSecrecyToken(contents: data)
        } else {
            self.lastBackupForwardSecrecyToken = nil
        }

        if let data = proto.nextBackupSecretData.nilIfEmpty {
            self.nextBackupSecretData = BackupNonce.NextSecretMetadata(data: data)
        } else {
            self.nextBackupSecretData = nil
        }
    }

    public func buildEncryptedMessageBody(theirPublicKey: PublicKey) throws -> Data {
        var messageBuilder = RegistrationProtos_RegistrationProvisionMessage()

        messageBuilder.accountEntropyPool = accountEntropyPool.rawString
        messageBuilder.aci = aci.serviceIdBinary
        if let pin {
            messageBuilder.pin = pin
        }

        messageBuilder.aciIdentityKeyPublic = aciIdentityKeyPair.publicKey.serialize()
        messageBuilder.aciIdentityKeyPrivate = aciIdentityKeyPair.privateKey.serialize()

        let phoneNumberState = self.phoneNumberState
        do {
            messageBuilder.e164 = phoneNumberState.phoneNumber.stringValue
            messageBuilder.pniIdentityKeyPublic = phoneNumberState.pniIdentityKeyPair.publicKey.serialize()
            messageBuilder.pniIdentityKeyPrivate = phoneNumberState.pniIdentityKeyPair.privateKey.serialize()
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

        if let backupVersion {
            messageBuilder.backupVersion = backupVersion
        }

        if let backupTimestamp {
            messageBuilder.backupTimestampMs = backupTimestamp
        }
        if let backupSizeBytes {
            messageBuilder.backupSizeBytes = backupSizeBytes
        }

        if let restoreMethodToken {
            messageBuilder.restoreMethodToken = restoreMethodToken
        }

        if let lastBackupForwardSecrecyToken {
            messageBuilder.lastBackupForwardSecrecyToken = lastBackupForwardSecrecyToken.serialize()
        }
        if let nextBackupSecretData {
            messageBuilder.nextBackupSecretData = nextBackupSecretData.data
        }

        messageBuilder.capabilities = capabilites.map { $0.rawValue }

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
        envelopeBuilder.publicKey = ourKeyPair.publicKey.serialize()
        envelopeBuilder.body = encryptedMessage

        return try envelopeBuilder.serializedData()
    }
}
