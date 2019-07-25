//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import XCTest
import SignalServiceKit
@testable import SignalMessaging

class YDBToGRDBMigrationTest: SignalBaseTest {

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func testKeyValueInt() {
        let store1 = SDSKeyValueStore(collection: "store1")
        let store2 = SDSKeyValueStore(collection: "store2")
        let store3 = SDSKeyValueStore(collection: "store3")

        self.read { transaction in
            XCTAssertEqual(0, store1.numberOfKeys(transaction: transaction))
            XCTAssertEqual(0, store2.numberOfKeys(transaction: transaction))
            XCTAssertEqual(0, store3.numberOfKeys(transaction: transaction))
        }

        self.yapWrite { transaction in
            store1.setInt(0, key: "key0", transaction: transaction.asAnyWrite)
            store2.setInt(1, key: "key0", transaction: transaction.asAnyWrite)
            store3.setInt(2, key: "key0", transaction: transaction.asAnyWrite)
            store1.setInt(3, key: "key1", transaction: transaction.asAnyWrite)
            store2.setInt(4, key: "key1", transaction: transaction.asAnyWrite)
        }

        self.read { transaction in
            XCTAssertEqual(0, store1.numberOfKeys(transaction: transaction))
            XCTAssertEqual(0, store2.numberOfKeys(transaction: transaction))
            XCTAssertEqual(0, store3.numberOfKeys(transaction: transaction))
        }

        let migratorGroups = [
            GRDBMigratorGroup { ydbTransaction in
                return [
                    GRDBKeyValueStoreMigrator<Any>(label: "store1", keyStore: store1, ydbTransaction: ydbTransaction, memorySamplerRatio: 1.0),
                    GRDBKeyValueStoreMigrator<Any>(label: "store2", keyStore: store2, ydbTransaction: ydbTransaction, memorySamplerRatio: 1.0),
                    GRDBKeyValueStoreMigrator<Any>(label: "store3", keyStore: store3, ydbTransaction: ydbTransaction, memorySamplerRatio: 1.0)
                ]
            }
        ]

        try! YDBToGRDBMigration().migrate(migratorGroups: migratorGroups)

        self.read { transaction in
            XCTAssertEqual(2, store1.numberOfKeys(transaction: transaction))
            XCTAssertEqual(2, store2.numberOfKeys(transaction: transaction))
            XCTAssertEqual(1, store3.numberOfKeys(transaction: transaction))

            XCTAssertTrue(store1.hasValue(forKey: "key0", transaction: transaction))
            XCTAssertTrue(store2.hasValue(forKey: "key0", transaction: transaction))
            XCTAssertTrue(store3.hasValue(forKey: "key0", transaction: transaction))

            XCTAssertTrue(store1.hasValue(forKey: "key1", transaction: transaction))
            XCTAssertTrue(store2.hasValue(forKey: "key1", transaction: transaction))
            XCTAssertFalse(store3.hasValue(forKey: "key1", transaction: transaction))

            XCTAssertEqual(0, store1.getInt("key0", transaction: transaction))
            XCTAssertEqual(1, store2.getInt("key0", transaction: transaction))
            XCTAssertEqual(2, store3.getInt("key0", transaction: transaction))
            XCTAssertEqual(3, store1.getInt("key1", transaction: transaction))
            XCTAssertEqual(4, store2.getInt("key1", transaction: transaction))
        }
    }

    private func randomData() -> Data {
        return UUID().uuidString.data(using: .utf8)!
    }

    func testKeyValueData() {
        let store1 = SDSKeyValueStore(collection: "store1")
        let store2 = SDSKeyValueStore(collection: "store2")
        let store3 = SDSKeyValueStore(collection: "store3")

        let value0 = randomData()
        let value1 = randomData()
        let value2 = randomData()
        let value3 = randomData()
        let value4 = randomData()

        self.read { transaction in
            XCTAssertEqual(0, store1.numberOfKeys(transaction: transaction))
            XCTAssertEqual(0, store2.numberOfKeys(transaction: transaction))
            XCTAssertEqual(0, store3.numberOfKeys(transaction: transaction))
        }

        self.yapWrite { transaction in
            store1.setData(value0, key: "key0", transaction: transaction.asAnyWrite)
            store2.setData(value1, key: "key0", transaction: transaction.asAnyWrite)
            store3.setData(value2, key: "key0", transaction: transaction.asAnyWrite)
            store1.setData(value3, key: "key1", transaction: transaction.asAnyWrite)
            store2.setData(value4, key: "key1", transaction: transaction.asAnyWrite)
        }

        self.read { transaction in
            XCTAssertEqual(0, store1.numberOfKeys(transaction: transaction))
            XCTAssertEqual(0, store2.numberOfKeys(transaction: transaction))
            XCTAssertEqual(0, store3.numberOfKeys(transaction: transaction))
        }

        let migratorGroups = [
            GRDBMigratorGroup { ydbTransaction in
                return [
                    GRDBKeyValueStoreMigrator<Any>(label: "store1", keyStore: store1, ydbTransaction: ydbTransaction, memorySamplerRatio: 1.0),
                    GRDBKeyValueStoreMigrator<Any>(label: "store2", keyStore: store2, ydbTransaction: ydbTransaction, memorySamplerRatio: 1.0),
                    GRDBKeyValueStoreMigrator<Any>(label: "store3", keyStore: store3, ydbTransaction: ydbTransaction, memorySamplerRatio: 1.0)
                ]
            }
        ]

        try! YDBToGRDBMigration().migrate(migratorGroups: migratorGroups)

        self.read { transaction in
            XCTAssertEqual(2, store1.numberOfKeys(transaction: transaction))
            XCTAssertEqual(2, store2.numberOfKeys(transaction: transaction))
            XCTAssertEqual(1, store3.numberOfKeys(transaction: transaction))

            XCTAssertTrue(store1.hasValue(forKey: "key0", transaction: transaction))
            XCTAssertTrue(store2.hasValue(forKey: "key0", transaction: transaction))
            XCTAssertTrue(store3.hasValue(forKey: "key0", transaction: transaction))

            XCTAssertTrue(store1.hasValue(forKey: "key1", transaction: transaction))
            XCTAssertTrue(store2.hasValue(forKey: "key1", transaction: transaction))
            XCTAssertFalse(store3.hasValue(forKey: "key1", transaction: transaction))

            XCTAssertEqual(value0, store1.getData("key0", transaction: transaction))
            XCTAssertEqual(value1, store2.getData("key0", transaction: transaction))
            XCTAssertEqual(value2, store3.getData("key0", transaction: transaction))
            XCTAssertEqual(value3, store1.getData("key1", transaction: transaction))
            XCTAssertEqual(value4, store2.getData("key1", transaction: transaction))
        }
    }

    private func randomString() -> String {
        return UUID().uuidString
    }

    func testKeyValueString() {
        let store1 = SDSKeyValueStore(collection: "store1")
        let store2 = SDSKeyValueStore(collection: "store2")
        let store3 = SDSKeyValueStore(collection: "store3")

        let value0 = randomString()
        let value1 = randomString()
        let value2 = randomString()
        let value3 = randomString()
        let value4 = randomString()

        self.read { transaction in
            XCTAssertEqual(0, store1.numberOfKeys(transaction: transaction))
            XCTAssertEqual(0, store2.numberOfKeys(transaction: transaction))
            XCTAssertEqual(0, store3.numberOfKeys(transaction: transaction))
        }

        self.yapWrite { transaction in
            store1.setString(value0, key: "key0", transaction: transaction.asAnyWrite)
            store2.setString(value1, key: "key0", transaction: transaction.asAnyWrite)
            store3.setString(value2, key: "key0", transaction: transaction.asAnyWrite)
            store1.setString(value3, key: "key1", transaction: transaction.asAnyWrite)
            store2.setString(value4, key: "key1", transaction: transaction.asAnyWrite)
        }

        self.read { transaction in
            XCTAssertEqual(0, store1.numberOfKeys(transaction: transaction))
            XCTAssertEqual(0, store2.numberOfKeys(transaction: transaction))
            XCTAssertEqual(0, store3.numberOfKeys(transaction: transaction))
        }

        let migratorGroups = [
            GRDBMigratorGroup { ydbTransaction in
                return [
                    GRDBKeyValueStoreMigrator<Any>(label: "store1", keyStore: store1, ydbTransaction: ydbTransaction, memorySamplerRatio: 1.0),
                    GRDBKeyValueStoreMigrator<Any>(label: "store2", keyStore: store2, ydbTransaction: ydbTransaction, memorySamplerRatio: 1.0),
                    GRDBKeyValueStoreMigrator<Any>(label: "store3", keyStore: store3, ydbTransaction: ydbTransaction, memorySamplerRatio: 1.0)
                ]
            }
        ]

        try! YDBToGRDBMigration().migrate(migratorGroups: migratorGroups)

        self.read { transaction in
            XCTAssertEqual(2, store1.numberOfKeys(transaction: transaction))
            XCTAssertEqual(2, store2.numberOfKeys(transaction: transaction))
            XCTAssertEqual(1, store3.numberOfKeys(transaction: transaction))

            XCTAssertTrue(store1.hasValue(forKey: "key0", transaction: transaction))
            XCTAssertTrue(store2.hasValue(forKey: "key0", transaction: transaction))
            XCTAssertTrue(store3.hasValue(forKey: "key0", transaction: transaction))

            XCTAssertTrue(store1.hasValue(forKey: "key1", transaction: transaction))
            XCTAssertTrue(store2.hasValue(forKey: "key1", transaction: transaction))
            XCTAssertFalse(store3.hasValue(forKey: "key1", transaction: transaction))

            XCTAssertEqual(value0, store1.getString("key0", transaction: transaction))
            XCTAssertEqual(value1, store2.getString("key0", transaction: transaction))
            XCTAssertEqual(value2, store3.getString("key0", transaction: transaction))
            XCTAssertEqual(value3, store1.getString("key1", transaction: transaction))
            XCTAssertEqual(value4, store2.getString("key1", transaction: transaction))
        }
    }

    private func randomDate() -> Date {
        return NSDate.ows_date(withMillisecondsSince1970: UInt64(arc4random()))
    }

    func testKeyValueDate() {
        let store1 = SDSKeyValueStore(collection: "store1")
        let store2 = SDSKeyValueStore(collection: "store2")
        let store3 = SDSKeyValueStore(collection: "store3")

        // A special store we use for date edge cases.
        let store4 = SDSKeyValueStore(collection: "store4")

        let value0 = randomDate()
        let value1 = randomDate()
        let value2 = randomDate()
        let value3 = randomDate()
        let value4 = randomDate()

        self.read { transaction in
            XCTAssertEqual(0, store1.numberOfKeys(transaction: transaction))
            XCTAssertEqual(0, store2.numberOfKeys(transaction: transaction))
            XCTAssertEqual(0, store3.numberOfKeys(transaction: transaction))
            XCTAssertEqual(0, store4.numberOfKeys(transaction: transaction))
        }

        self.yapWrite { transaction in
            store1.setDate(value0, key: "key0", transaction: transaction.asAnyWrite)
            store2.setDate(value1, key: "key0", transaction: transaction.asAnyWrite)
            store3.setDate(value2, key: "key0", transaction: transaction.asAnyWrite)
            store1.setDate(value3, key: "key1", transaction: transaction.asAnyWrite)
            store2.setDate(value4, key: "key1", transaction: transaction.asAnyWrite)

            // Setting as object should work.
            store4.setObject(value0, key: "key0", transaction: transaction.asAnyWrite)
            // Setting as timeIntervalSince1970 should work.
            store4.setObject(value1.timeIntervalSince1970, key: "key1", transaction: transaction.asAnyWrite)
        }

        self.read { transaction in
            XCTAssertEqual(0, store1.numberOfKeys(transaction: transaction))
            XCTAssertEqual(0, store2.numberOfKeys(transaction: transaction))
            XCTAssertEqual(0, store3.numberOfKeys(transaction: transaction))
            XCTAssertEqual(0, store4.numberOfKeys(transaction: transaction))
        }

        let migratorGroups = [
            GRDBMigratorGroup { ydbTransaction in
                return [
                    GRDBKeyValueStoreMigrator<Any>(label: "store1", keyStore: store1, ydbTransaction: ydbTransaction, memorySamplerRatio: 1.0),
                    GRDBKeyValueStoreMigrator<Any>(label: "store2", keyStore: store2, ydbTransaction: ydbTransaction, memorySamplerRatio: 1.0),
                    GRDBKeyValueStoreMigrator<Any>(label: "store3", keyStore: store3, ydbTransaction: ydbTransaction, memorySamplerRatio: 1.0),
                    GRDBKeyValueStoreMigrator<Any>(label: "store4", keyStore: store4, ydbTransaction: ydbTransaction, memorySamplerRatio: 1.0)
                ]
            }
        ]

        try! YDBToGRDBMigration().migrate(migratorGroups: migratorGroups)

        self.read { transaction in
            XCTAssertEqual(2, store1.numberOfKeys(transaction: transaction))
            XCTAssertEqual(2, store2.numberOfKeys(transaction: transaction))
            XCTAssertEqual(1, store3.numberOfKeys(transaction: transaction))

            XCTAssertTrue(store1.hasValue(forKey: "key0", transaction: transaction))
            XCTAssertTrue(store2.hasValue(forKey: "key0", transaction: transaction))
            XCTAssertTrue(store3.hasValue(forKey: "key0", transaction: transaction))

            XCTAssertTrue(store1.hasValue(forKey: "key1", transaction: transaction))
            XCTAssertTrue(store2.hasValue(forKey: "key1", transaction: transaction))
            XCTAssertFalse(store3.hasValue(forKey: "key1", transaction: transaction))

            XCTAssertEqual(value0, store1.getDate("key0", transaction: transaction))
            XCTAssertEqual(value1, store2.getDate("key0", transaction: transaction))
            XCTAssertEqual(value2, store3.getDate("key0", transaction: transaction))
            XCTAssertEqual(value3, store1.getDate("key1", transaction: transaction))
            XCTAssertEqual(value4, store2.getDate("key1", transaction: transaction))

            // Date edge cases.
            XCTAssertEqual(2, store4.numberOfKeys(transaction: transaction))
            XCTAssertTrue(store4.hasValue(forKey: "key0", transaction: transaction))
            XCTAssertTrue(store4.hasValue(forKey: "key1", transaction: transaction))
            XCTAssertFalse(store4.hasValue(forKey: "key2", transaction: transaction))
            XCTAssertEqual(value0, store4.getDate("key0", transaction: transaction))
            XCTAssertEqual(value1, store4.getDate("key1", transaction: transaction))
        }
    }
}
