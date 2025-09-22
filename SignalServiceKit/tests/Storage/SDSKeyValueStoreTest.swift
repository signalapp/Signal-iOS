//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Testing

@testable import SignalServiceKit

struct KeyValueStoreTest {
    private let db = InMemoryDB()

    @Test
    func test_bool() {
        let store = KeyValueStore(collection: "test")

        db.write { transaction in
            #expect(!store.getBool("boolA", defaultValue: false, transaction: transaction))
            #expect(store.getBool("boolA", defaultValue: true, transaction: transaction))
            #expect(!store.getBool("boolB", defaultValue: false, transaction: transaction))
            #expect(store.getBool("boolB", defaultValue: true, transaction: transaction))

            store.setBool(false, key: "boolA", transaction: transaction)

            #expect(!store.getBool("boolA", defaultValue: false, transaction: transaction))
            #expect(!store.getBool("boolA", defaultValue: true, transaction: transaction))
            #expect(!store.getBool("boolB", defaultValue: false, transaction: transaction))
            #expect(store.getBool("boolB", defaultValue: true, transaction: transaction))

            store.setBool(true, key: "boolA", transaction: transaction)

            #expect(store.getBool("boolA", defaultValue: false, transaction: transaction))
            #expect(store.getBool("boolA", defaultValue: true, transaction: transaction))
            #expect(!store.getBool("boolB", defaultValue: false, transaction: transaction))
            #expect(store.getBool("boolB", defaultValue: true, transaction: transaction))

            store.setBool(false, key: "boolB", transaction: transaction)

            #expect(store.getBool("boolA", defaultValue: false, transaction: transaction))
            #expect(store.getBool("boolA", defaultValue: true, transaction: transaction))
            #expect(!store.getBool("boolB", defaultValue: false, transaction: transaction))
            #expect(!store.getBool("boolB", defaultValue: true, transaction: transaction))

            store.setBool(true, key: "boolB", transaction: transaction)

            #expect(store.getBool("boolA", defaultValue: false, transaction: transaction))
            #expect(store.getBool("boolA", defaultValue: true, transaction: transaction))
            #expect(store.getBool("boolB", defaultValue: false, transaction: transaction))
            #expect(store.getBool("boolB", defaultValue: true, transaction: transaction))
        }
    }

    @Test
    func test_string() {
        let store = KeyValueStore(collection: "test")

        db.write { transaction in
            #expect(nil == store.getString("stringA", transaction: transaction))
            #expect(nil == store.getString("stringB", transaction: transaction))

            store.setString("valueA", key: "stringA", transaction: transaction)

            #expect("valueA" == store.getString("stringA", transaction: transaction))
            #expect(nil == store.getString("stringB", transaction: transaction))

            store.setString("valueB", key: "stringA", transaction: transaction)

            #expect("valueB" == store.getString("stringA", transaction: transaction))
            #expect(nil == store.getString("stringB", transaction: transaction))

            store.setString("valueC", key: "stringB", transaction: transaction)

            #expect("valueB" == store.getString("stringA", transaction: transaction))
            #expect("valueC" == store.getString("stringB", transaction: transaction))

            store.setString(nil, key: "stringA", transaction: transaction)

            #expect(nil == store.getString("stringA", transaction: transaction))
            #expect("valueC" == store.getString("stringB", transaction: transaction))
        }
    }

    @Test
    func test_data() {
        let store = KeyValueStore(collection: "test")

        let bytesA = Randomness.generateRandomBytes(32)
        let bytesB = Randomness.generateRandomBytes(32)

        db.write { transaction in
            #expect(nil == store.getData("dataA", transaction: transaction))
            #expect(nil == store.getData("dataB", transaction: transaction))

            store.setData(bytesA, key: "dataA", transaction: transaction)

            #expect(bytesA == store.getData("dataA", transaction: transaction))
            #expect(nil == store.getData("dataB", transaction: transaction))

            store.setData(bytesB, key: "dataA", transaction: transaction)

            #expect(bytesB == store.getData("dataA", transaction: transaction))
            #expect(nil == store.getData("dataB", transaction: transaction))

            store.setData("valueC".data(using: .utf8)!, key: "dataB", transaction: transaction)

            #expect(bytesB == store.getData("dataA", transaction: transaction))
            #expect("valueC".data(using: .utf8)! == store.getData("dataB", transaction: transaction))

            store.setData(nil, key: "dataA", transaction: transaction)

            #expect(store.getData("dataA", transaction: transaction) == nil)
            #expect("valueC".data(using: .utf8)! == store.getData("dataB", transaction: transaction))
        }
    }

    @Test
    func test_misc() {
        let store = KeyValueStore(collection: "test")

        db.write { transaction in
            let key = "string"
            #expect(!store.hasValue(key, transaction: transaction))
            store.setString("value", key: key, transaction: transaction)
            #expect(store.hasValue(key, transaction: transaction))
            store.removeValue(forKey: key, transaction: transaction)
            #expect(!store.hasValue(key, transaction: transaction))
        }

        db.write { transaction in
            let key = "date"
            #expect(!store.hasValue(key, transaction: transaction))
            store.setDate(Date(), key: key, transaction: transaction)
            #expect(store.hasValue(key, transaction: transaction))
            store.removeValue(forKey: key, transaction: transaction)
            #expect(!store.hasValue(key, transaction: transaction))
        }

        db.write { transaction in
            let key = "date edge cases"

            #expect(!store.hasValue(key, transaction: transaction))

            let date1 = Date()
            store.setDate(date1, key: key, transaction: transaction)
            #expect(store.hasValue(key, transaction: transaction))
            #expect(date1.timeIntervalSince1970 == store.getDate(key, transaction: transaction)?.timeIntervalSince1970)

            store.removeValue(forKey: key, transaction: transaction)
            #expect(!store.hasValue(key, transaction: transaction))

            let date2 = Date()
            store.setObject(date2, key: key, transaction: transaction)
            #expect(store.hasValue(key, transaction: transaction))
            #expect(date2.timeIntervalSince1970 == store.getDate(key, transaction: transaction)?.timeIntervalSince1970)

            store.removeValue(forKey: key, transaction: transaction)
            #expect(!store.hasValue(key, transaction: transaction))
        }

        let bytes = Randomness.generateRandomBytes(32)
        db.write { transaction in
            let key = "data"
            #expect(!store.hasValue(key, transaction: transaction))
            store.setData(bytes, key: key, transaction: transaction)
            #expect(store.hasValue(key, transaction: transaction))
            store.removeValue(forKey: key, transaction: transaction)
            #expect(!store.hasValue(key, transaction: transaction))
        }

        db.write { transaction in
            let key = "bool"
            #expect(!store.hasValue(key, transaction: transaction))
            store.setBool(true, key: key, transaction: transaction)
            #expect(store.hasValue(key, transaction: transaction))
            store.removeValue(forKey: key, transaction: transaction)
            #expect(!store.hasValue(key, transaction: transaction))
        }

        db.write { transaction in
            let key = "uint"
            #expect(!store.hasValue(key, transaction: transaction))
            store.setUInt(0, key: key, transaction: transaction)
            #expect(store.hasValue(key, transaction: transaction))
            store.removeValue(forKey: key, transaction: transaction)
            #expect(!store.hasValue(key, transaction: transaction))
        }
    }

    @Test
    func testTypeMismatch() {
        let store = KeyValueStore(collection: "")
        db.write { tx in
            store.setInt(123, key: "A", transaction: tx)
            #expect(store.getString("A", transaction: tx) == nil)
            #expect(store.getInt("A", transaction: tx) == 123)

            store.setString("123", key: "B", transaction: tx)
            #expect(store.getInt("B", transaction: tx) == nil)
            #expect(store.getString("B", transaction: tx) == "123")
        }
    }
}

struct NewKeyValueStoreTest {
    private let db = InMemoryDB()

    @Test
    func testWriteAndFetch() {
        let store = NewKeyValueStore(collection: "")
        db.write { tx in
            store.writeValue(1, forKey: "A", tx: tx)
            store.writeValue("ABC", forKey: "B", tx: tx)
            store.writeValue(true, forKey: "C", tx: tx)
            store.writeValue(false, forKey: "D", tx: tx)
            store.writeValue(3.5, forKey: "E", tx: tx)
            store.writeValue(-1, forKey: "F", tx: tx)
            store.writeValue(Int64(bitPattern: UInt64.max - 10), forKey: "G", tx: tx)

            #expect(store.fetchValue(Int64.self, forKey: "A", tx: tx) == 1)
            #expect(store.fetchValue(String.self, forKey: "B", tx: tx) == "ABC")
            #expect(store.fetchValue(Bool.self, forKey: "C", tx: tx) == true)
            #expect(store.fetchValue(Bool.self, forKey: "D", tx: tx) == false)
            #expect(store.fetchValue(TimeInterval.self, forKey: "E", tx: tx) == 3.5)
            #expect(store.fetchValue(Int64.self, forKey: "F", tx: tx).map(UInt64.init(bitPattern:)) == UInt64.max)
            #expect(store.fetchValue(Int64.self, forKey: "G", tx: tx).map(UInt64.init(bitPattern:)) == UInt64.max - 10)

            // Booleans and integers are interchangeable
            #expect(store.fetchValue(Bool.self, forKey: "A", tx: tx) == true)
            #expect(store.fetchValue(Int64.self, forKey: "C", tx: tx) == 1)
            #expect(store.fetchValue(Int64.self, forKey: "D", tx: tx) == 0)

            store.writeValue(nil as Data?, forKey: "A", tx: tx)
            store.writeValue(nil as Data?, forKey: "B", tx: tx)
            store.writeValue(nil as Data?, forKey: "C", tx: tx)
            store.writeValue(nil as Data?, forKey: "D", tx: tx)
            store.writeValue(nil as Data?, forKey: "E", tx: tx)

            #expect(store.fetchValue(Int64.self, forKey: "A", tx: tx) == nil)
            #expect(store.fetchValue(String.self, forKey: "B", tx: tx) == nil)
            #expect(store.fetchValue(Bool.self, forKey: "C", tx: tx) == nil)
            #expect(store.fetchValue(Bool.self, forKey: "D", tx: tx) == nil)
            #expect(store.fetchValue(Double.self, forKey: "E", tx: tx) == nil)
        }
    }

    @Test
    func testMigrate() throws {
        let oldStore = KeyValueStore(collection: "")
        let newStore = NewKeyValueStore(collection: "")
        let migrator = KeyValueStoreMigrator(collection: "")
        try db.write { tx in
            oldStore.setBool(true, key: "A", transaction: tx)
            oldStore.setInt(123, key: "B", transaction: tx)
            oldStore.setString("Hello", key: "C", transaction: tx)
            oldStore.setDate(Date(timeIntervalSince1970: 1234567890.5), key: "D", transaction: tx)
            oldStore.setObject(Date(timeIntervalSince1970: 1234567890.5), key: "E", transaction: tx)

            try migrator.migrateBool("A", tx: tx)
            try migrator.migrateUInt32("B", tx: tx)
            try migrator.migrateString("C", tx: tx)
            try migrator.migrateDate("D", tx: tx)
            try migrator.migrateDate("E", tx: tx)

            #expect(newStore.fetchValue(Bool.self, forKey: "A", tx: tx) == true)
            #expect(newStore.fetchValue(Int64.self, forKey: "B", tx: tx) == 123)
            #expect(newStore.fetchValue(String.self, forKey: "C", tx: tx) == "Hello")
            #expect(newStore.fetchValue(TimeInterval.self, forKey: "D", tx: tx) == 1234567890.5)
            #expect(newStore.fetchValue(TimeInterval.self, forKey: "E", tx: tx) == 1234567890.5)
        }
    }

    @Test
    func testMigrateGarbage() throws {
        let oldStore = KeyValueStore(collection: "")
        let newStore = NewKeyValueStore(collection: "")
        let migrator = KeyValueStoreMigrator(collection: "")
        try db.write { tx in
            oldStore.setData(Data(count: 16), key: "A", transaction: tx)
            #expect(newStore.fetchValue(Data.self, forKey: "A", tx: tx) != nil)
            try migrator.migrateString("A", tx: tx)
            #expect(newStore.fetchValue(Data.self, forKey: "A", tx: tx) == nil)
        }
    }
}
