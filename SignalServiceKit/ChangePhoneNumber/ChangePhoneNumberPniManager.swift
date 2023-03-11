//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Curve25519Kit
import Foundation

// MARK: - ChangePhoneNumberPniManager protocol

public protocol ChangePhoneNumberPniManager {
    /// Prepares for an impending "change number" request.
    ///
    /// Generates parameters to set a new PNI identity, including:
    /// - A new identity key for this account.
    /// - New signed pre-key pairs and registration IDs for all devices.
    /// - An encrypted message for each linked device informing them about the
    ///   new identity. Note that this message contains private key data.
    ///
    /// It is possible that the change-number request will be interrupted
    /// (e.g. app crash, connection loss), but that the new identity will have
    /// already been accepted and committed by the server. In this scenario the
    /// server will be using/returning the new identity while the client has not
    /// yet committed it. Therefore, on interruption the change-number caller
    /// must durably confirm whether or not the request succeeded.
    ///
    /// To facilitate this scenario, this API returns two values - "parameters"
    /// for a change-number request, and "pending state". Before making a
    /// change-number request with the parameters the caller should persist the
    /// pending state. If the change-number request succeeds, the caller must
    /// call ``finalizePniIdentity`` with the pending state and should then
    /// discard the pending state. If the change-number request is interrupted
    /// and the caller still holds pending state from a previous attempt, the
    /// caller must check if the pending state matches state on the server. If
    /// so, the server accepted the change before the interruption and the
    /// caller must immediately call ``finalizePniIdentity``. If not, the change
    /// was not accepted and the pending state should be discarded.
    ///
    /// - Returns
    /// Parameters included as part of a change-number request, and corresponding
    /// state to be retained until the outcome of the request is known. If an
    /// error is returned, automatic retry is not recommended.
    func generatePniIdentity(
        forNewE164 newE164: E164,
        localAci: ServiceId,
        localAccountId: String,
        localDeviceId: UInt32,
        localUserAllDeviceIds: [UInt32],
        transaction: DBWriteTransaction
    ) -> Guarantee<ChangePhoneNumberPni.GeneratePniIdentityResult>

    /// Commits an identity generated for a change number request.
    ///
    /// This method should be called after the caller has confirmed that the
    /// server has committed a new PNI identity, with the state from a prior
    /// call to ``generatePniIdentity``.
    func finalizePniIdentity(
        withPendingState pendingState: ChangePhoneNumberPni.PendingState,
        transaction: DBWriteTransaction
    )
}

// MARK: - Change-Number PNI types

/// Namespace for change-number PNI types.
public enum ChangePhoneNumberPni {

    /// PNI-related parameters for a change-number request.
    public struct Parameters {
        let pniIdentityKey: Data
        private(set) var devicePniSignedPreKeys: [String: SignedPreKeyRecord] = [:]
        private(set) var pniRegistrationIds: [String: UInt32] = [:]
        private(set) var deviceMessages: [DeviceMessage] = []

        fileprivate init(pniIdentityKey: Data) {
            self.pniIdentityKey = pniIdentityKey
        }

        fileprivate mutating func addLocalDevice(
            localDeviceId: UInt32,
            signedPreKey: SignedPreKeyRecord,
            registrationId: UInt32
        ) {
            devicePniSignedPreKeys["\(localDeviceId)"] = signedPreKey
            pniRegistrationIds["\(localDeviceId)"] = registrationId
        }

        fileprivate mutating func addLinkedDevice(
            deviceId: UInt32,
            signedPreKey: SignedPreKeyRecord,
            registrationId: UInt32,
            deviceMessage: DeviceMessage
        ) {
            owsAssert(deviceId == deviceMessage.destinationDeviceId)

            devicePniSignedPreKeys["\(deviceId)"] = signedPreKey
            pniRegistrationIds["\(deviceId)"] = registrationId
            deviceMessages.append(deviceMessage)
        }

        func requestParameters() -> [String: Any] {
            [
                "pniIdentityKey": pniIdentityKey.prependKeyType().base64EncodedString(),
                "devicePniSignedPrekeys": devicePniSignedPreKeys.mapValues { OWSRequestFactory.signedPreKeyRequestParameters($0) },
                "deviceMessages": deviceMessages.map { $0.requestParameters() },
                "pniRegistrationIds": pniRegistrationIds
            ]
        }
    }

    /// Represents a change-number operation that has not yet been finalized.
    public struct PendingState {
        let newE164: E164
        let pniIdentityKeyPair: ECKeyPair
        let localDevicePniSignedPreKeyRecord: SignedPreKeyRecord
        let localDevicePniRegistrationId: UInt32
    }

    public enum GeneratePniIdentityResult {
        /// Successful generation of PNI change-number parameters and state.
        case success(parameters: Parameters, pendingState: PendingState)

        /// An error occurred.
        case failure
    }
}

// MARK: - ChangeNumberPniManagerImpl implementation

class ChangePhoneNumberPniManagerImpl: ChangePhoneNumberPniManager {

    // MARK: - Init

    private let logger: PrefixedLogger = .init(prefix: "[CNPNI]")

    private let schedulers: Schedulers

    private let identityManager: Shims.IdentityManager
    private let messageSender: Shims.MessageSender
    private let preKeyManager: Shims.PreKeyManager
    private let pniSignedPreKeyStore: Shims.SignedPreKeyStore
    private let tsAccountManager: Shims.TSAccountManager

    init(
        schedulers: Schedulers,
        identityManager: Shims.IdentityManager,
        messageSender: Shims.MessageSender,
        preKeyManager: Shims.PreKeyManager,
        pniSignedPreKeyStore: Shims.SignedPreKeyStore,
        tsAccountManager: Shims.TSAccountManager
    ) {
        self.identityManager = identityManager
        self.messageSender = messageSender
        self.preKeyManager = preKeyManager
        self.pniSignedPreKeyStore = pniSignedPreKeyStore
        self.schedulers = schedulers
        self.tsAccountManager = tsAccountManager
    }

    // MARK: - Generating the New Identity

    func generatePniIdentity(
        forNewE164 newE164: E164,
        localAci: ServiceId,
        localAccountId: String,
        localDeviceId: UInt32,
        localUserAllDeviceIds: [UInt32],
        transaction: DBWriteTransaction
    ) -> Guarantee<ChangePhoneNumberPni.GeneratePniIdentityResult> {
        logger.info("Generating PNI identity!")

        let pniIdentityKeyPair = identityManager.generateNewIdentityKeyPair()

        let pendingState = ChangePhoneNumberPni.PendingState(
            newE164: newE164,
            pniIdentityKeyPair: pniIdentityKeyPair,
            localDevicePniSignedPreKeyRecord: SSKSignedPreKeyStore.generateSignedPreKey(signedBy: pniIdentityKeyPair),
            localDevicePniRegistrationId: TSAccountManager.generateRegistrationId()
        )

        var pniParameters = ChangePhoneNumberPni.Parameters(pniIdentityKey: pniIdentityKeyPair.publicKey)

        // Include the signed pre key & registration ID for the current device.
        pniParameters.addLocalDevice(
            localDeviceId: localDeviceId,
            signedPreKey: pendingState.localDevicePniSignedPreKeyRecord,
            registrationId: pendingState.localDevicePniRegistrationId
        )

        // Create a signed pre key & registration ID for linked devices.
        let linkedDevicePromises: [Promise<LinkedDevicePniGenerationParams?>]
        do {
            linkedDevicePromises = try buildLinkedDevicePniGenerationParams(
                localAci: localAci,
                localAccountId: localAccountId,
                localDeviceId: localDeviceId,
                localUserAllDeviceIds: localUserAllDeviceIds,
                pniIdentityKeyPair: pniIdentityKeyPair
            )
        } catch {
            return .value(.failure)
        }

        return firstly(on: schedulers.sync) { [schedulers] () -> Guarantee<[Result<LinkedDevicePniGenerationParams?, Error>]> in
            Guarantee.when(
                on: schedulers.global(),
                resolved: linkedDevicePromises
            )
        }.map(on: schedulers.sync) { linkedDeviceParamResults -> ChangePhoneNumberPni.GeneratePniIdentityResult in
            for linkedDeviceParamResult in linkedDeviceParamResults {
                switch linkedDeviceParamResult {
                case .success(let param):
                    guard let param else { continue }

                    pniParameters.addLinkedDevice(
                        deviceId: param.deviceId,
                        signedPreKey: param.signedPreKey,
                        registrationId: param.registrationId,
                        deviceMessage: param.deviceMessage
                    )
                case .failure:
                    // If we have any errors, return immediately.
                    return .failure
                }
            }

            return .success(
                parameters: pniParameters,
                pendingState: pendingState
            )
        }
    }

    /// Bundles parameters concerning linked devices and PNI identity
    /// generation.
    private struct LinkedDevicePniGenerationParams {
        let deviceId: UInt32
        let signedPreKey: SignedPreKeyRecord
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
        localAci: ServiceId,
        localAccountId: String,
        localDeviceId: UInt32,
        localUserAllDeviceIds: [UInt32],
        pniIdentityKeyPair: ECKeyPair
    ) throws -> [Promise<LinkedDevicePniGenerationParams?>] {
        let localUserLinkedDeviceIds: [UInt32] = localUserAllDeviceIds.filter { deviceId in
            deviceId != localDeviceId
        }

        guard localUserLinkedDeviceIds.count == (localUserAllDeviceIds.count - 1) else {
            throw OWSAssertionError("Local device ID missing - can't change number if the local device isn't registered.")
        }

        return localUserLinkedDeviceIds.map { linkedDeviceId in
            let logger = logger
            let signedPreKey = SSKSignedPreKeyStore.generateSignedPreKey(signedBy: pniIdentityKeyPair)
            let registrationId = TSAccountManager.generateRegistrationId()

            logger.info("Building device message for device with ID \(linkedDeviceId).")

            return encryptPniChangeNumber(
                forRecipientAci: localAci,
                recipientAccountId: localAccountId,
                recipientDeviceId: linkedDeviceId,
                identityKeyPair: pniIdentityKeyPair,
                signedPreKey: signedPreKey,
                registrationId: registrationId
            ).map(on: schedulers.sync) { deviceMessage -> LinkedDevicePniGenerationParams? in
                guard let deviceMessage else {
                    logger.warn("Missing device message - is device with ID \(linkedDeviceId) invalid?")
                    return nil
                }

                logger.info("Built device message for device with ID \(linkedDeviceId).")

                return LinkedDevicePniGenerationParams(
                    deviceId: linkedDeviceId,
                    signedPreKey: signedPreKey,
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
    private func encryptPniChangeNumber(
        forRecipientAci recipientAci: ServiceId,
        recipientAccountId: String,
        recipientDeviceId: UInt32,
        identityKeyPair: ECKeyPair,
        signedPreKey: SignedPreKeyRecord,
        registrationId: UInt32
    ) -> Promise<DeviceMessage?> {
        let message = PniChangePhoneNumberSyncMessage(
            pniIdentityKeyPair: identityKeyPair,
            signedPreKey: signedPreKey,
            registrationId: registrationId
        )

        let plaintextContent: Data
        do {
            plaintextContent = try message.buildSerializedMessageProto()
        } catch let error {
            return .init(error: error)
        }

        return firstly(on: schedulers.global()) { () throws -> DeviceMessage? in
            // Important to wrap this in asynchronity, since it might make
            // blocking network requests.
            let deviceMessage: DeviceMessage? = try self.messageSender.buildDeviceMessage(
                forMessagePlaintextContent: plaintextContent,
                messageEncryptionStyle: .whisper,
                recipientServiceId: recipientAci,
                recipientAccountId: recipientAccountId,
                recipientDeviceId: NSNumber(value: recipientDeviceId),
                isOnlineMessage: false,
                isTransientSenderKeyDistributionMessage: false,
                isStorySendMessage: false,
                isResendRequestMessage: false,
                udSendingParamsProvider: nil // Sync messages do not use UD
            )

            return deviceMessage
        }
    }

    // MARK: - Saving the New Identity

    func finalizePniIdentity(
        withPendingState pendingState: ChangePhoneNumberPni.PendingState,
        transaction: DBWriteTransaction
    ) {
        logger.info("Finalizing PNI identity.")

        // Store pending state in the right places

        identityManager.storeIdentityKeyPair(
            pendingState.pniIdentityKeyPair,
            for: .pni,
            transaction: transaction
        )

        let newSignedPreKeyRecord = pendingState.localDevicePniSignedPreKeyRecord
        pniSignedPreKeyStore.storeSignedPreKeyAsAcceptedAndCurrent(
            signedPreKeyId: newSignedPreKeyRecord.id,
            signedPreKeyRecord: newSignedPreKeyRecord,
            transaction: transaction
        )

        tsAccountManager.setPniRegistrationId(
            newRegistrationId: pendingState.localDevicePniRegistrationId,
            transaction: transaction
        )

        // Followup tasks

        // Since we rotated the identity key, we need new one-time pre-keys.
        // However, no need to update the signed pre-key, which we also just
        // rotated.
        preKeyManager.refreshOneTimePreKeys(
            forIdentity: .pni,
            alsoRefreshSignedPreKey: false
        )
    }
}

// MARK: - PendingState Codable

extension ChangePhoneNumberPni.PendingState: Codable {
    private enum CodingKeys: String, CodingKey {
        case newE164
        case pniIdentityKeyPair
        case localDevicePniSignedPreKeyRecord
        case localDevicePniRegistrationId
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.newE164 = try container.decode(E164.self, forKey: .newE164)
        self.localDevicePniRegistrationId = try container.decode(UInt32.self, forKey: .localDevicePniRegistrationId)

        guard
            let pniIdentityKeyPair: ECKeyPair = try Self.decodeKeyedArchive(
                fromDecodingContainer: container,
                forKey: .pniIdentityKeyPair
            ),
            let localDevicePniSignedPreKeyRecord: SignedPreKeyRecord = try Self.decodeKeyedArchive(
                fromDecodingContainer: container,
                forKey: .localDevicePniSignedPreKeyRecord
            )
        else {
            throw OWSAssertionError("Unable to deserialize NSKeyedArchiver fields!")
        }

        self.pniIdentityKeyPair = pniIdentityKeyPair
        self.localDevicePniSignedPreKeyRecord = localDevicePniSignedPreKeyRecord
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(newE164, forKey: .newE164)
        try container.encode(localDevicePniRegistrationId, forKey: .localDevicePniRegistrationId)

        try Self.encodeKeyedArchive(
            value: pniIdentityKeyPair,
            toEncodingContainer: &container,
            forKey: .pniIdentityKeyPair
        )

        try Self.encodeKeyedArchive(
            value: localDevicePniSignedPreKeyRecord,
            toEncodingContainer: &container,
            forKey: .localDevicePniSignedPreKeyRecord
        )
    }

    // MARK: NSKeyed[Un]Archiver

    private static func decodeKeyedArchive<T: NSObject & NSSecureCoding>(
        fromDecodingContainer decodingContainer: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> T? {
        let data = try decodingContainer.decode(Data.self, forKey: key)

        return try NSKeyedUnarchiver.unarchivedObject(ofClass: T.self, from: data)
    }

    private static func encodeKeyedArchive<T: NSObject & NSSecureCoding>(
        value: T,
        toEncodingContainer encodingContainer: inout KeyedEncodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws {
        let data = try NSKeyedArchiver.archivedData(
            withRootObject: value,
            requiringSecureCoding: true
        )

        try encodingContainer.encode(data, forKey: key)
    }
}
