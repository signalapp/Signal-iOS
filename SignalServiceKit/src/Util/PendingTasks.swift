//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalCoreKit

@objc
public class PendingTasks: NSObject {
    private let pendingTasks = AtomicDictionary<UInt, PendingTask>()

    public func pendingTasksPromise() -> Promise<Void> {
        // This promise blocks on all pending tasks already in flight,
        // but will not block on new tasks added after this promise
        // is created.
        let promises = pendingTasks.allValues.map { $0.promise }
        return Promise.when(resolved: promises).asVoid()
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
            Logger.info("---- Completed: \(pendingTask.label)")
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
