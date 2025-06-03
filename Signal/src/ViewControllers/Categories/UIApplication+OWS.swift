//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import UIKit

extension UIApplication {
    var frontmostViewControllerIgnoringAlerts: UIViewController? {
        guard let window = CurrentAppContext().mainWindow else {
            return nil
        }
        return window.findFrontmostViewController(ignoringAlerts: true)
    }

    @objc
    var frontmostViewController: UIViewController? {
        guard let window = CurrentAppContext().mainWindow else {
            return nil
        }
        return window.findFrontmostViewController(ignoringAlerts: false)
    }

    func openSystemSettings() {
        open(URL(string: UIApplication.openSettingsURLString)!, options: [:])
    }

    /// Wraps async blocks in a `beginBackgroundTask` task.
    ///
    /// The behavior is as follows:
    ///
    ///   acquireBackgroundTask()
    ///   await backgroundBlock()
    ///   await completionHandler()
    ///   releaseBackgroundTask()
    ///
    /// - The Task running `backgroundBlock` is canceled if the background task
    /// expires or is manually interrupted by the caller. In these cases,
    /// `backgroundBlock` should return quickly.
    ///
    /// - The `completionHandler` is run when `backgroundBlock` finishes. It
    /// should execute quickly.
    ///
    /// - The `completionHandler` runs STRICTLY AFTER `backgroundBlock`.
    ///
    /// The background task isn't released until after both blocks have run to
    /// completion. If either block takes too much time, the OS will terminate
    /// the app for failing to release its background task. (This API could
    /// release its background task prematurely, but that would cause the app to
    /// suspend too early, risking other problems such as dead10cc crashes. If
    /// the blocks are too slow, make them faster.)
    ///
    /// As of iOS 18, we have about 5 seconds to handle an expiration. This is
    /// enough time to tear down ongoing work, but it's not enough time to
    /// reliably complete roundtrip network requests.
    ///
    /// - Parameter backgroundBlock: The operation that should be performed in
    /// the background. This block is always executed.
    ///
    /// - Parameter completionHandler: The operation that should be performed
    /// after the background operation finishes. This block is performed before
    /// the app suspends.
    ///
    /// - Returns: A `BackgroundTaskHandle` that can interrupt this operation.
    @MainActor
    func beginBackgroundTask(
        backgroundBlock: @escaping () async -> Void,
        completionHandler: @escaping (BackgroundTaskHandle.Result) async -> Void,
    ) -> BackgroundTaskHandle {
        let handle = BackgroundTaskHandle(application: self)
        let taskIdentifier = self.beginBackgroundTask(expirationHandler: {
            handle.expire()
        })
        handle.start(
            taskIdentifier: taskIdentifier,
            operationTask: Task { await backgroundBlock() },
            completionHandler: completionHandler,
        )
        return handle
    }
}

extension UIWindow {
    func findFrontmostViewController(ignoringAlerts: Bool) -> UIViewController? {
        guard let viewController = self.rootViewController else {
            owsFailDebug("Missing root view controller.")
            return nil
        }
        return viewController.findFrontmostViewController(ignoringAlerts: ignoringAlerts)
    }
}

struct BackgroundTaskHandle {
    enum Result {
        case interrupted
        case expired
        case finished
    }

    private enum State {
        case initial
        case running(taskIdentifier: UIBackgroundTaskIdentifier, operationTask: Task<Void, Never>, completionHandler: (Result) async -> Void)
        case interrupted
        case expired
        case terminal
    }

    private let application: UIApplication
    private let state: AtomicValue<State>

    fileprivate init(application: UIApplication) {
        self.application = application
        self.state = AtomicValue(.initial, lock: .init())
    }

    fileprivate func start(taskIdentifier: UIBackgroundTaskIdentifier, operationTask: Task<Void, Never>, completionHandler: @escaping (Result) async -> Void) {
        state.update { mutableState -> (() -> Void) in
            switch mutableState {
            case .initial:
                mutableState = .running(taskIdentifier: taskIdentifier, operationTask: operationTask, completionHandler: completionHandler)
                return {
                    Task {
                        await operationTask.value
                        self._finish()
                    }
                }
            case .running(taskIdentifier: _, operationTask: _, completionHandler: _):
                owsFail("Can't start a task twice.")
            case .expired:
                mutableState = .terminal
                return {
                    self._complete(taskIdentifier: taskIdentifier, operationTask: operationTask, completionHandler: completionHandler, completionResult: .expired)
                }
            case .interrupted:
                mutableState = .terminal
                return {
                    self._complete(taskIdentifier: taskIdentifier, operationTask: operationTask, completionHandler: completionHandler, completionResult: .interrupted)
                }
            case .terminal:
                owsFail("Can't start a terminal task.")
            }
        }()
    }

    private func _finish() {
        state.update { mutableState -> (() -> Void) in
            switch mutableState {
            case .initial:
                owsFail("Can't finish a task that never started.")
            case .running(let taskIdentifier, let operationTask, let completionHandler):
                mutableState = .terminal
                return {
                    self._complete(taskIdentifier: taskIdentifier, operationTask: operationTask, completionHandler: completionHandler, completionResult: .finished)
                }
            case .interrupted, .expired, .terminal:
                return {}
            }
        }()
    }

    fileprivate func expire() {
        state.update { mutableState -> (() -> Void) in
            switch mutableState {
            case .initial:
                Logger.warn("Expiring a task that hasn't yet started.")
                mutableState = .expired
                return {}
            case .expired:
                owsFail("Can't expire a task twice.")
            case .running(let taskIdentifier, let operationTask, let completionHandler):
                mutableState = .terminal
                return {
                    self._complete(taskIdentifier: taskIdentifier, operationTask: operationTask, completionHandler: completionHandler, completionResult: .expired)
                }
            case .interrupted, .terminal:
                return {}
            }
        }()
    }

    func interrupt() {
        state.update { mutableState -> (() -> Void) in
            switch mutableState {
            case .initial:
                Logger.warn("Interrupted a task that hasn't yet started.")
                mutableState = .interrupted
                return {}
            case .running(let taskIdentifier, let operationTask, let completionHandler):
                mutableState = .terminal
                return {
                    self._complete(taskIdentifier: taskIdentifier, operationTask: operationTask, completionHandler: completionHandler, completionResult: .interrupted)
                }
            case .interrupted, .expired, .terminal:
                return {}
            }
        }()
    }

    private func _complete(
        taskIdentifier: UIBackgroundTaskIdentifier,
        operationTask: Task<Void, Never>,
        completionHandler: @escaping (Result) async -> Void,
        completionResult: Result,
    ) {
        operationTask.cancel()
        Task { @MainActor in
            await operationTask.value
            await completionHandler(completionResult)
            self.application.endBackgroundTask(taskIdentifier)
        }
    }
}
