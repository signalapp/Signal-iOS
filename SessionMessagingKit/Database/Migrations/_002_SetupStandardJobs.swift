// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import Curve25519Kit
import SessionUtilitiesKit
import SessionSnodeKit

/// This migration sets up the standard jobs, since we want these jobs to run before any "once-off" jobs we do this migration
/// before running the `YDBToGRDBMigration`
enum _002_SetupStandardJobs: Migration {
    static let identifier: String = "SetupStandardJobs"
    
    static func migrate(_ db: Database) throws {
        // Start by adding the jobs that don't have collections (in the jobs like these
        // will be added via migrations)
        try autoreleasepool {
            // TODO: Add additional jobs from the AppDelegate
            _ = try Job(
                variant: .disappearingMessages,
                behaviour: .recurringOnLaunchBlockingOncePerSession
            ).inserted(db)
            
            _ = try Job(
                variant: .failedMessages,
                behaviour: .recurringOnLaunchBlocking
            ).inserted(db)
            
            _ = try Job(
                variant: .failedAttachmentDownloads,
                behaviour: .recurringOnLaunchBlocking
            ).inserted(db)
            
            _ = try Job(
                variant: .updateProfilePicture,
                behaviour: .recurringOnActive
            ).inserted(db)
            
            _ = try Job(
                variant: .retrieveDefaultOpenGroupRooms,
                behaviour: .recurringOnActive
            ).inserted(db)
        }
    }
}
