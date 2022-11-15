//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc(OWSMessagePipelineSupervisor)
public class MessagePipelineSupervisor: NSObject {

    // MARK: - Stored Properties

    private let lock = UnfairLock()
    private let pipelineStages = NSHashTable<MessageProcessingPipelineStage>.weakObjects()
    private var suspensionCount = 0

    // MARK: - Lifecycle

    /// Constructs an instance of `MessagePipelineSupervisor` to be treated as a shared instance for the application.
    /// Should not be called more than once per app launch
    @objc
    public static func createStandardSupervisor() -> MessagePipelineSupervisor {
        self.init(isolated: false)
    }

    /// Initializes a MessagePipelineSupervisor
    /// - Parameter isolated: If set true, the returned instance is not configured to be a singleton.
    ///   Only to be used by tests.
    @objc
    required init(isolated: Bool = false) {
        super.init()
        assert(!isolated || CurrentAppContext().isRunningTests,
               "The isolated parameter may only be set in a test context")

        if !isolated {
            SwiftSingletons.register(self)
            configureDefaultSuspensions()
        }
    }

    // MARK: - Public

    /// Returns whether or not the message processing pipeline is/should be suspended. Thread-safe.
    @objc
    public var isMessageProcessingPermitted: Bool {
        if CurrentAppContext().shouldProcessIncomingMessages {
            return lock.withLock { (suspensionCount == 0) }
        } else {
            return false
        }
    }

    /// Invoking this method will ensure that all registered message processing stages are notified that they should
    /// suspend their activity. This suppression will persist until the returned handle is invalidated.
    /// Note: The caller *must* invalidate the returned handle.
    @objc
    public func suspendMessageProcessing(for reason: String) -> MessagePipelineSuspensionHandle {
        incrementSuspensionCount(for: reason)
        let handle = MessagePipelineSuspensionHandle {
            self.decrementSuspensionCount(for: "Handle invalidation: \(reason)")
        }
        return handle
    }

    /// Registers a message processing stage to receive updates on whether processing is permitted
    @objc(registerPipelineStage:)
    public func register(pipelineStage: MessageProcessingPipelineStage) {
        lock.withLock {
            pipelineStages.add(pipelineStage)
        }
    }

    /// Unregisters a message processing stage from receiving updates when suspension state changes
    @objc(unregisterPipelineStage:)
    public func unregister(pipelineStage: MessageProcessingPipelineStage) {
        lock.withLock {
            pipelineStages.remove(pipelineStage)
        }
    }

    // MARK: - Private

    private func incrementSuspensionCount(for reason: String) {
        let updatedCount: Int = lock.withLock {
            suspensionCount += 1
            return suspensionCount
        }
        Logger.info("Incremented suspension refcount to \(updatedCount) for reason: \(reason)")
        if updatedCount == 1 {
            notifyOfSuspensionStateChange()
        }
    }

    private func decrementSuspensionCount(for reason: String) {
        let updatedCount: Int = lock.withLock {
            suspensionCount -= 1
            return suspensionCount
        }
        Logger.info("Decremented suspension refcount to \(updatedCount) for reason: \(reason)")
        assert(updatedCount >= 0, "Suspension refcount dipped below zero")

        if updatedCount == 0 {
            notifyOfSuspensionStateChange()
        }
    }

    private func notifyOfSuspensionStateChange() {
        let isSuspended = !isMessageProcessingPermitted

        // Make a copy so we don't need to hold the lock while we call out
        let toNotify = lock.withLock { return Array(pipelineStages.allObjects) }
        Logger.debug("\(isSuspended ? "Suspending" : "Resuming") message processing...")

        toNotify.forEach { (stage) in
            if isSuspended {
                stage.supervisorDidSuspendMessageProcessing?(self)
            } else {
                stage.supervisorDidResumeMessageProcessing?(self)
            }
        }
    }

    private func configureDefaultSuspensions() {
        // By default, we want to make sure we're suspending message processing until
        // a UUID backfill task completes. Only do this if:
        // - We're in a context that will try processing messages
        // - We're not in a testing context. runNowOrWhenApp...Ready blocks never get invoked during tests,
        //   and this prevents a UUIDBackfillTask from ever starting.
        let shouldBackfillUUIDs = CurrentAppContext().shouldProcessIncomingMessages &&
                                  !CurrentAppContext().isRunningTests
        if shouldBackfillUUIDs {
            let uuidBackfillSuspension = suspendMessageProcessing(for: "UUID Backfill")
            AppReadiness.runNowOrWhenAppDidBecomeReadySync {
                firstly {
                    UUIDBackfillTask(
                        contactDiscoveryManager: self.contactDiscoveryManager,
                        databaseStorage: self.databaseStorage
                    ).perform()
                }.ensure(on: .global()) {
                    uuidBackfillSuspension.invalidate()
                }.cauterize()
            }
        }
    }
}

@objc(OWSMessagePipelineSuspensionHandle)
public class MessagePipelineSuspensionHandle: NSObject {
    private let lock = UnfairLock()
    private var invalidationClosure: (() -> Void)?

    fileprivate init(onInvalidate closure: @escaping () -> Void) {
        invalidationClosure = closure
    }

    deinit {
        assert(invalidationClosure == nil, "Handle was deallocated without an explicit invalidation")

        // For safety, perform the invalidation handle if we haven't done it yet:
        performOneshotInvalidation()
    }

    /// Invalidate the pipeline suspension. This must be invoked before the object is deallocated
    @objc
    public func invalidate() {
        // Why require an explicit invalidation and not just implicitly invalidate on -deinit?
        // There's a possibility that the handle gets captured in an autoreleasepool for an
        // indeterminate amount of time. By mandating explicit invalidation, we ensure that we
        // drop the handle when most appropriate.
        performOneshotInvalidation()
    }

    private func performOneshotInvalidation() {
        lock.withLock {
            invalidationClosure?()
            invalidationClosure = nil
        }
    }
}

@objc(OWSMessageProcessingPipelineStage)
public protocol MessageProcessingPipelineStage {
    /// Invoked on a registered pipeline stage whenever the supervisor requests suspension of message processing
    /// Not guaranteed to be invoked on a particular thread
    @objc
    optional func supervisorDidSuspendMessageProcessing(_ supervisor: MessagePipelineSupervisor)
    /// Invoked on a registered pipeline stage whenever the supervisor permits resumption of message processing
    /// Not guaranteed to be invoked on a particular thread
    @objc
    optional func supervisorDidResumeMessageProcessing(_ supervisor: MessagePipelineSupervisor)
}
