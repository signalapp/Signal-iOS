//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
import SignalServiceKit

final class SqliteUtilTest: XCTestCase {
    func testIsSafe() {
        let unsafeNames: [String] = [
            "",
            " table",
            "1table",
            "_table",
            "'table'",
            "táble",
            "sqlite",
            "sqlite_master",
            "SQLITE_master",
            String(repeating: "x", count: 2000)
        ]
        for unsafeName in unsafeNames {
            XCTAssertFalse(SqliteUtil.isSafe(sqlName: unsafeName))
        }

        let safeNames: [String] = ["table", "table_name", "table1"]
        for safeName in safeNames {
            XCTAssertTrue(SqliteUtil.isSafe(sqlName: safeName))
        }
    }
}
