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
            deferred(job)
            return
        }
        
        // Note: The user defaults flag is updated in ProfileManager
        let profile: Profile = Profile.fetchOrCreateCurrentUser()
        let profilePicture: UIImage? = ProfileManager.profileAvatar(id: profile.id)
        
        ProfileManager.updateLocal(
            profileName: profile.name,
            avatarImage: profilePicture,
            requiredSync: true,
            success: { success(job, false) },
            failure: { error in failure(job, error, false) }
        )
    }
}
