//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import BackgroundTasks
import Foundation
public import SignalServiceKit

/// Base protocol for classes that manage running a BGProcessingTask.
/// Implement the protocol methods and let the extension methods handle
/// the standardized registration and running of the BGProcessingTask.
public protocol BGProcessingTaskRunner {
    /// MUST be defined in Info.plist under the "Permitted background task scheduler identifiers" key.
    static var taskIdentifier: String { get }

    /// If true, informs iOS that we require a network connection to perform the task.
    static var requiresNetworkConnectivity: Bool { get }

    func shouldLaunchBGProcessingTask() -> Bool

    /// Run the operation.
    ///
    /// Conformers should detect Task cancellation to gracefully handle
    /// BGProcessingTask termination, and they should still make incremental
    /// progress when that happens.
    func run() async throws
}

extension BGProcessingTaskRunner {
    private var logger: PrefixedLogger { PrefixedLogger(prefix: Self.taskIdentifier) }

    /// Must be called synchronously within appDidFinishLaunching for every BGProcessingTask
    /// regardless of whether we eventually schedule and run it or not.
    /// Call `scheduleBGProcessingTaskIfNeeded` to actually schedule the task
    /// to run; that will simply not schedule any unecessary tasks.
    public func registerBGProcessingTask(appReadiness: any AppReadiness) {
        // We register the handler _regardless_ of whether we schedule the task.
        // Scheduling is what makes it actually run; apple docs say apps must register
        // handlers for every task identifier declared in info.plist.
        // https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler/register(fortaskwithidentifier:using:launchhandler:)
        // (Apple's WWDC sample app also unconditionally registers and then conditionally schedules.)
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskIdentifier,
            using: nil,
            launchHandler: { bgTask in
                let task = Task {
                    await withCheckedContinuation { continuation in
                        appReadiness.runNowOrWhenAppDidBecomeReadyAsync { continuation.resume() }
                    }
                    do {
                        try await self.run()
                        bgTask.setTaskCompleted(success: true)
                    } catch is CancellationError {
                        // Apple WWDC talk specifies tasks must be completed even if the expiration
                        // handler is called.
                        // Re-schedule so we try to run it again.
                        logger.warn("Rescheduling because it was canceled.")
                        await self.scheduleBGProcessingTask()
                        bgTask.setTaskCompleted(success: false)
                    } catch {
                        bgTask.setTaskCompleted(success: false)
                    }
                }
                bgTask.expirationHandler = {
                    logger.warn("Timed out; cancelling.")
                    // WWDC talk says we get a grace period after the expiration handler
                    // is called; use it to cleanly cancel the task.
                    task.cancel()
                }
            }
        )
    }

    public func scheduleBGProcessingTaskIfNeeded() {
        // Note: this file only exists in the main app (Signal/src) so this is guaranteed.
        owsAssertDebug(CurrentAppContext().isMainApp)

        guard shouldLaunchBGProcessingTask() else {
            return
        }

        Task {
            await self.scheduleBGProcessingTask()
        }
    }

    private func scheduleBGProcessingTask() async {
        // Dispatching off the main thread is recommended by apple in their WWDC talk
        // as BGTaskScheduler.submit can take time and block the main thread.
        let request = BGProcessingTaskRequest(identifier: Self.taskIdentifier)
        request.requiresNetworkConnectivity = Self.requiresNetworkConnectivity

        do {
            try BGTaskScheduler.shared.submit(request)
            logger.info("Scheduled.")
        } catch BGTaskScheduler.Error.notPermitted {
            logger.warn("Skipping: notPermitted")
        } catch BGTaskScheduler.Error.tooManyPendingTaskRequests {
            // Note: if we reschedule the same identifier, we don't get this error.
            logger.error("Skipping: tooManyPendingTaskRequests")
        } catch BGTaskScheduler.Error.unavailable {
            logger.warn("Skipping: unavailable (in a simulator?)")
        } catch {
            logger.error("Skipping: \(error)")
        }
    }

    /// Helper to run a migration in multiple batches.
    ///
    /// - Parameter willBegin: Called before the first call to `runNextBatch`.
    ///
    /// - Parameter runNextBatch: Run the next batch of migration, returning
    /// true if the entire migration is completed.
    func runInBatches(
        willBegin: () -> Void,
        runNextBatch: () async throws -> Bool
    ) async throws {
        logger.info("Starting.")

        guard shouldLaunchBGProcessingTask() else {
            logger.info("Finished early because we don't need to run.")
            return
        }

        willBegin()

        var batchCount = 0
        var didFinish = false
        while !didFinish {
            do {
                try Task.checkCancellation()
            } catch {
                logger.warn("Canceled after \(batchCount) batches")
                throw error
            }

            do {
                didFinish = try await runNextBatch()
            } catch {
                logger.error("Failed after \(batchCount) batches: \(error)")
                throw error
            }
            batchCount += 1
        }
        logger.info("Finished after \(batchCount) batches")
    }
}
