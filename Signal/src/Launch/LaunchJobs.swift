//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

enum LaunchJobs {
    static func run(
        tsAccountManager: TSAccountManager,
        databaseStorage: SDSDatabaseStorage
    ) -> Guarantee<Void> {
        AssertIsOnMainThread()

        guard tsAccountManager.isRegistered else {
            return .value(())
        }

        let backgroundTask = OWSBackgroundTask(label: #function)

        // Getting this work done ASAP is super high priority since we won't finish
        // launching until the completion block is fired.
        //
        // Originally, I considered making this all synchronous on the main thread,
        // but I figured that in the absolute *worst* case where this work takes
        // ~15s we risk getting watchdogged by SpringBoard.
        //
        // So instead, we'll use a user-interactive background queue.
        return firstly(on: DispatchQueue.sharedUserInteractive) { () -> Guarantee<Void> in
            // Mark all "attempting out" messages as "unsent", i.e. any messages that
            // were not successfully sent before the app exited should be marked as
            // failures.
            FailedMessagesJob().runSync(databaseStorage: databaseStorage)
            // Mark all "incomplete" calls as missed, e.g. any incoming or outgoing
            // calls that were not connected, failed or hung up before the app existed
            // should be marked as missed.
            IncompleteCallsJob().runSync(databaseStorage: databaseStorage)
            // Mark all "downloading" attachments as "failed", i.e. any incoming
            // attachments that were not successfully downloaded before the app exited
            // should be marked as failures.
            FailedAttachmentDownloadsJob().runSync(databaseStorage: databaseStorage)

            // Kick off a low priority trim of the MSL.
            // This will reschedule itself on a background queue ~24h or so.
            let messageSendLog = SSKEnvironment.shared.messageSendLogRef
            messageSendLog.schedulePeriodicCleanup(on: DispatchQueue.sharedUtility)

            return .value(())
        }.done(on: DispatchQueue.main) {
            backgroundTask.end()
        }
    }
}
