//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

public enum PniDistribution {
    /// Parameters for distributing PNI information to linked devices.
    public struct Parameters {
        let pniIdentityKey: IdentityKey
        private(set) var devicePniSignedPreKeys: [String: LibSignalClient.SignedPreKeyRecord] = [:]
        private(set) var devicePniPqLastResortPreKeys: [String: LibSignalClient.KyberPreKeyRecord] = [:]
        private(set) var pniRegistrationIds: [String: UInt32] = [:]
        private(set) var deviceMessages: [DeviceMessage] = []

        fileprivate init(pniIdentityKey: IdentityKey) {
            self.pniIdentityKey = pniIdentityKey
        }

#if TESTABLE_BUILD

        static func mock(
            pniIdentityKeyPair: ECKeyPair,
            localDeviceId: DeviceId,
            localDevicePniSignedPreKey: LibSignalClient.SignedPreKeyRecord,
            localDevicePniPqLastResortPreKey: LibSignalClient.KyberPreKeyRecord,
            localDevicePniRegistrationId: UInt32,
        ) -> Parameters {
            var mock = Parameters(pniIdentityKey: pniIdentityKeyPair.keyPair.identityKey)
            mock.addLocalDevice(
                localDeviceId: localDeviceId,
                signedPreKey: localDevicePniSignedPreKey,
                pqLastResortPreKey: localDevicePniPqLastResortPreKey,
                registrationId: localDevicePniRegistrationId,
            )
            return mock
        }

#endif

        fileprivate mutating func addLocalDevice(
            localDeviceId: DeviceId,
            signedPreKey: LibSignalClient.SignedPreKeyRecord,
            pqLastResortPreKey: LibSignalClient.KyberPreKeyRecord,
            registrationId: UInt32,
        ) {
            devicePniSignedPreKeys["\(localDeviceId)"] = signedPreKey
            devicePniPqLastResortPreKeys["\(localDeviceId)"] = pqLastResortPreKey
            pniRegistrationIds["\(localDeviceId)"] = registrationId
        }

        fileprivate mutating func addLinkedDevice(
            deviceId: DeviceId,
            signedPreKey: LibSignalClient.SignedPreKeyRecord,
            pqLastResortPreKey: LibSignalClient.KyberPreKeyRecord,
            registrationId: UInt32,
            deviceMessage: DeviceMessage,
        ) {
            owsPrecondition(deviceId == deviceMessage.destinationDeviceId)

            devicePniSignedPreKeys["\(deviceId)"] = signedPreKey
            devicePniPqLastResortPreKeys["\(deviceId)"] = pqLastResortPreKey
            pniRegistrationIds["\(deviceId)"] = registrationId
            deviceMessages.append(deviceMessage)
        }

        func requestParameters() -> [String: Any] {
            [
                "pniIdentityKey": pniIdentityKey.serialize().base64EncodedString(),
                "devicePniSignedPrekeys": devicePniSignedPreKeys.mapValues { OWSRequestFactory.signedPreKeyRequestParameters($0) },
                "devicePniPqLastResortPrekeys": devicePniPqLastResortPreKeys.mapValues { OWSRequestFactory.pqPreKeyRequestParameters($0) },
                "deviceMessages": deviceMessages.map { $0.requestParameters() },
                "pniRegistrationIds": pniRegistrationIds,
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
        localDeviceId: LocalDeviceId,
        localPniIdentityKeyPair: ECKeyPair,
        localE164: E164,
        localDevicePniSignedPreKey: LibSignalClient.SignedPreKeyRecord,
        localDevicePniPqLastResortPreKey: LibSignalClient.KyberPreKeyRecord,
        localDevicePniRegistrationId: UInt32,
    ) async throws -> PniDistribution.Parameters
}

final class PniDistributionParameterBuilderImpl: PniDistributionParamaterBuilder {
    private let logger = PrefixedLogger(prefix: "PDPBI")

    private let db: any DB
    private let messageSender: Shims.MessageSender
    private let pniKyberPreKeyStore: KyberPreKeyStoreImpl
    private let registrationIdGenerator: RegistrationIdGenerator

    init(
        db: any DB,
        messageSender: Shims.MessageSender,
        pniKyberPreKeyStore: KyberPreKeyStoreImpl,
        registrationIdGenerator: RegistrationIdGenerator,
    ) {
        self.db = db
        self.messageSender = messageSender
        self.pniKyberPreKeyStore = pniKyberPreKeyStore
        self.registrationIdGenerator = registrationIdGenerator
    }

    func buildPniDistributionParameters(
        localAci: Aci,
        localDeviceId: LocalDeviceId,
        localPniIdentityKeyPair: ECKeyPair,
        localE164: E164,
        localDevicePniSignedPreKey: LibSignalClient.SignedPreKeyRecord,
        localDevicePniPqLastResortPreKey: LibSignalClient.KyberPreKeyRecord,
        localDevicePniRegistrationId: UInt32,
    ) async throws -> PniDistribution.Parameters {
        var parameters = PniDistribution.Parameters(pniIdentityKey: localPniIdentityKeyPair.keyPair.identityKey)

        guard let localDeviceId = localDeviceId.ifValid else {
            let message = "Local device ID missing - can't build linked device params if the local device isn't registered."
            logger.error(message)
            throw OWSGenericError(message)
        }

        // Include the signed pre key & registration ID for the current device.
        parameters.addLocalDevice(
            localDeviceId: localDeviceId,
            signedPreKey: localDevicePniSignedPreKey,
            pqLastResortPreKey: localDevicePniPqLastResortPreKey,
            registrationId: localDevicePniRegistrationId,
        )

        // Create a signed pre key & registration ID for linked devices.
        let linkedDeviceParamResults = try await buildLinkedDevicePniGenerationParams(
            localAci: localAci,
            pniIdentityKeyPair: localPniIdentityKeyPair,
            e164: localE164,
        )

        for param in linkedDeviceParamResults {
            parameters.addLinkedDevice(
                deviceId: param.deviceId,
                signedPreKey: param.signedPreKey,
                pqLastResortPreKey: param.pqLastResortPreKey,
                registrationId: param.registrationId,
                deviceMessage: param.deviceMessage,
            )
        }

        return parameters
    }

    /// Bundles parameters concerning linked devices and PNI identity
    /// generation.
    private struct LinkedDevicePniGenerationParams {
        let deviceId: DeviceId
        let signedPreKey: LibSignalClient.SignedPreKeyRecord
        let pqLastResortPreKey: LibSignalClient.KyberPreKeyRecord
        let registrationId: UInt32
        let deviceMessage: DeviceMessage
    }

    /// Build messages for our linked devices with new PNI key material.
    private func buildLinkedDevicePniGenerationParams(
        localAci: Aci,
        pniIdentityKeyPair: ECKeyPair,
        e164: E164,
    ) async throws -> [LinkedDevicePniGenerationParams] {
        var syncMessages = [DeviceId: PniDistributionSyncMessage]()

        let identityKey = pniIdentityKeyPair.identityKeyPair.privateKey
        let deviceMessages = try await self.messageSender.buildDeviceMessages(
            serviceId: localAci,
            isSelfSend: true,
            encryptionStyle: .whisper,
            buildPlaintextContent: { deviceId, _ in
                let signedPreKey = SignedPreKeyStoreImpl.generateSignedPreKey(keyId: PreKeyId.random(), signedBy: identityKey)
                let pqLastResortPreKey = pniKyberPreKeyStore.generateLastResortKyberPreKeyForChangeNumber(signedBy: identityKey)
                let registrationId = registrationIdGenerator.generate()

                let syncMessage = PniDistributionSyncMessage(
                    pniIdentityKeyPair: pniIdentityKeyPair,
                    signedPreKey: signedPreKey,
                    pqLastResortPreKey: pqLastResortPreKey,
                    registrationId: registrationId,
                    e164: e164,
                )

                syncMessages[deviceId] = syncMessage

                return try syncMessage.buildSerializedMessageProto()
            },
            isTransient: false,
            sealedSenderParameters: nil, // Sync messages do not use UD
        )

        return deviceMessages.map {
            let syncMessage = syncMessages[$0.destinationDeviceId]!
            return LinkedDevicePniGenerationParams(
                deviceId: $0.destinationDeviceId,
                signedPreKey: syncMessage.signedPreKey,
                pqLastResortPreKey: syncMessage.pqLastResortPreKey,
                registrationId: syncMessage.registrationId,
                deviceMessage: $0,
            )
        }
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
    func buildDeviceMessages(
        serviceId: ServiceId,
        isSelfSend: Bool,
        encryptionStyle: EncryptionStyle,
        buildPlaintextContent: (DeviceId, DBWriteTransaction) throws -> Data,
        isTransient: Bool,
        sealedSenderParameters: SealedSenderParameters?,
    ) async throws -> [DeviceMessage]
}

class _PniDistributionParameterBuilder_MessageSender_Wrapper: _PniDistributionParameterBuilder_MessageSender_Shim {
    private let messageSender: MessageSender

    init(_ messageSender: MessageSender) {
        self.messageSender = messageSender
    }

    func buildDeviceMessages(
        serviceId: ServiceId,
        isSelfSend: Bool,
        encryptionStyle: EncryptionStyle,
        buildPlaintextContent: (DeviceId, DBWriteTransaction) throws -> Data,
        isTransient: Bool,
        sealedSenderParameters: SealedSenderParameters?,
    ) async throws -> [DeviceMessage] {
        try await messageSender.buildDeviceMessages(
            serviceId: serviceId,
            isSelfSend: isSelfSend,
            encryptionStyle: encryptionStyle,
            buildPlaintextContent: buildPlaintextContent,
            isTransient: isTransient,
            sealedSenderParameters: sealedSenderParameters,
        )
    }
}
