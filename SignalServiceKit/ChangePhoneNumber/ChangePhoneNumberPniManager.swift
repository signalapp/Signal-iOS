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
        localAddress: SignalServiceAddress,
        localDeviceId: UInt32,
        transaction: DBWriteTransaction
    ) -> Guarantee<ChangePhoneNumberPni.GeneratePniIdentityResult>

    /// Commits an identity generated for a change number request.
    ///
    /// This method should be called after the caller has confirmed that the
    /// server has committed a new PNI identity, with the state from a prior
    /// call to ``generatePniIdentity``.
    func finalizePniIdentity(
        withPendingState pendingState: ChangePhoneNumberPni.PendingState,
        localAddress: SignalServiceAddress,
        transaction: DBWriteTransaction
    )
}

// MARK: - Change-Number PNI types

/// Namespace for change-number PNI types.
public enum ChangePhoneNumberPni {

    /// PNI-related parameters for a change-number request.
    public struct Parameters {
        private let pniIdentityKey: Data
        private var devicePniSignedPreKeys: [String: SignedPreKeyRecord] = [:]
        private var pniRegistrationIds: [String: UInt32] = [:]
        private var deviceMessages: [DeviceMessage] = []

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

        fileprivate let pniIdentityKeyPair: ECKeyPair
        fileprivate let localDevicePniSignedPreKeyRecord: SignedPreKeyRecord
        fileprivate let localDevicePniRegistrationId: UInt32
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

    private let identityManager: OWSIdentityManager
    private let messageSender: MessageSender
    private let pniProtocolStore: SignalProtocolStore
    private let schedulers: Schedulers
    private let tsAccountManager: Shims.TSAccountManager

    init(
        identityManager: OWSIdentityManager,
        messageSender: MessageSender,
        pniProtocolStore: SignalProtocolStore,
        schedulers: Schedulers,
        tsAccountManager: Shims.TSAccountManager
    ) {
        self.identityManager = identityManager
        self.messageSender = messageSender
        self.pniProtocolStore = pniProtocolStore
        self.schedulers = schedulers
        self.tsAccountManager = tsAccountManager
    }

    // MARK: - Generating the New Identity

    func generatePniIdentity(
        forNewE164 newE164: E164,
        localAddress: SignalServiceAddress,
        localDeviceId: UInt32,
        transaction: DBWriteTransaction
    ) -> Guarantee<ChangePhoneNumberPni.GeneratePniIdentityResult> {
        logger.info("Generating PNI identity!")

        let transaction: SDSAnyWriteTransaction = SDSDB.shimOnlyBridge(transaction)

        let recipientParams: MyselfAsRecipientParams
        do {
            recipientParams = try loadRecipientParams(
                localAddress: localAddress,
                localDeviceId: localDeviceId,
                transaction: transaction
            )
        } catch {
            logger.error("Failed to load recipient params.")
            return .value(.failure)
        }

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
            localDeviceId: recipientParams.localDeviceId,
            signedPreKey: pendingState.localDevicePniSignedPreKeyRecord,
            registrationId: pendingState.localDevicePniRegistrationId
        )

        struct LinkedDeviceParams {
            let deviceId: UInt32
            let signedPreKey: SignedPreKeyRecord
            let registrationId: UInt32
            let deviceMessage: DeviceMessage
        }

        // Create a signed pre key & registration ID for linked devices.
        let linkedDevicePromises: [Promise<LinkedDeviceParams?>] = recipientParams.linkedDeviceIds.map { linkedDeviceId in
            let logger = logger
            let signedPreKey = SSKSignedPreKeyStore.generateSignedPreKey(signedBy: pniIdentityKeyPair)
            let registrationId = TSAccountManager.generateRegistrationId()

            logger.info("Building device message for device with ID \(linkedDeviceId).")

            return encryptPniChangeNumber(
                forRecipientAddress: recipientParams.localRecipient.address,
                recipientAccountId: recipientParams.localRecipient.accountId,
                recipientDeviceId: linkedDeviceId,
                identityKeyPair: pniIdentityKeyPair,
                signedPreKey: signedPreKey,
                registrationId: registrationId,
                localThread: recipientParams.localThread,
                transaction: transaction
            ).map(on: schedulers.global()) { deviceMessage -> LinkedDeviceParams? in
                guard let deviceMessage else {
                    logger.warn("Missing device message - is device with ID \(linkedDeviceId) invalid?")
                    return nil
                }

                logger.info("Built device message for device with ID \(linkedDeviceId).")

                return LinkedDeviceParams(
                    deviceId: linkedDeviceId,
                    signedPreKey: signedPreKey,
                    registrationId: registrationId,
                    deviceMessage: deviceMessage
                )
            }.recover(on: schedulers.global()) { error throws -> Promise<LinkedDeviceParams?> in
                logger.error("Failed to build device message for device with ID \(linkedDeviceId): \(error).")
                throw error
            }
        }

        return Guarantee.when(
            on: schedulers.global(),
            resolved: linkedDevicePromises
        ).map(on: schedulers.global()) { (linkedDeviceParamResults: [Result<LinkedDeviceParams?, Error>]) -> ChangePhoneNumberPni.GeneratePniIdentityResult in
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

    /// Params representing the local user.
    private struct MyselfAsRecipientParams {
        let localRecipient: SignalRecipient

        let localDeviceId: UInt32
        let linkedDeviceIds: [UInt32]

        /// A thread for the local user.
        ///
        /// Sync messages use the local thread when encrypting.
        let localThread: TSThread
    }

    private func loadRecipientParams(
        localAddress: SignalServiceAddress,
        localDeviceId: UInt32,
        transaction: SDSAnyWriteTransaction
    ) throws -> MyselfAsRecipientParams {
        guard let localRecipient = SignalRecipient.get(
            address: localAddress,
            mustHaveDevices: false,
            transaction: transaction
        ) else {
            throw OWSAssertionError("Can't change number without local recipient.")
        }

        let linkedDeviceIds: [UInt32] = try {
            var allDeviceIds =  localRecipient.deviceIds ?? []

            guard let localDeviceIdIndex = allDeviceIds.firstIndex(of: localDeviceId) else {
                throw OWSAssertionError("Can't change number if the local device isn't registered.")
            }

            allDeviceIds.remove(at: localDeviceIdIndex)
            return allDeviceIds
        }()

        return .init(
            localRecipient: localRecipient,
            localDeviceId: localDeviceId,
            linkedDeviceIds: linkedDeviceIds,
            localThread: TSContactThread.getOrCreateThread(
                withContactAddress: localAddress,
                transaction: transaction
            )
        )
    }

    /// Builds a ``DeviceMessage`` for the given parameters, for delivery to a
    /// linked device.
    ///
    /// - Returns
    /// The message for the linked device. If `nil`, indicates the device was
    /// invalid and should be skipped.
    private func encryptPniChangeNumber(
        forRecipientAddress recipientAddress: SignalServiceAddress,
        recipientAccountId: String,
        recipientDeviceId: UInt32,
        identityKeyPair: ECKeyPair,
        signedPreKey: SignedPreKeyRecord,
        registrationId: UInt32,
        localThread: TSThread,
        transaction: SDSAnyWriteTransaction
    ) -> Promise<DeviceMessage?> {
        let message = PniChangePhoneNumberSyncMessage(
            pniIdentityKeyPair: identityKeyPair,
            signedPreKey: signedPreKey,
            registrationId: registrationId,
            thread: localThread,
            transaction: transaction
        )

        let plaintextContent: Data? = message.buildPlainTextData(
            localThread,
            transaction: transaction
        )

        return firstly(on: schedulers.global()) { () throws -> DeviceMessage? in
            // Important to wrap this in asynchronity, since it might make
            // blocking network requests.
            let deviceMessage: DeviceMessage? = try self.messageSender.buildDeviceMessage(
                for: message,
                recipientAddress: recipientAddress,
                recipientAccountId: recipientAccountId,
                recipientDeviceId: NSNumber(value: recipientDeviceId),
                plaintextContent: plaintextContent,
                udSendingAccessProvider: nil // Sync messages do not use UD
            )

            return deviceMessage
        }
    }

    // MARK: - Saving the New Identity

    func finalizePniIdentity(
        withPendingState pendingState: ChangePhoneNumberPni.PendingState,
        localAddress: SignalServiceAddress,
        transaction v2Transaction: DBWriteTransaction
    ) {
        logger.info("Finalizing PNI identity.")

        let transaction: SDSAnyWriteTransaction = SDSDB.shimOnlyBridge(v2Transaction)

        // Store pending state in the right places

        identityManager.storeIdentityKeyPair(
            pendingState.pniIdentityKeyPair,
            for: .pni,
            transaction: transaction
        )

        let newSignedPreKeyRecord = pendingState.localDevicePniSignedPreKeyRecord
        pniProtocolStore.signedPreKeyStore.storeSignedPreKeyAsAcceptedAndCurrent(
            signedPreKeyId: newSignedPreKeyRecord.id,
            signedPreKeyRecord: newSignedPreKeyRecord,
            transaction: transaction
        )

        tsAccountManager.setPniRegistrationId(
            newRegistrationId: pendingState.localDevicePniRegistrationId,
            transaction: v2Transaction
        )

        // Followup tasks

        // Since we rotated the identity key, we need new one-time pre-keys.
        // However, no need to update the signed pre-key, which we also just
        // rotated.
        TSPreKeyManager.refreshOneTimePreKeys(
            forIdentity: .pni,
            alsoRefreshSignedPreKey: false
        )
    }
}

// MARK: - Shims

protocol _ChangePhoneNumberPniManager_TSAccountManagerShim {
    func setPniRegistrationId(
        newRegistrationId: UInt32,
        transaction: DBWriteTransaction
    )
}

class _ChangePhoneNumberPniManager_TSAccountManagerWrapper: _ChangePhoneNumberPniManager_TSAccountManagerShim {
    private let tsAccountManager: TSAccountManager

    init(tsAccountManager: TSAccountManager) {
        self.tsAccountManager = tsAccountManager
    }

    func setPniRegistrationId(
        newRegistrationId: UInt32,
        transaction: DBWriteTransaction
    ) {
        tsAccountManager.setPniRegistrationId(
            newRegistrationId: newRegistrationId,
            transaction: SDSDB.shimOnlyBridge(transaction)
        )
    }
}

extension ChangePhoneNumberPniManagerImpl {
    enum Shims {
        typealias TSAccountManager = _ChangePhoneNumberPniManager_TSAccountManagerShim
    }

    enum Wrappers {
        typealias TSAccountManager = _ChangePhoneNumberPniManager_TSAccountManagerWrapper
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
