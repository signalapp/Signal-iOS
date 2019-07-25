//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import XCTest
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

        let data0 = randomData()
        let data1 = randomData()
        let data2 = randomData()
        let data3 = randomData()
        let data4 = randomData()

        self.read { transaction in
            XCTAssertEqual(0, store1.numberOfKeys(transaction: transaction))
            XCTAssertEqual(0, store2.numberOfKeys(transaction: transaction))
            XCTAssertEqual(0, store3.numberOfKeys(transaction: transaction))
        }

        self.yapWrite { transaction in
            store1.setData(data0, key: "key0", transaction: transaction.asAnyWrite)
            store2.setData(data1, key: "key0", transaction: transaction.asAnyWrite)
            store3.setData(data2, key: "key0", transaction: transaction.asAnyWrite)
            store1.setData(data3, key: "key1", transaction: transaction.asAnyWrite)
            store2.setData(data4, key: "key1", transaction: transaction.asAnyWrite)
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

            XCTAssertEqual(data0, store1.getData("key0", transaction: transaction))
            XCTAssertEqual(data1, store2.getData("key0", transaction: transaction))
            XCTAssertEqual(data2, store3.getData("key0", transaction: transaction))
            XCTAssertEqual(data3, store1.getData("key1", transaction: transaction))
            XCTAssertEqual(data4, store2.getData("key1", transaction: transaction))
        }
    }
}
