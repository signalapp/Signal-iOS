//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import LibSignalClient

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
        localAci: Aci,
        localDeviceId: DeviceId,
    ) async -> ChangePhoneNumberPni.GeneratePniIdentityResult

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
    public struct PendingState {
        public let newE164: E164
        public let pniIdentityKeyPair: ECKeyPair
        public let localDevicePniSignedPreKeyRecord: SignalServiceKit.SignedPreKeyRecord
        // TODO (PQXDH): 8/14/2023 - This should me made non-optional after 90 days
        public let localDevicePniPqLastResortPreKeyRecord: KyberPreKeyRecord?
        public let localDevicePniRegistrationId: UInt32

        public init(
            newE164: E164,
            pniIdentityKeyPair: ECKeyPair,
            localDevicePniSignedPreKeyRecord: SignalServiceKit.SignedPreKeyRecord,
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

final class ChangePhoneNumberPniManagerImpl: ChangePhoneNumberPniManager {

    // MARK: - Init

    private let logger: PrefixedLogger = .init(prefix: "[CNPNI]")

    private let db: any DB
    private let identityManager: Shims.IdentityManager
    private let pniDistributionParameterBuilder: PniDistributionParamaterBuilder
    private let pniSignedPreKeyStore: SignedPreKeyStoreImpl
    private let pniKyberPreKeyStore: KyberPreKeyStoreImpl
    private let preKeyManager: Shims.PreKeyManager
    private let registrationIdGenerator: RegistrationIdGenerator
    private let tsAccountManager: TSAccountManager

    init(
        db: any DB,
        identityManager: Shims.IdentityManager,
        pniDistributionParameterBuilder: PniDistributionParamaterBuilder,
        pniSignedPreKeyStore: SignedPreKeyStoreImpl,
        pniKyberPreKeyStore: KyberPreKeyStoreImpl,
        preKeyManager: Shims.PreKeyManager,
        registrationIdGenerator: RegistrationIdGenerator,
        tsAccountManager: TSAccountManager
    ) {
        self.db = db
        self.identityManager = identityManager
        self.pniDistributionParameterBuilder = pniDistributionParameterBuilder
        self.pniSignedPreKeyStore = pniSignedPreKeyStore
        self.pniKyberPreKeyStore = pniKyberPreKeyStore
        self.preKeyManager = preKeyManager
        self.registrationIdGenerator = registrationIdGenerator
        self.tsAccountManager = tsAccountManager
    }

    // MARK: - Generating the New Identity

    func generatePniIdentity(
        forNewE164 newE164: E164,
        localAci: Aci,
        localDeviceId: DeviceId,
    ) async -> ChangePhoneNumberPni.GeneratePniIdentityResult {
        logger.info("Generating PNI identity!")

        let pniIdentityKeyPair = identityManager.generateNewIdentityKeyPair()

        let localDevicePniPqLastResortPreKeyRecord = await db.awaitableWrite { tx in
            pniKyberPreKeyStore.generateLastResortKyberPreKey(signedBy: pniIdentityKeyPair, tx: tx)
        }

        let pendingState = ChangePhoneNumberPni.PendingState(
            newE164: newE164,
            pniIdentityKeyPair: pniIdentityKeyPair,
            localDevicePniSignedPreKeyRecord: SignedPreKeyStoreImpl.generateSignedPreKey(signedBy: pniIdentityKeyPair),
            localDevicePniPqLastResortPreKeyRecord: localDevicePniPqLastResortPreKeyRecord,
            localDevicePniRegistrationId: registrationIdGenerator.generate()
        )

        do {
            let parameters = try await self.pniDistributionParameterBuilder.buildPniDistributionParameters(
                localAci: localAci,
                localDeviceId: .valid(localDeviceId),
                localPniIdentityKeyPair: pniIdentityKeyPair,
                localE164: newE164,
                localDevicePniSignedPreKey: pendingState.localDevicePniSignedPreKeyRecord,
                localDevicePniPqLastResortPreKey: localDevicePniPqLastResortPreKeyRecord,
                localDevicePniRegistrationId: pendingState.localDevicePniRegistrationId
            )
            return .success(parameters: parameters, pendingState: pendingState)
        } catch {
            return .failure
        }
    }

    // MARK: - Saving the New Identity

    func finalizePniIdentity(
        withPendingState pendingState: ChangePhoneNumberPni.PendingState,
        transaction: DBWriteTransaction
    ) throws {
        logger.info("Finalizing PNI identity.")

        // Store pending state in the right places

        identityManager.setIdentityKeyPair(
            pendingState.pniIdentityKeyPair,
            for: .pni,
            tx: transaction
        )

        if let newPqLastResortPreKeyRecord = pendingState.localDevicePniPqLastResortPreKeyRecord {
            try pniKyberPreKeyStore.storeLastResortPreKey(
                record: newPqLastResortPreKeyRecord,
                tx: transaction
            )
        }

        let newSignedPreKeyRecord = pendingState.localDevicePniSignedPreKeyRecord
        pniSignedPreKeyStore.storeSignedPreKey(
            newSignedPreKeyRecord.id,
            signedPreKeyRecord: newSignedPreKeyRecord,
            tx: transaction
        )

        tsAccountManager.setRegistrationId(
            pendingState.localDevicePniRegistrationId,
            for: .pni,
            tx: transaction
        )

        // Followup tasks

        transaction.addSyncCompletion { [preKeyManager] in
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
