// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SignalCoreKit
import SessionUtilitiesKit

public enum UpdateProfilePictureJob: JobExecutor {
    public static let maxFailureCount: Int = -1
    public static let requiresThreadId: Bool = false
    public static let requiresInteractionId: Bool = false
    
    public static func run(
        _ job: Job,
        queue: DispatchQueue,
        success: @escaping (Job, Bool) -> (),
        failure: @escaping (Job, Error?, Bool) -> (),
        deferred: @escaping (Job) -> ()
    ) {
        // Don't run when inactive or not in main app
        guard (UserDefaults.sharedLokiProject?[.isMainAppActive]).defaulting(to: false) else {
            deferred(job) // Don't need to do anything if it's not the main app
            return
        }
        
        // Only re-upload the profile picture if enough time has passed since the last upload
        guard
            let lastProfilePictureUpload: Date = UserDefaults.standard[.lastProfilePictureUpload],
            Date().timeIntervalSince(lastProfilePictureUpload) > (14 * 24 * 60 * 60)
        else {
            // Reset the `nextRunTimestamp` value just in case the last run failed so we don't get stuck
            // in a loop endlessly deferring the job
            if let jobId: Int64 = job.id {
                Storage.shared.write { db in
                    try Job
                        .filter(id: jobId)
                        .updateAll(db, Job.Columns.nextRunTimestamp.set(to: 0))
                }
            }
            deferred(job)
            return
        }
        
        // Note: The user defaults flag is updated in ProfileManager
        let profile: Profile = Profile.fetchOrCreateCurrentUser()
        let profileFilePath: String? = profile.profilePictureFileName
            .map { ProfileManager.profileAvatarFilepath(filename: $0) }
        
        ProfileManager.updateLocal(
            queue: queue,
            profileName: profile.name,
            image: nil,
            imageFilePath: profileFilePath,
            success: { db, _ in
                try MessageSender.syncConfiguration(db, forceSyncNow: true).retainUntilComplete()
                
                // Need to call the 'success' closure asynchronously on the queue to prevent a reentrancy
                // issue as it will write to the database and this closure is already called within
                // another database write
                queue.async {
                    success(job, false)
                }
            },
            failure: { error in failure(job, error, false) }
        )
    }
}
