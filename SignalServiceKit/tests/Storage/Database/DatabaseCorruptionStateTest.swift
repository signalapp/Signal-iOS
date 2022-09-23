//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import XCTest
import SignalServiceKit

class DatabaseCorruptionStateTest: XCTestCase {
    private func userDefaults() -> UserDefaults {
        let suiteName = UUID().uuidString
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        return userDefaults
    }

    func testCorruptionChanges() throws {
        let defaults = userDefaults()

        // Initial state
        XCTAssertEqual(
            DatabaseCorruptionState.databaseCorruptionStatus(userDefaults: defaults),
            .notCorrupted
        )

        // After flagging as corrupted
        DatabaseCorruptionState.flagDatabaseAsCorrupted(userDefaults: defaults)
        XCTAssertEqual(
            DatabaseCorruptionState.databaseCorruptionStatus(userDefaults: defaults),
            .corrupted
        )
    }
}
