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
        static let PreKeyCheckFrequencySeconds = (12 * kHourInterval)

        // Maximum amount of time that can elapse without rotating signed prekeys
        // before the message sending is disabled.
        static let SignedPreKeyMaxRotationDuration = (14 * kDayInterval)
    }

    /// PreKey state lives in two places - on the client and on the service.
    /// Some of our pre-key operations depend on the service state, e.g. we need to check our one-time-prekey count
    /// before we decide to upload new ones. This potentially entails multiple async operations, all of which should
    /// complete before starting any other pre-key operation. That's why they must run in serial.
    private static let taskQueue = SerialTaskQueue()

    private let db: DB
    private let identityManager: PreKey.Shims.IdentityManager
    private let protocolStoreManager: SignalProtocolStoreManager

    private let taskManager: PreKeyTaskManager

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
        self.db = db
        self.identityManager = identityManager
        self.protocolStoreManager = protocolStoreManager

        self.taskManager = PreKeyTaskManager(
            dateProvider: dateProvider,
            db: db,
            identityManager: identityManager,
            linkedDevicePniKeyManager: linkedDevicePniKeyManager,
            messageProcessor: messageProcessor,
            protocolStoreManager: protocolStoreManager,
            serviceClient: serviceClient,
            tsAccountManager: tsAccountManager
        )
    }

    @Atomic private var lastPreKeyCheckTimestamp: Date?

    private func needsSignedPreKeyRotation(identity: OWSIdentity, tx: DBReadTransaction) -> Bool {
        let store = protocolStoreManager.signalProtocolStore(for: identity).signedPreKeyStore

        guard let lastSuccessDate = store.getLastSuccessfulPreKeyRotationDate(tx: tx) else {
            return true
        }

        return lastSuccessDate.addingTimeInterval(Constants.SignedPreKeyMaxRotationDuration) < Date()
    }

    private func needsLastResortPreKeyRotation(identity: OWSIdentity, tx: DBReadTransaction) -> Bool {
        let store = protocolStoreManager.signalProtocolStore(for: identity).kyberPreKeyStore

        guard let lastSuccessDate = store.getLastSuccessfulPreKeyRotationDate(tx: tx) else {
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

    private func refreshPreKeysDidSucceed() {
        lastPreKeyCheckTimestamp = Date()
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

        let shouldRefreshOneTimePrekeys = {
            if
                shouldThrottle,
                let lastPreKeyCheckTimestamp,
                fabs(lastPreKeyCheckTimestamp.timeIntervalSinceNow) < Constants.PreKeyCheckFrequencySeconds
            {
                return false
            }
            return true
        }()

        var targets: PreKey.Target = [.signedPreKey, .lastResortPqPreKey]
        if shouldRefreshOneTimePrekeys {
            targets.insert(target: .oneTimePreKey)
            targets.insert(target: .oneTimePqPreKey)
        }
        let shouldPerformPniOp = hasPniIdentityKey(tx: tx)

        Task { [weak self, taskManager, targets] in
            let task = await Self.taskQueue.enqueue {
                try Task.checkCancellation()
                try await taskManager.refresh(identity: .aci, targets: targets, auth: .implicit())
                if shouldPerformPniOp {
                    try Task.checkCancellation()
                    try await taskManager.refresh(identity: .pni, targets: targets, auth: .implicit())
                }
            }
            try await task.value
            self?.refreshPreKeysDidSucceed()
        }
    }

    public func createPreKeysForRegistration() async -> Task<RegistrationPreKeyUploadBundles, Error> {
        PreKey.logger.info("Create registration prekeys")
        /// Note that we do not report a `refreshPreKeysDidSucceed, because this operation does not`
        /// generate one time prekeys, so we shouldn't mark the routine refresh as having been "checked".
        return await Self.taskQueue.enqueueCancellingPrevious { [taskManager] in
            return try await taskManager.createForRegistration()
        }
    }

    public func createPreKeysForProvisioning(
        aciIdentityKeyPair: ECKeyPair,
        pniIdentityKeyPair: ECKeyPair
    ) async -> Task<RegistrationPreKeyUploadBundles, Error> {
        PreKey.logger.info("Create provisioning prekeys")
        /// Note that we do not report a `refreshPreKeysDidSucceed`, because this operation does not
        /// generate one time prekeys, so we shouldn't mark the routine refresh as having been "checked".
        return await Self.taskQueue.enqueueCancellingPrevious { [taskManager] in
            return try await taskManager.createForProvisioning(
                aciIdentityKeyPair: aciIdentityKeyPair,
                pniIdentityKeyPair: pniIdentityKeyPair
            )
        }
    }

    public func finalizeRegistrationPreKeys(
        _ bundles: RegistrationPreKeyUploadBundles,
        uploadDidSucceed: Bool
    ) async -> Task<Void, Error> {
        PreKey.logger.info("Finalize registration prekeys")
        return await Self.taskQueue.enqueue { [taskManager] in
            try await taskManager.persistAfterRegistration(
                bundles: bundles,
                uploadDidSucceed: uploadDidSucceed
            )
        }
    }

    public func rotateOneTimePreKeysForRegistration(auth: ChatServiceAuth) async -> Task<Void, Error> {
        PreKey.logger.info("Rotate one-time prekeys for registration")

        return await Self.taskQueue.enqueue { [weak self, taskManager] in
            try Task.checkCancellation()
            try await taskManager.createOneTimePreKeys(identity: .aci, auth: auth)
            try Task.checkCancellation()
            try await taskManager.createOneTimePreKeys(identity: .pni, auth: auth)
            self?.refreshPreKeysDidSucceed()
        }
    }

    public func createOrRotatePNIPreKeys(auth: ChatServiceAuth) async -> Task<Void, Error> {
        PreKey.logger.info("Create or rotate PNI prekeys")
        let targets: PreKey.Target = [
            .oneTimePreKey,
            .signedPreKey,
            .oneTimePqPreKey,
            .lastResortPqPreKey
        ]
        return await Self.taskQueue.enqueue { [weak self, taskManager] in
            try await taskManager.createOrRotatePniKeys(targets: targets, auth: auth)
            self?.refreshPreKeysDidSucceed()
        }
    }

    public func rotateSignedPreKeys() async -> Task<Void, Error> {
        PreKey.logger.info("Rotate signed prekeys")

        let targets: PreKey.Target = [.signedPreKey, .lastResortPqPreKey]
        let shouldPerformPniOp = db.read(block: hasPniIdentityKey(tx:))

        return await Self.taskQueue.enqueue { [weak self, taskManager, targets] in
            try Task.checkCancellation()
            try await taskManager.rotate(identity: .aci, targets: targets, auth: .implicit())
            if shouldPerformPniOp {
                try Task.checkCancellation()
                try await taskManager.rotate(identity: .pni, targets: targets, auth: .implicit())
            }
            self?.refreshPreKeysDidSucceed()
        }
    }

    /// Refresh one-time pre-keys for the given identity, and optionally refresh
    /// the signed pre-key.
    /// TODO: callers of this method _feel_ like they actually want a rotation (forced) not
    /// a refresh (conditional). TBD.
   public func refreshOneTimePreKeys(
        forIdentity identity: OWSIdentity,
        alsoRefreshSignedPreKey shouldRefreshSignedPreKey: Bool
    ) {
        PreKey.logger.info("[\(identity)] Refresh onetime prekeys")

        var targets: PreKey.Target = [.oneTimePreKey, .oneTimePqPreKey]
        if shouldRefreshSignedPreKey {
            targets.insert(.signedPreKey)
            targets.insert(target: .lastResortPqPreKey)
        }

        Task { [weak self, taskManager, targets] in
            let task = await Self.taskQueue.enqueue { [targets] in
                try Task.checkCancellation()
                try await taskManager.refresh(identity: identity, targets: targets, auth: .implicit())
            }
            try await task.value
            self?.refreshPreKeysDidSucceed()
        }
    }

    /// If we don't have a PNI identity key, we should not run PNI operations.
    /// If we try, they will fail, and we will count the joint pni+aci operation as failed.
    private func hasPniIdentityKey(tx: DBReadTransaction) -> Bool {
        return self.identityManager.identityKeyPair(for: .pni, tx: tx) != nil
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
