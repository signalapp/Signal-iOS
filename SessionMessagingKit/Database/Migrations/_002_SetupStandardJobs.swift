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
                failureCount: 0,
                variant: .disappearingMessages,
                behaviour: .recurringOnLaunch,
                nextRunTimestamp: 0
            ).inserted(db)
            
            _ = try Job(
                failureCount: 0,
                variant: .failedMessages,
                behaviour: .recurringOnLaunch,
                nextRunTimestamp: 0
            ).inserted(db)
            
            _ = try Job(
                failureCount: 0,
                variant: .failedAttachmentDownloads,
                behaviour: .recurringOnLaunch,
                nextRunTimestamp: 0
            ).inserted(db)
            
            // Note: This job exists in the 'Session' target but that doesn't have it's own migrations
            _ = try Job(
                failureCount: 0,
                variant: .syncPushTokens,
                behaviour: .recurringOnLaunch,
                nextRunTimestamp: 0
            ).inserted(db)
        }
    }
}
