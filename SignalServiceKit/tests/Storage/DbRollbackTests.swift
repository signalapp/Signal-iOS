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
            XCTAssertFalse(kvStore.getBool(key, defaultValue: false, transaction: tx.asV2Read))
            kvStore.setBool(true, key: key, transaction: tx.asV2Write)
            throw SomeError()
        }

        // Even though we threw an error, "normal" writes don't rollback.
        databaseStorage.read { tx in
            XCTAssertTrue(kvStore.getBool(key, defaultValue: false, transaction: tx.asV2Read))
        }
    }

    func test_writeNoRollback_async() async {
        try? await databaseStorage.awaitableWrite { tx in
            XCTAssertFalse(kvStore.getBool(key, defaultValue: false, transaction: tx.asV2Read))
            kvStore.setBool(true, key: key, transaction: tx.asV2Write)
            throw SomeError()
        }

        // Even though we threw an error, "normal" writes don't rollback.
        databaseStorage.read { tx in
            XCTAssertTrue(kvStore.getBool(key, defaultValue: false, transaction: tx.asV2Read))
        }
    }

    func test_writeWithTxCompletionRollback() {
        databaseStorage.writeWithTxCompletion { tx in
            XCTAssertFalse(kvStore.getBool(key, defaultValue: false, transaction: tx.asV2Write))
            kvStore.setBool(true, key: key, transaction: tx.asV2Write)
            return .rollback(())
        }

        // Should have rolled back.
        databaseStorage.read { tx in
            XCTAssertFalse(kvStore.getBool(key, defaultValue: false, transaction: tx.asV2Read))
        }

        // Run it again but don't roll back this time.
        databaseStorage.writeWithTxCompletion { tx in
            do {
                kvStore.setBool(true, key: key, transaction: tx.asV2Write)
                throw SomeError()
            } catch {
                return .commit(())
            }
        }

        // Should NOT have rolled back.
        databaseStorage.read { tx in
            XCTAssertTrue(kvStore.getBool(key, defaultValue: false, transaction: tx.asV2Read))
        }
    }

    func test_writeWithTxCompletionRollback_async() async {
        await databaseStorage.awaitableWriteWithTxCompletion { tx in
            XCTAssertFalse(kvStore.getBool(key, defaultValue: false, transaction: tx.asV2Read))
            kvStore.setBool(true, key: key, transaction: tx.asV2Write)
            return .rollback(())
        }

        // Should have rolled back.
        databaseStorage.read { tx in
            XCTAssertFalse(kvStore.getBool(key, defaultValue: false, transaction: tx.asV2Read))
        }

        // Run it again but don't roll back this time.
        await databaseStorage.awaitableWriteWithTxCompletion { tx in
            do {
                kvStore.setBool(true, key: key, transaction: tx.asV2Write)
                throw SomeError()
            } catch {
                return .commit(())
            }
        }

        // Should NOT have rolled back.
        databaseStorage.read { tx in
            XCTAssertTrue(kvStore.getBool(key, defaultValue: false, transaction: tx.asV2Read))
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
            try! tx.databaseConnection.execute(sql: "CREATE TABLE testTable (value BOOLEAN);")
        }
    }

    func getBool(tx: InMemoryDB.ReadTransaction) -> Bool {
        return try! Bool.fetchOne(tx.databaseConnection, sql: "SELECT value FROM testTable LIMIT 1;") ?? false
    }

    func setBool(_ newValue: Bool, tx: InMemoryDB.ReadTransaction) {
        try! tx.databaseConnection.execute(sql: "DELETE FROM testTable;")
        try! tx.databaseConnection.execute(sql: "INSERT INTO testTable VALUES (?);", arguments: [newValue])
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

    func test_writeWithTxCompletionRollback() {
        db.writeWithTxCompletion { tx in
            XCTAssertFalse(getBool(tx: tx))
            setBool(true, tx: tx)
            return .rollback(())
        }

        // Should have rolled back.
        db.read { tx in
            XCTAssertFalse(getBool(tx: tx))
        }

        // Run it again but don't roll back this time.
        db.writeWithTxCompletion { tx in
            do {
                setBool(true, tx: tx)
                throw SomeError()
            } catch {
                return .commit(())
            }
        }

        // Should NOT have rolled back.
        db.read { tx in
            XCTAssertTrue(getBool(tx: tx))
        }
    }

    func test_writeWithTxCompletionRollback_async() async {
        await db.awaitableWriteWithTxCompletion { tx in
            XCTAssertFalse(getBool(tx: tx))
            setBool(true, tx: tx)
            return .rollback(())
        }

        // Should have rolled back.
        db.read { tx in
            XCTAssertFalse(getBool(tx: tx))
        }

        // Run it again but don't roll back this time.
        await db.awaitableWriteWithTxCompletion { tx in
            do {
                setBool(true, tx: tx)
                throw SomeError()
            } catch {
                return .commit(())
            }
        }

        // Should NOT have rolled back.
        db.read { tx in
            XCTAssertTrue(getBool(tx: tx))
        }
    }

    // MARK: - testing convenience methods

    func testConvenience_writeWithTxCompletionRollback() {
        var writeBlock: (InMemoryDB.WriteTransaction) -> TransactionCompletion<String?> = { tx in
            return .commit("Hello, World!")
        }

        var string: String? = db.writeWithTxCompletion(block: writeBlock)
        XCTAssertEqual(string, "Hello, World!")

        writeBlock = { tx in
            return .commit(nil)
        }
        string = db.writeWithTxCompletion(block: writeBlock)
        XCTAssertNil(string)

        writeBlock = { tx in
            return .rollback(nil)
        }
        string = db.writeWithTxCompletion(block: writeBlock)
        XCTAssertNil(string)
    }
}
