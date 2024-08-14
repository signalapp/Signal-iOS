//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import BackgroundTasks
import Foundation
import SignalServiceKit

private enum IncrementalMessageTSAttachmentMigratorConstants {
    // Must be kept in sync with the value in info.plist.
    static let taskIdentifier = "MessageAttachmentMigrationTask"
}

/// Manages the BGProcessingTask for doing the migration as well as the runner for
/// doing so while the main app is running.
extension IncrementalMessageTSAttachmentMigrator {

    typealias Store = IncrementalTSAttachmentMigrationStore

    public func registerBGProcessingTask(databaseStorage: SDSDatabaseStorage) {
        // We register the handler _regardless_ of whether we schedule the task.
        // Scheduling is what makes it actually run; apple docs say apps must register
        // handlers for every task identifier declared in info.plist.
        // https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler/register(fortaskwithidentifier:using:launchhandler:)
        // (Apple's WWDC sample app also unconditionally registers and then conditionally schedules.)
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: IncrementalMessageTSAttachmentMigratorConstants.taskIdentifier,
            using: nil,
            launchHandler: { [self] task in
                self.runInBGProcessingTask(task, databaseStorage: databaseStorage)
            }
        )
    }

    public func scheduleBGProcessingTaskIfNeeded(databaseStorage: SDSDatabaseStorage) {
        // Note: this file only exists in the main app (Signal/src) so this is guaranteed.
        owsAssertDebug(CurrentAppContext().isMainApp)

        guard shouldLaunchBGProcessingTask(databaseStorage: databaseStorage) else {
            return
        }

        // Dispatching off the main thread is recommended by apple in their WWDC talk
        // as BGTaskScheduler.submit can take time and block the main thread.
        DispatchQueue.global().async {
            let request = BGProcessingTaskRequest(identifier: IncrementalMessageTSAttachmentMigratorConstants.taskIdentifier)

            do {
                try BGTaskScheduler.shared.submit(request)
                Logger.info("Scheduled BGProcessingTask")
            } catch let error {
                let errorCode = (error as NSError).code
                switch errorCode {
                case BGTaskScheduler.Error.Code.notPermitted.rawValue:
                    Logger.warn("Skipping bg task; user permission required.")
                case BGTaskScheduler.Error.Code.tooManyPendingTaskRequests.rawValue:
                    // Note: if we reschedule the same identifier, we don't get this error.
                    Logger.error("Too many pending bg processing tasks; only 10 are allowed at any time.")
                case BGTaskScheduler.Error.Code.unavailable.rawValue:
                    Logger.warn("Trying to schedule bg task from an extension or simulator?")
                default:
                    Logger.error("Unknown error code scheduling bg task: \(errorCode)")
                }
            }
        }
    }

    private func shouldLaunchBGProcessingTask(databaseStorage: SDSDatabaseStorage) -> Bool {
        guard AttachmentFeatureFlags.incrementalMigration else { return false }
        let state = databaseStorage.read(block: Store.getState(tx:))
        return state != .finished
    }

    private func runInBGProcessingTask(_ bgTask: BGTask, databaseStorage: SDSDatabaseStorage) {
        guard shouldLaunchBGProcessingTask(databaseStorage: databaseStorage) else {
            Logger.info("Not running BGProcessingTask; not allowed or already finished")
            bgTask.setTaskCompleted(success: true)
            return
        }

        Logger.info("Starting migration in BGProcessingTask")
        let task = Task {
            var batchCount = 0
            var didFinish = false
            while !didFinish {
                do {
                    try Task.checkCancellation()
                } catch {
                    Logger.warn("Canceled BGProcessingTask after \(batchCount) batches")
                    // Apple WWDC talk specifies tasks must be completed even if the expiration
                    // handler is called.
                    bgTask.setTaskCompleted(success: false)
                    // Re-schedule so we try to run it again.
                    self.scheduleBGProcessingTaskIfNeeded(databaseStorage: databaseStorage)
                    return
                }

                do {
                    didFinish = try await self.runNextBatch()
                } catch let error {
                    owsFailDebug("Failed migration batch in BGProcessingTask, stopping after \(batchCount) batches: \(error)")
                    bgTask.setTaskCompleted(success: false)
                    // Next app launch will attempt to re-schedule it; don't reschedule here.
                    return
                }
                batchCount += 1
            }
            Logger.info("Finished in BGProcessingTask after \(batchCount) batches")
            bgTask.setTaskCompleted(success: true)
        }
        bgTask.expirationHandler = { [task] in
            Logger.warn("BGProcessingTask timed out; cancelling.")
            // WWDC talk says we get a grace period after the expiration handler
            // is called; use it to cleanly cancel the task.
            task.cancel()
        }
    }

    public func runInMainAppBackgroundIfNeeded(databaseStorage: SDSDatabaseStorage) {
        guard AttachmentFeatureFlags.incrementalMigration else { return }
        let state = databaseStorage.read(block: Store.getState(tx:))
        switch state {
        case .finished, .unstarted:
            return
        case .started:
            // Don't _start_ in the main app, but continue making progress if we already started.

            if isRunningInMainApp.get() {
                return
            }

            Logger.info("Continuing migration in main app")
            Task {
                await runInMainAppBackground()
            }
        }
    }

    private func runInMainAppBackground() async {
        var batchCount = 0
        var didFinish = false
        isRunningInMainApp.set(true)
        defer {
            isRunningInMainApp.set(false)
        }
        while !didFinish {
            do {
                guard CurrentAppContext().isMainAppAndActive else {
                    // If the main app goes into the background, we shouldn't be
                    // grabbing the sql write lock. Stop.
                    Logger.info("Stopping when backgrounding app")
                    return
                }

                // Add a small delay between each batch to avoid locking the db write queue.
                try await Task.sleep(nanoseconds: 300 * NSEC_PER_MSEC)

                didFinish = try await self.runNextBatch()
                batchCount += 1
            } catch let error {
                owsFailDebug("Failed migration batch, stopping after \(batchCount) batches: \(error)")
                return
            }
        }
        Logger.info("Finished in main app after \(batchCount) batches")
    }
}
