//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public struct LinkingProvisioningMessage {

    public enum Constants {
        public static let provisioningVersion: UInt32 = 1
        public static let userAgent: String = "OWI"
    }

    /// Wraps state that's only available for accounts with phone numbers.
    public struct PhoneNumberState {
        public let phoneNumber: LocalIdentifiers.PhoneNumber
        public let pniIdentityKeyPair: IdentityKeyPair

        public init(phoneNumber: LocalIdentifiers.PhoneNumber, pniIdentityKeyPair: IdentityKeyPair) {
            self.phoneNumber = phoneNumber
            self.pniIdentityKeyPair = pniIdentityKeyPair
        }
    }

    public let aci: Aci
    public let aciIdentityKeyPair: IdentityKeyPair
    public let aep: AccountEntropyPool
    public let phoneNumberState: PhoneNumberState
    public let profileKey: Aes256Key
    public let mrbk: MediaRootBackupKey
    public let ephemeralBackupKey: MessageRootBackupKey?
    public let areReadReceiptsEnabled: Bool
    public let provisioningCode: String
    public let provisioningUserAgent: String?
    public let provisioningVersion: UInt32

    public init(
        aci: Aci,
        aciIdentityKeyPair: IdentityKeyPair,
        aep: AccountEntropyPool,
        phoneNumberState: PhoneNumberState,
        profileKey: Aes256Key,
        mrbk: MediaRootBackupKey,
        ephemeralBackupKey: MessageRootBackupKey?,
        areReadReceiptsEnabled: Bool,
        provisioningCode: String,
        provisioningUserAgent: String? = Constants.userAgent,
        provisioningVersion: UInt32 = Constants.provisioningVersion,
    ) {
        self.aep = aep
        self.aci = aci
        self.phoneNumberState = phoneNumberState
        self.aciIdentityKeyPair = aciIdentityKeyPair
        self.profileKey = profileKey
        self.mrbk = mrbk
        self.ephemeralBackupKey = ephemeralBackupKey
        self.areReadReceiptsEnabled = areReadReceiptsEnabled
        self.provisioningCode = provisioningCode
        self.provisioningUserAgent = provisioningUserAgent
        self.provisioningVersion = provisioningVersion
    }

    public init(_ proto: ProvisioningProtos_ProvisionMessage) throws {
        self.aciIdentityKeyPair = try IdentityKeyPair(
            publicKey: PublicKey(proto.aciIdentityKeyPublic),
            privateKey: PrivateKey(proto.aciIdentityKeyPrivate),
        )

        guard let profileKey = Aes256Key(data: proto.profileKey) else {
            throw OWSGenericError("invalid profileKey - count: \(proto.profileKey.count)")
        }
        self.profileKey = profileKey

        self.areReadReceiptsEnabled = proto.readReceipts // defaults to false
        self.provisioningCode = proto.provisioningCode

        self.provisioningUserAgent = proto.userAgent
        let provisioningVersion = proto.provisioningVersion
        self.provisioningVersion = provisioningVersion

        var phoneNumberState: PhoneNumberState?
        if proto.hasNumber {
            guard let e164 = E164(proto.number) else {
                throw OWSGenericError("malformed number in provisioning message")
            }
            guard let pniUuid = UUID(data: proto.pniBinary) else {
                throw OWSGenericError("malformed PNI in provisioning message")
            }
            let pni = Pni(fromUUID: pniUuid)
            let pniIdentityKeyPair = try IdentityKeyPair(
                publicKey: PublicKey(proto.pniIdentityKeyPublic),
                privateKey: PrivateKey(proto.pniIdentityKeyPrivate),
            )
            let phoneNumber = LocalIdentifiers.PhoneNumber(e164: e164, pni: pni)
            phoneNumberState = PhoneNumberState(phoneNumber: phoneNumber, pniIdentityKeyPair: pniIdentityKeyPair)
        }
        guard let phoneNumberState else {
            // TODO: [#less] Allow linking accounts without phone numbers.
            throw OWSGenericError("missing phone number")
        }
        self.phoneNumberState = phoneNumberState

        self.aci = try Aci.parseFrom(serviceIdBinary: proto.aciBinary)

        self.aep = try AccountEntropyPool(key: proto.accountEntropyPool)

        self.mrbk = MediaRootBackupKey(backupKey: try BackupKey(contents: proto.mediaRootBackupKey))

        var ephemeralBackupKey: MessageRootBackupKey?
        if proto.hasEphemeralBackupKey {
            ephemeralBackupKey = MessageRootBackupKey(
                backupKey: try BackupKey(contents: proto.ephemeralBackupKey),
                aci: self.aci,
            )
        }
        self.ephemeralBackupKey = ephemeralBackupKey
    }

    public func buildEncryptedMessageBody(theirPublicKey: PublicKey) throws -> Data {
        var message = ProvisioningProtos_ProvisionMessage()
        message.aciIdentityKeyPublic = aciIdentityKeyPair.publicKey.serialize()
        message.aciIdentityKeyPrivate = aciIdentityKeyPair.privateKey.serialize()
        message.provisioningCode = provisioningCode
        message.profileKey = profileKey.keyData
        message.userAgent = Constants.userAgent
        message.readReceipts = areReadReceiptsEnabled
        message.provisioningVersion = Constants.provisioningVersion
        message.aciBinary = aci.rawUUID.data
        message.accountEntropyPool = aep.rawString
        message.mediaRootBackupKey = mrbk.serialize()
        if let ephemeralBackupKey {
            message.ephemeralBackupKey = ephemeralBackupKey.serialize()
        }
        // TODO: [#less] Don't include this when phoneNumber is nil.
        let phoneNumberState = self.phoneNumberState
        do {
            message.number = phoneNumberState.phoneNumber.e164.stringValue
            message.pniBinary = phoneNumberState.phoneNumber.pni.rawUUID.data
            message.pniIdentityKeyPublic = phoneNumberState.pniIdentityKeyPair.publicKey.serialize()
            message.pniIdentityKeyPrivate = phoneNumberState.pniIdentityKeyPair.privateKey.serialize()
        }

        let plainTextProvisionMessage = try message.serializedData()

        // Note that this is a one-time-use *cipher* public key, not our Signal *identity* public key
        let ourKeyPair = IdentityKeyPair.generate()
        let cipher = ProvisioningCipher(ourKeyPair: ourKeyPair)
        let encryptedProvisionMessage: Data
        do {
            encryptedProvisionMessage = try cipher.encrypt(
                plainTextProvisionMessage,
                theirPublicKey: theirPublicKey,
            )
        } catch {
            throw OWSAssertionError("Failed to encrypt provision message")
        }

        var envelope = ProvisioningProtos_ProvisionEnvelope()
        envelope.publicKey = ourKeyPair.publicKey.serialize()
        envelope.body = encryptedProvisionMessage
        return try envelope.serializedData()
    }
}
