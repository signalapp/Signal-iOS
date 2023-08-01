//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol PreKeyManager {
    func isAppLockedDueToPreKeyUpdateFailures(tx: DBReadTransaction) -> Bool

    func refreshPreKeysDidSucceed()

    func checkPreKeysIfNecessary(tx: DBReadTransaction)

    func createPreKeys(auth: ChatServiceAuth) -> Promise<Void>

    func createPreKeys(identity: OWSIdentity) -> Promise<Void>

    func rotateSignedPreKeys() -> Promise<Void>

    func refreshOneTimePreKeys(
        forIdentity identity: OWSIdentity,
        alsoRefreshSignedPreKey shouldRefreshSignedPreKey: Bool
    )
}

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

    private let accountManager: PreKeyManagerImpl.Shims.TSAccountManager
    private let messageProcessor: PreKeyManagerImpl.Shims.MessageProcessor
    private let preKeyOperationFactory: PreKeyManagerImpl.Shims.PreKeyOperationFactory
    private let protocolStoreManager: SignalProtocolStoreManager

    init(
        accountManager: PreKeyManagerImpl.Shims.TSAccountManager,
        messageProcessor: PreKeyManagerImpl.Shims.MessageProcessor,
        preKeyOperationFactory: PreKeyManagerImpl.Shims.PreKeyOperationFactory,
        protocolStoreManager: SignalProtocolStoreManager
    ) {
        self.accountManager = accountManager
        self.messageProcessor = messageProcessor
        self.preKeyOperationFactory = preKeyOperationFactory
        self.protocolStoreManager = protocolStoreManager
    }

    private var lastPreKeyCheckTimestamp: Date?

    private func needsSignedPreKeyRotation(identity: OWSIdentity, tx: DBReadTransaction) -> Bool {
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

    public func isAppLockedDueToPreKeyUpdateFailures(tx: DBReadTransaction) -> Bool {
        return
            needsSignedPreKeyRotation(identity: .aci, tx: tx)
            || needsSignedPreKeyRotation(identity: .pni, tx: tx)
    }

    public func refreshPreKeysDidSucceed() {
        lastPreKeyCheckTimestamp = Date()
    }

    public func checkPreKeysIfNecessary(tx: DBReadTransaction) {
        checkPreKeys(shouldThrottle: true, tx: tx)
    }

    fileprivate func checkPreKeys(shouldThrottle: Bool, tx: DBReadTransaction) {
        guard
            CurrentAppContext().isMainAppAndActive,
            accountManager.isRegisteredAndReady(tx: tx)
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
            var refreshOperation: OWSOperation?
            if shouldRefreshOneTimePrekeys {
                let refreshOp = preKeyOperationFactory.refreshPreKeysOperation(
                    for: identity,
                    shouldRefreshSignedPreKey: true
                )
                refreshOp.addDependency(messageProcessingOperation)
                operations.append(refreshOp)
                refreshOperation = refreshOp
            }

            // Order matters here - if we rotated *before* refreshing, we'd risk uploading
            // two SPK's in a row since RefreshPreKeysOperation can also upload a new SPK.
            let rotationOperation = preKeyOperationFactory.rotateSignedPreKeyOperation(
                for: identity,
                shouldSkipIfRecent: shouldThrottle
            )

            rotationOperation.addDependency(messageProcessingOperation)
            if let refreshOperation {
                rotationOperation.addDependency(refreshOperation)
            }
            operations.append(rotationOperation)
        }

        addOperation(for: .aci)
        addOperation(for: .pni)

        Self.operationQueue.addOperations(operations, waitUntilFinished: false)
    }

    public func createPreKeys(auth: ChatServiceAuth) -> Promise<Void> {
        let aciOp = preKeyOperationFactory.createPreKeysOperation(for: .aci, auth: auth)
        let pniOp = preKeyOperationFactory.createPreKeysOperation(for: .pni, auth: auth)
        return runPreKeyOperations([aciOp, pniOp])
    }

    public func createPreKeys(identity: OWSIdentity) -> Promise<Void> {
        let operation = preKeyOperationFactory.createPreKeysOperation(for: identity, auth: .implicit())
        return runPreKeyOperations([operation])
    }

    public func rotateSignedPreKeys() -> Promise<Void> {
        let aciOp = preKeyOperationFactory.rotateSignedPreKeyOperation(for: .aci, shouldSkipIfRecent: false)
        let pniOp = preKeyOperationFactory.rotateSignedPreKeyOperation(for: .pni, shouldSkipIfRecent: false)
        return runPreKeyOperations([aciOp, pniOp])
    }

    /// Refresh one-time pre-keys for the given identity, and optionally refresh
    /// the signed pre-key.
   public func refreshOneTimePreKeys(
        forIdentity identity: OWSIdentity,
        alsoRefreshSignedPreKey shouldRefreshSignedPreKey: Bool
    ) {
        let refreshOperation = preKeyOperationFactory.refreshPreKeysOperation(
            for: identity,
            shouldRefreshSignedPreKey: shouldRefreshSignedPreKey
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
        let messageProcessorWrapper: PreKeyManagerImpl.Shims.MessageProcessor
        public init(messageProcessor: PreKeyManagerImpl.Shims.MessageProcessor) {
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

extension PreKeyManagerImpl {
    public enum Shims {
        public typealias TSAccountManager = _PreKeyManager_TSAccountManagerShim
        public typealias MessageProcessor = _PreKeyManager_MessageProcessorShim
        public typealias PreKeyOperationFactory = _PreKeyManager_PreKeyOperationFactoryShims
    }

    public enum Wrappers {
        public typealias TSAccountManager = _PreKeyManager_TSAccountManagerWrapper
        public typealias MessageProcessor = _PreKeyManager_MessageProcessorWrapper
        public typealias LegacyPreKeyOperationFactory = _PreKeyManager_LegacyPreKeyOperationFactoryWrapper
        public typealias PreKeyOperationFactory = _PreKeyManager_PreKeyOperationFactoryWrapper
    }
}

// MARK: - AccountManager

public protocol _PreKeyManager_TSAccountManagerShim {
    func isRegisteredAndReady(tx: DBReadTransaction) -> Bool
}

public class _PreKeyManager_TSAccountManagerWrapper: PreKeyManagerImpl.Shims.TSAccountManager {
    private let accountManager: TSAccountManager
    public init(_ accountManager: TSAccountManager) { self.accountManager = accountManager }

    public func isRegisteredAndReady(tx: DBReadTransaction) -> Bool {
        return accountManager.isRegisteredAndReady(transaction: SDSDB.shimOnlyBridge(tx))
    }
}

// MARK: - MessageProcessor

public protocol _PreKeyManager_MessageProcessorShim {
    func fetchingAndProcessingCompletePromise() -> Promise<Void>
}

public struct _PreKeyManager_MessageProcessorWrapper: PreKeyManagerImpl.Shims.MessageProcessor {
    private let messageProcessor: MessageProcessor
    public init(messageProcessor: MessageProcessor) {
        self.messageProcessor = messageProcessor
    }

    public func fetchingAndProcessingCompletePromise() -> Promise<Void> {
        messageProcessor.fetchingAndProcessingCompletePromise()
    }
}

// MARK: - PreKeyOperationFactory

public protocol _PreKeyManager_PreKeyOperationFactoryShims {
    func rotateSignedPreKeyOperation(for identity: OWSIdentity, shouldSkipIfRecent: Bool) -> OWSOperation
    func createPreKeysOperation(for identity: OWSIdentity, auth: ChatServiceAuth) -> OWSOperation
    func refreshPreKeysOperation(for identity: OWSIdentity, shouldRefreshSignedPreKey: Bool) -> OWSOperation
}

public struct _PreKeyManager_LegacyPreKeyOperationFactoryWrapper: PreKeyManagerImpl.Shims.PreKeyOperationFactory {
    public func rotateSignedPreKeyOperation(for identity: OWSIdentity, shouldSkipIfRecent: Bool) -> OWSOperation {
        RotateSignedPreKeyOperation(for: identity, shouldSkipIfRecent: shouldSkipIfRecent)
    }

    public func createPreKeysOperation(for identity: OWSIdentity, auth: ChatServiceAuth) -> OWSOperation {
        CreatePreKeysOperation(for: identity, auth: auth)
    }

    public func refreshPreKeysOperation(for identity: OWSIdentity, shouldRefreshSignedPreKey: Bool) -> OWSOperation {
        RefreshPreKeysOperation(for: identity, shouldRefreshSignedPreKey: shouldRefreshSignedPreKey)
    }
}

public struct _PreKeyManager_PreKeyOperationFactoryWrapper: PreKeyManagerImpl.Shims.PreKeyOperationFactory {
    private let context: PreKeyTask.Context
    init(context: PreKeyTask.Context) {
        self.context = context
    }

    public func rotateSignedPreKeyOperation(for identity: OWSIdentity, shouldSkipIfRecent: Bool) -> OWSOperation {
        PreKeyOperation(
            for: identity,
            action: .refresh([.signedPreKey], forceRefresh: !shouldSkipIfRecent),
            context: context
        )
    }

    public func createPreKeysOperation(for identity: OWSIdentity, auth: ChatServiceAuth) -> OWSOperation {
        PreKeyOperation(
            for: identity,
            action: .create([.oneTimePreKey, .signedPreKey]),
            auth: auth,
            context: context
        )
    }

    public func refreshPreKeysOperation(for identity: OWSIdentity, shouldRefreshSignedPreKey: Bool) -> OWSOperation {
        var target: PreKey.Operation.Target = .oneTimePreKey
        if shouldRefreshSignedPreKey {
            target.insert(.signedPreKey)
        }

        return PreKeyOperation(
            for: identity,
            action: .refresh([.oneTimePreKey, .signedPreKey], forceRefresh: false),
            context: context
        )
    }
}

// MARK: - Default Mock PreKeymanager

internal class MockPreKeyManager: PreKeyManager {
    func isAppLockedDueToPreKeyUpdateFailures(tx: SignalServiceKit.DBReadTransaction) -> Bool { false }
    func refreshPreKeysDidSucceed() { }
    func checkPreKeysIfNecessary(tx: SignalServiceKit.DBReadTransaction) { }
    func createPreKeys(auth: SignalServiceKit.ChatServiceAuth) -> SignalCoreKit.Promise<Void> { Promise.value(()) }
    func createPreKeys(identity: OWSIdentity) -> SignalCoreKit.Promise<Void> { Promise.value(()) }
    func rotateSignedPreKeys() -> SignalCoreKit.Promise<Void> { Promise.value(()) }
    func refreshOneTimePreKeys(forIdentity identity: OWSIdentity, alsoRefreshSignedPreKey shouldRefreshSignedPreKey: Bool) { }
}
