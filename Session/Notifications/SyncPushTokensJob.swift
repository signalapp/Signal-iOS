// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import PromiseKit
import SignalCoreKit
import SessionMessagingKit
import SessionUtilitiesKit

public enum SyncPushTokensJob: JobExecutor {
    public static let maxFailureCount: Int = -1
    public static let requiresThreadId: Bool = false
    public static let requiresInteractionId: Bool = false
    
    public static func run(
        _ job: Job,
        success: @escaping (Job, Bool) -> (),
        failure: @escaping (Job, Error?, Bool) -> (),
        deferred: @escaping (Job) -> ()
    ) {
        // Don't run when inactive or not in main app
        guard (UserDefaults.sharedLokiProject?[.isMainAppActive]).defaulting(to: false) else {
            deferred(job) // Don't need to do anything if it's not the main app
            return
        }
        
        // We need to check a UIApplication setting which needs to run on the main thread so if we aren't on
        // the main thread then swap to it
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                run(job, success: success, failure: failure, deferred: deferred)
            }
            return
        }
        guard !UIApplication.shared.isRegisteredForRemoteNotifications else {
            deferred(job) // Don't need to do anything if push notifications are already registered
            return
        }
        
        Logger.info("Retrying remote notification registration since user hasn't registered yet.")
        
        // Determine if we want to upload only if stale (Note: This should default to true, and be true if
        // 'details' isn't provided)
        // TODO: Double check on a real device
        let uploadOnlyIfStale: Bool = ((try? JSONDecoder().decode(Details.self, from: job.details ?? Data()))?.uploadOnlyIfStale ?? true)
        
        // Get the app version info (used to determine if we want to update the push tokens)
        let lastAppVersion: String? = AppVersion.sharedInstance().lastAppVersion
        let currentAppVersion: String? = AppVersion.sharedInstance().currentAppVersion
        
        PushRegistrationManager.shared.requestPushTokens()
            .then { (pushToken: String, voipToken: String) -> Promise<Void> in
                let lastPushToken: String? = GRDBStorage.shared.read { db in db[.lastRecordedPushToken] }
                let lastVoipToken: String? = GRDBStorage.shared.read { db in db[.lastRecordedVoipToken] }
                let shouldUploadTokens: Bool = (
                    !uploadOnlyIfStale || (
                        lastPushToken != pushToken ||
                        lastVoipToken != voipToken
                    ) ||
                    lastAppVersion != currentAppVersion
                )

                guard shouldUploadTokens else { return Promise.value(()) }
                
                let (promise, seal) = Promise<Void>.pending()
                
                SSKEnvironment.shared.tsAccountManager
                    .registerForPushNotifications(
                        pushToken: pushToken,
                        voipToken: voipToken,
                        isForcedUpdate: shouldUploadTokens,
                        success: { seal.fulfill(()) },
                        failure: seal.reject
                    )
                
                return promise
                    .done { _ in
                        Logger.warn("Recording push tokens locally. pushToken: \(redact(pushToken)), voipToken: \(redact(voipToken))")

                        GRDBStorage.shared.write { db in
                            db[.lastRecordedPushToken] = pushToken
                            db[.lastRecordedVoipToken] = voipToken
                        }
                    }
            }
            .ensure { success(job, false) }    // We want to complete this job regardless of success or failure
            .retainUntilComplete()
    }
    
    public static func run(uploadOnlyIfStale: Bool) {
        guard let job: Job = Job(
            variant: .syncPushTokens,
            details: SyncPushTokensJob.Details(
                uploadOnlyIfStale: uploadOnlyIfStale
            )
        )
        else { return }
                                 
        SyncPushTokensJob.run(
            job,
            success: { _, _ in },
            failure: { _, _, _ in },
            deferred: { _ in }
        )
    }
}

// MARK: - SyncPushTokensJob.Details

extension SyncPushTokensJob {
    public struct Details: Codable {
        public let uploadOnlyIfStale: Bool
    }
}

// MARK: - Convenience

private func redact(_ string: String) -> String {
    return OWSIsDebugBuild() ? string : "[ READACTED \(string.prefix(2))...\(string.suffix(2)) ]"
}

// MARK: - Objective C Support

@objc(OWSSyncPushTokensJob)
class OWSSyncPushTokensJob: NSObject {
    @objc static func run() {
        SyncPushTokensJob.run(uploadOnlyIfStale: false)
    }
}
