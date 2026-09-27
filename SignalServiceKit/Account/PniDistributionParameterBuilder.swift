//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

public enum PniDistribution {
    /// Parameters for distributing PNI information to linked devices.
    public struct Parameters {
        let pniIdentityKey: IdentityKey
        private(set) var devicePniSignedPreKeys: [DeviceId: LibSignalClient.SignedPreKeyRecord] = [:]
        private(set) var devicePniPqLastResortPreKeys: [DeviceId: LibSignalClient.KyberPreKeyRecord] = [:]
        private(set) var pniRegistrationIds: [DeviceId: UInt32] = [:]
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
            devicePniSignedPreKeys[localDeviceId] = signedPreKey
            devicePniPqLastResortPreKeys[localDeviceId] = pqLastResortPreKey
            pniRegistrationIds[localDeviceId] = registrationId
        }

        fileprivate mutating func addLinkedDevice(
            deviceId: DeviceId,
            signedPreKey: LibSignalClient.SignedPreKeyRecord,
            pqLastResortPreKey: LibSignalClient.KyberPreKeyRecord,
            registrationId: UInt32,
            deviceMessage: DeviceMessage,
        ) {
            owsPrecondition(deviceId == deviceMessage.deviceId)

            devicePniSignedPreKeys[deviceId] = signedPreKey
            devicePniPqLastResortPreKeys[deviceId] = pqLastResortPreKey
            pniRegistrationIds[deviceId] = registrationId
            deviceMessages.append(deviceMessage)
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
        localDeviceId: DeviceId,
        localNewPhoneNumber: E164,
        localPniIdentityKeyPair: ECKeyPair,
        localDevicePniSignedPreKey: LibSignalClient.SignedPreKeyRecord,
        localDevicePniPqLastResortPreKey: LibSignalClient.KyberPreKeyRecord,
        localDevicePniRegistrationId: UInt32,
    ) async throws -> PniDistribution.Parameters
}

final class PniDistributionParameterBuilderImpl: PniDistributionParamaterBuilder {
    private let logger = PrefixedLogger(prefix: "PDPBI")

    private let db: any DB
    private let deviceMessageBuilder: any DeviceMessageBuilder
    private let pniKyberPreKeyStore: KyberPreKeyStoreImpl
    private let registrationIdGenerator: RegistrationIdGenerator

    init(
        db: any DB,
        deviceMessageBuilder: any DeviceMessageBuilder,
        pniKyberPreKeyStore: KyberPreKeyStoreImpl,
        registrationIdGenerator: RegistrationIdGenerator,
    ) {
        self.db = db
        self.deviceMessageBuilder = deviceMessageBuilder
        self.pniKyberPreKeyStore = pniKyberPreKeyStore
        self.registrationIdGenerator = registrationIdGenerator
    }

    func buildPniDistributionParameters(
        localAci: Aci,
        localDeviceId: DeviceId,
        localNewPhoneNumber: E164,
        localPniIdentityKeyPair: ECKeyPair,
        localDevicePniSignedPreKey: LibSignalClient.SignedPreKeyRecord,
        localDevicePniPqLastResortPreKey: LibSignalClient.KyberPreKeyRecord,
        localDevicePniRegistrationId: UInt32,
    ) async throws -> PniDistribution.Parameters {
        var parameters = PniDistribution.Parameters(pniIdentityKey: localPniIdentityKeyPair.keyPair.identityKey)

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
            localDeviceId: localDeviceId,
            newPhoneNumber: localNewPhoneNumber,
            pniIdentityKeyPair: localPniIdentityKeyPair,
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
        localDeviceId: DeviceId,
        newPhoneNumber: E164,
        pniIdentityKeyPair: ECKeyPair,
    ) async throws -> [LinkedDevicePniGenerationParams] {
        var syncMessages = [DeviceId: PniDistributionSyncMessage]()

        let identityKey = pniIdentityKeyPair.identityKeyPair.privateKey
        let deviceMessages = try await self.deviceMessageBuilder.buildDeviceMessages(
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
                    e164: newPhoneNumber,
                )

                syncMessages[deviceId] = syncMessage

                return try syncMessage.buildSerializedMessageProto()
            },
            isTransient: false,
            sealedSenderParameters: nil, // Sync messages do not use UD
            localAci: localAci,
            localDeviceId: localDeviceId,
        )

        return deviceMessages.map {
            let syncMessage = syncMessages[$0.deviceId]!
            return LinkedDevicePniGenerationParams(
                deviceId: $0.deviceId,
                signedPreKey: syncMessage.signedPreKey,
                pqLastResortPreKey: syncMessage.pqLastResortPreKey,
                registrationId: syncMessage.registrationId,
                deviceMessage: $0,
            )
        }
    }
}
