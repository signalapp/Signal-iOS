//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum BackgroundTaskState {
    case success
    case couldNotStart
    case expired
}

/// This class makes it easier and safer to use background tasks.
///
/// * Uses RAII (Resource Acquisition Is Initialization) pattern.
/// * Ensures completion block is called exactly once and on main thread,
///   to facilitate handling "background task timed out" case, for example.
/// * Ensures we properly handle the "background task could not be created"
///   case.
///
/// Usage:
///
/// * Use init to start a background task.
/// * Retain a strong reference to the OWSBackgroundTask during the "work".
/// * Clear all references to the OWSBackgroundTask when the work is done,
///   if possible.
@objc
public class OWSBackgroundTask: NSObject {
    private let label: String

    // TODO: Replace all of the below ivars with Mutex in Swift 6.
    private let lock = NSRecursiveLock()

    /// This property should only be accessed while holding `lock`.
    private var taskId: UInt64?

    /// This property should only be accessed while holding `lock`.
    private var completionBlock: (@MainActor @Sendable (BackgroundTaskState) -> Void)?

    // This could be a default param but objc is in the way for now.
    @objc
    public convenience init(label: String) {
        self.init(label: label, completionBlock: nil)
    }

    /// - Parameters:
    ///   - completionBlock: will be called exactly once on the main thread
    public init(label: String, completionBlock: (@MainActor @Sendable (BackgroundTaskState) -> Void)?) {
        owsAssertDebug(!label.isEmpty)

        self.label = label
        self.completionBlock = completionBlock

        super.init()

        start()
    }

    deinit {
        end()
    }

    private func start() {
        taskId = OWSBackgroundTaskManager.shared.addTaskWithExpirationBlock { [weak self] in
            DispatchMainThreadSafe {
                guard let self else {
                    return
                }

                // Make a local copy of completionBlock to ensure that it is called
                // exactly once.
                var completionBlock: (@MainActor @Sendable (BackgroundTaskState) -> Void)?
                self.lock.withLock {
                    guard self.taskId != nil else {
                        return
                    }
                    Logger.info("\(self.label) background task expired.")
                    self.taskId = nil

                    completionBlock = self.completionBlock
                    self.completionBlock = nil
                }
                if let completionBlock {
                    completionBlock(.expired)
                }
            }
        }

        // If a background task could not be begun, call the completion block.
        if taskId == nil {
            // Make a local copy of completionBlock to ensure that it is called
            // exactly once.
            var completionBlock: (@MainActor @Sendable (BackgroundTaskState) -> Void)?
            lock.withLock {
                completionBlock = self.completionBlock
                self.completionBlock = nil
            }
            if let completionBlock {
                DispatchMainThreadSafe {
                    completionBlock(.couldNotStart)
                }
            }
        }
    }

    public func end() {
        // Make a local copy of this state, since this method is called by `dealloc`.
        var completionBlock: (@MainActor @Sendable (BackgroundTaskState) -> Void)?

        lock.withLock {
            guard let taskId = self.taskId else {
                return
            }
            OWSBackgroundTaskManager.shared.removeTask(taskId)
            self.taskId = nil

            completionBlock = self.completionBlock
            self.completionBlock = nil
        }

        // endBackgroundTask must be called on the main thread.
        DispatchMainThreadSafe {
            if let completionBlock {
                completionBlock(.success)
            }
        }
    }
}

public class OWSBackgroundTaskManager {
    public static let shared = {
        if Thread.isMainThread {
            return OWSBackgroundTaskManager()
        } else {
            return DispatchQueue.main.sync {
                OWSBackgroundTaskManager()
            }
        }
    }()

    /// We use this timer to provide continuity and reduce churn,
    /// so that if one OWSBackgroundTask ends right before another
    /// begins, we use a single uninterrupted background task that
    /// spans their lifetimes.
    ///
    /// This property should only be accessed on the main thread.
    private var continuityTimer: Timer?

    // TODO: Replace all of the below ivars with Mutex in Swift 6.
    private let lock = NSRecursiveLock()

    /// This property should only be accessed while holding `lock`.
    private var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid

    /// This property should only be accessed while holding `lock`.
    private var expirationMap: [UInt64: @Sendable () -> Void] = [:]

    /// This property should only be accessed while holding `lock`.
    private var idCounter: UInt64 = 0

    /// Note that this flag is set a little early in "will resign active".
    ///
    /// This property should only be accessed while holding `lock`.
    private var isAppActive: Bool = CurrentAppContext().isMainAppAndActive

    /// This property should only be accessed while holding `lock`.
    private var isMaintainingContinuity: Bool = false

    /// This property should only be accessed while holding `lock`.
    private var didBecomeActiveObserver: (any NSObjectProtocol)?

    /// This property should only be accessed while holding `lock`.
    private var willResignActiveObserver: (any NSObjectProtocol)?

    /// Due to `isAppActive` should only be executed from the main thread.
    private init() {
        AssertIsOnMainThread()
        SwiftSingletons.register(self)
    }

    deinit {
        lock.withLock {
            self.clearObservers()
        }
    }

    /// Do not call unless `lock` is held.
    private func clearObservers() {
        if let didBecomeActiveObserver = self.didBecomeActiveObserver {
            NotificationCenter.default.removeObserver(didBecomeActiveObserver, name: .OWSApplicationDidBecomeActive, object: nil)
            self.didBecomeActiveObserver = nil
        }
        if let willResignActiveObserver = self.willResignActiveObserver {
            NotificationCenter.default.removeObserver(willResignActiveObserver, name: .OWSApplicationWillResignActive, object: nil)
            self.willResignActiveObserver = nil
        }
    }

    public func observeNotifications() {
        guard CurrentAppContext().isMainApp else {
            return
        }

        lock.withLock {
            self.clearObservers()

            self.didBecomeActiveObserver = NotificationCenter.default.addObserver(forName: .OWSApplicationDidBecomeActive, object: nil, queue: nil) { [weak self] _ in
                AssertIsOnMainThread()

                guard let self else {
                    return
                }

                self.lock.withLock {
                    self.isAppActive = true
                    self.ensureBackgroundTaskState()
                }
            }
            self.willResignActiveObserver = NotificationCenter.default.addObserver(forName: .OWSApplicationWillResignActive, object: nil, queue: nil) { [weak self] _ in
                AssertIsOnMainThread()

                guard let self else {
                    return
                }

                self.lock.withLock {
                    self.isAppActive = false
                    self.ensureBackgroundTaskState()
                }
            }
        }
    }

    /// This method registers a new task with this manager.  We only bother
    /// requesting a background task from iOS if the app is inactive (or about
    /// to become inactive), so this will often not start a background task.
    /// 
    /// - Returns nil if adding this task _should have_ started a
    /// background task, but the background task couldn't be begun.
    /// In that case expirationBlock will not be called.
    fileprivate func addTaskWithExpirationBlock(_ expirationBlock: @escaping @Sendable () -> Void) -> UInt64? {
        lock.withLock {
            self.idCounter += 1
            let taskId = self.idCounter
            self.expirationMap[taskId] = expirationBlock

            guard self.ensureBackgroundTaskState() else {
                self.expirationMap.removeValue(forKey: taskId)
                return nil
            }
            return taskId
        }
    }

    fileprivate func removeTask(_ taskId: UInt64) {
        var shouldMaintainContinuity = false

        lock.withLock {
            let removedBlock = self.expirationMap.removeValue(forKey: taskId)
            owsAssertDebug(removedBlock != nil)

            // If expirationMap has just been emptied, try to maintain continuity.
            // See: scheduleCleanupOfContinuity().
            shouldMaintainContinuity = self.expirationMap.isEmpty
            if shouldMaintainContinuity {
                self.isMaintainingContinuity = true
            }

            self.ensureBackgroundTaskState()
        }

        if shouldMaintainContinuity {
            self.scheduleCleanupOfContinuity()
        }
    }

    /// Begins or end a background task if necessary.
    @discardableResult
    private func ensureBackgroundTaskState() -> Bool {
        guard CurrentAppContext().isMainApp else {
            // We can't create background tasks in the SAE, but pretend that we succeeded.
            return true
        }

        return lock.withLock {
            // We only want to have a background task if we are:
            // a) "not active" AND
            // b1) there is one or more active instance of OWSBackgroundTask OR...
            // b2) ...there _was_ an active instance recently.
            let shouldHaveBackgroundTask = (!self.isAppActive && (!self.expirationMap.isEmpty || self.isMaintainingContinuity))
            let hasBackgroundTask = self.backgroundTaskId != .invalid

            if shouldHaveBackgroundTask == hasBackgroundTask {
                // Current state is correct.
                return true
            } else if shouldHaveBackgroundTask {
                Logger.info("Starting background task.")
                return self.startBackgroundTask()
            } else {
                // Need to end background task.
                Logger.info("Ending background task.")
                CurrentAppContext().endBackgroundTask(self.backgroundTaskId)
                self.backgroundTaskId = .invalid
                return true
            }
        }
    }

    /// - Returns false if the background task cannot be begun.
    private func startBackgroundTask() -> Bool {
        owsAssertDebug(CurrentAppContext().isMainApp)

        return lock.withLock {
            owsAssertDebug(self.backgroundTaskId == .invalid)

            self.backgroundTaskId = CurrentAppContext().beginBackgroundTask {
                // Supposedly [UIApplication beginBackgroundTaskWithExpirationHandler]'s handler
                // will always be called on the main thread, but in practice we've observed
                // otherwise.
                //
                // See:
                // https://developer.apple.com/documentation/uikit/uiapplication/1623031-beginbackgroundtaskwithexpiratio)
                AssertIsOnMainThread()

                self.backgroundTaskExpired()
            }

            // If the background task could not begin, return NO to indicate that.
            guard self.backgroundTaskId != .invalid else {
                Logger.warn("background task could not be started.")
                return false
            }
            return true
        }
    }

    private func backgroundTaskExpired() {
        let (backgroundTaskId, expirationMap) = lock.withLock {
            let backgroundTaskId = self.backgroundTaskId
            self.backgroundTaskId = .invalid

            let expirationMap = self.expirationMap
            self.expirationMap.removeAll()

            return (backgroundTaskId, expirationMap)
        }

        // Supposedly [UIApplication beginBackgroundTaskWithExpirationHandler]'s handler
        // will always be called on the main thread, but in practice we've observed
        // otherwise.  OWSBackgroundTask's API guarantees that completionBlock will
        // always be called on the main thread, so we use DispatchSyncMainThreadSafe()
        // to ensure that.  We thereby ensure that we don't end the background task
        // until all of the completion blocks have completed.
        DispatchSyncMainThreadSafe {
            for expirationBlock in expirationMap.values {
                expirationBlock()
            }
            if backgroundTaskId != .invalid {
                // Apparently we need to "end" even expired background tasks.
                CurrentAppContext().endBackgroundTask(backgroundTaskId)
            }
        }
    }

    private func scheduleCleanupOfContinuity() {
        // This timer will ensure that we keep the background task active (if necessary)
        // for an extra fraction of a second to provide continuity between tasks.
        // This makes it easier and safer to use background tasks, since most code
        // should be able to ensure background tasks by "narrowly" wrapping
        // their core logic with a OWSBackgroundTask and not worrying about "hand off"
        // between OWSBackgroundTasks.
        DispatchQueue.main.async {
            self.continuityTimer?.invalidate()
            self.continuityTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false, block: { [weak self] timer in
                AssertIsOnMainThread()

                guard let self else {
                    timer.invalidate()
                    return
                }

                self.continuityTimer?.invalidate()
                self.continuityTimer = nil

                self.lock.withLock {
                    self.isMaintainingContinuity = false
                    self.ensureBackgroundTaskState()
                }
            })
        }
    }
}
