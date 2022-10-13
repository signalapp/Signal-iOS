//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
import SignalServiceKit

final class GRDBDatabaseStorageAdapterTest: XCTestCase {
    func testWalFileUrl() throws {
        let input = URL(fileURLWithPath: "/tmp/foo.db")
        let expected = URL(fileURLWithPath: "/tmp/foo.db-wal")
        let actual = GRDBDatabaseStorageAdapter.walFileUrl(for: input)
        XCTAssertEqual(actual, expected)
    }

    func testShmFileUrl() throws {
        let input = URL(fileURLWithPath: "/tmp/foo.db")
        let expected = URL(fileURLWithPath: "/tmp/foo.db-shm")
        let actual = GRDBDatabaseStorageAdapter.shmFileUrl(for: input)
        XCTAssertEqual(actual, expected)
    }
}
