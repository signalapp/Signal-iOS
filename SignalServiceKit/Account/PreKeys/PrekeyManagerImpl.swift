//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Boradly speaking, this class does not perform PreKey operations. It just manages scheduling
/// them (they must occur in serial), including deciding which need to happen in the first place.
/// Actual execution is handed off to ``PreKeyTaskManager``.
public class PreKeyManagerImpl: PreKeyManager {

    public enum Constants {

        // How often we check prekey state on app activation.
        static let oneTimePreKeyCheckFrequencySeconds = 12 * kHourInterval

        // Maximum amount of time that can elapse without rotating signed prekeys
        // before the message sending is disabled.
        static let SignedPreKeyMaxRotationDuration = (14 * kDayInterval)

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
    private let identityManager: PreKey.Shims.IdentityManager
    private let keyValueStore: KeyValueStore
    private let protocolStoreManager: SignalProtocolStoreManager
    private let chatConnectionManager: any ChatConnectionManager
    private let tsAccountManager: any TSAccountManager

    private let taskManager: PreKeyTaskManager

    init(
        dateProvider: @escaping DateProvider,
        db: any DB,
        identityManager: PreKey.Shims.IdentityManager,
        linkedDevicePniKeyManager: LinkedDevicePniKeyManager,
        messageProcessor: PreKey.Shims.MessageProcessor,
        preKeyTaskAPIClient: PreKeyTaskAPIClient,
        protocolStoreManager: SignalProtocolStoreManager,
        chatConnectionManager: any ChatConnectionManager,
        tsAccountManager: TSAccountManager
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
            identityManager: identityManager,
            linkedDevicePniKeyManager: linkedDevicePniKeyManager,
            messageProcessor: messageProcessor,
            protocolStoreManager: protocolStoreManager,
            tsAccountManager: tsAccountManager
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
        let shouldCheckPniState = hasPniIdentityKey(tx: tx)
        let needPreKeyRotation =
            needsSignedPreKeyRotation(identity: .aci, tx: tx)
            || (
                shouldCheckPniState
                && needsSignedPreKeyRotation(identity: .pni, tx: tx)
            )

        let needLastResortKeyRotation =
            needsLastResortPreKeyRotation(identity: .aci, tx: tx)
            || (
                shouldCheckPniState
                && needsLastResortPreKeyRotation(identity: .pni, tx: tx)
            )

        return needPreKeyRotation || needLastResortKeyRotation
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

        let shouldCheckOneTimePrekeys = {
            if
                shouldThrottle,
                let lastOneTimePreKeyCheckTimestamp,
                fabs(lastOneTimePreKeyCheckTimestamp.timeIntervalSinceNow) < Constants.oneTimePreKeyCheckFrequencySeconds
            {
                return false
            }
            return true
        }()

        var targets: PreKey.Target = [.signedPreKey, .lastResortPqPreKey]
        if shouldCheckOneTimePrekeys {
            targets.insert(target: .oneTimePreKey)
            targets.insert(target: .oneTimePqPreKey)
        }
        let shouldPerformPniOp = hasPniIdentityKey(tx: tx)

        Task { [weak self, chatConnectionManager, taskManager, targets] in
            let task = Self.taskQueue.enqueue {
                try await chatConnectionManager.waitForIdentifiedConnectionToOpen()
                try Task.checkCancellation()
                try await taskManager.refresh(identity: .aci, targets: targets, auth: .implicit())
                if shouldPerformPniOp {
                    try Task.checkCancellation()
                    try await taskManager.refresh(identity: .pni, targets: targets, auth: .implicit())
                }
            }
            try await task.value
            if shouldCheckOneTimePrekeys {
                self?.refreshOneTimePreKeysCheckDidSucceed()
            }
        }
    }

    public func createPreKeysForRegistration() -> Task<RegistrationPreKeyUploadBundles, Error> {
        PreKey.logger.info("Create registration prekeys")
        /// Note that we do not report a `refreshOneTimePreKeysCheckDidSucceed`
        /// because this operation does not generate one time prekeys, so we
        /// shouldn't mark the routine refresh as having been "checked".
        return Self.taskQueue.enqueueCancellingPrevious { [taskManager] in
            return try await taskManager.createForRegistration()
        }
    }

    public func createPreKeysForProvisioning(
        aciIdentityKeyPair: ECKeyPair,
        pniIdentityKeyPair: ECKeyPair
    ) -> Task<RegistrationPreKeyUploadBundles, Error> {
        PreKey.logger.info("Create provisioning prekeys")
        /// Note that we do not report a `refreshOneTimePreKeysCheckDidSucceed`
        /// because this operation does not generate one time prekeys, so we
        /// shouldn't mark the routine refresh as having been "checked".
        return Self.taskQueue.enqueueCancellingPrevious { [taskManager] in
            return try await taskManager.createForProvisioning(
                aciIdentityKeyPair: aciIdentityKeyPair,
                pniIdentityKeyPair: pniIdentityKeyPair
            )
        }
    }

    public func finalizeRegistrationPreKeys(
        _ bundles: RegistrationPreKeyUploadBundles,
        uploadDidSucceed: Bool
    ) -> Task<Void, Error> {
        PreKey.logger.info("Finalize registration prekeys")
        return Self.taskQueue.enqueue { [taskManager] in
            try await taskManager.persistAfterRegistration(
                bundles: bundles,
                uploadDidSucceed: uploadDidSucceed
            )
        }
    }

    public func rotateOneTimePreKeysForRegistration(auth: ChatServiceAuth) -> Task<Void, Error> {
        PreKey.logger.info("Rotate one-time prekeys for registration")

        return Self.taskQueue.enqueue { [weak self, taskManager] in
            try Task.checkCancellation()
            try await taskManager.createOneTimePreKeys(identity: .aci, auth: auth)
            try Task.checkCancellation()
            try await taskManager.createOneTimePreKeys(identity: .pni, auth: auth)
            self?.refreshOneTimePreKeysCheckDidSucceed()
        }
    }

    public func rotateSignedPreKeys() -> Task<Void, Error> {
        PreKey.logger.info("Rotate signed prekeys")

        let targets: PreKey.Target = [.signedPreKey, .lastResortPqPreKey]
        let shouldPerformPniOp = db.read(block: hasPniIdentityKey(tx:))

        return Self.taskQueue.enqueue { [chatConnectionManager, taskManager, targets] in
            if OWSChatConnection.canAppUseSocketsToMakeRequests {
                try await chatConnectionManager.waitForIdentifiedConnectionToOpen()
            } else {
                // TODO: Migrate the NSE to use web sockets.
                // The NSE generally launches only when network is available, and we try to
                // run this only when we have network, but it's not harmful if that's not
                // true, so this is fine.
            }
            try Task.checkCancellation()
            try await taskManager.rotate(identity: .aci, targets: targets, auth: .implicit())
            if shouldPerformPniOp {
                try Task.checkCancellation()
                try await taskManager.rotate(identity: .pni, targets: targets, auth: .implicit())
            }
        }
    }

    /// Refresh one-time pre-keys for the given identity, and optionally refresh
    /// the signed pre-key.
    public func refreshOneTimePreKeys(
        forIdentity identity: OWSIdentity,
        alsoRefreshSignedPreKey shouldRefreshSignedPreKey: Bool
    ) {
        Task {
            try? await self._refreshOneTimePreKeys(
                forIdentity: identity,
                alsoRefreshSignedPreKey: shouldRefreshSignedPreKey
            )
        }
    }

    private func _refreshOneTimePreKeys(
        forIdentity identity: OWSIdentity,
        alsoRefreshSignedPreKey shouldRefreshSignedPreKey: Bool
    ) async throws {
        PreKey.logger.info("[\(identity)] Force refresh onetime prekeys (also refresh signed pre key? \(shouldRefreshSignedPreKey))")
        /// Note that we do not report a `refreshOneTimePreKeysCheckDidSucceed`
        /// because this operation does not generate BOTH types of one time prekeys,
        /// so we shouldn't mark the routine refresh as having been "checked".

        var targets: PreKey.Target = [.oneTimePreKey, .oneTimePqPreKey]
        if shouldRefreshSignedPreKey {
            targets.insert(.signedPreKey)
            targets.insert(target: .lastResortPqPreKey)
        }

        let task = Self.taskQueue.enqueue { [taskManager, targets] in
            try Task.checkCancellation()
            try await taskManager.refresh(
                identity: identity,
                targets: targets,
                force: true,
                auth: .implicit()
            )
        }
        try await task.value
    }

    /// If we don't have a PNI identity key, we should not run PNI operations.
    /// If we try, they will fail, and we will count the joint pni+aci operation as failed.
    private func hasPniIdentityKey(tx: DBReadTransaction) -> Bool {
        return self.identityManager.identityKeyPair(for: .pni, tx: tx) != nil
    }

    public func rotatePreKeysOnUpgradeIfNecessary(for identity: OWSIdentity) async {
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
        var retryInterval: TimeInterval = 0.5
        while db.read(block: tsAccountManager.registrationState(tx:)).isRegistered {
            do {
                if OWSChatConnection.canAppUseSocketsToMakeRequests {
                    try await chatConnectionManager.waitForIdentifiedConnectionToOpen()
                } else {
                    // TODO: Migrate the NSE to use web sockets.
                    // The NSE generally launches only when network is available, and we try to
                    // run this only when we have network, but it's not harmful if that's not
                    // true, so this is fine.
                }
                try await _refreshOneTimePreKeys(forIdentity: identity, alsoRefreshSignedPreKey: true)
                break
            } catch {
                Logger.warn("Couldn't rotate pre keys: \(error)")
                try? await Task.sleep(nanoseconds: UInt64(retryInterval * TimeInterval(NSEC_PER_SEC)))
                retryInterval *= 2
            }
        }
        await db.awaitableWrite { [keyValueStore] tx in
            keyValueStore.setInt(
                Constants.preKeyRotationVersion,
                key: keyValueStoreKey,
                transaction: tx
            )
        }
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
