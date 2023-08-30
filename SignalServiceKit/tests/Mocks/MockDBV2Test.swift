//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import SignalServiceKit

final class MockDBV2Test: XCTestCase {
    private var schedulers: TestSchedulers {
        return TestSchedulers(scheduler: TestScheduler())
    }

    func testReetrantTransactionFails() {
        var reentrantTransactions = 0
        let db = MockDB(
            schedulers: schedulers,
            reentrantTransactionBlock: { reentrantTransactions += 1 }
        )

        db.read { tx in
            db.read { tx in
                // The Danger Zone
            }
        }

        XCTAssertEqual(reentrantTransactions, 1)

        db.write { _ in
            db.write { _ in
                // The Mega Danger Zone
            }
        }

        XCTAssertEqual(reentrantTransactions, 2)

        db.read { _ in
            db.write { _ in
                db.read { _ in
                    // You monster!
                }
            }
        }

        XCTAssertEqual(reentrantTransactions, 4)
    }

    func testRetainedTransactionFails() {
        var retainedTransactions = 0
        let db = MockDB(
            schedulers: schedulers,
            retainedTransactionBlock: { retainedTransactions += 1 }
        )

        var retainedTx: DBReadTransaction?
        defer { _ = retainedTx }

        db.read { tx in
            retainedTx = tx
        }

        XCTAssertEqual(retainedTransactions, 1)

        db.write { tx in
            retainedTx = tx
        }

        XCTAssertEqual(retainedTransactions, 2)
    }

    func testRetainedAndReentrance() {
        var retainedTransactions = 0
        var reentrantTransactions = 0
        let db = MockDB(
            schedulers: schedulers,
            reentrantTransactionBlock: { reentrantTransactions += 1 },
            retainedTransactionBlock: { retainedTransactions += 1 }
        )

        var transactions: [DBReadTransaction] = []
        defer { _ = transactions }

        db.write { tx in
            transactions.append(tx)

            db.read { tx in
                transactions.append(tx)
            }
        }

        XCTAssertEqual(retainedTransactions, 2)
        XCTAssertEqual(reentrantTransactions, 1)
    }

    func testRetainedWithThrowing() {
        var retainedTransactions = 0
        var reentrantTransactions = 0
        let db = MockDB(
            schedulers: schedulers,
            reentrantTransactionBlock: { reentrantTransactions += 1 },
            retainedTransactionBlock: { retainedTransactions += 1 }
        )

        var transactions: [DBReadTransaction] = []
        defer { _ = transactions }

        try? db.write { tx in
            transactions.append(tx)

            db.read { tx in
                transactions.append(tx)
            }

            struct SomeError: Error {}
            throw SomeError()
        }

        XCTAssertEqual(retainedTransactions, 2)
        XCTAssertEqual(reentrantTransactions, 1)
    }
}
