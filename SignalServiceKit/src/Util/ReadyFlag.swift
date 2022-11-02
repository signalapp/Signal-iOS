//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// We often want to enqueue work that should only be performed
// once a certain milestone is reached. e.g. when the app
// "becomes ready" or when the user's account is "registered
// and ready", etc.
//
// This class provides the following functionality:
//
// * A boolean flag whose value can be consulted from any thread.
// * "Will become ready" and "did become ready" blocks that are
//   performed immediately if the flag is already set or later
//   when the flag is set.
// * Additionally, there's support for a "polite" flavor of "did
//   become ready" block which are performed with slight delays
//   to avoid a stampede which could block the main thread. One
//   of the risks there is 0x8badf00d crashes.
// * The flag can be used in various "queue modes". "App readiness"
//   blocks should be enqueued and performed on the main thread.
//   Other flags will want to do their work off the main thread.
@objc
public class ReadyFlag: NSObject {

    private let unfairLock = UnfairLock()

    public typealias ReadyBlock = () -> Void
    public typealias Priority = Int

    private struct ReadyTask {
        let label: String?
        let priority: Priority
        let block: ReadyBlock

        var displayLabel: String {
            label ?? "unknown"
        }

        static func sort(_ tasks: [ReadyTask]) -> [ReadyTask] {
            tasks.sorted { (left, right) -> Bool in
                // TODO: Verify correctness.
                left.priority <= right.priority
            }
        }
    }

    private static let defaultPriority: Priority = 0

    private let name: String

    private static let blockLogDuration: TimeInterval = 0.01
    private static let groupLogDuration: TimeInterval = 0.1

    // This property should only be set with unfairLock.
    // It can be read from any queue.
    private let flag = AtomicBool(false)

    // This property should only be accessed with unfairLock.
    private var willBecomeReadyTasks = [ReadyTask]()

    // This property should only be accessed with unfairLock.
    private var didBecomeReadySyncTasks = [ReadyTask]()

    // This property should only be accessed with unfairLock.
    private var didBecomeReadyAsyncTasks = [ReadyTask]()

    @objc
    public required init(name: String) {
        self.name = name
    }

    @objc
    public var isSet: Bool {
        flag.get()
    }

    public func runNowOrWhenWillBecomeReady(_ readyBlock: @escaping ReadyBlock,
                                            label: String? = nil,
                                            priority: Priority? = nil) {
        AssertIsOnMainThread()

        let priority = priority ?? Self.defaultPriority
        let task = ReadyTask(label: label, priority: priority, block: readyBlock)

        let didEnqueue: Bool = {
            unfairLock.withLock {
                guard !isSet else {
                    return false
                }
                willBecomeReadyTasks.append(task)
                return true
            }
        }()

        if !didEnqueue {
            // We perform the block outside unfairLock to avoid deadlock.
            BenchManager.bench(title: self.name + ".willBecomeReady " + task.displayLabel,
                               logIfLongerThan: Self.blockLogDuration,
                               logInProduction: true) {
                autoreleasepool {
                    task.block()
                }
            }
        }
    }

    public func runNowOrWhenDidBecomeReadySync(_ readyBlock: @escaping ReadyBlock,
                                               label: String? = nil,
                                               priority: Priority? = nil) {
        AssertIsOnMainThread()

        let priority = priority ?? Self.defaultPriority
        let task = ReadyTask(label: label, priority: priority, block: readyBlock)

        let didEnqueue: Bool = {
            unfairLock.withLock {
                guard !isSet else {
                    return false
                }
                didBecomeReadySyncTasks.append(task)
                return true
            }
        }()

        if !didEnqueue {
            // We perform the block outside unfairLock to avoid deadlock.
            BenchManager.bench(title: self.name + ".didBecomeReady " + task.displayLabel,
                               logIfLongerThan: Self.blockLogDuration,
                               logInProduction: true) {
                autoreleasepool {
                    task.block()
                }
            }
        }
    }

    public func runNowOrWhenDidBecomeReadyAsync(_ readyBlock: @escaping ReadyBlock,
                                                label: String? = nil,
                                                priority: Priority? = nil) {
        AssertIsOnMainThread()

        let priority = priority ?? Self.defaultPriority
        let task = ReadyTask(label: label, priority: priority, block: readyBlock)

        let didEnqueue: Bool = {
            unfairLock.withLock {
                guard !isSet else {
                    return false
                }
                didBecomeReadyAsyncTasks.append(task)
                return true
            }
        }()

        if !didEnqueue {
            // We perform the block outside unfairLock to avoid deadlock.
            //
            // Always perform async blocks async.
            DispatchQueue.main.async { () -> Void in
                BenchManager.bench(title: self.name + ".didBecomeReadyPolite " + task.displayLabel,
                                   logIfLongerThan: Self.blockLogDuration,
                                   logInProduction: true) {
                    autoreleasepool {
                        task.block()
                    }
                }
            }
        }
    }

    @objc
    public func setIsReady() {
        AssertIsOnMainThread()

        guard let tasksToPerform = tryToSetFlag() else {
            return
        }

        let willBecomeReadyTasks = ReadyTask.sort(tasksToPerform.willBecomeReadyTasks)
        let didBecomeReadySyncTasks = ReadyTask.sort(tasksToPerform.didBecomeReadySyncTasks)
        let didBecomeReadyAsyncTasks = ReadyTask.sort(tasksToPerform.didBecomeReadyAsyncTasks)

        // We bench the blocks individually and as a group.
        BenchManager.bench(title: self.name + ".willBecomeReady group",
                           logIfLongerThan: Self.groupLogDuration,
                           logInProduction: true) {
            for task in willBecomeReadyTasks {
                BenchManager.bench(title: self.name + ".willBecomeReady " + task.displayLabel,
                                   logIfLongerThan: Self.blockLogDuration,
                                   logInProduction: true) {
                    autoreleasepool {
                        task.block()
                    }
                }
            }
        }

        BenchManager.bench(title: self.name + ".didBecomeReady group",
                           logIfLongerThan: Self.groupLogDuration,
                           logInProduction: true) {
            for task in didBecomeReadySyncTasks {
                BenchManager.bench(title: self.name + ".didBecomeReady " + task.displayLabel,
                                   logIfLongerThan: Self.blockLogDuration,
                                   logInProduction: true) {
                    autoreleasepool {
                        task.block()
                    }
                }
            }
        }

        self.performDidBecomeReadyAsyncTasks(didBecomeReadyAsyncTasks)
    }

    private struct TasksToPerform {
        let willBecomeReadyTasks: [ReadyTask]
        let didBecomeReadySyncTasks: [ReadyTask]
        let didBecomeReadyAsyncTasks: [ReadyTask]
    }

    private func tryToSetFlag() -> TasksToPerform? {
        unfairLock.withLock {
            guard flag.tryToSetFlag() else {
                // We can only set the flag once.  If it's already set,
                // ensure that
                owsAssertDebug(willBecomeReadyTasks.isEmpty)
                owsAssertDebug(didBecomeReadySyncTasks.isEmpty)
                owsAssertDebug(didBecomeReadyAsyncTasks.isEmpty)
                return nil
            }

            let tasksToPerform = TasksToPerform(willBecomeReadyTasks: self.willBecomeReadyTasks,
                                                didBecomeReadySyncTasks: self.didBecomeReadySyncTasks,
                                                didBecomeReadyAsyncTasks: self.didBecomeReadyAsyncTasks)
            self.willBecomeReadyTasks = []
            self.didBecomeReadySyncTasks = []
            self.didBecomeReadyAsyncTasks = []
            return tasksToPerform
        }
    }

    private func performDidBecomeReadyAsyncTasks(_ tasks: [ReadyTask]) {
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.025) { [weak self] in
            guard let self = self else {
                return
            }
            guard let task = tasks.first else {
                return
            }
            BenchManager.bench(title: self.name + ".didBecomeReadyPolite " + task.displayLabel,
                               logIfLongerThan: Self.blockLogDuration,
                               logInProduction: true,
                               block: task.block)

            let remainder = Array(tasks.suffix(from: 1))
            self.performDidBecomeReadyAsyncTasks(remainder)
        }
    }
}
