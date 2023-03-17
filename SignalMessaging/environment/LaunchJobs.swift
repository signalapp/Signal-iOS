//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

@objc
public class LaunchJobs: NSObject {

    private enum LaunchJobsState: String {
        case notYetStarted
        case inFlight
        case complete
    }
    // This should only be accessed on the main thread.
    private var state: LaunchJobsState = .notYetStarted

    // Returns true IFF the launch jobs are complete.
    //
    // completion will be invoked async on the main thread,
    // but only for the first time this method is called.
    @objc(ensureLaunchJobsWithCompletion:)
    public func ensureLaunchJobs(completion: @escaping () -> Void) -> Bool {
        AssertIsOnMainThread()

        switch state {
        case .notYetStarted:
            startLaunchJobs(completion: completion)
            return false
        case .inFlight:
            Logger.verbose("Already started.")
            return false
        case .complete:
            Logger.verbose("Already complete.")
            return true
        }
    }

    // completion will be invoked async on the main thread.
    private func startLaunchJobs(completion: @escaping () -> Void) {
        AssertIsOnMainThread()
        owsAssertDebug(!CurrentAppContext().isNSE)

        state = .inFlight

        guard tsAccountManager.isRegistered else {
            Logger.verbose("Skipping.")
            state = .complete
            DispatchQueue.main.async {
                completion()
            }
            return
        }

        Logger.verbose("Starting.")

        var backgroundTask: OWSBackgroundTask? = OWSBackgroundTask(label: "\(#function)")

        // Getting this work done ASAP is super high priority, since we won't finish launching until
        // the completion block is fired.
        //
        // Originally, I considered making this all synchronous on the main thread (there's no UI to
        // interrupt anyway) but I figured that in the absolute *worst* case where this work takes ~15s
        // we risk getting watchdogged by SpringBoard.
        //
        // So instead, we'll use a user interactive queue and hope that's good enough.
        DispatchQueue.sharedUserInteractive.async {
            // Mark all "attempting out" messages as "unsent", i.e. any messages that were not successfully
            // sent before the app exited should be marked as failures.
            FailedMessagesJob().runSync(databaseStorage: self.databaseStorage)
            // Mark all "incomplete" calls as missed, e.g. any incoming or outgoing calls that were not
            // connected, failed or hung up before the app existed should be marked as missed.
            IncompleteCallsJob().runSync(databaseStorage: self.databaseStorage)
            // Mark all "downloading" attachments as "failed", i.e. any incoming attachments that were not
            // successfully downloaded before the app exited should be marked as failures.
            FailedAttachmentDownloadsJob().runSync(databaseStorage: self.databaseStorage)

            // Kick off a low priority trim of the MSL
            // This will reschedule itself on a background queue ~24h or so
            MessageSendLog.schedulePeriodicCleanup()

            DispatchQueue.main.async {
                Logger.verbose("Completing.")
                self.state = .complete
                completion()

                owsAssertDebug(backgroundTask != nil)
                backgroundTask = nil
            }
        }
    }
}
