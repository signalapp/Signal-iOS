// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import Curve25519Kit

/// This migration sets up the standard jobs, since we want these jobs to run before any "once-off" jobs we do this migration
/// before running the `YDBToGRDBMigration`
enum _002_SetupStandardJobs: Migration {
    static let target: TargetMigrations.Identifier = .utilitiesKit
    static let identifier: String = "SetupStandardJobs"
    static let needsConfigSync: Bool = false
    static let minExpectedRunDuration: TimeInterval = 0.1
    
    static func migrate(_ db: Database) throws {
        try autoreleasepool {
            // Note: This job exists in the 'Session' target but that doesn't have it's own migrations
            _ = try Job(
                variant: .syncPushTokens,
                behaviour: .recurringOnLaunch
            ).migrationSafeInserted(db)
            
            // Note: We actually need this job to run both onLaunch and onActive as the logic differs
            // slightly and there are cases where a user might not be registered in 'onLaunch' but is
            // in 'onActive' (see the `SyncPushTokensJob` for more info)
            _ = try Job(
                variant: .syncPushTokens,
                behaviour: .recurringOnActive,
                shouldSkipLaunchBecomeActive: true
            ).migrationSafeInserted(db)
        }
        
        Storage.update(progress: 1, for: self, in: target) // In case this is the last migration
    }
}
