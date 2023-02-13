//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

@objc
public final class OWSDeviceProvisionerConstant: NSObject {
    @objc
    public static var provisioningVersion: UInt32 { 1 }
}

public final class OWSDeviceProvisioner {
    internal static var userAgent: String { "OWI" }

    private let myAciIdentityKeyPair: IdentityKeyPair
    private let myPniIdentityKeyPair: IdentityKeyPair?
    private let theirPublicKey: Data
    private let ephemeralDeviceId: String
    private let myAci: UUID
    private let myPhoneNumber: String
    private let myPni: UUID?
    private let profileKey: Data
    private let readReceiptsEnabled: Bool

    private let provisioningService: DeviceProvisioningService
    private let schedulers: Schedulers

    public init(
        myAciIdentityKeyPair: IdentityKeyPair,
        myPniIdentityKeyPair: IdentityKeyPair?,
        theirPublicKey: Data,
        theirEphemeralDeviceId: String,
        myAci: UUID,
        myPhoneNumber: String,
        myPni: UUID?,
        profileKey: Data,
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
        self.readReceiptsEnabled = readReceiptsEnabled
        self.provisioningService = provisioningService
        self.schedulers = schedulers
    }

    public func provision() -> Promise<Void> {
        firstly {
            provisioningService.requestDeviceProvisioningCode()
        }.then(on: schedulers.sharedUserInitiated) { provisioningCode in
            self.provisionDevice(provisioningCode: provisioningCode)
        }
    }

    private func provisionDevice(provisioningCode: String) -> Promise<Void> {
        let messageBody: Data
        do {
            messageBody = try self.buildEncryptedMessageBody(withCode: provisioningCode)
        } catch {
            return Promise(error: error)
        }
        return provisioningService.provisionDevice(messageBody: messageBody, ephemeralDeviceId: ephemeralDeviceId)
    }

    private func buildEncryptedMessageBody(withCode provisioningCode: String) throws -> Data {
        let messageBuilder = ProvisioningProtoProvisionMessage.builder(
            aciIdentityKeyPublic: Data(myAciIdentityKeyPair.publicKey.serialize()),
            aciIdentityKeyPrivate: Data(myAciIdentityKeyPair.privateKey.serialize()),
            provisioningCode: provisioningCode,
            profileKey: profileKey
        )
        messageBuilder.setUserAgent(Self.userAgent)
        messageBuilder.setReadReceipts(readReceiptsEnabled)
        messageBuilder.setProvisioningVersion(OWSDeviceProvisionerConstant.provisioningVersion)
        messageBuilder.setNumber(myPhoneNumber)
        messageBuilder.setAci(myAci.uuidString)

        if let myPni, let myPniIdentityKeyPair {
            messageBuilder.setPni(myPni.uuidString)
            messageBuilder.setPniIdentityKeyPublic(Data(myPniIdentityKeyPair.publicKey.serialize()))
            messageBuilder.setPniIdentityKeyPrivate(Data(myPniIdentityKeyPair.privateKey.serialize()))
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
