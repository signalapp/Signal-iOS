//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Broadly speaking, this class does not perform PreKey operations. It just manages scheduling
/// them (they must occur in serial), including deciding which need to happen in the first place.
/// Actual execution is handed off to ``PreKeyTaskManager``.
public class PreKeyManagerImpl: PreKeyManager {
    private let logger = PrefixedLogger(prefix: "[PreKey]")

    public enum Constants {

        // How often we check prekey state on app activation.
        static let oneTimePreKeyCheckFrequencySeconds: TimeInterval = 12 * .hour

        // Maximum amount of time that can elapse without rotating signed prekeys
        // before the message sending is disabled.
        static let SignedPreKeyMaxRotationDuration: TimeInterval = (
            BuildFlags.shouldUseTestIntervals ? (4 * .day) : (14 * .day),
        )

        /// Maximum amount of time a pre key can be used before a new one will be
        /// fetched. This should be equivalent to the largest
        /// `MAX_UNACKNOWLEDGED_SESSION_AGE` (from LibSignalClient) value currently
        /// in use by any client.
        static let maxUnacknowledgedSessionAge: TimeInterval = 30 * .day

        fileprivate static let preKeyRotationVersion = 1
        fileprivate static let aciPreKeyRotationVersionKey = "ACIPreKeyRotationVersion"
        fileprivate static let pniPreKeyRotationVersionKey = "PNIPreKeyRotationVersion"
    }

    /// PreKey state lives in two places - on the client and on the service.
    /// Some of our pre-key operations depend on the service state, e.g. we need to check our one-time-prekey count
    /// before we decide to upload new ones. This potentially entails multiple async operations, all of which should
    /// complete before starting any other pre-key operation. That's why they must run in serial.
    private static let taskQueue = SerialTaskQueue()

    private let db: any DB
    private let identityManager: OWSIdentityManager
    private let keyValueStore: KeyValueStore
    private let protocolStoreManager: SignalProtocolStoreManager
    private let chatConnectionManager: any ChatConnectionManager
    private let tsAccountManager: any TSAccountManager

    private let taskManager: PreKeyTaskManager

    init(
        dateProvider: @escaping DateProvider,
        db: any DB,
        identityKeyMismatchManager: IdentityKeyMismatchManager,
        identityManager: OWSIdentityManager,
        messageProcessor: MessageProcessor,
        preKeyTaskAPIClient: PreKeyTaskAPIClient,
        protocolStoreManager: SignalProtocolStoreManager,
        remoteConfigProvider: any RemoteConfigProvider,
        chatConnectionManager: any ChatConnectionManager,
        tsAccountManager: TSAccountManager,
    ) {
        self.db = db
        self.identityManager = identityManager
        self.keyValueStore = KeyValueStore(collection: "PreKeyManager")
        self.protocolStoreManager = protocolStoreManager
        self.chatConnectionManager = chatConnectionManager
        self.tsAccountManager = tsAccountManager

        self.taskManager = PreKeyTaskManager(
            apiClient: preKeyTaskAPIClient,
            dateProvider: dateProvider,
            db: db,
            identityKeyMismatchManager: identityKeyMismatchManager,
            identityManager: identityManager,
            messageProcessor: messageProcessor,
            protocolStoreManager: protocolStoreManager,
            remoteConfigProvider: remoteConfigProvider,
            tsAccountManager: tsAccountManager,
        )
    }

    @Atomic private var lastOneTimePreKeyCheckTimestamp: Date?

    private func needsSignedPreKeyRotation(identity: OWSIdentity, tx: DBReadTransaction) -> Bool {
        let store = protocolStoreManager.signalProtocolStore(for: identity).signedPreKeyStore

        guard let lastSuccessDate = store.getLastSuccessfulRotationDate(tx: tx) else {
            return true
        }

        return lastSuccessDate.addingTimeInterval(Constants.SignedPreKeyMaxRotationDuration) < Date()
    }

    private func needsLastResortPreKeyRotation(identity: OWSIdentity, tx: DBReadTransaction) -> Bool {
        let store = protocolStoreManager.signalProtocolStore(for: identity).kyberPreKeyStore

        guard let lastSuccessDate = store.getLastSuccessfulRotationDate(tx: tx) else {
            return true
        }

        return lastSuccessDate.addingTimeInterval(Constants.SignedPreKeyMaxRotationDuration) < Date()
    }

    public func isAppLockedDueToPreKeyUpdateFailures(tx: DBReadTransaction) -> Bool {
        return
            needsSignedPreKeyRotation(identity: .aci, tx: tx)
                || needsSignedPreKeyRotation(identity: .pni, tx: tx)
                || needsLastResortPreKeyRotation(identity: .aci, tx: tx)
                || needsLastResortPreKeyRotation(identity: .pni, tx: tx)

    }

    private func refreshOneTimePreKeysCheckDidSucceed() {
        lastOneTimePreKeyCheckTimestamp = Date()
    }

    public func checkPreKeysIfNecessary(tx: DBReadTransaction) {
        checkPreKeys(shouldThrottle: true, tx: tx)
    }

    fileprivate func checkPreKeys(shouldThrottle: Bool, tx: DBReadTransaction) {
        guard
            CurrentAppContext().isMainAppAndActive
        else {
            return
        }

        let shouldCheckOneTimePreKeys = {
            if
                shouldThrottle,
                let lastOneTimePreKeyCheckTimestamp,
                fabs(lastOneTimePreKeyCheckTimestamp.timeIntervalSinceNow) < Constants.oneTimePreKeyCheckFrequencySeconds
            {
                return false
            }
            return true
        }()

        // If we can throttle this check, and if we're changing our number, assume
        // that the change number will refresh our pre keys. (This check is
        // optional, so it's fine to skip it.)
        let shouldSkipPniPreKeyCheck = shouldThrottle && changeNumberState.update(block: { $0.isChangingNumber })
        if shouldSkipPniPreKeyCheck {
            logger.warn("Skipping PNI pre key check due to change number.")
        }

        _ = self._checkPreKeys(
            shouldCheckOneTimePreKeys: shouldCheckOneTimePreKeys,
            shouldCheckPniPreKeys: !shouldSkipPniPreKeyCheck,
            tx: tx,
        )
    }

    private func _checkPreKeys(
        shouldCheckOneTimePreKeys: Bool,
        shouldCheckPniPreKeys: Bool,
        tx: DBReadTransaction,
    ) -> Task<Void, any Error> {
        var targets: PreKeyTargets = [.signedPreKey, .lastResortPqPreKey]
        if shouldCheckOneTimePreKeys {
            targets.insert(target: .oneTimePreKey)
            targets.insert(target: .oneTimePqPreKey)
        }
        return Self.taskQueue.enqueue { [self, chatConnectionManager, taskManager, targets] in
            try await chatConnectionManager.waitForIdentifiedConnectionToOpen()
            try Task.checkCancellation()
            try await taskManager.refresh(identity: .aci, targets: targets, auth: .implicit())
            if shouldCheckPniPreKeys {
                try Task.checkCancellation()
                try await self.waitUntilNotChangingNumberIfNeeded(targets: targets)
                try await taskManager.refresh(identity: .pni, targets: targets, auth: .implicit())
            }
            if shouldCheckOneTimePreKeys, shouldCheckPniPreKeys {
                self.refreshOneTimePreKeysCheckDidSucceed()
            }
        }
    }

    public func createPreKeysForRegistration() -> Task<RegistrationPreKeyUploadBundles, Error> {
        logger.info("Create registration prekeys")
        /// Note that we do not report a `refreshOneTimePreKeysCheckDidSucceed`
        /// because this operation does not generate one time prekeys, so we
        /// shouldn't mark the routine refresh as having been "checked".
        return Self.taskQueue.enqueueCancellingPrevious { [taskManager] in
            return try await taskManager.createForRegistration()
        }
    }

    public func createPreKeysForProvisioning(
        aciIdentityKeyPair: ECKeyPair,
        pniIdentityKeyPair: ECKeyPair,
    ) -> Task<RegistrationPreKeyUploadBundles, Error> {
        logger.info("Create provisioning prekeys")
        /// Note that we do not report a `refreshOneTimePreKeysCheckDidSucceed`
        /// because this operation does not generate one time prekeys, so we
        /// shouldn't mark the routine refresh as having been "checked".
        return Self.taskQueue.enqueueCancellingPrevious { [taskManager] in
            return try await taskManager.createForProvisioning(
                aciIdentityKeyPair: aciIdentityKeyPair,
                pniIdentityKeyPair: pniIdentityKeyPair,
            )
        }
    }

    public func finalizeRegistrationPreKeys(
        _ bundles: RegistrationPreKeyUploadBundles,
        uploadDidSucceed: Bool,
    ) -> Task<Void, Error> {
        logger.info("Finalize registration prekeys")
        return Self.taskQueue.enqueue { [taskManager] in
            try await taskManager.persistAfterRegistration(
                bundles: bundles,
                uploadDidSucceed: uploadDidSucceed,
            )
        }
    }

    public func rotateOneTimePreKeysForRegistration(auth: ChatServiceAuth) -> Task<Void, Error> {
        logger.info("Rotate one-time prekeys for registration")

        return Self.taskQueue.enqueue { [weak self, taskManager] in
            try Task.checkCancellation()
            try await taskManager.createOneTimePreKeys(identity: .aci, auth: auth)
            try Task.checkCancellation()
            try await taskManager.createOneTimePreKeys(identity: .pni, auth: auth)
            self?.refreshOneTimePreKeysCheckDidSucceed()
        }
    }

    public func rotateSignedPreKeysIfNeeded() -> Task<Void, Error> {
        logger.info("Rotating signed prekeys if needed")

        return db.read { tx in
            return _checkPreKeys(shouldCheckOneTimePreKeys: false, shouldCheckPniPreKeys: true, tx: tx)
        }
    }

    /// Refresh one-time pre-keys for the given identity, and optionally refresh
    /// the signed pre-key.
    public func refreshOneTimePreKeys(
        forIdentity identity: OWSIdentity,
        alsoRefreshSignedPreKey shouldRefreshSignedPreKey: Bool,
    ) {
        Task {
            try? await self._refreshOneTimePreKeys(
                forIdentity: identity,
                alsoRefreshSignedPreKey: shouldRefreshSignedPreKey,
            )
        }
    }

    private func _refreshOneTimePreKeys(
        forIdentity identity: OWSIdentity,
        alsoRefreshSignedPreKey shouldRefreshSignedPreKey: Bool,
    ) async throws {
        logger.info("[\(identity)] Force refresh onetime prekeys (also refresh signed pre key? \(shouldRefreshSignedPreKey))")
        /// Note that we do not report a `refreshOneTimePreKeysCheckDidSucceed`
        /// because this operation does not generate BOTH types of one time prekeys,
        /// so we shouldn't mark the routine refresh as having been "checked".

        var targets: PreKeyTargets = [.oneTimePreKey, .oneTimePqPreKey]
        if shouldRefreshSignedPreKey {
            targets.insert(.signedPreKey)
            targets.insert(target: .lastResortPqPreKey)
        }
        try await waitUntilNotChangingNumberIfNeeded(targets: targets)

        let task = Self.taskQueue.enqueue { [taskManager, targets] in
            try Task.checkCancellation()
            try await taskManager.refresh(
                identity: identity,
                targets: targets,
                force: true,
                auth: .implicit(),
            )
        }
        try await task.value
    }

    /// If we don't have a PNI identity key, we should not run PNI operations.
    /// If we try, they will fail, and we will count the joint pni+aci operation as failed.
    private func hasPniIdentityKey(tx: DBReadTransaction) -> Bool {
        return self.identityManager.identityKeyPair(for: .pni, tx: tx) != nil
    }

    public func rotatePreKeysOnUpgradeIfNecessary(for identity: OWSIdentity) async throws {
        let keyValueStoreKey: String = {
            switch identity {
            case .aci:
                return Constants.aciPreKeyRotationVersionKey
            case .pni:
                return Constants.pniPreKeyRotationVersionKey
            }
        }()
        let preKeyRotationVersion = db.read { tx in
            return keyValueStore.getInt(keyValueStoreKey, defaultValue: 0, transaction: tx)
        }
        guard preKeyRotationVersion < Constants.preKeyRotationVersion else {
            return
        }
        try await Retry.performWithBackoff(maxAttempts: .max, isRetryable: { _ in true }) {
            guard db.read(block: tsAccountManager.registrationState(tx:)).isRegistered else {
                // If we're not registered, we don't need to do this. Our pre keys will be
                // rotated when we re-register.
                return
            }
            do {
                try await chatConnectionManager.waitForIdentifiedConnectionToOpen()
                try await _refreshOneTimePreKeys(forIdentity: identity, alsoRefreshSignedPreKey: true)
            } catch {
                logger.warn("Couldn't rotate pre keys: \(error)")
                throw error
            }
        }
        await db.awaitableWrite { [keyValueStore] tx in
            keyValueStore.setInt(
                Constants.preKeyRotationVersion,
                key: keyValueStoreKey,
                transaction: tx,
            )
        }
    }

    // MARK: - Change Number

    private struct ChangeNumberState {
        var isChangingNumber = false
        var onNotChangingNumber = [NSObject: Monitor.Continuation]()
    }

    private let changeNumberState = AtomicValue(ChangeNumberState(), lock: .init())

    private let notChangingNumberCondition = Monitor.Condition<ChangeNumberState>(
        isSatisfied: { !$0.isChangingNumber },
        waiters: \.onNotChangingNumber,
    )

    /// Waits until the current "Change Number" operation is resolved.
    ///
    /// If we're changing our number, the currently-active PNI identity key is
    /// ambiguous (it's either the old one or the new one, but we don't know
    /// which). We should therefore defer periodic pre key refreshes until after
    /// we've finished changing our number.
    private func waitUntilNotChangingNumberIfNeeded(targets: PreKeyTargets) async throws(CancellationError) {
        guard targets.intersects([.signedPreKey, .lastResortPqPreKey]) else {
            return
        }
        try await Monitor.waitForCondition(notChangingNumberCondition, in: changeNumberState)
    }

    public func setIsChangingNumber(_ isChangingNumber: Bool) {
        Monitor.updateAndNotify(
            in: changeNumberState,
            block: { $0.isChangingNumber = isChangingNumber },
            conditions: notChangingNumberCondition,
        )
    }
}

// MARK: - Debug UI

#if TESTABLE_BUILD

public extension PreKeyManagerImpl {
    func checkPreKeysImmediately(tx: DBReadTransaction) {
        checkPreKeys(shouldThrottle: false, tx: tx)
    }
}

#endif
