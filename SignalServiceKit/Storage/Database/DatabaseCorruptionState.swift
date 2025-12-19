//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

public struct DatabaseCorruptionState: Equatable {
    public enum DatabaseCorruptionStatus: Int, Codable {
        // We used to store these as booleans, so the value is important.
        case notCorrupted = 0
        case corrupted = 1
        case corruptedButAlreadyDumpedAndRestored = 2
        // This case was deprecated, but is left here such that we don't
        // inadvertently reuse this rawValue and resurrect it.
        // case readCorrupted = 3

        public var isCorrupted: Bool {
            switch self {
            case .notCorrupted: return false
            case .corrupted, .corruptedButAlreadyDumpedAndRestored: return true
            }
        }
    }

    public let status: DatabaseCorruptionStatus

    init(status: DatabaseCorruptionStatus) {
        self.status = status
    }

    // MARK: - Reading and writing from `UserDefaults`

    // The value of this key doesn't match the name because that's what we used to store.
    static var databaseCorruptionStatusKey: String { "hasGrdbDatabaseCorruption" }

    public init(userDefaults: UserDefaults) {
        let rawStatus = userDefaults.integer(forKey: Self.databaseCorruptionStatusKey)
        let status = DatabaseCorruptionStatus(rawValue: rawStatus) ?? .notCorrupted
        self.init(status: status)
    }

    private func save(to userDefaults: UserDefaults) {
        userDefaults.set(status.rawValue, forKey: Self.databaseCorruptionStatusKey)
    }

    public static func flagDatabaseAsCorrupted(userDefaults: UserDefaults) {
        let oldState = DatabaseCorruptionState(userDefaults: userDefaults)
        switch oldState.status {
        case .notCorrupted:
            Self(status: .corrupted).save(to: userDefaults)
        case .corrupted, .corruptedButAlreadyDumpedAndRestored:
            break
        }
    }

    public static func flagCorruptedDatabaseAsDumpedAndRestored(userDefaults: UserDefaults) {
        let oldState = DatabaseCorruptionState(userDefaults: userDefaults)
        switch oldState.status {
        case .corrupted:
            DatabaseCorruptionState(status: .corruptedButAlreadyDumpedAndRestored).save(to: userDefaults)
        case .notCorrupted, .corruptedButAlreadyDumpedAndRestored:
            owsFailDebug("Flagging database as partially recovered, but it was not in the right state previously")
        }
    }

    public static func flagDatabaseAsNotCorrupted(userDefaults: UserDefaults) {
        let oldState = DatabaseCorruptionState(userDefaults: userDefaults)
        switch oldState.status {
        case .notCorrupted:
            break
        case .corrupted, .corruptedButAlreadyDumpedAndRestored:
            Self(status: .notCorrupted).save(to: userDefaults)
        }
    }
}
