//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public struct LinkingProvisioningMessage {

    public enum RootKey {
        case accountEntropyPool(AccountEntropyPool)
        case masterKey(MasterKey)
    }

    public enum Constants {
        public static let provisioningVersion: UInt32 = 1
        public static let userAgent: String = "OWI"
    }

    public let rootKey: RootKey
    public let aci: Aci
    public let phoneNumber: String
    public let pni: Pni
    public let aciIdentityKeyPair: IdentityKeyPair
    public let pniIdentityKeyPair: IdentityKeyPair
    public let profileKey: Aes256Key
    public let mrbk: MediaRootBackupKey
    public let ephemeralBackupKey: MessageRootBackupKey?
    public let areReadReceiptsEnabled: Bool
    public let provisioningCode: String
    public let provisioningUserAgent: String?
    public let provisioningVersion: UInt32

    public init(
        rootKey: RootKey,
        aci: Aci,
        phoneNumber: String,
        pni: Pni,
        aciIdentityKeyPair: IdentityKeyPair,
        pniIdentityKeyPair: IdentityKeyPair,
        profileKey: Aes256Key,
        mrbk: MediaRootBackupKey,
        ephemeralBackupKey: MessageRootBackupKey?,
        areReadReceiptsEnabled: Bool,
        provisioningCode: String,
        provisioningUserAgent: String? = Constants.userAgent,
        provisioningVersion: UInt32 = Constants.provisioningVersion,
    ) {
        self.rootKey = rootKey
        self.aci = aci
        self.phoneNumber = phoneNumber
        self.pni = pni
        self.aciIdentityKeyPair = aciIdentityKeyPair
        self.pniIdentityKeyPair = pniIdentityKeyPair
        self.profileKey = profileKey
        self.mrbk = mrbk
        self.ephemeralBackupKey = ephemeralBackupKey
        self.areReadReceiptsEnabled = areReadReceiptsEnabled
        self.provisioningCode = provisioningCode
        self.provisioningUserAgent = provisioningUserAgent
        self.provisioningVersion = provisioningVersion
    }

    public init(plaintext: Data) throws {
        let proto = try ProvisioningProtoProvisionMessage(serializedData: plaintext)

        self.aciIdentityKeyPair = try IdentityKeyPair(
            publicKey: PublicKey(proto.aciIdentityKeyPublic),
            privateKey: PrivateKey(proto.aciIdentityKeyPrivate),
        )

        self.pniIdentityKeyPair = try IdentityKeyPair(
            publicKey: PublicKey(proto.pniIdentityKeyPublic),
            privateKey: PrivateKey(proto.pniIdentityKeyPrivate),
        )

        guard let profileKey = Aes256Key(data: proto.profileKey) else {
            throw ProvisioningError.invalidProvisionMessage("invalid profileKey - count: \(proto.profileKey.count)")
        }
        self.profileKey = profileKey

        self.areReadReceiptsEnabled = proto.readReceipts // defaults to false
        self.provisioningCode = proto.provisioningCode

        self.provisioningUserAgent = proto.userAgent
        let provisioningVersion = proto.provisioningVersion
        self.provisioningVersion = provisioningVersion

        guard let phoneNumber = proto.number, phoneNumber.count > 1 else {
            throw ProvisioningError.invalidProvisionMessage("missing number from provisioning message")
        }
        self.phoneNumber = phoneNumber

        self.aci = try {
            guard let aci = Aci.parseFrom(serviceIdBinary: proto.aciBinary, serviceIdString: proto.aci) else {
                throw ProvisioningError.invalidProvisionMessage("invalid ACI from provisioning message")
            }
            return aci
        }()

        self.pni = try {
            if let pniBinary = proto.pniBinary {
                guard let pniUuid = UUID(data: pniBinary) else {
                    throw ProvisioningError.invalidProvisionMessage("invalid PNI from provisioning message")
                }
                return Pni(fromUUID: pniUuid)
            }
            if let pniString = proto.pni {
                guard let pni = Pni.parseFrom(ambiguousString: pniString) else {
                    throw ProvisioningError.invalidProvisionMessage("invalid PNI from provisioning message")
                }
                return pni
            }
            throw ProvisioningError.invalidProvisionMessage("invalid PNI from provisioning message")
        }()

        if
            let accountEntropyPool = proto.accountEntropyPool?.nilIfEmpty,
            let aep = try? AccountEntropyPool(key: accountEntropyPool)
        {
            self.rootKey = .accountEntropyPool(aep)
        } else if let masterKey = try proto.masterKey.map({ try MasterKey(data: $0) }) {
            self.rootKey = .masterKey(masterKey)
        } else {
            throw ProvisioningError.invalidProvisionMessage("missing master key from provisioning message")
        }

        guard let mrbkBytes = proto.mediaRootBackupKey else {
            throw ProvisioningError.invalidProvisionMessage("missing media key from provisioning message")
        }
        self.mrbk = try MediaRootBackupKey(backupKey: BackupKey(contents: mrbkBytes))

        let aci = aci
        self.ephemeralBackupKey = try proto.ephemeralBackupKey.map {
            return MessageRootBackupKey(
                backupKey: try BackupKey(contents: $0),
                aci: aci,
            )
        }
    }

    public func buildEncryptedMessageBody(theirPublicKey: PublicKey) throws -> Data {
        let messageBuilder = ProvisioningProtoProvisionMessage.builder(
            aciIdentityKeyPublic: aciIdentityKeyPair.publicKey.serialize(),
            aciIdentityKeyPrivate: aciIdentityKeyPair.privateKey.serialize(),
            pniIdentityKeyPublic: pniIdentityKeyPair.publicKey.serialize(),
            pniIdentityKeyPrivate: pniIdentityKeyPair.privateKey.serialize(),
            provisioningCode: provisioningCode,
            profileKey: profileKey.keyData,
        )
        messageBuilder.setUserAgent(Constants.userAgent)
        messageBuilder.setReadReceipts(areReadReceiptsEnabled)
        messageBuilder.setProvisioningVersion(Constants.provisioningVersion)
        messageBuilder.setNumber(phoneNumber)
        if BuildFlags.serviceIdStrings {
            messageBuilder.setAci(aci.rawUUID.uuidString.lowercased())
        }
        if BuildFlags.serviceIdBinaryProvisioning {
            messageBuilder.setAciBinary(aci.rawUUID.data)
        }
        if BuildFlags.serviceIdStrings {
            messageBuilder.setPni(pni.rawUUID.uuidString.lowercased())
        }
        if BuildFlags.serviceIdBinaryProvisioning {
            messageBuilder.setPniBinary(pni.rawUUID.data)
        }

        switch rootKey {
        case .accountEntropyPool(let accountEntropyPool):
            messageBuilder.setAccountEntropyPool(accountEntropyPool.rawString)
            messageBuilder.setMasterKey(accountEntropyPool.getMasterKey().rawData)
        case .masterKey(let masterKey):
            messageBuilder.setMasterKey(masterKey.rawData)
        }
        messageBuilder.setMediaRootBackupKey(mrbk.serialize())
        ephemeralBackupKey.map { messageBuilder.setEphemeralBackupKey($0.serialize()) }

        let plainTextProvisionMessage = try messageBuilder.buildSerializedData()

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

        let envelopeBuilder = ProvisioningProtoProvisionEnvelope.builder(
            publicKey: ourKeyPair.publicKey.serialize(),
            body: encryptedProvisionMessage,
        )
        return try envelopeBuilder.buildSerializedData()
    }
}
