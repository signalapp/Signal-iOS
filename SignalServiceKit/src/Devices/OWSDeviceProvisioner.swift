//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

@objc
public final class OWSDeviceProvisioner: NSObject {
    @objc
    public static var provisioningVersion: UInt32 { 1 }
    internal static var userAgent: String { "OWI" }

    private let myAciIdentityKeyPair: IdentityKeyPair
    private let myPniIdentityKeyPair: IdentityKeyPair?
    private let theirPublicKey: Data
    private let ephemeralDeviceId: String
    private let accountAddress: SignalServiceAddress
    private let pni: UUID
    private let profileKey: Data
    private let readReceiptsEnabled: Bool

    private let provisioningCodeService: OWSDeviceProvisioningCodeService
    private let provisioningService: OWSDeviceProvisioningService

#if TESTABLE_BUILD
    init(myAciIdentityKeyPair: IdentityKeyPair,
         theirPublicKey: Data,
         theirEphemeralDeviceId: String,
         accountAddress: SignalServiceAddress,
         pni: UUID,
         profileKey: Data,
         readReceiptsEnabled: Bool,
         provisioningCodeService: OWSDeviceProvisioningCodeService,
         provisioningService: OWSDeviceProvisioningService) {
        self.myAciIdentityKeyPair = myAciIdentityKeyPair
        self.myPniIdentityKeyPair = nil
        self.theirPublicKey = theirPublicKey
        self.ephemeralDeviceId = theirEphemeralDeviceId
        self.accountAddress = accountAddress
        self.pni = pni
        self.profileKey = profileKey
        self.readReceiptsEnabled = readReceiptsEnabled
        self.provisioningCodeService = provisioningCodeService
        self.provisioningService = provisioningService
    }
#endif

    @objc
    public init(myAciIdentityKeyPair: ECKeyPair,
                myPniIdentityKeyPair: ECKeyPair?,
                theirPublicKey: Data,
                theirEphemeralDeviceId: String,
                accountAddress: SignalServiceAddress,
                pni: UUID,
                profileKey: Data,
                readReceiptsEnabled: Bool) {
        self.myAciIdentityKeyPair = myAciIdentityKeyPair.identityKeyPair
        self.myPniIdentityKeyPair = myPniIdentityKeyPair?.identityKeyPair
        self.theirPublicKey = theirPublicKey
        self.ephemeralDeviceId = theirEphemeralDeviceId
        self.accountAddress = accountAddress
        self.pni = pni
        self.profileKey = profileKey
        self.readReceiptsEnabled = readReceiptsEnabled
        self.provisioningCodeService = OWSDeviceProvisioningCodeService()
        self.provisioningService = OWSDeviceProvisioningService()
    }

    @objc(provisionWithSuccess:failure:)
    public func provision(success successCallback: @escaping () -> Void,
                          failure failureCallback: @escaping (Error) -> Void) {
        provisioningCodeService.requestProvisioningCode(success: { provisioningCode in
            Logger.info("Retrieved provisioning code.")
            self.provision(withCode: provisioningCode, success: successCallback, failure: failureCallback)
        }, failure: { error in
            Logger.error("Failed to get provisioning code with error: \(error)")
            failureCallback(error)
        })
    }

    private func provision(withCode provisioningCode: String,
                           success successCallback: @escaping () -> Void,
                           failure failureCallback: @escaping (Error) -> Void) {
        let messageBody: Data
        do {
            messageBody = try self.buildEncryptedMessageBody(withCode: provisioningCode)
        } catch {
            Logger.error("Failed building provisioning message: \(error)")
            failureCallback(error)
            return
        }

        self.provisioningService.provision(
            messageBody: messageBody,
            ephemeralDeviceId: ephemeralDeviceId,
            success: {
                Logger.info("ProvisioningService SUCCEEDED")
                successCallback()
            },
            failure: { error in
                Logger.error("ProvisioningService FAILED with error: \(error)")
                failureCallback(error)
            })
    }

    private func buildEncryptedMessageBody(withCode provisioningCode: String) throws -> Data {
        let messageBuilder = ProvisioningProtoProvisionMessage.builder(
            aciIdentityKeyPublic: Data(myAciIdentityKeyPair.publicKey.serialize()),
            aciIdentityKeyPrivate: Data(myAciIdentityKeyPair.privateKey.serialize()),
            provisioningCode: provisioningCode,
            profileKey: profileKey)
        messageBuilder.setUserAgent(Self.userAgent)
        messageBuilder.setReadReceipts(readReceiptsEnabled)
        messageBuilder.setProvisioningVersion(Self.provisioningVersion)

        guard let phoneNumber = accountAddress.phoneNumber else {
            throw OWSAssertionError("phone number unexpectedly missing")
        }
        messageBuilder.setNumber(phoneNumber)

        guard let uuidString = accountAddress.uuidString else {
            throw OWSAssertionError("UUID unexpectedly missing")
        }
        messageBuilder.setAci(uuidString)

        if let myPniIdentityKeyPair = myPniIdentityKeyPair {
            // Note that we don't set a PNI at all if we don't have an identity key.
            messageBuilder.setPni(pni.uuidString)
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
            body: encryptedProvisionMessage)
        return try envelopeBuilder.buildSerializedData()
    }
}
