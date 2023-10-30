//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Curve25519Kit
import LibSignalClient
import SignalCoreKit

public enum PniDistribution {
    enum ParameterGenerationResult {
        case success(Parameters)
        case failure
    }

    /// Parameters for distributing PNI information to linked devices.
    public struct Parameters {
        let pniIdentityKey: Data
        private(set) var devicePniSignedPreKeys: [String: SignalServiceKit.SignedPreKeyRecord] = [:]
        private(set) var devicePniPqLastResortPreKeys: [String: KyberPreKeyRecord] = [:]
        private(set) var pniRegistrationIds: [String: UInt32] = [:]
        private(set) var deviceMessages: [DeviceMessage] = []

        fileprivate init(pniIdentityKey: Data) {
            self.pniIdentityKey = pniIdentityKey
        }

        #if TESTABLE_BUILD

        public static func mock(
            pniIdentityKeyPair: ECKeyPair,
            localDeviceId: UInt32,
            localDevicePniSignedPreKey: SignalServiceKit.SignedPreKeyRecord,
            localDevicePniPqLastResortPreKey: KyberPreKeyRecord,
            localDevicePniRegistrationId: UInt32
        ) -> Parameters {
            var mock = Parameters(pniIdentityKey: pniIdentityKeyPair.publicKey)
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
            localDeviceId: UInt32,
            signedPreKey: SignalServiceKit.SignedPreKeyRecord,
            pqLastResortPreKey: KyberPreKeyRecord,
            registrationId: UInt32
        ) {
            devicePniSignedPreKeys["\(localDeviceId)"] = signedPreKey
            devicePniPqLastResortPreKeys["\(localDeviceId)"] = pqLastResortPreKey
            pniRegistrationIds["\(localDeviceId)"] = registrationId
        }

        fileprivate mutating func addLinkedDevice(
            deviceId: UInt32,
            signedPreKey: SignalServiceKit.SignedPreKeyRecord,
            pqLastResortPreKey: KyberPreKeyRecord,
            registrationId: UInt32,
            deviceMessage: DeviceMessage
        ) {
            owsAssert(deviceId == deviceMessage.destinationDeviceId)

            devicePniSignedPreKeys["\(deviceId)"] = signedPreKey
            devicePniPqLastResortPreKeys["\(deviceId)"] = pqLastResortPreKey
            pniRegistrationIds["\(deviceId)"] = registrationId
            deviceMessages.append(deviceMessage)
        }

        func requestParameters() -> [String: Any] {
            [
                "pniIdentityKey": pniIdentityKey.prependKeyType().base64EncodedString(),
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
        localAccountId: String,
        localDeviceId: UInt32,
        localUserAllDeviceIds: [UInt32],
        localPniIdentityKeyPair: ECKeyPair,
        localE164: E164,
        localDevicePniSignedPreKey: SignalServiceKit.SignedPreKeyRecord,
        localDevicePniPqLastResortPreKey: KyberPreKeyRecord,
        localDevicePniRegistrationId: UInt32
    ) -> Guarantee<PniDistribution.ParameterGenerationResult>
}

final class PniDistributionParameterBuilderImpl: PniDistributionParamaterBuilder {
    private let logger = PrefixedLogger(prefix: "PDPBI")

    private let db: DB
    private let messageSender: Shims.MessageSender
    private let pniSignedPreKeyStore: SignalSignedPreKeyStore
    private let pniKyberPreKeyStore: SignalKyberPreKeyStore
    private let registrationIdGenerator: RegistrationIdGenerator
    private let schedulers: Schedulers

    init(
        db: DB,
        messageSender: Shims.MessageSender,
        pniSignedPreKeyStore: SignalSignedPreKeyStore,
        pniKyberPreKeyStore: SignalKyberPreKeyStore,
        registrationIdGenerator: RegistrationIdGenerator,
        schedulers: Schedulers
    ) {
        self.db = db
        self.messageSender = messageSender
        self.pniSignedPreKeyStore = pniSignedPreKeyStore
        self.pniKyberPreKeyStore = pniKyberPreKeyStore
        self.registrationIdGenerator = registrationIdGenerator
        self.schedulers = schedulers
    }

    func buildPniDistributionParameters(
        localAci: Aci,
        localAccountId: String,
        localDeviceId: UInt32,
        localUserAllDeviceIds: [UInt32],
        localPniIdentityKeyPair: ECKeyPair,
        localE164: E164,
        localDevicePniSignedPreKey: SignalServiceKit.SignedPreKeyRecord,
        localDevicePniPqLastResortPreKey: KyberPreKeyRecord,
        localDevicePniRegistrationId: UInt32
    ) -> Guarantee<PniDistribution.ParameterGenerationResult> {
        var parameters = PniDistribution.Parameters(pniIdentityKey: localPniIdentityKeyPair.publicKey)

        // Include the signed pre key & registration ID for the current device.
        parameters.addLocalDevice(
            localDeviceId: localDeviceId,
            signedPreKey: localDevicePniSignedPreKey,
            pqLastResortPreKey: localDevicePniPqLastResortPreKey,
            registrationId: localDevicePniRegistrationId
        )

        // Create a signed pre key & registration ID for linked devices.
        let linkedDevicePromises: [Promise<LinkedDevicePniGenerationParams?>]
        do {
            linkedDevicePromises = try buildLinkedDevicePniGenerationParams(
                localAci: localAci,
                localAccountId: localAccountId,
                localDeviceId: localDeviceId,
                localUserAllDeviceIds: localUserAllDeviceIds,
                pniIdentityKeyPair: localPniIdentityKeyPair,
                e164: localE164
            )
        } catch {
            return .value(.failure)
        }

        return firstly(on: schedulers.sync) { [schedulers] () -> Guarantee<[Result<LinkedDevicePniGenerationParams?, Error>]> in
            Guarantee.when(
                on: schedulers.global(),
                resolved: linkedDevicePromises
            )
        }.map(on: schedulers.sync) { linkedDeviceParamResults -> PniDistribution.ParameterGenerationResult in
            for linkedDeviceParamResult in linkedDeviceParamResults {
                switch linkedDeviceParamResult {
                case .success(let param):
                    guard let param else { continue }

                    parameters.addLinkedDevice(
                        deviceId: param.deviceId,
                        signedPreKey: param.signedPreKey,
                        pqLastResortPreKey: param.pqLastResortPreKey,
                        registrationId: param.registrationId,
                        deviceMessage: param.deviceMessage
                    )
                case .failure:
                    // If we have any errors, return immediately.
                    return .failure
                }
            }

            return .success(parameters)
        }
    }

    /// Bundles parameters concerning linked devices and PNI identity
    /// generation.
    private struct LinkedDevicePniGenerationParams {
        let deviceId: UInt32
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
        localAccountId: String,
        localDeviceId: UInt32,
        localUserAllDeviceIds: [UInt32],
        pniIdentityKeyPair: ECKeyPair,
        e164: E164
    ) throws -> [Promise<LinkedDevicePniGenerationParams?>] {
        let localUserLinkedDeviceIds: [UInt32] = localUserAllDeviceIds.filter { deviceId in
            deviceId != localDeviceId
        }

        guard localUserLinkedDeviceIds.count == (localUserAllDeviceIds.count - 1) else {
            let message = "Local device ID missing - can't build linked device params if the local device isn't registered."
            logger.error(message)
            throw OWSGenericError(message)
        }

        return try localUserLinkedDeviceIds.map { linkedDeviceId -> Promise<LinkedDevicePniGenerationParams?> in
            let logger = logger

            let signedPreKey = pniSignedPreKeyStore.generateSignedPreKey(signedBy: pniIdentityKeyPair)
            let pqLastResortPreKey = try pniKyberPreKeyStore.generateEphemeralLastResortKyberPreKey(
                signedBy: pniIdentityKeyPair
            )

            let registrationId = registrationIdGenerator.generate()

            logger.info("Building device message for device with ID \(linkedDeviceId).")

            return encryptPniDistributionMessage(
                recipientId: localAccountId,
                recipientAci: localAci,
                recipientDeviceId: linkedDeviceId,
                identityKeyPair: pniIdentityKeyPair,
                signedPreKey: signedPreKey,
                pqLastResortPreKey: pqLastResortPreKey,
                registrationId: registrationId,
                e164: e164
            ).map(on: schedulers.sync) { deviceMessage -> LinkedDevicePniGenerationParams? in
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
            }.recover(on: schedulers.sync) { error throws -> Promise<LinkedDevicePniGenerationParams?> in
                logger.error("Failed to build device message for device with ID \(linkedDeviceId): \(error).")
                throw error
            }
        }
    }

    /// Builds a ``DeviceMessage`` for the given parameters, for delivery to a
    /// linked device.
    ///
    /// - Returns
    /// The message for the linked device. If `nil`, indicates the device was
    /// invalid and should be skipped.
    private func encryptPniDistributionMessage(
        recipientId: String,
        recipientAci: Aci,
        recipientDeviceId: UInt32,
        identityKeyPair: ECKeyPair,
        signedPreKey: SignalServiceKit.SignedPreKeyRecord,
        pqLastResortPreKey: KyberPreKeyRecord,
        registrationId: UInt32,
        e164: E164
    ) -> Promise<DeviceMessage?> {
        let message = PniDistributionSyncMessage(
            pniIdentityKeyPair: identityKeyPair,
            signedPreKey: signedPreKey,
            pqLastResortPreKey: pqLastResortPreKey,
            registrationId: registrationId,
            e164: e164
        )

        let plaintextContent: Data
        do {
            plaintextContent = try message.buildSerializedMessageProto()
        } catch let error {
            return .init(error: error)
        }

        return Promise.wrapAsync {
            return try await self.messageSender.buildDeviceMessage(
                forMessagePlaintextContent: plaintextContent,
                messageEncryptionStyle: .whisper,
                recipientId: recipientId,
                serviceId: recipientAci,
                deviceId: recipientDeviceId,
                isOnlineMessage: false,
                isTransientSenderKeyDistributionMessage: false,
                isStoryMessage: false,
                isResendRequestMessage: false,
                sealedSenderParameters: nil // Sync messages do not use UD
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
    func buildDeviceMessage(
        forMessagePlaintextContent messagePlaintextContent: Data,
        messageEncryptionStyle: EncryptionStyle,
        recipientId: String,
        serviceId: ServiceId,
        deviceId: UInt32,
        isOnlineMessage: Bool,
        isTransientSenderKeyDistributionMessage: Bool,
        isStoryMessage: Bool,
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
        recipientId: String,
        serviceId: ServiceId,
        deviceId: UInt32,
        isOnlineMessage: Bool,
        isTransientSenderKeyDistributionMessage: Bool,
        isStoryMessage: Bool,
        isResendRequestMessage: Bool,
        sealedSenderParameters: SealedSenderParameters?
    ) async throws -> DeviceMessage? {
        try await messageSender.buildDeviceMessage(
            messagePlaintextContent: messagePlaintextContent,
            messageEncryptionStyle: messageEncryptionStyle,
            recipientId: recipientId,
            serviceId: serviceId,
            deviceId: deviceId,
            isOnlineMessage: isOnlineMessage,
            isTransientSenderKeyDistributionMessage: isTransientSenderKeyDistributionMessage,
            isStoryMessage: isStoryMessage,
            isResendRequestMessage: isResendRequestMessage,
            sealedSenderParameters: sealedSenderParameters
        )
    }
}
