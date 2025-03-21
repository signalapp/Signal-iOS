//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

public enum PniDistribution {
    /// Parameters for distributing PNI information to linked devices.
    public struct Parameters {
        let pniIdentityKey: IdentityKey
        private(set) var devicePniSignedPreKeys: [String: SignalServiceKit.SignedPreKeyRecord] = [:]
        private(set) var devicePniPqLastResortPreKeys: [String: KyberPreKeyRecord] = [:]
        private(set) var pniRegistrationIds: [String: UInt32] = [:]
        private(set) var deviceMessages: [DeviceMessage] = []

        fileprivate init(pniIdentityKey: IdentityKey) {
            self.pniIdentityKey = pniIdentityKey
        }

        #if TESTABLE_BUILD

        public static func mock(
            pniIdentityKeyPair: ECKeyPair,
            localDeviceId: DeviceId,
            localDevicePniSignedPreKey: SignalServiceKit.SignedPreKeyRecord,
            localDevicePniPqLastResortPreKey: KyberPreKeyRecord,
            localDevicePniRegistrationId: UInt32
        ) -> Parameters {
            var mock = Parameters(pniIdentityKey: pniIdentityKeyPair.keyPair.identityKey)
            mock.addLocalDevice(
                localDeviceId: localDeviceId,
                signedPreKey: localDevicePniSignedPreKey,
                pqLastResortPreKey: localDevicePniPqLastResortPreKey,
                registrationId: localDevicePniRegistrationId
            )
            return mock
        }

        #endif

        fileprivate mutating func addLocalDevice(
            localDeviceId: DeviceId,
            signedPreKey: SignalServiceKit.SignedPreKeyRecord,
            pqLastResortPreKey: KyberPreKeyRecord,
            registrationId: UInt32
        ) {
            devicePniSignedPreKeys["\(localDeviceId)"] = signedPreKey
            devicePniPqLastResortPreKeys["\(localDeviceId)"] = pqLastResortPreKey
            pniRegistrationIds["\(localDeviceId)"] = registrationId
        }

        fileprivate mutating func addLinkedDevice(
            deviceId: DeviceId,
            signedPreKey: SignalServiceKit.SignedPreKeyRecord,
            pqLastResortPreKey: KyberPreKeyRecord,
            registrationId: UInt32,
            deviceMessage: DeviceMessage
        ) {
            owsPrecondition(deviceId == deviceMessage.destinationDeviceId)

            devicePniSignedPreKeys["\(deviceId)"] = signedPreKey
            devicePniPqLastResortPreKeys["\(deviceId)"] = pqLastResortPreKey
            pniRegistrationIds["\(deviceId)"] = registrationId
            deviceMessages.append(deviceMessage)
        }

        func requestParameters() -> [String: Any] {
            [
                "pniIdentityKey": pniIdentityKey.serialize().asData.base64EncodedString(),
                "devicePniSignedPrekeys": devicePniSignedPreKeys.mapValues { OWSRequestFactory.signedPreKeyRequestParameters($0) },
                "devicePniPqLastResortPrekeys": devicePniPqLastResortPreKeys.mapValues { OWSRequestFactory.pqPreKeyRequestParameters($0) },
                "deviceMessages": deviceMessages.map { $0.requestParameters() },
                "pniRegistrationIds": pniRegistrationIds
            ]
        }
    }
}

protocol PniDistributionParamaterBuilder {
    /// Generates parameters to distribute a new PNI identity from the primary
    /// to linked devices.
    ///
    /// These parameters include:
    /// - A new public identity key for this account.
    /// - Signed pre-key pairs and registration IDs for all devices. Data for
    ///   the local (primary) device may be fresh or existing.
    /// - An encrypted message for each linked device informing them about the
    ///   new identity. Note that this message contains private key data.
    func buildPniDistributionParameters(
        localAci: Aci,
        localRecipientUniqueId: String,
        localDeviceId: LocalDeviceId,
        localUserAllDeviceIds: [DeviceId],
        localPniIdentityKeyPair: ECKeyPair,
        localE164: E164,
        localDevicePniSignedPreKey: SignalServiceKit.SignedPreKeyRecord,
        localDevicePniPqLastResortPreKey: KyberPreKeyRecord,
        localDevicePniRegistrationId: UInt32
    ) async throws -> PniDistribution.Parameters
}

final class PniDistributionParameterBuilderImpl: PniDistributionParamaterBuilder {
    private let logger = PrefixedLogger(prefix: "PDPBI")

    private let db: any DB
    private let messageSender: Shims.MessageSender
    private let pniSignedPreKeyStore: SignalSignedPreKeyStore
    private let pniKyberPreKeyStore: SignalKyberPreKeyStore
    private let registrationIdGenerator: RegistrationIdGenerator

    init(
        db: any DB,
        messageSender: Shims.MessageSender,
        pniSignedPreKeyStore: SignalSignedPreKeyStore,
        pniKyberPreKeyStore: SignalKyberPreKeyStore,
        registrationIdGenerator: RegistrationIdGenerator
    ) {
        self.db = db
        self.messageSender = messageSender
        self.pniSignedPreKeyStore = pniSignedPreKeyStore
        self.pniKyberPreKeyStore = pniKyberPreKeyStore
        self.registrationIdGenerator = registrationIdGenerator
    }

    func buildPniDistributionParameters(
        localAci: Aci,
        localRecipientUniqueId: String,
        localDeviceId: LocalDeviceId,
        localUserAllDeviceIds: [DeviceId],
        localPniIdentityKeyPair: ECKeyPair,
        localE164: E164,
        localDevicePniSignedPreKey: SignalServiceKit.SignedPreKeyRecord,
        localDevicePniPqLastResortPreKey: KyberPreKeyRecord,
        localDevicePniRegistrationId: UInt32
    ) async throws -> PniDistribution.Parameters {
        var parameters = PniDistribution.Parameters(pniIdentityKey: localPniIdentityKeyPair.keyPair.identityKey)

        var localUserDeviceId: DeviceId?
        var localUserLinkedDeviceIds = [DeviceId]()

        for deviceId in localUserAllDeviceIds {
            if localDeviceId.equals(deviceId) {
                localUserDeviceId = deviceId
            } else {
                localUserLinkedDeviceIds.append(deviceId)
            }
        }

        guard let localUserDeviceId else {
            let message = "Local device ID missing - can't build linked device params if the local device isn't registered."
            logger.error(message)
            throw OWSGenericError(message)
        }

        // Include the signed pre key & registration ID for the current device.
        parameters.addLocalDevice(
            localDeviceId: localUserDeviceId,
            signedPreKey: localDevicePniSignedPreKey,
            pqLastResortPreKey: localDevicePniPqLastResortPreKey,
            registrationId: localDevicePniRegistrationId
        )

        // Create a signed pre key & registration ID for linked devices.
        let linkedDeviceParamResults = try await buildLinkedDevicePniGenerationParams(
            localAci: localAci,
            localRecipientUniqueId: localRecipientUniqueId,
            localUserLinkedDeviceIds: localUserLinkedDeviceIds,
            pniIdentityKeyPair: localPniIdentityKeyPair,
            e164: localE164
        )

        for param in linkedDeviceParamResults {
            parameters.addLinkedDevice(
                deviceId: param.deviceId,
                signedPreKey: param.signedPreKey,
                pqLastResortPreKey: param.pqLastResortPreKey,
                registrationId: param.registrationId,
                deviceMessage: param.deviceMessage
            )
        }

        return parameters
    }

    /// Bundles parameters concerning linked devices and PNI identity
    /// generation.
    private struct LinkedDevicePniGenerationParams {
        let deviceId: DeviceId
        let signedPreKey: SignalServiceKit.SignedPreKeyRecord
        let pqLastResortPreKey: KyberPreKeyRecord
        let registrationId: UInt32
        let deviceMessage: DeviceMessage
    }

    /// Asynchronously build params for generating a new PNI identity, for each
    /// linked device.
    /// - Returns
    /// One promise per linked device for which PNI identity generation params
    /// are being built. A `nil` param in a resolved promise indicates a linked
    /// device that is no longer valid, and was ignored.
    private func buildLinkedDevicePniGenerationParams(
        localAci: Aci,
        localRecipientUniqueId: String,
        localUserLinkedDeviceIds: [DeviceId],
        pniIdentityKeyPair: ECKeyPair,
        e164: E164
    ) async throws -> [LinkedDevicePniGenerationParams] {
        let logger = logger

        return try await withThrowingTaskGroup(of: LinkedDevicePniGenerationParams?.self) { taskGroup in
            for linkedDeviceId in localUserLinkedDeviceIds {
                let signedPreKey = pniSignedPreKeyStore.generateSignedPreKey(signedBy: pniIdentityKeyPair)
                let pqLastResortPreKey = pniKyberPreKeyStore.generateLastResortKyberPreKeyForLinkedDevice(signedBy: pniIdentityKeyPair)
                let registrationId = registrationIdGenerator.generate()

                logger.info("Building device message for device with ID \(linkedDeviceId).")

                taskGroup.addTask {
                    let deviceMessage: DeviceMessage?
                    do {
                        deviceMessage = try await self.encryptPniDistributionMessage(
                            recipientUniqueId: localRecipientUniqueId,
                            recipientAci: localAci,
                            recipientDeviceId: linkedDeviceId,
                            identityKeyPair: pniIdentityKeyPair,
                            signedPreKey: signedPreKey,
                            pqLastResortPreKey: pqLastResortPreKey,
                            registrationId: registrationId,
                            e164: e164
                        )
                    } catch {
                        logger.error("Failed to build device message for device with ID \(linkedDeviceId): \(error).")
                        throw error
                    }

                    guard let deviceMessage else {
                        logger.warn("Missing device message - is device with ID \(linkedDeviceId) invalid?")
                        return nil
                    }

                    logger.info("Built device message for device with ID \(linkedDeviceId).")

                    return LinkedDevicePniGenerationParams(
                        deviceId: linkedDeviceId,
                        signedPreKey: signedPreKey,
                        pqLastResortPreKey: pqLastResortPreKey,
                        registrationId: registrationId,
                        deviceMessage: deviceMessage
                    )
                }

            }
            return try await taskGroup.reduce(into: [], { $0.append($1) }).compacted()
        }
    }

    /// Builds a ``DeviceMessage`` for the given parameters, for delivery to a
    /// linked device.
    ///
    /// - Returns
    /// The message for the linked device. If `nil`, indicates the device was
    /// invalid and should be skipped.
    private func encryptPniDistributionMessage(
        recipientUniqueId: String,
        recipientAci: Aci,
        recipientDeviceId: DeviceId,
        identityKeyPair: ECKeyPair,
        signedPreKey: SignalServiceKit.SignedPreKeyRecord,
        pqLastResortPreKey: KyberPreKeyRecord,
        registrationId: UInt32,
        e164: E164
    ) async throws -> DeviceMessage? {
        let message = PniDistributionSyncMessage(
            pniIdentityKeyPair: identityKeyPair,
            signedPreKey: signedPreKey,
            pqLastResortPreKey: pqLastResortPreKey,
            registrationId: registrationId,
            e164: e164
        )

        let plaintextContent = try message.buildSerializedMessageProto()

        return try await self.messageSender.buildDeviceMessage(
            forMessagePlaintextContent: plaintextContent,
            messageEncryptionStyle: .whisper,
            recipientUniqueId: recipientUniqueId,
            serviceId: recipientAci,
            deviceId: recipientDeviceId,
            isOnlineMessage: false,
            isTransientSenderKeyDistributionMessage: false,
            isResendRequestMessage: false,
            sealedSenderParameters: nil // Sync messages do not use UD
        )
    }
}

// MARK: - Shims

extension PniDistributionParameterBuilderImpl {
    enum Shims {
        typealias MessageSender = _PniDistributionParameterBuilder_MessageSender_Shim
    }

    enum Wrappers {
        typealias MessageSender = _PniDistributionParameterBuilder_MessageSender_Wrapper
    }
}

// MARK: MessageSender

protocol _PniDistributionParameterBuilder_MessageSender_Shim {
    func buildDeviceMessage(
        forMessagePlaintextContent messagePlaintextContent: Data,
        messageEncryptionStyle: EncryptionStyle,
        recipientUniqueId: String,
        serviceId: ServiceId,
        deviceId: DeviceId,
        isOnlineMessage: Bool,
        isTransientSenderKeyDistributionMessage: Bool,
        isResendRequestMessage: Bool,
        sealedSenderParameters: SealedSenderParameters?
    ) async throws -> DeviceMessage?
}

class _PniDistributionParameterBuilder_MessageSender_Wrapper: _PniDistributionParameterBuilder_MessageSender_Shim {
    private let messageSender: MessageSender

    init(_ messageSender: MessageSender) {
        self.messageSender = messageSender
    }

    func buildDeviceMessage(
        forMessagePlaintextContent messagePlaintextContent: Data,
        messageEncryptionStyle: EncryptionStyle,
        recipientUniqueId: String,
        serviceId: ServiceId,
        deviceId: DeviceId,
        isOnlineMessage: Bool,
        isTransientSenderKeyDistributionMessage: Bool,
        isResendRequestMessage: Bool,
        sealedSenderParameters: SealedSenderParameters?
    ) async throws -> DeviceMessage? {
        try await messageSender.buildDeviceMessage(
            messagePlaintextContent: messagePlaintextContent,
            messageEncryptionStyle: messageEncryptionStyle,
            recipientUniqueId: recipientUniqueId,
            serviceId: serviceId,
            deviceId: deviceId,
            isOnlineMessage: isOnlineMessage,
            isTransientSenderKeyDistributionMessage: isTransientSenderKeyDistributionMessage,
            isResendRequestMessage: isResendRequestMessage,
            sealedSenderParameters: sealedSenderParameters
        )
    }
}
