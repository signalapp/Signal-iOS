//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class PreKeyManagerImpl: PreKeyManager {

    public enum Constants {

        // How often we check prekey state on app activation.
        static let PreKeyCheckFrequencySeconds = (12 * kHourInterval)

        // Maximum number of failures while updating signed prekeys
        // before the message sending is disabled.
        static let MaxPrekeyUpdateFailureCount = 5

        // Maximum amount of time that can elapse without updating signed prekeys
        // before the message sending is disabled.
        static let SignedPreKeyUpdateFailureMaxFailureDuration = (10 * kDayInterval)

        // Maximum amount of time that can elapse without rotating signed prekeys
        // before the message sending is disabled.
        static let SignedPreKeyMaxRotationDuration = (14 * kDayInterval)
    }

    /// PreKey state lives in two places - on the client and on the service.
    /// Some of our pre-key operations depend on the service state, e.g. we need to check our one-time-prekey count
    /// before we decide to upload new ones. This potentially entails multiple async operations, all of which should
    /// complete before starting any other pre-key operation. That's why a dispatch_queue is insufficient for
    /// coordinating PreKey operations and instead we use Operation's on a serial OperationQueue.
    private static let operationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "PreKeyManager"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    private let messageProcessor: PreKey.Manager.Shims.MessageProcessor
    private let preKeyOperationFactory: PreKeyOperationFactory
    private let protocolStoreManager: SignalProtocolStoreManager

    init(
        messageProcessor: PreKey.Manager.Shims.MessageProcessor,
        preKeyOperationFactory: PreKeyOperationFactory,
        protocolStoreManager: SignalProtocolStoreManager
    ) {
        self.messageProcessor = messageProcessor
        self.preKeyOperationFactory = preKeyOperationFactory
        self.protocolStoreManager = protocolStoreManager
    }

    private var lastPreKeyCheckTimestamp: Date?

    private func legacy_needsSignedPreKeyRotation(identity: OWSIdentity, tx: DBReadTransaction) -> Bool {
        let store = protocolStoreManager.signalProtocolStore(for: identity).signedPreKeyStore

        // Only disable message sending if we have failed more than N times...
        if store.getPreKeyUpdateFailureCount(tx: tx) < Constants.MaxPrekeyUpdateFailureCount {
            return false
        }

        // ...over a period of at least M days.
        guard let firstFailureDate = store.getFirstPreKeyUpdateFailureDate(tx: tx) else {
            return false
        }

        return fabs(firstFailureDate.timeIntervalSinceNow) >= Constants.SignedPreKeyUpdateFailureMaxFailureDuration
    }

    private func needsSignedPreKeyRotation(identity: OWSIdentity, tx: DBReadTransaction) -> Bool {
        let store = protocolStoreManager.signalProtocolStore(for: identity).signedPreKeyStore

        guard let lastSuccessDate = store.getLastSuccessfulPreKeyRotationDate(tx: tx) else {
            return true
        }

        return lastSuccessDate.timeIntervalSinceNow >= Constants.SignedPreKeyMaxRotationDuration

    }

    private func needsLastResortPreKeyRotation(identity: OWSIdentity, tx: DBReadTransaction) -> Bool {
        let store = protocolStoreManager.signalProtocolStore(for: identity).kyberPreKeyStore

        guard let lastSuccessDate = store.getLastSuccessfulPreKeyRotationDate(tx: tx) else {
            return true
        }

        return lastSuccessDate.timeIntervalSinceNow >= Constants.SignedPreKeyMaxRotationDuration
    }

    public func isAppLockedDueToPreKeyUpdateFailures(tx: DBReadTransaction) -> Bool {
        let needPreKeyRotation =
            needsSignedPreKeyRotation(identity: .aci, tx: tx)
            || needsSignedPreKeyRotation(identity: .pni, tx: tx)

        let needLastResortKeyRotation =
            needsLastResortPreKeyRotation(identity: .aci, tx: tx)
            || needsLastResortPreKeyRotation(identity: .pni, tx: tx)

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

        var operations = [Operation]()

        // Don't rotate or clean up prekeys until all incoming messages
        // have been drained, decrypted and processed.
        let messageProcessingOperation = MessageProcessingOperation(messageProcessor: messageProcessor)
        operations.append(messageProcessingOperation)

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

        func addOperation(for identity: OWSIdentity) {
            let refreshOp = preKeyOperationFactory.refreshPreKeysOperation(
                for: identity,
                shouldRefreshOneTimePreKeys: shouldRefreshOneTimePrekeys,
                shouldRefreshSignedPreKeys: true,
                didSucceed: { [weak self] in self?.refreshPreKeysDidSucceed() }
            )
            refreshOp.addDependency(messageProcessingOperation)
            operations.append(refreshOp)
        }

        addOperation(for: .aci)
        addOperation(for: .pni)

        Self.operationQueue.addOperations(operations, waitUntilFinished: false)
    }

    public func createPreKeysForRegistration() -> Promise<RegistrationPreKeyUploadBundles> {
        /// Note that we do not report a `refreshPreKeysDidSucceed, because this operation does not`
        /// generate one time prekeys, so we shouldn't mark the routine refresh as having been "checked".
        let (promise, future) = Promise<RegistrationPreKeyUploadBundles>.pending()
        let operation = preKeyOperationFactory.createForRegistration(future: future)
        Self.operationQueue.addOperation(operation)
        return promise
    }

    public func createPreKeysForProvisioning(
        aciIdentityKeyPair: ECKeyPair,
        pniIdentityKeyPair: ECKeyPair
    ) -> Promise<RegistrationPreKeyUploadBundles> {
        /// Note that we do not report a `refreshPreKeysDidSucceed, because this operation does not`
        /// generate one time prekeys, so we shouldn't mark the routine refresh as having been "checked".
        let (promise, future) = Promise<RegistrationPreKeyUploadBundles>.pending()
        let operation = preKeyOperationFactory.createForProvisioning(
            aciIdentityKeyPair: aciIdentityKeyPair,
            pniIdentityKeyPair: pniIdentityKeyPair,
            future: future
        )
        Self.operationQueue.addOperation(operation)
        return promise
    }

    public func finalizeRegistrationPreKeys(
        _ bundles: RegistrationPreKeyUploadBundles,
        uploadDidSucceed: Bool
    ) -> Promise<Void> {
        let (promise, future) = Promise<Void>.pending()
        let operation = preKeyOperationFactory.finalizeRegistrationPreKeys(
            bundles,
            uploadDidSucceed: uploadDidSucceed,
            future: future
        )
        Self.operationQueue.addOperation(operation)
        return promise
    }

    public func rotateOneTimePreKeysForRegistration(auth: ChatServiceAuth) -> Promise<Void> {
        let (aciPromise, aciFuture) = Promise<Void>.pending()
        let aciOperation = preKeyOperationFactory.rotateOneTimePreKeysForRegistration(
            identity: .aci,
            auth: auth,
            future: aciFuture,
            didSucceed: { [weak self] in self?.refreshPreKeysDidSucceed() }
        )
        let (pniPromise, pniFuture) = Promise<Void>.pending()
        let pniOperation = preKeyOperationFactory.rotateOneTimePreKeysForRegistration(
            identity: .pni,
            auth: auth,
            future: pniFuture,
            didSucceed: { [weak self] in self?.refreshPreKeysDidSucceed() }
        )
        Self.operationQueue.addOperations([aciOperation, pniOperation], waitUntilFinished: false)
        return Promise.when(fulfilled: [aciPromise, pniPromise])
    }

    public func legacy_createPreKeys(auth: ChatServiceAuth) -> Promise<Void> {
        let aciOp = preKeyOperationFactory.legacy_createPreKeysOperation(
            for: .aci,
            auth: auth,
            didSucceed: { [weak self] in self?.refreshPreKeysDidSucceed() }
        )
        let pniOp = preKeyOperationFactory.legacy_createPreKeysOperation(
            for: .pni,
            auth: auth,
            didSucceed: { [weak self] in self?.refreshPreKeysDidSucceed() }
        )
        return runPreKeyOperations([aciOp, pniOp])
    }

    public func createOrRotatePNIPreKeys(auth: ChatServiceAuth) -> Promise<Void> {
        let operation = preKeyOperationFactory.createOrRotatePNIPreKeysOperation(
            didSucceed: { [weak self] in self?.refreshPreKeysDidSucceed() }
        )
        return runPreKeyOperations([operation])
    }

    public func rotateSignedPreKeys() -> Promise<Void> {
        let aciOp = preKeyOperationFactory.rotateSignedPreKeyOperation(
            for: .aci,
            didSucceed: { [weak self] in self?.refreshPreKeysDidSucceed() }
        )
        let pniOp = preKeyOperationFactory.rotateSignedPreKeyOperation(
            for: .pni,
            didSucceed: { [weak self] in self?.refreshPreKeysDidSucceed() }
        )
        return runPreKeyOperations([aciOp, pniOp])
    }

    /// Refresh one-time pre-keys for the given identity, and optionally refresh
    /// the signed pre-key.
    /// TODO: callers of this method _feel_ like they actually want a rotation (forced) not
    /// a refresh (conditional). TBD.
   public func refreshOneTimePreKeys(
        forIdentity identity: OWSIdentity,
        alsoRefreshSignedPreKey shouldRefreshSignedPreKey: Bool
    ) {
        let refreshOperation = preKeyOperationFactory.refreshPreKeysOperation(
            for: identity,
            shouldRefreshOneTimePreKeys: true,
            shouldRefreshSignedPreKeys: shouldRefreshSignedPreKey,
            didSucceed: { [weak self] in self?.refreshPreKeysDidSucceed() }
        )

        Self.operationQueue.addOperation(refreshOperation)
    }

    private func runPreKeyOperations(_ operations: [Operation]) -> Promise<Void> {

        let (promise, future) = Promise<Void>.pending()

        DispatchQueue.global().async {
            Self.operationQueue.addOperations(operations, waitUntilFinished: true)

            let error = operations.compactMap({ ($0 as? OWSOperation)?.failingError }).first
            if let error {
                DispatchQueue.main.async {
                    future.reject(error)
                }
            } else {
                DispatchQueue.main.async {
                    future.resolve()
                }
            }
        }

        return promise
    }

    private class MessageProcessingOperation: OWSOperation {
        let messageProcessorWrapper: PreKey.Manager.Shims.MessageProcessor
        public init(messageProcessor: PreKey.Manager.Shims.MessageProcessor) {
            self.messageProcessorWrapper = messageProcessor
        }

        public override func run() {
            Logger.debug("")

            firstly(on: DispatchQueue.global()) {
                self.messageProcessorWrapper.fetchingAndProcessingCompletePromise()
            }.done { _ in
                Logger.verbose("Complete.")
                self.reportSuccess()
            }.catch { error in
                owsFailDebug("Error: \(error)")
                self.reportError(SSKUnretryableError.messageProcessingFailed)
            }
        }
    }
}

// MARK: - Debug UI

#if TESTABLE_BUILD

public extension PreKeyManagerImpl {

    func storeFakePreKeyUploadFailures(for identity: OWSIdentity, tx: DBWriteTransaction) {
        let store = protocolStoreManager.signalProtocolStore(for: identity).signedPreKeyStore
        let firstFailureDate = Date(timeIntervalSinceNow: -Constants.SignedPreKeyUpdateFailureMaxFailureDuration)
        store.setPrekeyUpdateFailureCount(
            Constants.MaxPrekeyUpdateFailureCount,
            firstFailureDate: firstFailureDate,
            tx: tx
        )
    }

    func checkPreKeysImmediately(tx: DBReadTransaction) {
        checkPreKeys(shouldThrottle: false, tx: tx)
    }
}

#endif
