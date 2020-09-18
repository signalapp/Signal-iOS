//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class LaunchJobs: NSObject {

    // MARK: Singletons

    private var tsAccountManager: TSAccountManager {
        return TSAccountManager.shared()
    }

    // MARK: 

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

        DispatchQueue.global().async {
            // Mark all "attempting out" messages as "unsent", i.e. any messages that were not successfully
            // sent before the app exited should be marked as failures.
            OWSFailedMessagesJob().runSync()
            // Mark all "incomplete" calls as missed, e.g. any incoming or outgoing calls that were not
            // connected, failed or hung up before the app existed should be marked as missed.
            OWSIncompleteCallsJob().runSync()
            // Mark all "downloading" attachments as "failed", i.e. any incoming attachments that were not
            // successfully downloaded before the app exited should be marked as failures.
            OWSFailedAttachmentDownloadsJob().runSync()

            DispatchQueue.main.async {
                Logger.verbose("Completing.")
                self.state = .complete
                completion()
            }
        }
    }
}
