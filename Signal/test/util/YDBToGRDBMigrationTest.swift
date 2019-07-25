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

    func testKeyValueMigration() {
        let store1 = SDSKeyValueStore(collection: "store1")
        let store2 = SDSKeyValueStore(collection: "store2")
        let store3 = SDSKeyValueStore(collection: "store3")

        self.yapWrite { transaction in
            store1.setInt(0, key: "int0", transaction: transaction.asAnyWrite)
            store2.setInt(1, key: "int0", transaction: transaction.asAnyWrite)
            store3.setInt(2, key: "int0", transaction: transaction.asAnyWrite)
            store1.setInt(3, key: "int1", transaction: transaction.asAnyWrite)
            store2.setInt(4, key: "int1", transaction: transaction.asAnyWrite)
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
            XCTAssertTrue(store1.hasValue(forKey: "int0", transaction: transaction))
            XCTAssertTrue(store2.hasValue(forKey: "int0", transaction: transaction))
            XCTAssertTrue(store3.hasValue(forKey: "int0", transaction: transaction))

            XCTAssertTrue(store1.hasValue(forKey: "int1", transaction: transaction))
            XCTAssertTrue(store2.hasValue(forKey: "int1", transaction: transaction))
            XCTAssertFalse(store3.hasValue(forKey: "int1", transaction: transaction))

            XCTAssertEqual(0, store1.getInt("int0", transaction: transaction))
            XCTAssertEqual(1, store2.getInt("int0", transaction: transaction))
            XCTAssertEqual(2, store3.getInt("int0", transaction: transaction))
            XCTAssertEqual(3, store1.getInt("int1", transaction: transaction))
            XCTAssertEqual(4, store2.getInt("int1", transaction: transaction))
        }
    }
}
