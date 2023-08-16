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
        localAci: UntypedServiceId,
        localAccountId: String,
        localDeviceId: UInt32,
        localUserAllDeviceIds: [UInt32]
    ) -> Guarantee<ChangePhoneNumberPni.GeneratePniIdentityResult>

    /// Commits an identity generated for a change number request.
    ///
    /// This method should be called after the caller has confirmed that the
    /// server has committed a new PNI identity, with the state from a prior
    /// call to ``generatePniIdentity``.
    func finalizePniIdentity(
        withPendingState pendingState: ChangePhoneNumberPni.PendingState,
        transaction: DBWriteTransaction
    ) throws
}

// MARK: - Change-Number PNI types

/// Namespace for change-number PNI types.
public enum ChangePhoneNumberPni {

    /// Represents a change-number operation that has not yet been finalized.
    public struct PendingState: Equatable {
        public let newE164: E164
        public let pniIdentityKeyPair: ECKeyPair
        public let localDevicePniSignedPreKeyRecord: SignedPreKeyRecord
        // TODO (PQXDH): 8/14/2023 - This should me made non-optional after 90 days
        public let localDevicePniPqLastResortPreKeyRecord: KyberPreKeyRecord?
        public let localDevicePniRegistrationId: UInt32

        public init(
            newE164: E164,
            pniIdentityKeyPair: ECKeyPair,
            localDevicePniSignedPreKeyRecord: SignedPreKeyRecord,
            localDevicePniPqLastResortPreKeyRecord: KyberPreKeyRecord?,
            localDevicePniRegistrationId: UInt32
        ) {
            self.newE164 = newE164
            self.pniIdentityKeyPair = pniIdentityKeyPair
            self.localDevicePniSignedPreKeyRecord = localDevicePniSignedPreKeyRecord
            self.localDevicePniPqLastResortPreKeyRecord = localDevicePniPqLastResortPreKeyRecord
            self.localDevicePniRegistrationId = localDevicePniRegistrationId
        }
    }

    public enum GeneratePniIdentityResult {
        /// Successful generation of PNI change-number parameters and state.
        case success(parameters: PniDistribution.Parameters, pendingState: PendingState)

        /// An error occurred.
        case failure
    }
}

// MARK: - ChangeNumberPniManagerImpl implementation

class ChangePhoneNumberPniManagerImpl: ChangePhoneNumberPniManager {

    // MARK: - Init

    private let logger: PrefixedLogger = .init(prefix: "[CNPNI]")

    private let schedulers: Schedulers
    private let pniDistributionParameterBuilder: PniDistributionParamaterBuilder

    private let identityManager: Shims.IdentityManager
    private let preKeyManager: Shims.PreKeyManager
    private let pniSignedPreKeyStore: SignalSignedPreKeyStore
    private let pniKyberPreKeyStore: SignalKyberPreKeyStore
    private let tsAccountManager: Shims.TSAccountManager

    init(
        schedulers: Schedulers,
        pniDistributionParameterBuilder: PniDistributionParamaterBuilder,
        identityManager: Shims.IdentityManager,
        preKeyManager: Shims.PreKeyManager,
        pniSignedPreKeyStore: SignalSignedPreKeyStore,
        pniKyberPreKeyStore: SignalKyberPreKeyStore,
        tsAccountManager: Shims.TSAccountManager
    ) {
        self.schedulers = schedulers
        self.pniDistributionParameterBuilder = pniDistributionParameterBuilder

        self.identityManager = identityManager
        self.preKeyManager = preKeyManager
        self.pniSignedPreKeyStore = pniSignedPreKeyStore
        self.pniKyberPreKeyStore = pniKyberPreKeyStore
        self.tsAccountManager = tsAccountManager
    }

    // MARK: - Generating the New Identity

    func generatePniIdentity(
        forNewE164 newE164: E164,
        localAci: UntypedServiceId,
        localAccountId: String,
        localDeviceId: UInt32,
        localUserAllDeviceIds: [UInt32]
    ) -> Guarantee<ChangePhoneNumberPni.GeneratePniIdentityResult> {
        logger.info("Generating PNI identity!")

        let pniIdentityKeyPair = identityManager.generateNewIdentityKeyPair()

        let localDevicePniPqLastResortPreKeyRecord = try? pniKyberPreKeyStore.generateEphemeralLastResortKyberPreKey(signedBy: pniIdentityKeyPair)
        guard let localDevicePniPqLastResortPreKeyRecord else {
            return Guarantee.value(.failure)
        }

        let pendingState = ChangePhoneNumberPni.PendingState(
            newE164: newE164,
            pniIdentityKeyPair: pniIdentityKeyPair,
            localDevicePniSignedPreKeyRecord: pniSignedPreKeyStore.generateSignedPreKey(signedBy: pniIdentityKeyPair),
            localDevicePniPqLastResortPreKeyRecord: localDevicePniPqLastResortPreKeyRecord,
            localDevicePniRegistrationId: tsAccountManager.generateRegistrationId()
        )

        return firstly(on: schedulers.sync) { () -> Guarantee<PniDistribution.ParameterGenerationResult> in
            self.pniDistributionParameterBuilder.buildPniDistributionParameters(
                localAci: localAci,
                localAccountId: localAccountId,
                localDeviceId: localDeviceId,
                localUserAllDeviceIds: localUserAllDeviceIds,
                localPniIdentityKeyPair: pniIdentityKeyPair,
                localE164: newE164,
                localDevicePniSignedPreKey: pendingState.localDevicePniSignedPreKeyRecord,
                localDevicePniPqLastResortPreKey: localDevicePniPqLastResortPreKeyRecord,
                localDevicePniRegistrationId: pendingState.localDevicePniRegistrationId
            )
        }.map(on: schedulers.sync) { paramGenerationResult in
            switch paramGenerationResult {
            case .success(let parameters):
                return .success(parameters: parameters, pendingState: pendingState)
            case .failure:
                return .failure
            }
        }
    }

    // MARK: - Saving the New Identity

    func finalizePniIdentity(
        withPendingState pendingState: ChangePhoneNumberPni.PendingState,
        transaction: DBWriteTransaction
    ) throws {
        logger.info("Finalizing PNI identity.")

        // Store pending state in the right places

        identityManager.storeIdentityKeyPair(
            pendingState.pniIdentityKeyPair,
            for: .pni,
            transaction: transaction
        )

        if let newPqLastResortPreKeyRecord = pendingState.localDevicePniPqLastResortPreKeyRecord {
            try pniKyberPreKeyStore.storeLastResortPreKeyAndMarkAsCurrent(
                record: newPqLastResortPreKeyRecord,
                tx: transaction
            )
        }

        let newSignedPreKeyRecord = pendingState.localDevicePniSignedPreKeyRecord
        pniSignedPreKeyStore.storeSignedPreKeyAsAcceptedAndCurrent(
            signedPreKeyId: newSignedPreKeyRecord.id,
            signedPreKeyRecord: newSignedPreKeyRecord,
            tx: transaction
        )

        tsAccountManager.setPniRegistrationId(
            newRegistrationId: pendingState.localDevicePniRegistrationId,
            transaction: transaction
        )

        // Followup tasks

        transaction.addAsyncCompletion(on: schedulers.main) { [preKeyManager] in
            // Since we rotated the identity key, we need new one-time pre-keys.
            // However, no need to update the signed pre-key, which we also just
            // rotated.
            preKeyManager.refreshOneTimePreKeys(
                forIdentity: .pni,
                alsoRefreshSignedPreKey: false
            )
        }
    }
}
