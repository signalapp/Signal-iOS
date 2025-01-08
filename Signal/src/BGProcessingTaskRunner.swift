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

    /// A store class to be used to determine if the migration needs to be run.
    /// Must be available immediately on app launch, after the database is set
    /// up but before any asynchronous app/dependencies setup completes.
    associatedtype Store
    /// The class that actually runs the migration. Can be loaded asynchronously.
    associatedtype Migrator

    /// MUST be defined in Info.plist under the "Permitted background task scheduler identifiers" key.
    static var taskIdentifier: String { get }

    /// If true, informs iOS that we require a network connection to perform the task.
    static var requiresNetworkConnectivity: Bool { get }

    static var logger: PrefixedLogger { get }

    static func shouldLaunchBGProcessingTask(
        store: Store,
        db: SDSDatabaseStorage
    ) -> Bool

    /// Called before the first call to ``runNextBatch``
    static func willBeginBGProcessingTask(
        store: Store,
        db: SDSDatabaseStorage
    )

    /// Run the next batch of migration (or run it to completion), returning true if completed.
    ///
    /// Batching is preferred to gracefully handle BGProcessingTask termination while still
    /// making incremental progress.
    static func runNextBatch(
        migrator: Migrator,
        store: Store,
        db: SDSDatabaseStorage
    ) async throws -> Bool
}

extension BGProcessingTaskRunner {

    /// Must be called synchronously within appDidFinishLaunching for every BGProcessingTask
    /// regardless of whether we eventually schedule and run it or not.
    /// Call `scheduleBGProcessingTaskIfNeeded` to actually schedule the task
    /// to run; that will simply not schedule any unecessary tasks.
    public static func registerBGProcessingTask(
        store: Store,
        migrator: Task<Migrator, Never>,
        db: SDSDatabaseStorage
    ) {
        // We register the handler _regardless_ of whether we schedule the task.
        // Scheduling is what makes it actually run; apple docs say apps must register
        // handlers for every task identifier declared in info.plist.
        // https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler/register(fortaskwithidentifier:using:launchhandler:)
        // (Apple's WWDC sample app also unconditionally registers and then conditionally schedules.)
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskIdentifier,
            using: nil,
            launchHandler: { task in
                Self.runInBGProcessingTask(
                    task,
                    store: store,
                    migrator: migrator,
                    db: db
                )
            }
        )
    }

    public static func scheduleBGProcessingTaskIfNeeded(store: Store, db: SDSDatabaseStorage) {
        // Note: this file only exists in the main app (Signal/src) so this is guaranteed.
        owsAssertDebug(CurrentAppContext().isMainApp)

        guard shouldLaunchBGProcessingTask(store: store, db: db) else {
            return
        }

        // Dispatching off the main thread is recommended by apple in their WWDC talk
        // as BGTaskScheduler.submit can take time and block the main thread.
        DispatchQueue.global().async {
            let request = BGProcessingTaskRequest(identifier: Self.taskIdentifier)
            request.requiresNetworkConnectivity = Self.requiresNetworkConnectivity

            do {
                try BGTaskScheduler.shared.submit(request)
                logger.info("Scheduled BGProcessingTask")
            } catch let error {
                let errorCode = (error as NSError).code
                switch errorCode {
                case BGTaskScheduler.Error.Code.notPermitted.rawValue:
                    logger.warn("Skipping bg task; user permission required.")
                case BGTaskScheduler.Error.Code.tooManyPendingTaskRequests.rawValue:
                    // Note: if we reschedule the same identifier, we don't get this error.
                    logger.error("Too many pending bg processing tasks; only 10 are allowed at any time.")
                case BGTaskScheduler.Error.Code.unavailable.rawValue:
                    logger.warn("Trying to schedule bg task from an extension or simulator?")
                default:
                    logger.error("Unknown error code scheduling bg task: \(errorCode)")
                }
            }
        }
    }

    private static func runInBGProcessingTask(
        _ bgTask: BGTask,
        store: Store,
        migrator: Task<Migrator, Never>,
        db: SDSDatabaseStorage
    ) {
        guard shouldLaunchBGProcessingTask(store: store, db: db) else {
            logger.info("Not running BGProcessingTask; not allowed or already finished")
            bgTask.setTaskCompleted(success: true)
            return
        }

        logger.info("Starting migration in BGProcessingTask")
        let task = Task {
            self.willBeginBGProcessingTask(store: store, db: db)

            let migrator = await migrator.value

            var batchCount = 0
            var didFinish = false
            while !didFinish {
                do {
                    try Task.checkCancellation()
                } catch {
                    logger.warn("Canceled BGProcessingTask after \(batchCount) batches")
                    // Apple WWDC talk specifies tasks must be completed even if the expiration
                    // handler is called.
                    bgTask.setTaskCompleted(success: false)
                    // Re-schedule so we try to run it again.
                    self.scheduleBGProcessingTaskIfNeeded(store: store, db: db)
                    return
                }

                do {
                    didFinish = try await self.runNextBatch(migrator: migrator, store: store, db: db)
                } catch let error {
                    logger.error("Failed migration batch in BGProcessingTask, stopping after \(batchCount) batches: \(error)")
                    bgTask.setTaskCompleted(success: false)
                    // Next app launch will attempt to re-schedule it; don't reschedule here.
                    return
                }
                batchCount += 1
            }
            logger.info("Finished in BGProcessingTask after \(batchCount) batches")
            bgTask.setTaskCompleted(success: true)
        }
        bgTask.expirationHandler = { [task] in
            logger.warn("BGProcessingTask timed out; cancelling.")
            // WWDC talk says we get a grace period after the expiration handler
            // is called; use it to cleanly cancel the task.
            task.cancel()
        }
    }
}
