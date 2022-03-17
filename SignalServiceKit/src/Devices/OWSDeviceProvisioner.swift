//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import SignalClient

@objc
public final class OWSDeviceProvisioner: NSObject {
    @objc
    public static var provisioningVersion: UInt32 { 1 }
    internal static var userAgent: String { "OWI" }

    private let myIdentityKeyPair: IdentityKeyPair
    private let theirPublicKey: Data
    private let ephemeralDeviceId: String
    private let accountAddress: SignalServiceAddress
    private let profileKey: Data
    private let readReceiptsEnabled: Bool

    private let provisioningCodeService: OWSDeviceProvisioningCodeService
    private let provisioningService: OWSDeviceProvisioningService

    init(myIdentityKeyPair: IdentityKeyPair,
         theirPublicKey: Data,
         theirEphemeralDeviceId: String,
         accountAddress: SignalServiceAddress,
         profileKey: Data,
         readReceiptsEnabled: Bool,
         provisioningCodeService: OWSDeviceProvisioningCodeService,
         provisioningService: OWSDeviceProvisioningService) {
        self.myIdentityKeyPair = myIdentityKeyPair
        self.theirPublicKey = theirPublicKey
        self.ephemeralDeviceId = theirEphemeralDeviceId
        self.accountAddress = accountAddress
        self.profileKey = profileKey
        self.readReceiptsEnabled = readReceiptsEnabled
        self.provisioningCodeService = provisioningCodeService
        self.provisioningService = provisioningService
    }

    @objc
    public convenience init(myIdentityKeyPair: ECKeyPair,
                            theirPublicKey: Data,
                            theirEphemeralDeviceId: String,
                            accountAddress: SignalServiceAddress,
                            profileKey: Data,
                            readReceiptsEnabled: Bool) {
        self.init(myIdentityKeyPair: myIdentityKeyPair.identityKeyPair,
                  theirPublicKey: theirPublicKey,
                  theirEphemeralDeviceId: theirEphemeralDeviceId,
                  accountAddress: accountAddress,
                  profileKey: profileKey,
                  readReceiptsEnabled: readReceiptsEnabled,
                  provisioningCodeService: OWSDeviceProvisioningCodeService(),
                  provisioningService: OWSDeviceProvisioningService())
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
            identityKeyPublic: Data(myIdentityKeyPair.publicKey.serialize()),
            identityKeyPrivate: Data(myIdentityKeyPair.privateKey.serialize()),
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
        messageBuilder.setUuid(uuidString)

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
