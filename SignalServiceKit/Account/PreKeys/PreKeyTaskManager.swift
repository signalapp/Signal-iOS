//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

/// Used by ``PreKeyManagerImpl`` to actually execute prekey tasks.
/// Stateless! All state exists within each task function. The only instance vars are dependencies.
///
/// A PreKey task is broken down into the following steps:
/// 1. Fetch the identity key.  If this is a create operation, create the key, otherwise error if missing
/// 2. If registered and not a create operation, check that message processing is idle before continuing
/// 3. Check the server for the number of remaining PreKeys (skip on create/force refresh)
/// 4. Run any logic to determine what requested operations are really necessary
/// 5. Generate the necessary keys for the resulting operations
/// 6. Upload these new keys to the server (except for registration/provisioning)
/// 7. Store the new keys and run any cleanup logic
struct PreKeyTaskManager {
    private let logger = PrefixedLogger(prefix: "[PreKey]")

    private let apiClient: PreKeyTaskAPIClient
    private let dateProvider: DateProvider
    private let db: any DB
    private let identityKeyMismatchManager: IdentityKeyMismatchManager
    private let identityManager: OWSIdentityManager
    private let messageProcessor: MessageProcessor
    private let protocolStoreManager: SignalProtocolStoreManager
    private let remoteConfigProvider: any RemoteConfigProvider
    private let tsAccountManager: TSAccountManager

    init(
        apiClient: PreKeyTaskAPIClient,
        dateProvider: @escaping DateProvider,
        db: any DB,
        identityKeyMismatchManager: IdentityKeyMismatchManager,
        identityManager: OWSIdentityManager,
        messageProcessor: MessageProcessor,
        protocolStoreManager: SignalProtocolStoreManager,
        remoteConfigProvider: any RemoteConfigProvider,
        tsAccountManager: TSAccountManager,
    ) {
        self.apiClient = apiClient
        self.dateProvider = dateProvider
        self.db = db
        self.identityKeyMismatchManager = identityKeyMismatchManager
        self.identityManager = identityManager
        self.messageProcessor = messageProcessor
        self.protocolStoreManager = protocolStoreManager
        self.remoteConfigProvider = remoteConfigProvider
        self.tsAccountManager = tsAccountManager
    }

    enum Constants {
        // We generate 100 one-time prekeys at a time.
        // Replenish whenever 10 or less remain
        static let EphemeralPreKeysMinimumCount: UInt = 10

        static let PqPreKeysMinimumCount: UInt = 10

        // Signed prekeys should be rotated every at least every 2 days
        static let SignedPreKeyRotationTime: TimeInterval = 2 * .day

        static let LastResortPqPreKeyRotationTime: TimeInterval = 2 * .day
    }

    enum Error: Swift.Error {
        case noIdentityKey
        case notRegistered
        case cancelled
    }

    // MARK: - API

    // MARK: Registration/Provisioning

    /// When we register, we create a new identity key and other keys. So this variant:
    /// CAN create a new identity key (or uses any existing one)
    /// ALWAYS changes the targeted keys (regardless of current key state)
    func createForRegistration() async throws -> RegistrationPreKeyUploadBundles {
        logger.info("Create for registration")

        try Task.checkCancellation()
        let (aciBundle, pniBundle) = try await db.awaitableWrite { tx in
            let aciBundle = self.generateKeysForRegistration(identity: .aci, tx: tx)
            let pniBundle = self.generateKeysForRegistration(identity: .pni, tx: tx)
            try self.persistKeysPriorToUpload(bundle: aciBundle, tx: tx)
            try self.persistKeysPriorToUpload(bundle: pniBundle, tx: tx)
            return (aciBundle, pniBundle)
        }
        return .init(aci: aciBundle, pni: pniBundle)
    }

    /// When we provision, we use the primary's identity key to create other keys. So this variant:
    /// NEVER creates an identity key
    /// ALWAYS changes the targeted keys (regardless of current key state)
    func createForProvisioning(
        aciIdentityKeyPair: ECKeyPair,
        pniIdentityKeyPair: ECKeyPair,
    ) async throws -> RegistrationPreKeyUploadBundles {
        logger.info("Create for provisioning")

        try Task.checkCancellation()
        let (aciBundle, pniBundle) = try await db.awaitableWrite { tx in
            let aciBundle = self.generateKeysForProvisioning(
                identity: .aci,
                identityKeyPair: aciIdentityKeyPair,
                tx: tx,
            )
            let pniBundle = self.generateKeysForProvisioning(
                identity: .pni,
                identityKeyPair: pniIdentityKeyPair,
                tx: tx,
            )
            try self.persistKeysPriorToUpload(bundle: aciBundle, tx: tx)
            try self.persistKeysPriorToUpload(bundle: pniBundle, tx: tx)
            return (aciBundle, pniBundle)
        }
        return .init(aci: aciBundle, pni: pniBundle)
    }

    func persistAfterRegistration(
        bundles: RegistrationPreKeyUploadBundles,
        uploadDidSucceed: Bool,
    ) async throws {
        logger.info("Persist after provisioning")
        try Task.checkCancellation()
        try await db.awaitableWrite { tx in
            if uploadDidSucceed {
                try self.persistStateAfterUpload(bundle: bundles.aci, tx: tx)
                try self.persistStateAfterUpload(bundle: bundles.pni, tx: tx)
            } else {
                // Wipe the keys.
                self.wipeKeysAfterFailedRegistration(bundle: bundles.aci, tx: tx)
                self.wipeKeysAfterFailedRegistration(bundle: bundles.pni, tx: tx)
            }
        }
    }

    // MARK: Standard Operations

    /// When we create refresh keys (happens periodically) we should never change
    /// our identity key, but may rotate other keys depending on expiration. So this variant:
    /// CANNOT create a new identity key
    /// SOMETIMES changes the targeted keys (dependent on current key state)
    /// In other words, this variant can potentially no-op.
    func refresh(
        identity: OWSIdentity,
        targets: PreKeyTargets,
        force: Bool = false,
        auth: ChatServiceAuth,
    ) async throws {
        try Task.checkCancellation()
        try await waitForMessageProcessing(identity: identity)
        try Task.checkCancellation()

        let filteredTargets: PreKeyTargets
        if force {
            filteredTargets = targets
        } else {
            let ecCount: Int?
            let pqCount: Int?
            if targets.contains(target: .oneTimePreKey) || targets.contains(target: .oneTimePqPreKey) {
                (ecCount, pqCount) = try await self.apiClient.getAvailablePreKeys(for: identity)
            } else {
                // No need to fetch prekey counts.
                (ecCount, pqCount) = (nil, nil)
            }
            try Task.checkCancellation()

            filteredTargets = self.filterToNecessaryTargets(
                identity: identity,
                unfilteredTargets: targets,
                ecPreKeyRecordCount: ecCount,
                pqPreKeyRecordCount: pqCount,
            )
        }

        if filteredTargets.isEmpty {
            return
        }

        logger.info("[\(identity)] Refresh: [\(filteredTargets)]")
        let bundle = try await db.awaitableWrite { tx in
            let identityKeyPair = try self.requireIdentityKeyPair(for: identity, tx: tx)
            return try self.createAndPersistPartialBundle(
                identity: identity,
                identityKeyPair: identityKeyPair,
                targets: filteredTargets,
                tx: tx,
            )
        }

        try Task.checkCancellation()
        try await uploadAndPersistBundle(bundle, auth: auth)
    }

    func createOneTimePreKeys(
        identity: OWSIdentity,
        auth: ChatServiceAuth,
    ) async throws {
        logger.info("[\(identity)] Create one-time prekeys")
        try Task.checkCancellation()
        let bundle = try await db.awaitableWrite { tx in
            let identityKeyPair = try self.requireIdentityKeyPair(for: identity, tx: tx)
            return try self.createAndPersistPartialBundle(
                identity: identity,
                identityKeyPair: identityKeyPair,
                targets: [.oneTimePreKey, .oneTimePqPreKey],
                tx: tx,
            )
        }

        try Task.checkCancellation()
        try await uploadAndPersistBundle(bundle, auth: auth)
    }

    // MARK: - Private helpers

    // MARK: Per-identity registration generators

    private func generateKeysForRegistration(
        identity: OWSIdentity,
        tx: DBWriteTransaction,
    ) -> RegistrationPreKeyUploadBundle {
        return generateKeysForProvisioning(
            identity: identity,
            identityKeyPair: getOrCreateIdentityKeyPair(identity: identity, tx: tx),
            tx: tx,
        )
    }

    private func generateKeysForProvisioning(
        identity: OWSIdentity,
        identityKeyPair: ECKeyPair,
        tx: DBWriteTransaction,
    ) -> RegistrationPreKeyUploadBundle {
        let identityKey = identityKeyPair.keyPair.privateKey
        let protocolStore = self.protocolStoreManager.signalProtocolStore(for: identity)

        let signedPreKeyStore = protocolStore.signedPreKeyStore
        let signedPreKey = SignedPreKeyStoreImpl.generateSignedPreKey(
            keyId: signedPreKeyStore.allocatePreKeyId(tx: tx),
            signedBy: identityKey,
        )

        let kyberPreKeyStore = protocolStore.kyberPreKeyStore
        let lastResortPreKey = kyberPreKeyStore.generatePreKeyRecords(
            forPreKeyIds: kyberPreKeyStore.allocatePreKeyIds(count: 1, tx: tx),
            signedBy: identityKey,
        ).first!

        return RegistrationPreKeyUploadBundle(
            identity: identity,
            identityKeyPair: identityKeyPair,
            signedPreKey: signedPreKey,
            lastResortPreKey: lastResortPreKey,
        )
    }

    // MARK: Identity Key

    private func getOrCreateIdentityKeyPair(
        identity: OWSIdentity,
        tx: DBWriteTransaction,
    ) -> ECKeyPair {
        let existingKeyPair = identityManager.identityKeyPair(for: identity, tx: tx)
        if let identityKeyPair = existingKeyPair {
            return identityKeyPair
        }
        let identityKeyPair = identityManager.generateNewIdentityKeyPair()
        identityManager.setIdentityKeyPair(
            identityKeyPair,
            for: identity,
            tx: tx,
        )
        return identityKeyPair
    }

    func requireIdentityKeyPair(
        for identity: OWSIdentity,
        tx: DBReadTransaction,
    ) throws -> ECKeyPair {
        guard let identityKey = identityManager.identityKeyPair(for: identity, tx: tx) else {
            logger.warn("cannot perform operation for \(identity); missing identity key")
            throw Error.noIdentityKey
        }
        return identityKey
    }

    // MARK: Bundle construction

    private func createAndPersistPartialBundle(
        identity: OWSIdentity,
        identityKeyPair: ECKeyPair,
        targets: PreKeyTargets,
        tx: DBWriteTransaction,
    ) throws -> PartialPreKeyUploadBundle {
        let protocolStore = self.protocolStoreManager.signalProtocolStore(
            for: identity,
        )

        // Map the keys to the requested operation.  Create the necessary keys and
        // pass them along to be uploaded to the service/stored/accepted
        var signedPreKey: LibSignalClient.SignedPreKeyRecord?
        var preKeyRecords: [LibSignalClient.PreKeyRecord]?
        var lastResortPreKey: LibSignalClient.KyberPreKeyRecord?
        var pqPreKeyRecords: [LibSignalClient.KyberPreKeyRecord]?

        let identityKey = identityKeyPair.keyPair.privateKey

        targets.targets.forEach { target in
            switch target {
            case .oneTimePreKey:
                let preKeyIds = protocolStore.preKeyStore.allocatePreKeyIds(tx: tx)
                preKeyRecords = PreKeyStoreImpl.generatePreKeyRecords(forPreKeyIds: preKeyIds)
            case .signedPreKey:
                let preKeyId = protocolStore.signedPreKeyStore.allocatePreKeyId(tx: tx)
                signedPreKey = SignedPreKeyStoreImpl.generateSignedPreKey(keyId: preKeyId, signedBy: identityKey)
            case .oneTimePqPreKey:
                let preKeyIds = protocolStore.kyberPreKeyStore.allocatePreKeyIds(count: 100, tx: tx)
                pqPreKeyRecords = protocolStore.kyberPreKeyStore.generatePreKeyRecords(forPreKeyIds: preKeyIds, signedBy: identityKey)
            case .lastResortPqPreKey:
                let preKeyIds = protocolStore.kyberPreKeyStore.allocatePreKeyIds(count: 1, tx: tx)
                lastResortPreKey = protocolStore.kyberPreKeyStore.generatePreKeyRecords(forPreKeyIds: preKeyIds, signedBy: identityKey).first!
            }
        }
        let result = PartialPreKeyUploadBundle(
            identity: identity,
            signedPreKey: signedPreKey,
            preKeyRecords: preKeyRecords,
            lastResortPreKey: lastResortPreKey,
            pqPreKeyRecords: pqPreKeyRecords,
        )
        try persistKeysPriorToUpload(bundle: result, tx: tx)
        return result
    }

    // MARK: Filtering (based on fetched prekey results)

    private func filterToNecessaryTargets(
        identity: OWSIdentity,
        unfilteredTargets: PreKeyTargets,
        ecPreKeyRecordCount: Int?,
        pqPreKeyRecordCount: Int?,
    ) -> PreKeyTargets {
        let protocolStore = self.protocolStoreManager.signalProtocolStore(for: identity)
        let (lastSuccessfulRotation, lastKyberSuccessfulRotation) = db.read { tx in
            let lastSuccessfulRotation = protocolStore.signedPreKeyStore.getLastSuccessfulRotationDate(tx: tx)
            let lastKyberSuccessfulRotation = protocolStore.kyberPreKeyStore.getLastSuccessfulRotationDate(tx: tx)
            return (lastSuccessfulRotation, lastKyberSuccessfulRotation)
        }

        // Take the gathered PreKeyState information and run it through
        // logic to determine what really needs to be updated.
        return unfilteredTargets.targets.reduce(into: []) { value, target in
            switch target {
            case .oneTimePreKey:
                guard let ecPreKeyRecordCount else {
                    logger.warn("Did not fetch prekey count, aborting.")
                    return
                }
                if ecPreKeyRecordCount < Constants.EphemeralPreKeysMinimumCount {
                    value.insert(target: target)
                }
            case .oneTimePqPreKey:
                guard let pqPreKeyRecordCount else {
                    logger.warn("Did not fetch pq prekey count, aborting.")
                    return
                }
                if pqPreKeyRecordCount < Constants.PqPreKeysMinimumCount {
                    value.insert(target: target)
                }
            case .signedPreKey:
                if
                    let lastSuccessfulRotation,
                    dateProvider().timeIntervalSince(lastSuccessfulRotation) < Constants.SignedPreKeyRotationTime
                {
                    // it's recent enough
                } else {
                    value.insert(target: target)
                }
            case .lastResortPqPreKey:
                if
                    let lastKyberSuccessfulRotation,
                    dateProvider().timeIntervalSince(lastKyberSuccessfulRotation) < Constants.LastResortPqPreKeyRotationTime
                {
                    // it's recent enough
                } else {
                    value.insert(target: target)
                }
            }
        }
    }

    // MARK: Message Processing

    /// Waits (potentially forever) for message processing. Supports cancellation.
    private func waitForMessageProcessing(identity: OWSIdentity) async throws(CancellationError) {
        switch identity {
        case .aci:
            // We can't change our ACI via a message, so there's no need to wait.
            return
        case .pni:
            // Our PNI might change via a change number message, so wait.
            break
        }

        try await messageProcessor.waitForFetchingAndProcessing()
    }

    // MARK: Persist

    private func persistKeysPriorToUpload(
        bundle: PreKeyUploadBundle,
        tx: DBWriteTransaction,
    ) throws {
        let protocolStore = protocolStoreManager.signalProtocolStore(for: bundle.identity)
        if let signedPreKeyRecord = bundle.getSignedPreKey() {
            protocolStore.signedPreKeyStore.storeSignedPreKey(signedPreKeyRecord, tx: tx)
        }
        if let lastResortPreKey = bundle.getLastResortPreKey() {
            protocolStore.kyberPreKeyStore.storePreKeyRecords([lastResortPreKey], isLastResort: true, tx: tx)
        }
        if let newPreKeyRecords = bundle.getPreKeyRecords() {
            protocolStore.preKeyStore.storePreKeyRecords(newPreKeyRecords, tx: tx)
        }
        if let pqPreKeyRecords = bundle.getPqPreKeyRecords() {
            protocolStore.kyberPreKeyStore.storePreKeyRecords(pqPreKeyRecords, isLastResort: false, tx: tx)
        }
    }

    private func persistStateAfterUpload(
        bundle: PreKeyUploadBundle,
        tx: DBWriteTransaction,
    ) throws {
        let protocolStore = protocolStoreManager.signalProtocolStore(for: bundle.identity)

        if let signedPreKeyRecord = bundle.getSignedPreKey() {
            protocolStore.signedPreKeyStore.setLastSuccessfulRotationDate(self.dateProvider(), tx: tx)
            protocolStore.signedPreKeyStore.setReplacedAtToNowIfNil(exceptFor: signedPreKeyRecord.id, tx: tx)
        }

        if let lastResortPreKey = bundle.getLastResortPreKey() {
            // Register a successful key rotation
            protocolStore.kyberPreKeyStore.setLastSuccessfulRotationDate(self.dateProvider(), tx: tx)
            protocolStore.kyberPreKeyStore.setReplacedAtToNowIfNil(exceptFor: [lastResortPreKey.id], isLastResort: true, tx: tx)
        }

        if let preKeyRecords = bundle.getPreKeyRecords() {
            protocolStore.preKeyStore.setReplacedAtToNowIfNil(exceptFor: preKeyRecords.map(\.id), tx: tx)
        }

        if let oneTimePreKeys = bundle.getPqPreKeyRecords() {
            protocolStore.kyberPreKeyStore.setReplacedAtToNowIfNil(exceptFor: oneTimePreKeys.map(\.id), isLastResort: false, tx: tx)
        }

        protocolStoreManager.preKeyStore.cullPreKeys(gracePeriod: gracePeriodBeforeMessageProcessing(), tx: tx)
    }

    /// The "grace period" to use when culling pre keys before we've finished
    /// processing messages. After we rotate pre keys, there might still be
    /// not-yet-received messages that we're about to receive that reference
    /// obsolete pre keys. We defer culling pre keys in this "grace period"
    /// until `cullStateAfterMessageProcessing` (which is typically called in
    /// quick succession but may take longer in pathological cases).
    private func gracePeriodBeforeMessageProcessing() -> TimeInterval {
        let messageQueueTime = remoteConfigProvider.currentConfig().messageQueueTime
        owsAssertDebug(.day <= messageQueueTime && messageQueueTime <= 90 * .day)
        return messageQueueTime.clamp(.day, 90 * .day)
    }

    /// Called after we've finished processing messages to cull any pre keys in
    /// the "grace period".
    private func cullStateAfterMessageProcessing(tx: DBWriteTransaction) {
        protocolStoreManager.preKeyStore.cullPreKeys(gracePeriod: 0, tx: tx)
    }

    private func wipeKeysAfterFailedRegistration(
        bundle: RegistrationPreKeyUploadBundle,
        tx: DBWriteTransaction,
    ) {
        let preKeyStore = protocolStoreManager.preKeyStore.forIdentity(bundle.identity)
        preKeyStore.removePreKey(in: .signed, keyId: bundle.signedPreKey.id, tx: tx)
        preKeyStore.removePreKey(in: .kyber, keyId: bundle.lastResortPreKey.id, tx: tx)
    }

    // MARK: Upload

    private func uploadAndPersistBundle(
        _ bundle: PreKeyUploadBundle,
        auth: ChatServiceAuth,
    ) async throws {
        let identity = bundle.identity
        let uploadResult = await upload(bundle: bundle, auth: auth)

        switch uploadResult {
        case .skipped:
            break
        case .success:
            logger.info("[\(identity)] Successfully uploaded prekeys")
            try await db.awaitableWrite { tx in
                try self.persistStateAfterUpload(bundle: bundle, tx: tx)
            }
            Task {
                try await self.messageProcessor.waitForFetchingAndProcessing()
                await self.db.awaitableWrite { tx in self.cullStateAfterMessageProcessing(tx: tx) }
            }
        case let .failure(error) where error.httpStatusCode == 422:
            // We think we might have an incorrect identity key -- check it and
            // deregister if it's wrong.
            await self.identityKeyMismatchManager.validateIdentityKey(for: identity)
            fallthrough
        case let .failure(error):
            logger.info("[\(identity)] Failed to upload prekeys")
            throw error
        }
    }

    private enum UploadResult {
        case success
        case skipped
        case failure(Swift.Error)
    }

    private func upload(
        bundle: PreKeyUploadBundle,
        auth: ChatServiceAuth,
    ) async -> UploadResult {
        // If there is nothing to update, skip this step.
        guard !bundle.isEmpty() else { return .skipped }

        logger.info("[\(bundle.identity)] uploading prekeys")

        do {
            try await self.apiClient.registerPreKeys(
                for: bundle.identity,
                signedPreKeyRecord: bundle.getSignedPreKey(),
                preKeyRecords: bundle.getPreKeyRecords(),
                pqLastResortPreKeyRecord: bundle.getLastResortPreKey(),
                pqPreKeyRecords: bundle.getPqPreKeyRecords(),
                auth: auth,
            )
            return .success
        } catch let error {
            return .failure(error)
        }
    }
}
