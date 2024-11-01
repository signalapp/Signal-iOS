//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import LibSignalClient

@objc
public final class OWSDeviceProvisionerConstant: NSObject {
    @objc
    public static var provisioningVersion: UInt32 { 1 }
}

public final class OWSDeviceProvisioner {
    internal static var userAgent: String { "OWI" }

    private let myAciIdentityKeyPair: IdentityKeyPair
    private let myPniIdentityKeyPair: IdentityKeyPair
    private let theirPublicKey: PublicKey
    private let ephemeralDeviceId: String
    private let myAci: Aci
    private let myPhoneNumber: String
    private let myPni: Pni
    private let profileKey: Data
    private let masterKey: Data
    private let mrbk: Data
    private let ephemeralBackupKey: BackupKey?
    private let readReceiptsEnabled: Bool

    private let provisioningService: DeviceProvisioningService
    private let schedulers: Schedulers

    public init(
        myAciIdentityKeyPair: IdentityKeyPair,
        myPniIdentityKeyPair: IdentityKeyPair,
        theirPublicKey: PublicKey,
        theirEphemeralDeviceId: String,
        myAci: Aci,
        myPhoneNumber: String,
        myPni: Pni,
        profileKey: Data,
        masterKey: Data,
        mrbk: Data,
        ephemeralBackupKey: BackupKey?,
        readReceiptsEnabled: Bool,
        provisioningService: DeviceProvisioningService,
        schedulers: Schedulers
    ) {
        self.myAciIdentityKeyPair = myAciIdentityKeyPair
        self.myPniIdentityKeyPair = myPniIdentityKeyPair
        self.theirPublicKey = theirPublicKey
        self.ephemeralDeviceId = theirEphemeralDeviceId
        self.myAci = myAci
        self.myPhoneNumber = myPhoneNumber
        self.myPni = myPni
        self.profileKey = profileKey
        self.masterKey = masterKey
        self.mrbk = mrbk
        self.ephemeralBackupKey = ephemeralBackupKey
        self.readReceiptsEnabled = readReceiptsEnabled
        self.provisioningService = provisioningService
        self.schedulers = schedulers
    }

    public func provision() -> Promise<DeviceProvisioningTokenId> {
        firstly {
            provisioningService.requestDeviceProvisioningCode()
        }.then(on: schedulers.sharedUserInitiated) { provisioningCode in
            return self.provisionDevice(provisioningCode: provisioningCode)
        }
    }

    private func provisionDevice(provisioningCode: DeviceProvisioningCodeResponse) -> Promise<DeviceProvisioningTokenId> {
        let messageBody: Data
        do {
            messageBody = try self.buildEncryptedMessageBody(withCode: provisioningCode)
        } catch {
            return Promise(error: error)
        }
        return provisioningService.provisionDevice(messageBody: messageBody, ephemeralDeviceId: ephemeralDeviceId)
            .map(on: SyncScheduler()) { provisioningCode.tokenId }
    }

    private func buildEncryptedMessageBody(withCode provisioningCode: DeviceProvisioningCodeResponse) throws -> Data {
        let messageBuilder = ProvisioningProtoProvisionMessage.builder(
            aciIdentityKeyPublic: Data(myAciIdentityKeyPair.publicKey.serialize()),
            aciIdentityKeyPrivate: Data(myAciIdentityKeyPair.privateKey.serialize()),
            pniIdentityKeyPublic: Data(myPniIdentityKeyPair.publicKey.serialize()),
            pniIdentityKeyPrivate: Data(myPniIdentityKeyPair.privateKey.serialize()),
            provisioningCode: provisioningCode.verificationCode,
            profileKey: profileKey
        )
        messageBuilder.setUserAgent(Self.userAgent)
        messageBuilder.setReadReceipts(readReceiptsEnabled)
        messageBuilder.setProvisioningVersion(OWSDeviceProvisionerConstant.provisioningVersion)
        messageBuilder.setNumber(myPhoneNumber)
        messageBuilder.setAci(myAci.rawUUID.uuidString.lowercased())
        messageBuilder.setPni(myPni.rawUUID.uuidString.lowercased())
        messageBuilder.setMasterKey(masterKey)
        messageBuilder.setMediaRootBackupKey(mrbk)
        if let ephemeralBackupKey {
            messageBuilder.setEphemeralBackupKey(ephemeralBackupKey.serialize().asData)
        }

        let plainTextProvisionMessage = try messageBuilder.buildSerializedData()
        let cipher = OWSProvisioningCipher(theirPublicKey: theirPublicKey)
        guard let encryptedProvisionMessage = cipher.encrypt(plainTextProvisionMessage) else {
            throw OWSAssertionError("Failed to encrypt provision message")
        }

        // Note that this is a one-time-use *cipher* public key, not our Signal *identity* public key
        let envelopeBuilder = ProvisioningProtoProvisionEnvelope.builder(
            publicKey: Data(cipher.ourPublicKey.serialize()),
            body: encryptedProvisionMessage
        )
        return try envelopeBuilder.buildSerializedData()
    }
}
