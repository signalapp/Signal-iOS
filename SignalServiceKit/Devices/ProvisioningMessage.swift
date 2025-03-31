//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public struct ProvisioningMessage {

    public enum RootKey {
        case accountEntropyPool(AccountEntropyPool)
        case masterKey(MasterKey)
    }

    public enum Constants {
        public static let provisioningVersion: UInt32  = 1
        public static let userAgent: String = "OWI"
    }

    public let rootKey: RootKey
    public let aci: Aci
    public let phoneNumber: String
    public let pni: Pni
    public let aciIdentityKeyPair: IdentityKeyPair
    public let pniIdentityKeyPair: IdentityKeyPair
    public let profileKey: Aes256Key
    public let mrbk: BackupKey
    public let ephemeralBackupKey: BackupKey?
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
        mrbk: BackupKey,
        ephemeralBackupKey: BackupKey?,
        areReadReceiptsEnabled: Bool,
        provisioningCode: String,
        provisioningUserAgent: String? = Constants.userAgent,
        provisioningVersion: UInt32 = Constants.provisioningVersion
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
            privateKey: PrivateKey(proto.aciIdentityKeyPrivate)
        )

        self.pniIdentityKeyPair = try IdentityKeyPair(
            publicKey: PublicKey(proto.pniIdentityKeyPublic),
            privateKey: PrivateKey(proto.pniIdentityKeyPrivate)
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
            guard
                let aciString = proto.aci,
                let aci = Aci.parseFrom(aciString: aciString)
            else {
                throw ProvisioningError.invalidProvisionMessage("invalid ACI from provisioning message")
            }
            return aci
        }()

        self.pni = try {
            guard
                let pniString = proto.pni,
                let pni = Pni.parseFrom(ambiguousString: pniString)
            else {
                throw ProvisioningError.invalidProvisionMessage("invalid PNI from provisioning message")
            }
            return pni
        }()

        if
            let accountEntropyPool = proto.accountEntropyPool?.nilIfEmpty,
            let aep = try? AccountEntropyPool(key: accountEntropyPool)
        {
            self.rootKey = .accountEntropyPool(aep)
        } else if let masterKey = try proto.masterKey.map({ try MasterKey(data: $0)}) {
            self.rootKey = .masterKey(masterKey)
        } else {
            throw ProvisioningError.invalidProvisionMessage("missing master key from provisioning message")
        }

        guard let mrbkBytes = proto.mediaRootBackupKey else {
            throw ProvisioningError.invalidProvisionMessage("missing media key from provisioning message")
        }
        self.mrbk = try BackupKey(contents: Array(mrbkBytes))

        self.ephemeralBackupKey = try proto.ephemeralBackupKey.map({ try BackupKey.init(contents: Array($0)) })
    }

    public func buildEncryptedMessageBody(theirPublicKey: PublicKey) throws -> Data {
        let messageBuilder = ProvisioningProtoProvisionMessage.builder(
            aciIdentityKeyPublic: aciIdentityKeyPair.publicKey.serialize().asData,
            aciIdentityKeyPrivate: aciIdentityKeyPair.privateKey.serialize().asData,
            pniIdentityKeyPublic: pniIdentityKeyPair.publicKey.serialize().asData,
            pniIdentityKeyPrivate: pniIdentityKeyPair.privateKey.serialize().asData,
            provisioningCode: provisioningCode,
            profileKey: profileKey.keyData
        )
        messageBuilder.setUserAgent(Constants.userAgent)
        messageBuilder.setReadReceipts(areReadReceiptsEnabled)
        messageBuilder.setProvisioningVersion(Constants.provisioningVersion)
        messageBuilder.setNumber(phoneNumber)
        messageBuilder.setAci(aci.rawUUID.uuidString.lowercased())
        messageBuilder.setPni(pni.rawUUID.uuidString.lowercased())

        switch rootKey {
        case .accountEntropyPool(let accountEntropyPool):
            messageBuilder.setAccountEntropyPool(accountEntropyPool.rawData)
            messageBuilder.setMasterKey(accountEntropyPool.getMasterKey().rawData)
        case .masterKey(let masterKey):
            messageBuilder.setMasterKey(masterKey.rawData)
        }
        messageBuilder.setMediaRootBackupKey(mrbk.serialize().asData)
        ephemeralBackupKey.map { messageBuilder.setEphemeralBackupKey($0.serialize().asData)}

        let plainTextProvisionMessage = try messageBuilder.buildSerializedData()

        // Note that this is a one-time-use *cipher* public key, not our Signal *identity* public key
        let ourKeyPair = IdentityKeyPair.generate()
        let cipher = ProvisioningCipher(ourKeyPair: ourKeyPair)
        let encryptedProvisionMessage: Data
        do {
            encryptedProvisionMessage = try cipher.encrypt(
                plainTextProvisionMessage,
                theirPublicKey: theirPublicKey
            )
        } catch {
            throw OWSAssertionError("Failed to encrypt provision message")
        }

        let envelopeBuilder = ProvisioningProtoProvisionEnvelope.builder(
            publicKey: ourKeyPair.publicKey.serialize().asData,
            body: encryptedProvisionMessage
        )
        return try envelopeBuilder.buildSerializedData()
    }
}
