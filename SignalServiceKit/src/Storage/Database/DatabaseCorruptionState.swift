//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

public class DatabaseCorruptionState: Codable, Equatable, CustomStringConvertible {
    public enum DatabaseCorruptionStatus: Int, Codable, CustomStringConvertible {
        // We used to store these as booleans, so the value is important.
        case notCorrupted = 0
        case corrupted = 1
        case corruptedButAlreadyDumpedAndRestored = 2
        case readCorrupted = 3

        public var isCorrupted: Bool {
            switch self {
            case .notCorrupted, .readCorrupted: return false
            case .corrupted, .corruptedButAlreadyDumpedAndRestored: return true
            }
        }

        public var description: String {
            switch self {
            case .notCorrupted:
                return "not corrupted"
            case .readCorrupted:
                return "read corrupted"
            case .corrupted:
                return "corrupted"
            case .corruptedButAlreadyDumpedAndRestored:
                return "corrupted (but already dumped and restored)"
            }
        }
    }

    public let status: DatabaseCorruptionStatus
    public let count: UInt

    required init(status: DatabaseCorruptionStatus, count: UInt) {
        self.status = status
        self.count = count
    }

    public static func == (lhs: DatabaseCorruptionState, rhs: DatabaseCorruptionState) -> Bool {
        (lhs.status == rhs.status) && (lhs.count == rhs.count)
    }

    public var description: String {
        "Database is \(status). Corruption count: \(count)"
    }

    // MARK: - Reading and writing from `UserDefaults`

    // The value of this key doesn't match the name because that's what we used to store.
    static var databaseCorruptionStatusKey: String { "hasGrdbDatabaseCorruption" }
    static var databaseCorruptionCountKey: String { "databaseCorruptionCount" }

    public convenience init(userDefaults: UserDefaults) {
        let rawStatus = userDefaults.integer(forKey: Self.databaseCorruptionStatusKey)
        let rawCount = userDefaults.integer(forKey: Self.databaseCorruptionCountKey)

        let status = DatabaseCorruptionStatus(rawValue: rawStatus) ?? .notCorrupted
        let count: UInt = status.isCorrupted ? max(UInt(rawCount), 1) : UInt(rawCount)

        self.init(status: status, count: count)
    }

    private func save(to userDefaults: UserDefaults) {
        userDefaults.set(status.rawValue, forKey: Self.databaseCorruptionStatusKey)
        userDefaults.set(count, forKey: Self.databaseCorruptionCountKey)
    }

    /// If the error is a `SQLITE_CORRUPT` error, set the "has database corruption" flag, log, and crash.
    /// We do this so we can attempt to perform diagnostics/recovery on relaunch.
    public static func flagDatabaseCorruptionIfNecessary(
        userDefaults: UserDefaults,
        error: Error,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        if let error = error as? DatabaseError, error.resultCode == .SQLITE_CORRUPT {
            flagDatabaseAsCorrupted(userDefaults: userDefaults)
            owsFail("Crashing due to database corruption. Source: [\(file):\(line) \(function)]. Extended result code: \(error.extendedResultCode)")
        }
    }

    /// If the error is a `SQLITE_CORRUPT` error, set the "has database read corruption" flag, log, but don't crash.
    /// We do this so we can attempt to perform diagnostics/recovery if this read error is coupled with a crash..
    public static func flagDatabaseReadCorruptionIfNecessary(
        userDefaults: UserDefaults,
        error: Error,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        if let error = error as? DatabaseError, error.resultCode == .SQLITE_CORRUPT {
            flagDatabaseAsReadCorrupted(userDefaults: userDefaults)
        }
    }

    public static func flagDatabaseAsCorrupted(userDefaults: UserDefaults) {
        let oldState = DatabaseCorruptionState(userDefaults: userDefaults)
        switch oldState.status {
        case .notCorrupted, .readCorrupted:
            Self(status: .corrupted, count: oldState.count + 1).save(to: userDefaults)
        case .corrupted, .corruptedButAlreadyDumpedAndRestored:
            return
        }
    }

    public static func flagDatabaseAsReadCorrupted(userDefaults: UserDefaults) {
        let oldState = DatabaseCorruptionState(userDefaults: userDefaults)
        switch oldState.status {
        case .notCorrupted:
            Self(status: .readCorrupted, count: oldState.count).save(to: userDefaults)
        case .corrupted, .readCorrupted, .corruptedButAlreadyDumpedAndRestored:
            return
        }
    }

    public static func flagCorruptedDatabaseAsDumpedAndRestored(userDefaults: UserDefaults) {
        let oldState = DatabaseCorruptionState(userDefaults: userDefaults)
        switch oldState.status {
        case .corrupted, .readCorrupted:
            DatabaseCorruptionState(status: .corruptedButAlreadyDumpedAndRestored, count: oldState.count).save(to: userDefaults)
        case .notCorrupted, .corruptedButAlreadyDumpedAndRestored:
            owsFailDebug("Flagging database as partially recovered, but it was not in the right state previously")
        }
    }

    public static func flagDatabaseAsRecoveredFromCorruption(userDefaults: UserDefaults) {
        let oldState = DatabaseCorruptionState(userDefaults: userDefaults)
        switch oldState.status {
        case .notCorrupted:
            owsFailDebug("Flagging database as recovered from corruption, but it wasn't marked corrupted")
        case .corrupted, .readCorrupted, .corruptedButAlreadyDumpedAndRestored:
            Self(status: .notCorrupted, count: oldState.count).save(to: userDefaults)
        }
    }

    @objc(stringForLoggingWith:)
    public static func objcStringForLogging(userDefaults: UserDefaults) -> String {
        let state = DatabaseCorruptionState(userDefaults: userDefaults)
        return String(describing: state)
    }
}
