// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

/// This migration sets up the standard jobs, since we want these jobs to run before any "once-off" jobs we do this migration
/// before running the `YDBToGRDBMigration`
enum _002_SetupStandardJobs: Migration {
    static let target: TargetMigrations.Identifier = .snodeKit
    static let identifier: String = "SetupStandardJobs"
    static let needsConfigSync: Bool = false
    static let minExpectedRunDuration: TimeInterval = 0.1
    
    static func migrate(_ db: Database) throws {
        try autoreleasepool {
            _ = try Job(
                variant: .getSnodePool,
                behaviour: .recurringOnActive,
                shouldBlockFirstRunEachSession: true
            ).inserted(db)
        }
        
        Storage.update(progress: 1, for: self, in: target) // In case this is the last migration
    }
}
