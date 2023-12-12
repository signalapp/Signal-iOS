//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit

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
internal struct PreKeyTaskManager {
    private let dateProvider: DateProvider
    private let db: DB
    private let identityManager: PreKey.Shims.IdentityManager
    private let linkedDevicePniKeyManager: LinkedDevicePniKeyManager
    private let messageProcessor: PreKey.Shims.MessageProcessor
    private let protocolStoreManager: SignalProtocolStoreManager
    private let serviceClient: AccountServiceClient
    private let tsAccountManager: TSAccountManager

    init(
        dateProvider: @escaping DateProvider,
        db: DB,
        identityManager: PreKey.Shims.IdentityManager,
        linkedDevicePniKeyManager: LinkedDevicePniKeyManager,
        messageProcessor: PreKey.Shims.MessageProcessor,
        protocolStoreManager: SignalProtocolStoreManager,
        serviceClient: AccountServiceClient,
        tsAccountManager: TSAccountManager
    ) {
        self.dateProvider = dateProvider
        self.db = db
        self.identityManager = identityManager
        self.linkedDevicePniKeyManager = linkedDevicePniKeyManager
        self.messageProcessor = messageProcessor
        self.protocolStoreManager = protocolStoreManager
        self.serviceClient = serviceClient
        self.tsAccountManager = tsAccountManager
    }

    enum Constants {
        // We generate 100 one-time prekeys at a time.
        // Replenish whenever 10 or less remain
        internal static let EphemeralPreKeysMinimumCount: UInt = 10

        internal static let PqPreKeysMinimumCount: UInt = 10

        // Signed prekeys should be rotated every at least every 2 days
        internal static let SignedPreKeyRotationTime: TimeInterval = 2 * kDayInterval

        internal static let LastResortPqPreKeyRotationTime: TimeInterval = 2 * kDayInterval
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
    internal func createForRegistration() async throws -> RegistrationPreKeyUploadBundles {
        PreKey.logger.info("Create for registration")

        try Task.checkCancellation()
        let (aciBundle, pniBundle) = try await db.awaitableWrite { tx in
            let aciBundle = try self.generateKeysForRegistration(identity: .aci, tx: tx)
            let pniBundle = try self.generateKeysForRegistration(identity: .pni, tx: tx)
            try self.persistKeysPriorToUpload(bundle: aciBundle, tx: tx)
            try self.persistKeysPriorToUpload(bundle: pniBundle, tx: tx)
            return (aciBundle, pniBundle)
        }
        return .init(aci: aciBundle, pni: pniBundle)
    }

    /// When we provision, we use the primary's identity key to create other keys. So this variant:
    /// NEVER creates an identity key
    /// ALWAYS changes the targeted keys (regardless of current key state)
    internal func createForProvisioning(
        aciIdentityKeyPair: ECKeyPair,
        pniIdentityKeyPair: ECKeyPair
    ) async throws -> RegistrationPreKeyUploadBundles {
        PreKey.logger.info("Create for provisioning")

        try Task.checkCancellation()
        let (aciBundle, pniBundle) = try await db.awaitableWrite { tx in
            let aciBundle = try self.generateKeysForProvisioning(
                identity: .aci,
                identityKeyPair: aciIdentityKeyPair,
                tx: tx
            )
            let pniBundle = try self.generateKeysForProvisioning(
                identity: .pni,
                identityKeyPair: pniIdentityKeyPair,
                tx: tx
            )
            try self.persistKeysPriorToUpload(bundle: aciBundle, tx: tx)
            try self.persistKeysPriorToUpload(bundle: pniBundle, tx: tx)
            return (aciBundle, pniBundle)
        }
        return .init(aci: aciBundle, pni: pniBundle)
    }

    internal func persistAfterRegistration(
        bundles: RegistrationPreKeyUploadBundles,
        uploadDidSucceed: Bool
    ) async throws {
        PreKey.logger.info("Persist after provisioning")
        try Task.checkCancellation()
        try await db.awaitableWrite { tx in
            if uploadDidSucceed {
                try self.persistKeysAfterUpload(bundle: bundles.aci, tx: tx)
                try self.persistKeysAfterUpload(bundle: bundles.pni, tx: tx)
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
    internal func refresh(
        identity: OWSIdentity,
        targets: PreKey.Target,
        auth: ChatServiceAuth
    ) async throws {
        PreKey.logger.info("[\(identity)] Refresh [\(targets)]")
        try Task.checkCancellation()
        try await waitForMessageProcessing()
        try Task.checkCancellation()

        let unfilteredTargets = targets
        let (ecCount, pqCount): (Int?, Int?)
        if unfilteredTargets.contains(target: .oneTimePreKey) || unfilteredTargets.contains(target: .oneTimePqPreKey) {
            (ecCount, pqCount) = try await self.serviceClient.getPreKeysCount(for: identity).awaitable()
        } else {
            // No need to fetch prekey counts.
            (ecCount, pqCount) = (nil, nil)
        }
        try Task.checkCancellation()
        let targets = self.filterToNecessaryTargets(
            identity: identity,
            unfilteredTargets: unfilteredTargets,
            ecPreKeyRecordCount: ecCount,
            pqPreKeyRecordCount: pqCount
        )

        PreKey.logger.info("[\(identity)] Refresh(filtered): [\(targets)]")
        let bundle = try await db.awaitableWrite { tx in
            let identityKeyPair = try self.requireIdentityKeyPair(for: identity, tx: tx)
            return try self.createPartialBundle(
                identity: identity,
                identityKeyPair: identityKeyPair,
                targets: targets,
                tx: tx
            )
        }

        try Task.checkCancellation()
        try await uploadAndPersistBundle(bundle, auth: auth)
    }

    /// When we rotate keys (e.g. due to prior prekey failure) we should never change
    /// our identity key. So this variant:
    /// CANNOT create a new identity key
    /// ALWAYS changes the targeted keys (regardless of current key state)
    internal func rotate(
        identity: OWSIdentity,
        targets: PreKey.Target,
        auth: ChatServiceAuth
    ) async throws {
        PreKey.logger.info("[\(identity)] Rotate [\(targets)]")
        try Task.checkCancellation()
        try await waitForMessageProcessing()
        try Task.checkCancellation()
        let bundle = try await db.awaitableWrite { tx in
            let identityKeyPair = try self.requireIdentityKeyPair(for: identity, tx: tx)
            return try self.createPartialBundle(
                identity: identity,
                identityKeyPair: identityKeyPair,
                targets: targets,
                tx: tx
            )
        }
        try Task.checkCancellation()
        try await uploadAndPersistBundle(bundle, auth: auth)
    }

    internal func createOneTimePreKeys(
        identity: OWSIdentity,
        auth: ChatServiceAuth
    ) async throws {
        PreKey.logger.info("[\(identity)] Create one-time prekeys")
        try Task.checkCancellation()
        let bundle = try await db.awaitableWrite { tx in
            let identityKeyPair = try self.requireIdentityKeyPair(for: identity, tx: tx)
            return try self.createPartialBundle(
                identity: identity,
                identityKeyPair: identityKeyPair,
                targets: [.oneTimePreKey, .oneTimePqPreKey],
                tx: tx
            )
        }

        try Task.checkCancellation()
        try await uploadAndPersistBundle(bundle, auth: auth)
    }

    /// When we create our PNI (as part of hello world) we are allowed to
    /// create a new identity key. So this variant:
    /// CAN create a new identity key (or uses any existing one)
    /// ALWAYS changes the targeted keys (regardless of current key state)
    internal func createOrRotatePniKeys(
        targets: PreKey.Target,
        auth: ChatServiceAuth
    ) async throws {
        PreKey.logger.info("[PNI] Create or Rotate PNI [\(targets)]")
        try Task.checkCancellation()
        try await waitForMessageProcessing()
        try Task.checkCancellation()
        let bundle = try await db.awaitableWrite { tx in
            let identityKeyPair = self.getOrCreateIdentityKeyPair(identity: .pni, tx: tx)
            return try self.createPartialBundle(
                identity: .pni,
                identityKeyPair: identityKeyPair,
                targets: targets,
                tx: tx
            )
        }
        try Task.checkCancellation()
        try await uploadAndPersistBundle(bundle, auth: auth)
    }

    // MARK: - Private helpers

    // MARK: Per-identity registration generators

    private func generateKeysForRegistration(
        identity: OWSIdentity,
        tx: DBWriteTransaction
    ) throws -> RegistrationPreKeyUploadBundle {
        let identityKeyPair = getOrCreateIdentityKeyPair(identity: identity, tx: tx)
        let protocolStore = self.protocolStoreManager.signalProtocolStore(for: identity)
        return RegistrationPreKeyUploadBundle(
            identity: identity,
            identityKeyPair: identityKeyPair,
            signedPreKey: protocolStore.signedPreKeyStore.generateSignedPreKey(signedBy: identityKeyPair),
            lastResortPreKey: try protocolStore.kyberPreKeyStore.generateLastResortKyberPreKey(
                signedBy: identityKeyPair,
                tx: tx
            )
        )
    }

    private func generateKeysForProvisioning(
        identity: OWSIdentity,
        identityKeyPair: ECKeyPair,
        tx: DBWriteTransaction
    ) throws -> RegistrationPreKeyUploadBundle {
        let protocolStore = self.protocolStoreManager.signalProtocolStore(for: identity)
        return RegistrationPreKeyUploadBundle(
            identity: identity,
            identityKeyPair: identityKeyPair,
            signedPreKey: protocolStore.signedPreKeyStore.generateSignedPreKey(
                signedBy: identityKeyPair
            ),
            lastResortPreKey: try protocolStore.kyberPreKeyStore.generateLastResortKyberPreKey(
                signedBy: identityKeyPair,
                tx: tx
            )
        )
    }

    // MARK: Identity Key

    fileprivate func getOrCreateIdentityKeyPair(
        identity: OWSIdentity,
        tx: DBWriteTransaction
    ) -> ECKeyPair {
        let existingKeyPair = identityManager.identityKeyPair(for: identity, tx: tx)
        if let identityKeyPair = existingKeyPair {
            return identityKeyPair
        }
        let identityKeyPair = identityManager.generateNewIdentityKeyPair()
        self.identityManager.store(
            keyPair: identityKeyPair,
            for: identity,
            tx: tx
        )
        return identityKeyPair
    }

    func requireIdentityKeyPair(
        for identity: OWSIdentity,
        tx: DBReadTransaction
    ) throws -> ECKeyPair {
        guard let identityKey = identityManager.identityKeyPair(for: identity, tx: tx) else { Logger.warn("cannot perform operation for \(identity); missing identity key")
            throw Error.noIdentityKey
        }
        return identityKey
    }

    // MARK: Bundle construction

    fileprivate func createPartialBundle(
        identity: OWSIdentity,
        identityKeyPair: ECKeyPair,
        targets: PreKey.Target,
        tx: DBWriteTransaction
    ) throws -> PartialPreKeyUploadBundle {
        let protocolStore = self.protocolStoreManager.signalProtocolStore(
            for: identity
        )

        // Map the keys to the requested operation.  Create the necessary keys and
        // pass them along to be uploaded to the service/stored/accepted
        var signedPreKey: SignedPreKeyRecord?
        var preKeyRecords: [PreKeyRecord]?
        var lastResortPreKey: KyberPreKeyRecord?
        var pqPreKeyRecords: [KyberPreKeyRecord]?

        try targets.targets.forEach { target in
            switch target {
            case .oneTimePreKey:
                preKeyRecords = protocolStore.preKeyStore.generatePreKeyRecords(tx: tx)
            case .signedPreKey:
                signedPreKey = protocolStore.signedPreKeyStore.generateSignedPreKey(signedBy: identityKeyPair)
            case .oneTimePqPreKey:
                pqPreKeyRecords = try protocolStore.kyberPreKeyStore.generateKyberPreKeyRecords(
                    count: 100,
                    signedBy: identityKeyPair,
                    tx: tx
                )
            case .lastResortPqPreKey:
                lastResortPreKey = try protocolStore.kyberPreKeyStore.generateLastResortKyberPreKey(
                    signedBy: identityKeyPair,
                    tx: tx
                )
            }
        }
        return PartialPreKeyUploadBundle(
            identity: identity,
            signedPreKey: signedPreKey,
            preKeyRecords: preKeyRecords,
            lastResortPreKey: lastResortPreKey,
            pqPreKeyRecords: pqPreKeyRecords
        )
    }

    // MARK: Filtering (based on fetched prekey results)

    private func filterToNecessaryTargets(
        identity: OWSIdentity,
        unfilteredTargets: PreKey.Target,
        ecPreKeyRecordCount: Int?,
        pqPreKeyRecordCount: Int?
    ) -> PreKey.Target {
        let protocolStore = self.protocolStoreManager.signalProtocolStore(for: identity)
        let (currentSignedPreKey, currentLastResortPqPreKey) = db.read { tx in
            let signedPreKey = protocolStore.signedPreKeyStore.currentSignedPreKey(tx: tx)
            let lastResortKey = protocolStore.kyberPreKeyStore.getLastResortKyberPreKey(tx: tx)
            return (signedPreKey, lastResortKey)
        }

        // Take the gathered PreKeyState information and run it through
        // logic to determine what really needs to be updated.
        return unfilteredTargets.targets.reduce(into: []) { value, target in
            switch target {
            case .oneTimePreKey:
                guard let ecPreKeyRecordCount else {
                    Logger.warn("Did not fetch prekey count, aborting.")
                    return
                }
                if ecPreKeyRecordCount < Constants.EphemeralPreKeysMinimumCount {
                    value.insert(target: target)
                } else {
                    Logger.info("Available \(identity) keys sufficient: \(ecPreKeyRecordCount)")
                }
            case .oneTimePqPreKey:
                guard let pqPreKeyRecordCount else {
                    Logger.warn("Did not fetch pq prekey count, aborting.")
                    return
                }
                if pqPreKeyRecordCount < Constants.PqPreKeysMinimumCount {
                    value.insert(target: target)
                } else {
                    Logger.info("Available \(identity) PQ keys sufficient: \(pqPreKeyRecordCount)")
                }
            case .signedPreKey:
                if
                    let signedPreKey = currentSignedPreKey,
                    case let currentDate = self.dateProvider(),
                    case let generatedDate = signedPreKey.generatedAt,
                    currentDate.timeIntervalSince(generatedDate) < Constants.SignedPreKeyRotationTime
                {
                    Logger.info("Available \(identity) signed PreKey sufficient: \(signedPreKey.generatedAt)")
                } else {
                    value.insert(target: target)
                }
            case .lastResortPqPreKey:
                if
                    let lastResortPreKey = currentLastResortPqPreKey,
                    case let currentDate = self.dateProvider(),
                    case let generatedDate = lastResortPreKey.generatedAt,
                    currentDate.timeIntervalSince(generatedDate) < Constants.LastResortPqPreKeyRotationTime
                {
                    Logger.info("Available \(identity) last resort PreKey sufficient: \(lastResortPreKey.generatedAt)")
                } else {
                    value.insert(target: target)
                }
            }
        }
    }

    // MARK: Message Processing

    private class MessageProcessingTimeoutError: Swift.Error {}

    /// Waits (potentially forever) for message processing, pausing every couple of seconds if not finished to check for cancellation.
    private func waitForMessageProcessing() async throws {
        try Task.checkCancellation()

        do {
            try await messageProcessor.fetchingAndProcessingCompletePromise()
                .timeout(seconds: 3, timeoutErrorBlock: { MessageProcessingTimeoutError() })
                .awaitable()
        } catch let error {
            if error is MessageProcessingTimeoutError {
                // try again so we get the chance to check for cancellation.
                try await self.waitForMessageProcessing()
                return
            }
            throw SSKUnretryableError.messageProcessingFailed
        }
    }

    // MARK: Persist

    /// Unlike the below method, this does not mark the stored prekeys as "current" or "accepted by server"
    /// TODO: should the concept of "current" and "accepted" go away?
    private func persistKeysPriorToUpload(
        bundle: PreKeyUploadBundle,
        tx: DBWriteTransaction
    ) throws {
        let protocolStore = protocolStoreManager.signalProtocolStore(for: bundle.identity)
        if let signedPreKeyRecord = bundle.getSignedPreKey() {
            protocolStore.signedPreKeyStore.storeSignedPreKey(
                signedPreKeyRecord.id,
                signedPreKeyRecord: signedPreKeyRecord,
                tx: tx
            )
        }
        if let lastResortPreKey = bundle.getLastResortPreKey() {
            try protocolStore.kyberPreKeyStore.storeKyberPreKey(
                record: lastResortPreKey,
                tx: tx
            )
        }
        if let newPreKeyRecords = bundle.getPreKeyRecords() {
            protocolStore.preKeyStore.storePreKeyRecords(newPreKeyRecords, tx: tx)
        }
        if let pqPreKeyRecords = bundle.getPqPreKeyRecords() {
            try protocolStore.kyberPreKeyStore.storeKyberPreKeyRecords(records: pqPreKeyRecords, tx: tx)
        }
    }

    private func persistKeysAfterUpload(
        bundle: PreKeyUploadBundle,
        tx: DBWriteTransaction
    ) throws {
        let protocolStore = protocolStoreManager.signalProtocolStore(for: bundle.identity)

        if let signedPreKeyRecord = bundle.getSignedPreKey() {

            // Mark the new Signed Prekey as accepted
            protocolStore.signedPreKeyStore.storeSignedPreKeyAsAcceptedAndCurrent(
                signedPreKeyId: signedPreKeyRecord.id,
                signedPreKeyRecord: signedPreKeyRecord,
                tx: tx
            )

            protocolStore.signedPreKeyStore.setLastSuccessfulPreKeyRotationDate(self.dateProvider(), tx: tx)

            protocolStore.signedPreKeyStore.cullSignedPreKeyRecords(tx: tx)
        }

        // save last-resort PQ key here as well (if created)
        if let lastResortPreKey = bundle.getLastResortPreKey() {

            try protocolStore.kyberPreKeyStore.storeLastResortPreKeyAndMarkAsCurrent(
                record: lastResortPreKey,
                tx: tx
            )

            // Register a successful key rotation
            protocolStore.kyberPreKeyStore.setLastSuccessfulPreKeyRotationDate(self.dateProvider(), tx: tx)

            // Cleanup any old keys
            try protocolStore.kyberPreKeyStore.cullLastResortPreKeyRecords(tx: tx)
        }

        if let newPreKeyRecords = bundle.getPreKeyRecords() {

            // Store newly added prekeys
            protocolStore.preKeyStore.storePreKeyRecords(newPreKeyRecords, tx: tx)

            // OneTime PreKey Cleanup
            protocolStore.preKeyStore.cullPreKeyRecords(tx: tx)
        }

        if let pqPreKeyRecords = bundle.getPqPreKeyRecords() {
            try protocolStore.kyberPreKeyStore.storeKyberPreKeyRecords(records: pqPreKeyRecords, tx: tx)

            try protocolStore.kyberPreKeyStore.cullOneTimePreKeyRecords(tx: tx)
        }
    }

    private func wipeKeysAfterFailedRegistration(
        bundle: RegistrationPreKeyUploadBundle,
        tx: DBWriteTransaction
    ) {
        let protocolStore = protocolStoreManager.signalProtocolStore(for: bundle.identity)
        protocolStore.signedPreKeyStore.removeSignedPreKey(bundle.signedPreKey, tx: tx)
        protocolStore.kyberPreKeyStore.removeLastResortPreKey(record: bundle.lastResortPreKey, tx: tx)
    }

    // MARK: Upload

    private func uploadAndPersistBundle(
        _ bundle: PreKeyUploadBundle,
        auth: ChatServiceAuth
    ) async throws {
        let identity = bundle.identity
        let uploadResult = await upload(bundle: bundle, auth: auth)

        let protocolStore = protocolStoreManager.signalProtocolStore(for: identity)

        switch uploadResult {
        case .skipped:
            PreKey.logger.info("[\(identity)] No keys to upload")
        case .success:
            PreKey.logger.info("[\(identity)] Successfully uploaded prekeys")
            try await db.awaitableWrite { tx in
                try self.persistKeysAfterUpload(bundle: bundle, tx: tx)
            }
        case .incorrectIdentityKeyOnLinkedDevice:
            guard
                identity == .pni
            else {
                throw OWSAssertionError("Expected to be a PNI operation!")
            }

            // We think we have an incorrect PNI identity key, which
            // we should record so we can handle it later.
            db.asyncWrite { tx in
                self.linkedDevicePniKeyManager
                    .recordSuspectedIssueWithPniIdentityKey(tx: tx)
            }
        case let .failure(error):
            PreKey.logger.info("[\(identity)] Failed to upload prekeys")
            throw error
        }
    }

    private enum UploadResult {
        case success
        case skipped
        /// An error in which we, a linked device, attempted an upload and
        /// were told by the server that the identity key in our bundle was
        /// incorrect.
        ///
        /// This error should never occur on a primary.
        case incorrectIdentityKeyOnLinkedDevice
        case failure(Swift.Error)
    }

    private func upload(
        bundle: PreKeyUploadBundle,
        auth: ChatServiceAuth
    ) async -> UploadResult {
        // If there is nothing to update, skip this step.
        guard !bundle.isEmpty() else { return .skipped }

        PreKey.logger.info("[\(bundle.identity)] uploading prekeys")

        do {
            try await self.serviceClient.setPreKeys(
                for: bundle.identity,
                signedPreKeyRecord: bundle.getSignedPreKey(),
                preKeyRecords: bundle.getPreKeyRecords(),
                pqLastResortPreKeyRecord: bundle.getLastResortPreKey(),
                pqPreKeyRecords: bundle.getPqPreKeyRecords(),
                auth: auth
            ).awaitable()
            return .success
        } catch let error {
            switch error.httpStatusCode {
            case 403:
                return .incorrectIdentityKeyOnLinkedDevice
            default:
                return .failure(error)
            }
        }
    }
}
