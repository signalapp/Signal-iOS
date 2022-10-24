// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import Curve25519Kit
import SessionUtilitiesKit
import SessionSnodeKit

/// This migration sets up the standard jobs, since we want these jobs to run before any "once-off" jobs we do this migration
/// before running the `YDBToGRDBMigration`
enum _002_SetupStandardJobs: Migration {
    static let target: TargetMigrations.Identifier = .messagingKit
    static let identifier: String = "SetupStandardJobs"
    static let needsConfigSync: Bool = false
    static let minExpectedRunDuration: TimeInterval = 0.1
    
    static func migrate(_ db: Database) throws {
        // Start by adding the jobs that don't have collections (in the jobs like these
        // will be added via migrations)
        try autoreleasepool {
            _ = try Job(
                variant: .disappearingMessages,
                behaviour: .recurringOnLaunch,
                shouldBlock: true
            ).migrationSafeInserted(db)
            
            _ = try Job(
                variant: .failedMessageSends,
                behaviour: .recurringOnLaunch,
                shouldBlock: true
            ).migrationSafeInserted(db)
            
            _ = try Job(
                variant: .failedAttachmentDownloads,
                behaviour: .recurringOnLaunch,
                shouldBlock: true
            ).migrationSafeInserted(db)
            
            _ = try Job(
                variant: .updateProfilePicture,
                behaviour: .recurringOnActive
            ).migrationSafeInserted(db)
            
            _ = try Job(
                variant: .retrieveDefaultOpenGroupRooms,
                behaviour: .recurringOnActive
            ).migrationSafeInserted(db)
            
            _ = try Job(
                variant: .garbageCollection,
                behaviour: .recurringOnActive
            ).migrationSafeInserted(db)
        }
        
        Storage.update(progress: 1, for: self, in: target) // In case this is the last migration
    }
}
