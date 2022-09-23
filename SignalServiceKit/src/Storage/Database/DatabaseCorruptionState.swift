//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDB

// We could hang everything off of the enum, but we intend to add some additional information to this class soon.
public class DatabaseCorruptionState {
    public enum DatabaseCorruptionStatus: UInt8 {
        case notCorrupted
        case corrupted
    }

    static var hasGrdbDatabaseCorruptionKey: String { "hasGrdbDatabaseCorruption" }

    public static func databaseCorruptionStatus(userDefaults: UserDefaults) -> DatabaseCorruptionStatus {
        userDefaults.bool(forKey: hasGrdbDatabaseCorruptionKey) ? .corrupted : .notCorrupted
    }

    /// If the error is a `SQLITE_CORRUPT` error, set the "has database corruption" flag, log, and crash.
    /// We do this so we can attempt to perform diagnostics/recovery on relaunch.
    public static func flagDatabaseCorruptionIfNecessary(userDefaults: UserDefaults, error: Error) {
        if let error = error as? DatabaseError, error.resultCode == .SQLITE_CORRUPT {
            flagDatabaseAsCorrupted(userDefaults: userDefaults)
            owsFail("Crashing due to database corruption. Extended result code: \(error.extendedResultCode)")
        }
    }

    public static func flagDatabaseAsCorrupted(userDefaults: UserDefaults) {
        userDefaults.set(true, forKey: hasGrdbDatabaseCorruptionKey)
    }
}
