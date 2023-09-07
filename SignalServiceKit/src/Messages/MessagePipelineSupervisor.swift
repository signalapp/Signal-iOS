//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

@objc(OWSMessagePipelineSupervisor)
public class MessagePipelineSupervisor: NSObject {

    // MARK: - Stored Properties

    private let lock = UnfairLock()
    private let pipelineStages = NSHashTable<MessageProcessingPipelineStage>.weakObjects()
    private var suspensions = Set<Suspension>()

    // MARK: - Lifecycle

    /// Initializes a MessagePipelineSupervisor
    ///   Only to be used by tests.
    @objc
    public override init() {
        super.init()

        SwiftSingletons.register(self)
    }

    // MARK: - Public

    /// Returns whether or not the message processing pipeline is/should be suspended. Thread-safe.
    @objc
    public var isMessageProcessingPermitted: Bool {
        if CurrentAppContext().shouldProcessIncomingMessages {
            return lock.withLock { suspensions.isEmpty }
        } else {
            return false
        }
    }

    public enum Suspension: Hashable {
        case nseWakingUpApp(suspensionId: UUID, payloadString: String)
        case pendingChangeNumber

        fileprivate var reasonString: String {
            switch self {
            case .nseWakingUpApp(_, let payloadString):
                return "Waking main app for \(payloadString)"
            case .pendingChangeNumber:
                return "Pending change number"
            }
        }
    }

    /// Invoking this method will ensure that all registered message processing stages are notified that they should
    /// suspend their activity. This suppression will persist until the returned handle is invalidated.
    /// Note: The caller *must* invalidate the returned handle; if it is deallocated without having been invalidated it will crash the app.
    public func suspendMessageProcessing(for suspension: Suspension) -> MessagePipelineSuspensionHandle {
        addSuspension(suspension)
        let handle = MessagePipelineSuspensionHandle {
            self.removeSuspension(suspension)
        }
        return handle
    }

    /// Invoking this method will ensure that all registered message processing stages are notified that they should
    /// suspend their activity. This suppression will persist until the suspension is explicitly lifted.
    /// For this reason calling this method is highly dangerous, and the variety that returns a handle is preferred where possible.
    public func suspendMessageProcessingWithoutHandle(for suspension: Suspension) {
        addSuspension(suspension)
    }

    public func unsuspendMessageProcessing(for suspension: Suspension) {
        removeSuspension(suspension)
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

    private func addSuspension(_ suspension: Suspension) {
        let (oldCount, updatedCount): (Int, Int) = lock.withLock {
            let oldCount = suspensions.count
            suspensions.insert(suspension)
            return (oldCount, suspensions.count)
        }
        if oldCount != updatedCount {
            Logger.info("Incremented suspension refcount to \(updatedCount) for reason: \(suspension.reasonString)")
            if updatedCount == 1 {
                notifyOfSuspensionStateChange()
            }
        } else {
            Logger.info("Already suspended for reason: \(suspension.reasonString)")
        }
    }

    private func removeSuspension(_ suspension: Suspension) {
        let (oldCount, updatedCount): (Int, Int) = lock.withLock {
            let oldCount = suspensions.count
            suspensions.remove(suspension)
            return (oldCount, suspensions.count)
        }
        if oldCount != updatedCount {
            Logger.info("Decremented suspension refcount to \(updatedCount) for reason: \(suspension.reasonString)")

            if updatedCount == 0 {
                notifyOfSuspensionStateChange()
            }
        } else {
            Logger.info("Was already not suspended, doing nothing for reason: \(suspension.reasonString)")
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
