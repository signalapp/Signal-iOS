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
        ) -> DatabaseCorruptionState {
            DatabaseCorruptionState(status: status)
        }

        // Initial state
        XCTAssertEqual(fetch(), expected(.notCorrupted))

        // After flagging as corrupted
        DatabaseCorruptionState.flagDatabaseAsCorrupted(userDefaults: defaults)
        XCTAssertEqual(fetch(), expected(.corrupted))

        // After partial recovery
        DatabaseCorruptionState.flagCorruptedDatabaseAsDumpedAndRestored(userDefaults: defaults)
        XCTAssertEqual(fetch(), expected(.corruptedButAlreadyDumpedAndRestored))

        // After full recovery
        DatabaseCorruptionState.flagDatabaseAsNotCorrupted(userDefaults: defaults)
        XCTAssertEqual(fetch(), expected(.notCorrupted))

        // After another corruption
        DatabaseCorruptionState.flagDatabaseAsCorrupted(userDefaults: defaults)
        XCTAssertEqual(fetch(), expected(.corrupted))
    }

    func testLegacyFalseValue() throws {
        let defaults = TestUtils.userDefaults()
        defaults.set(false, forKey: DatabaseCorruptionState.databaseCorruptionStatusKey)

        let expected = DatabaseCorruptionState(status: .notCorrupted)
        let actual = DatabaseCorruptionState(userDefaults: defaults)
        XCTAssertEqual(actual, expected)
    }

    func testLegacyTrueValue() throws {
        let defaults = TestUtils.userDefaults()
        defaults.set(true, forKey: DatabaseCorruptionState.databaseCorruptionStatusKey)

        let expected = DatabaseCorruptionState(status: .corrupted)
        let actual = DatabaseCorruptionState(userDefaults: defaults)
        XCTAssertEqual(actual, expected)
    }

    func testInvalidData() throws {
        let defaults = TestUtils.userDefaults()
        defaults.set("garbage", forKey: DatabaseCorruptionState.databaseCorruptionStatusKey)

        let expected = DatabaseCorruptionState(status: .notCorrupted)
        let actual = DatabaseCorruptionState(userDefaults: defaults)
        XCTAssertEqual(actual, expected)
    }
}
