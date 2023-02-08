//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

@objc
public class PendingTasks: NSObject {

    fileprivate let label: String

    private let pendingTasks = AtomicDictionary<UInt, PendingTask>()

    @objc
    public required init(label: String) {
        self.label = label
    }

    public func pendingTasksPromise() -> Promise<Void> {
        // This promise blocks on all pending tasks already in flight,
        // but will not block on new tasks added after this promise
        // is created.
        let label = self.label
        if DebugFlags.internalLogging {
            Logger.info("Waiting \(label).")
        }
        let promises = pendingTasks.allValues.map { $0.promise }
        return firstly(on: DispatchQueue.global()) {
            Promise.when(resolved: promises).asVoid()
        }.map(on: DispatchQueue.global()) {
            if DebugFlags.internalLogging {
                Logger.info("Complete \(label) (memoryUsage: \(LocalDevice.memoryUsageString)).")
            }
        }
    }

    @objc
    public func buildPendingTask(label: String) -> PendingTask {
        let pendingTask = PendingTask(pendingTasks: self, label: label)
        pendingTasks[pendingTask.id] = pendingTask
        return pendingTask
    }

    fileprivate func completePendingTask(_ pendingTask: PendingTask) {
        guard pendingTask.isComplete.tryToSetFlag() else {
            return
        }
        let wasRemoved = nil != pendingTasks.removeValue(forKey: pendingTask.id)
        owsAssertDebug(wasRemoved)
        if DebugFlags.internalLogging {
            Logger.info("Completed: \(self.label).\(pendingTask.label) (memoryUsage: \(LocalDevice.memoryUsageString))")
        }
        pendingTask.future.resolve(())
    }
}

// MARK: -

@objc
public class PendingTask: NSObject {
    private static let idCounter = AtomicUInt()
    fileprivate let id = PendingTask.idCounter.increment()

    private weak var pendingTasks: PendingTasks?

    fileprivate let label: String

    public let promise: Promise<Void>
    fileprivate let future: Future<Void>

    let isComplete = AtomicBool(false)

    init(pendingTasks: PendingTasks, label: String) {
        self.pendingTasks = pendingTasks
        self.label = label

        let (promise, future) = Promise<Void>.pending()
        self.promise = promise
        self.future = future
    }

    deinit {
        owsAssertDebug(isComplete.get())
        complete()
    }

    @objc
    public func complete() {
        guard let pendingTasks = pendingTasks else {
            owsFailDebug("Missing pendingTasks.")
            return
        }
        pendingTasks.completePendingTask(self)
    }
}
