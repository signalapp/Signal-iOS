//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalServiceKit

class DatabaseCorruptionStateTest: XCTestCase {
    func testCorruptionChanges() throws {
        let defaults = TestUtils.userDefaults()
        func fetch() -> DatabaseCorruptionState {
            DatabaseCorruptionState(userDefaults: defaults)
        }
        func expected(
            _ status: DatabaseCorruptionState.DatabaseCorruptionStatus,
            count: UInt
        ) -> DatabaseCorruptionState {
            DatabaseCorruptionState(status: status, count: count)
        }

        // Initial state
        XCTAssertEqual(fetch(), expected(.notCorrupted, count: 0))

        // After flagging as corrupted
        DatabaseCorruptionState.flagDatabaseAsCorrupted(userDefaults: defaults)
        XCTAssertEqual(fetch(), expected(.corrupted, count: 1))

        // After partial recovery
        DatabaseCorruptionState.flagCorruptedDatabaseAsDumpedAndRestored(userDefaults: defaults)
        XCTAssertEqual(fetch(), expected(.corruptedButAlreadyDumpedAndRestored, count: 1))

        // After full recovery
        DatabaseCorruptionState.flagDatabaseAsRecoveredFromCorruption(userDefaults: defaults)
        XCTAssertEqual(fetch(), expected(.notCorrupted, count: 1))

        // After another corruption
        DatabaseCorruptionState.flagDatabaseAsCorrupted(userDefaults: defaults)
        XCTAssertEqual(fetch(), expected(.corrupted, count: 2))
    }

    func testLegacyFalseValueWithoutCount() throws {
        let defaults = TestUtils.userDefaults()
        defaults.set(false, forKey: DatabaseCorruptionState.databaseCorruptionStatusKey)

        let expected = DatabaseCorruptionState(status: .notCorrupted, count: 0)
        let actual = DatabaseCorruptionState(userDefaults: defaults)
        XCTAssertEqual(actual, expected)
    }

    func testLegacyTrueValueWithoutCount() throws {
        let defaults = TestUtils.userDefaults()
        defaults.set(true, forKey: DatabaseCorruptionState.databaseCorruptionStatusKey)

        let expected = DatabaseCorruptionState(status: .corrupted, count: 1)
        let actual = DatabaseCorruptionState(userDefaults: defaults)
        XCTAssertEqual(actual, expected)
    }

    func testInvalidData() throws {
        let defaults = TestUtils.userDefaults()
        defaults.set("garbage", forKey: DatabaseCorruptionState.databaseCorruptionStatusKey)
        defaults.set("garbage", forKey: DatabaseCorruptionState.databaseCorruptionCountKey)

        let expected = DatabaseCorruptionState(status: .notCorrupted, count: 0)
        let actual = DatabaseCorruptionState(userDefaults: defaults)
        XCTAssertEqual(actual, expected)
    }
}
