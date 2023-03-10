//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Curve25519Kit
import Foundation

// MARK: - ChangeNumberPniManager protocol

public protocol ChangeNumberPniManager {
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
    /// caller must call ``checkServicePniIdentityMatches`` and take further
    /// action per that method's documentation.
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
    ) -> Guarantee<ChangeNumberPni.GeneratePniIdentityResult>

    /// Checks whether the identity committed to the service matches pending
    /// state from a previous change-number request.
    ///
    /// If a change-number request is interrupted, the server may have
    /// committed the identity change without the caller being aware of the
    /// outcome. In this scenario, the caller should use this method to check
    /// the current identity committed on the service, using pending state from
    /// a prior call to ``generatePniIdentity``.
    ///
    /// If the identity on the service matches the local identity, then the
    /// pending state is obsolete and should be discarded. If it matches the
    /// identity in the pending state, the caller should immediately call
    /// ``finalizePendingState`` with the pending state to update the local
    /// identity. If neither matches...we're in trouble (and should force a
    /// re-registration?).
    ///
    /// - Parameter pendingState
    /// Pending state the caller believes may match the identity committed on
    /// the service.
    /// - Returns
    /// The result of attempting to match the identity on the service.
    func checkServicePniIdentityMatches(
        pendingState: ChangeNumberPni.PendingState,
        localE164: E164
    ) -> Guarantee<ChangeNumberPni.CheckServiceIdentityResult>

    /// Commits an identity generated for a change number request.
    ///
    /// This method should be called after the caller has confirmed that the
    /// server has committed a new PNI identity, with the state from a prior
    /// call to ``generatePniIdentity``.
    func finalizePniIdentity(
        withPendingState pendingState: ChangeNumberPni.PendingState,
        localAddress: SignalServiceAddress,
        transaction: DBWriteTransaction
    )
}

// MARK: - Change-Number PNI types

/// Namespace for change-number PNI types.
public enum ChangeNumberPni {

    /// PNI-related parameters for a change-number request.
    public struct Parameters {
        private let pniIdentityKey: Data
        private var devicePniSignedPreKeys: [UInt32: SignedPreKeyRecord] = [:]
        private var pniRegistrationIds: [UInt32: UInt32] = [:]
        private var deviceMessages: [DeviceMessage] = []

        fileprivate init(pniIdentityKey: Data) {
            self.pniIdentityKey = pniIdentityKey
        }

        fileprivate mutating func addLocalDevice(
            localDeviceId: UInt32,
            signedPreKey: SignedPreKeyRecord,
            registrationId: UInt32
        ) {
            devicePniSignedPreKeys[localDeviceId] = signedPreKey
            pniRegistrationIds[localDeviceId] = registrationId
        }

        fileprivate mutating func addLinkedDevice(
            deviceId: UInt32,
            signedPreKey: SignedPreKeyRecord,
            registrationId: UInt32,
            deviceMessage: DeviceMessage
        ) {
            owsAssert(deviceId == deviceMessage.destinationDeviceId)
            owsAssert(registrationId == deviceMessage.destinationRegistrationId)

            devicePniSignedPreKeys[deviceId] = signedPreKey
            pniRegistrationIds[deviceId] = registrationId
            deviceMessages.append(deviceMessage)
        }

        func requestParameters() -> [String: Any] {
            [
                "pniIdentityKey": pniIdentityKey.prependKeyType().base64EncodedString(),
                "devicePniSignedPreKeys": devicePniSignedPreKeys.mapValues { OWSRequestFactory.signedPreKeyRequestParameters($0) },
                "deviceMessages": deviceMessages.map { $0.requestParameters() },
                "pniRegistrationIds": pniRegistrationIds
            ]
        }
    }

    /// Represents a change-number operation that has not yet been finalized.
    public struct PendingState {
        fileprivate let newE164: E164
        fileprivate let pniIdentityKeyPair: ECKeyPair
        fileprivate let localDevicePniSignedPreKeyRecord: SignedPreKeyRecord
        fileprivate let localDevicePniRegistrationId: UInt32
    }

    public enum GeneratePniIdentityResult {
        /// Successful generation of PNI change-number parameters and state.
        case success(parameters: Parameters, pendingState: PendingState)

        /// An error occurred. Automatic recovery or retry is not recommended.
        case failure(underlyingError: Error)
    }

    /// The result of checking the identity committed on the service.
    public enum CheckServiceIdentityResult {
        public enum MatchResult {
            /// The service identity matches the local identity.
            case matchesLocalIdentity
            /// The service identity matches pending identity state.
            case matchesPendingState
            /// The service identity did not match any known identity.
            case matchUnknown
        }

        /// A match was successfully computed.
        case match(matchResult: MatchResult)
        /// A network error occurred. Retry may succeed.
        case networkError(underlyingError: Error)
        /// An unexpected error occurred. Retry is unlikely to succeed.
        case assertionError(underlyingError: Error)
    }
}

// MARK: - ChangeNumberPniManagerImpl implementation

class ChangeNumberPniManagerImpl: ChangeNumberPniManager {

    // MARK: - Init

    private let logger: PrefixedLogger = .init(prefix: "[CNPNI]")

    private let accountServiceClient: AccountServiceClient
    private let identityManager: OWSIdentityManager
    private let messageSender: MessageSender
    private let networkManager: NetworkManager
    private let pniProtocolStore: SignalProtocolStore
    private let schedulers: Schedulers
    private let tsAccountManager: Shims.TSAccountManager

    init(
        accountServiceClient: AccountServiceClient,
        identityManager: OWSIdentityManager,
        messageSender: MessageSender,
        networkManager: NetworkManager,
        pniProtocolStore: SignalProtocolStore,
        schedulers: Schedulers,
        tsAccountManager: Shims.TSAccountManager
    ) {
        self.accountServiceClient = accountServiceClient
        self.identityManager = identityManager
        self.messageSender = messageSender
        self.networkManager = networkManager
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
    ) -> Guarantee<ChangeNumberPni.GeneratePniIdentityResult> {
        logger.info("Generating PNI identity!")

        let transaction: SDSAnyWriteTransaction = SDSDB.shimOnlyBridge(transaction)

        let recipientParams: MyselfAsRecipientParams
        do {
            recipientParams = try loadRecipientParams(
                localAddress: localAddress,
                localDeviceId: localDeviceId,
                transaction: transaction
            )
        } catch let error {
            logger.error("Failed to load recipient params.")
            return .value(.failure(underlyingError: error))
        }

        let pniIdentityKeyPair = identityManager.generateNewIdentityKeyPair()

        let pendingState = ChangeNumberPni.PendingState(
            newE164: newE164,
            pniIdentityKeyPair: pniIdentityKeyPair,
            localDevicePniSignedPreKeyRecord: SSKSignedPreKeyStore.generateSignedPreKey(signedBy: pniIdentityKeyPair),
            localDevicePniRegistrationId: TSAccountManager.generateRegistrationId()
        )

        var pniParameters = ChangeNumberPni.Parameters(pniIdentityKey: pniIdentityKeyPair.publicKey)

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
        ).map(on: schedulers.global()) { (linkedDeviceParamResults: [Result<LinkedDeviceParams?, Error>]) -> ChangeNumberPni.GeneratePniIdentityResult in
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
                case .failure(let error):
                    // If we have any errors, return the first we hit.
                    return .failure(underlyingError: error)
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
        guard let localRecipient = SignalRecipient.get(address: localAddress, mustHaveDevices: false, transaction: transaction) else {
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
            let deviceMessage: DeviceMessage? = try self.messageSender.buildDeviceMessage(
                for: message,
                recipientAddress: recipientAddress,
                recipientAccountId: recipientAccountId,
                recipientDeviceId: NSNumber(value: recipientDeviceId),
                plaintextContent: plaintextContent,
                udSendingAccessProvider: nil // Sync messages do not use UD
            )

            // Important to wrap this in asynchronity, since it might make
            // blocking network requests.
            return deviceMessage
        }
    }

    // MARK: - Check the service identity

    func checkServicePniIdentityMatches(
        pendingState: ChangeNumberPni.PendingState,
        localE164: E164
    ) -> Guarantee<ChangeNumberPni.CheckServiceIdentityResult> {
        let logger = logger

        logger.info("Checking service PNI identity.")

        return firstly { () -> Promise<WhoAmIRequestFactory.Responses.WhoAmI> in
            accountServiceClient.getAccountWhoAmI()
        }.map(on: schedulers.global()) { whoami -> ChangeNumberPni.CheckServiceIdentityResult in
            guard let whoamiE164 = E164(whoami.e164) else {
                return .assertionError(underlyingError: OWSAssertionError("whoami response contained invalid e164 string!"))
            }

            let matchResult: ChangeNumberPni.CheckServiceIdentityResult.MatchResult = {
                switch whoamiE164 {
                case localE164:
                    return .matchesLocalIdentity
                case pendingState.newE164:
                    return .matchesPendingState
                default:
                    return .matchUnknown
                }
            }()

            logger.info("Service identity matched: \(matchResult).")
            return .match(matchResult: matchResult)
        }.recover(on: schedulers.global()) { error -> Guarantee<ChangeNumberPni.CheckServiceIdentityResult> in
            if error.isNetworkFailureOrTimeout {
                return .value(.networkError(underlyingError: error))
            }

            return .value(.assertionError(underlyingError: error))
        }
    }

    // MARK: - Saving the New Identity

    func finalizePniIdentity(
        withPendingState pendingState: ChangeNumberPni.PendingState,
        localAddress: SignalServiceAddress,
        transaction v2Transaction: DBWriteTransaction
    ) {
        logger.info("Finalizing PNI identity.")

        let transaction: SDSAnyWriteTransaction = SDSDB.shimOnlyBridge(v2Transaction)

        // Store the identity key.
        identityManager.storeIdentityKeyPair(
            pendingState.pniIdentityKeyPair,
            for: .pni,
            transaction: transaction
        )

        // Store the signed pre-key, and kick off a pre-key upload.
        let newSignedPreKeyRecord = pendingState.localDevicePniSignedPreKeyRecord

        pniProtocolStore.signedPreKeyStore.storeSignedPreKeyAsAcceptedAndCurrent(
            signedPreKeyId: newSignedPreKeyRecord.id,
            signedPreKeyRecord: newSignedPreKeyRecord,
            transaction: transaction
        )

        TSPreKeyManager.refreshOneTimePreKeys(
            forIdentity: .pni,
            alsoRefreshSignedPreKey: false
        )

        // Save the registration ID.
        tsAccountManager.setPniRegistrationId(
            newRegistrationId: pendingState.localDevicePniRegistrationId,
            transaction: v2Transaction
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

extension ChangeNumberPniManagerImpl {
    enum Shims {
        typealias TSAccountManager = _ChangePhoneNumberPniManager_TSAccountManagerShim
    }

    enum Wrappers {
        typealias TSAccountManager = _ChangePhoneNumberPniManager_TSAccountManagerWrapper
    }
}
