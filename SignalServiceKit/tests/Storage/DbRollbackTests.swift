//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest
@testable import SignalServiceKit

// MARK: -

class SDSDatabaseStorageRollbackTest: SSKBaseTest {

    // MARK: - Test Life Cycle

    var databaseStorage: SDSDatabaseStorage!
    var kvStore: KeyValueStore!
    let key = "boolKey"

    override func setUp() {
        super.setUp()

        kvStore = KeyValueStore(collection: "SDSDatabaseStorageRollbackTest")
        databaseStorage = SSKEnvironment.shared.databaseStorageRef
    }

    // MARK: -

    class SomeError: Error {}

    func test_writeNoRollback() {
        try? databaseStorage.write { tx in
            XCTAssertFalse(kvStore.getBool(key, defaultValue: false, transaction: tx))
            kvStore.setBool(true, key: key, transaction: tx)
            throw SomeError()
        }

        // Even though we threw an error, "normal" writes don't rollback.
        databaseStorage.read { tx in
            XCTAssertTrue(kvStore.getBool(key, defaultValue: false, transaction: tx))
        }
    }

    func test_writeNoRollback_async() async {
        try? await databaseStorage.awaitableWrite { tx in
            XCTAssertFalse(kvStore.getBool(key, defaultValue: false, transaction: tx))
            kvStore.setBool(true, key: key, transaction: tx)
            throw SomeError()
        }

        // Even though we threw an error, "normal" writes don't rollback.
        databaseStorage.read { tx in
            XCTAssertTrue(kvStore.getBool(key, defaultValue: false, transaction: tx))
        }
    }

    func test_writeWithRollbackIfThrows() {
        try? databaseStorage.writeWithRollbackIfThrows { tx in
            XCTAssertFalse(kvStore.getBool(key, defaultValue: false, transaction: tx))
            kvStore.setBool(true, key: key, transaction: tx)
            throw SomeError()
        }

        // Should have rolled back.
        databaseStorage.read { tx in
            XCTAssertFalse(kvStore.getBool(key, defaultValue: false, transaction: tx))
        }

        // Run it again but catch the throw this time.
        databaseStorage.writeWithRollbackIfThrows { tx in
            do {
                kvStore.setBool(true, key: key, transaction: tx)
                throw SomeError()
            } catch {
                // Suppress error
            }
        }

        // Should NOT have rolled back.
        databaseStorage.read { tx in
            XCTAssertTrue(kvStore.getBool(key, defaultValue: false, transaction: tx))
        }
    }

    func test_writeWithRollbackIfThrows_async() async {
        try? await databaseStorage.awaitableWriteWithRollbackIfThrows { tx in
            XCTAssertFalse(kvStore.getBool(key, defaultValue: false, transaction: tx))
            kvStore.setBool(true, key: key, transaction: tx)
            throw SomeError()
        }

        // Should have rolled back.
        databaseStorage.read { tx in
            XCTAssertFalse(kvStore.getBool(key, defaultValue: false, transaction: tx))
        }

        // Run it again but catch the throw this time.
        await databaseStorage.awaitableWriteWithRollbackIfThrows { tx in
            do {
                kvStore.setBool(true, key: key, transaction: tx)
                throw SomeError()
            } catch {
                // Suppress error
            }
        }

        // Should NOT have rolled back.
        databaseStorage.read { tx in
            XCTAssertTrue(kvStore.getBool(key, defaultValue: false, transaction: tx))
        }
    }
}

class InMemoryDBRollbackTest: XCTestCase {

    // MARK: - Test Life Cycle

    var db: InMemoryDB!

    override func setUp() {
        super.setUp()

        db = InMemoryDB()
        db.write { tx in
            try! tx.database.execute(sql: "CREATE TABLE testTable (value BOOLEAN);")
        }
    }

    func getBool(tx: DBReadTransaction) -> Bool {
        return try! Bool.fetchOne(tx.database, sql: "SELECT value FROM testTable LIMIT 1;") ?? false
    }

    func setBool(_ newValue: Bool, tx: DBReadTransaction) {
        try! tx.database.execute(sql: "DELETE FROM testTable;")
        try! tx.database.execute(sql: "INSERT INTO testTable VALUES (?);", arguments: [newValue])
    }

    // MARK: -

    class SomeError: Error {}

    func test_writeNoRollback() {
        try? db.write { tx in
            XCTAssertFalse(getBool(tx: tx))
            setBool(true, tx: tx)
            throw SomeError()
        }

        // Even though we threw an error, "normal" writes don't rollback.
        db.read { tx in
            XCTAssertTrue(getBool(tx: tx))
        }
    }

    func test_writeNoRollback_async() async {
        try? await db.awaitableWrite { tx in
            XCTAssertFalse(getBool(tx: tx))
            setBool(true, tx: tx)
            throw SomeError()
        }

        // Even though we threw an error, "normal" writes don't rollback.
        db.read { tx in
            XCTAssertTrue(getBool(tx: tx))
        }
    }

    func test_writeWithRollbackIfThrows() {
        try? db.writeWithRollbackIfThrows { tx in
            XCTAssertFalse(getBool(tx: tx))
            setBool(true, tx: tx)
            throw SomeError()
        }

        // Should have rolled back.
        db.read { tx in
            XCTAssertFalse(getBool(tx: tx))
        }

        // Run it again but catch the throw this time.
        db.writeWithRollbackIfThrows { tx in
            do {
                setBool(true, tx: tx)
                throw SomeError()
            } catch {
                // Suppress error
            }
        }

        // Should NOT have rolled back.
        db.read { tx in
            XCTAssertTrue(getBool(tx: tx))
        }
    }

    func test_writeWithRollbackIfThrows_async() async {
        try? await db.awaitableWriteWithRollbackIfThrows { tx in
            XCTAssertFalse(getBool(tx: tx))
            setBool(true, tx: tx)
            throw SomeError()
        }

        // Should have rolled back.
        db.read { tx in
            XCTAssertFalse(getBool(tx: tx))
        }

        // Run it again but catch the throw this time.
        await db.awaitableWriteWithRollbackIfThrows { tx in
            do {
                setBool(true, tx: tx)
                throw SomeError()
            } catch {
                // Suppress error
            }
        }

        // Should NOT have rolled back.
        db.read { tx in
            XCTAssertTrue(getBool(tx: tx))
        }
    }
}
