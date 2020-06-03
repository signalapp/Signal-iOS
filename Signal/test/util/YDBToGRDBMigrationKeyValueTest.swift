//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import XCTest
import SignalServiceKit
@testable import SignalMessaging

class YDBToGRDBMigrationKeyValueTest: SignalBaseTest {

    // MARK: - Dependencies

    var storageCoordinator: StorageCoordinator {
        return SSKEnvironment.shared.storageCoordinator
    }

    // MARK: -

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func testKeyValueInt() {
        storageCoordinator.useGRDBForTests()

        let store1 = SDSKeyValueStore(collection: "store1")
        let store2 = SDSKeyValueStore(collection: "store2")
        let store3 = SDSKeyValueStore(collection: "store3")

        let randomValue = {
            return Int(arc4random())
        }
        let value0 = randomValue()
        let value1 = randomValue()
        let value2 = randomValue()
        let value3 = randomValue()
        let value4 = randomValue()

        self.read { transaction in
            XCTAssertEqual(0, store1.numberOfKeys(transaction: transaction))
            XCTAssertEqual(0, store2.numberOfKeys(transaction: transaction))
            XCTAssertEqual(0, store3.numberOfKeys(transaction: transaction))
        }

        self.yapWrite { transaction in
            store1.setInt(value0, key: "key0", transaction: transaction.asAnyWrite)
            store2.setInt(value1, key: "key0", transaction: transaction.asAnyWrite)
            store3.setInt(value2, key: "key0", transaction: transaction.asAnyWrite)
            store1.setInt(value3, key: "key1", transaction: transaction.asAnyWrite)
            store2.setInt(value4, key: "key1", transaction: transaction.asAnyWrite)
        }

        self.read { transaction in
            XCTAssertEqual(0, store1.numberOfKeys(transaction: transaction))
            XCTAssertEqual(0, store2.numberOfKeys(transaction: transaction))
            XCTAssertEqual(0, store3.numberOfKeys(transaction: transaction))
        }

        let migratorGroups = [
            GRDBMigratorGroup { ydbTransaction in
                return [
                    GRDBKeyValueStoreMigrator<Any>(label: "store1", keyStore: store1, ydbTransaction: ydbTransaction),
                    GRDBKeyValueStoreMigrator<Any>(label: "store2", keyStore: store2, ydbTransaction: ydbTransaction),
                    GRDBKeyValueStoreMigrator<Any>(label: "store3", keyStore: store3, ydbTransaction: ydbTransaction)
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

            XCTAssertEqual(value0, store1.getInt("key0", transaction: transaction))
            XCTAssertEqual(value1, store2.getInt("key0", transaction: transaction))
            XCTAssertEqual(value2, store3.getInt("key0", transaction: transaction))
            XCTAssertEqual(value3, store1.getInt("key1", transaction: transaction))
            XCTAssertEqual(value4, store2.getInt("key1", transaction: transaction))
            XCTAssertNil(store3.getInt("key1", transaction: transaction))

            // NSNumber variations
            XCTAssertEqual(NSNumber(value: value0), store1.getNSNumber("key0", transaction: transaction))
            XCTAssertEqual(NSNumber(value: value1), store2.getNSNumber("key0", transaction: transaction))
            XCTAssertEqual(NSNumber(value: value2), store3.getNSNumber("key0", transaction: transaction))
            XCTAssertEqual(NSNumber(value: value3), store1.getNSNumber("key1", transaction: transaction))
            XCTAssertEqual(NSNumber(value: value4), store2.getNSNumber("key1", transaction: transaction))
            XCTAssertNil(store3.getNSNumber("key1", transaction: transaction))
        }
    }

    func testKeyValueUInt() {
        storageCoordinator.useGRDBForTests()

        let store1 = SDSKeyValueStore(collection: "store1")
        let store2 = SDSKeyValueStore(collection: "store2")
        let store3 = SDSKeyValueStore(collection: "store3")

        let randomValue = {
            return UInt(arc4random())
        }
        let value0 = randomValue()
        let value1 = randomValue()
        let value2 = randomValue()
        let value3 = randomValue()
        let value4 = randomValue()

        self.read { transaction in
            XCTAssertEqual(0, store1.numberOfKeys(transaction: transaction))
            XCTAssertEqual(0, store2.numberOfKeys(transaction: transaction))
            XCTAssertEqual(0, store3.numberOfKeys(transaction: transaction))
        }

        self.yapWrite { transaction in
            store1.setUInt(value0, key: "key0", transaction: transaction.asAnyWrite)
            store2.setUInt(value1, key: "key0", transaction: transaction.asAnyWrite)
            store3.setUInt(value2, key: "key0", transaction: transaction.asAnyWrite)
            store1.setUInt(value3, key: "key1", transaction: transaction.asAnyWrite)
            store2.setUInt(value4, key: "key1", transaction: transaction.asAnyWrite)
        }

        self.read { transaction in
            XCTAssertEqual(0, store1.numberOfKeys(transaction: transaction))
            XCTAssertEqual(0, store2.numberOfKeys(transaction: transaction))
            XCTAssertEqual(0, store3.numberOfKeys(transaction: transaction))
        }

        let migratorGroups = [
            GRDBMigratorGroup { ydbTransaction in
                return [
                    GRDBKeyValueStoreMigrator<Any>(label: "store1", keyStore: store1, ydbTransaction: ydbTransaction),
                    GRDBKeyValueStoreMigrator<Any>(label: "store2", keyStore: store2, ydbTransaction: ydbTransaction),
                    GRDBKeyValueStoreMigrator<Any>(label: "store3", keyStore: store3, ydbTransaction: ydbTransaction)
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

            XCTAssertEqual(value0, store1.getUInt("key0", transaction: transaction))
            XCTAssertEqual(value1, store2.getUInt("key0", transaction: transaction))
            XCTAssertEqual(value2, store3.getUInt("key0", transaction: transaction))
            XCTAssertEqual(value3, store1.getUInt("key1", transaction: transaction))
            XCTAssertEqual(value4, store2.getUInt("key1", transaction: transaction))
            XCTAssertNil(store3.getUInt("key1", transaction: transaction))

            // NSNumber variations
            XCTAssertEqual(NSNumber(value: value0), store1.getNSNumber("key0", transaction: transaction))
            XCTAssertEqual(NSNumber(value: value1), store2.getNSNumber("key0", transaction: transaction))
            XCTAssertEqual(NSNumber(value: value2), store3.getNSNumber("key0", transaction: transaction))
            XCTAssertEqual(NSNumber(value: value3), store1.getNSNumber("key1", transaction: transaction))
            XCTAssertEqual(NSNumber(value: value4), store2.getNSNumber("key1", transaction: transaction))
            XCTAssertNil(store3.getNSNumber("key1", transaction: transaction))
        }
    }

    func testKeyValueDouble() {
        storageCoordinator.useGRDBForTests()

        let store1 = SDSKeyValueStore(collection: "store1")
        let store2 = SDSKeyValueStore(collection: "store2")
        let store3 = SDSKeyValueStore(collection: "store3")

        let randomValue = {
            return Double(arc4random()) / Double(arc4random())
        }
        let value0 = randomValue()
        let value1 = randomValue()
        let value2 = randomValue()
        let value3 = randomValue()
        let value4 = randomValue()

        self.read { transaction in
            XCTAssertEqual(0, store1.numberOfKeys(transaction: transaction))
            XCTAssertEqual(0, store2.numberOfKeys(transaction: transaction))
            XCTAssertEqual(0, store3.numberOfKeys(transaction: transaction))
        }

        self.yapWrite { transaction in
            store1.setDouble(value0, key: "key0", transaction: transaction.asAnyWrite)
            store2.setDouble(value1, key: "key0", transaction: transaction.asAnyWrite)
            store3.setDouble(value2, key: "key0", transaction: transaction.asAnyWrite)
            store1.setDouble(value3, key: "key1", transaction: transaction.asAnyWrite)
            store2.setDouble(value4, key: "key1", transaction: transaction.asAnyWrite)
        }

        self.read { transaction in
            XCTAssertEqual(0, store1.numberOfKeys(transaction: transaction))
            XCTAssertEqual(0, store2.numberOfKeys(transaction: transaction))
            XCTAssertEqual(0, store3.numberOfKeys(transaction: transaction))
        }

        let migratorGroups = [
            GRDBMigratorGroup { ydbTransaction in
                return [
                    GRDBKeyValueStoreMigrator<Any>(label: "store1", keyStore: store1, ydbTransaction: ydbTransaction),
                    GRDBKeyValueStoreMigrator<Any>(label: "store2", keyStore: store2, ydbTransaction: ydbTransaction),
                    GRDBKeyValueStoreMigrator<Any>(label: "store3", keyStore: store3, ydbTransaction: ydbTransaction)
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

            XCTAssertEqual(value0, store1.getDouble("key0", transaction: transaction))
            XCTAssertEqual(value1, store2.getDouble("key0", transaction: transaction))
            XCTAssertEqual(value2, store3.getDouble("key0", transaction: transaction))
            XCTAssertEqual(value3, store1.getDouble("key1", transaction: transaction))
            XCTAssertEqual(value4, store2.getDouble("key1", transaction: transaction))
            XCTAssertNil(store3.getDouble("key1", transaction: transaction))

            // NSNumber variations
            XCTAssertEqual(NSNumber(value: value0), store1.getNSNumber("key0", transaction: transaction))
            XCTAssertEqual(NSNumber(value: value1), store2.getNSNumber("key0", transaction: transaction))
            XCTAssertEqual(NSNumber(value: value2), store3.getNSNumber("key0", transaction: transaction))
            XCTAssertEqual(NSNumber(value: value3), store1.getNSNumber("key1", transaction: transaction))
            XCTAssertEqual(NSNumber(value: value4), store2.getNSNumber("key1", transaction: transaction))
            XCTAssertNil(store3.getNSNumber("key1", transaction: transaction))
        }
    }

    func testKeyValueData() {
        storageCoordinator.useGRDBForTests()

        let store1 = SDSKeyValueStore(collection: "store1")
        let store2 = SDSKeyValueStore(collection: "store2")
        let store3 = SDSKeyValueStore(collection: "store3")

        let randomValue = {
            return UUID().uuidString.data(using: .utf8)!
        }
        let value0 = randomValue()
        let value1 = randomValue()
        let value2 = randomValue()
        let value3 = randomValue()
        let value4 = randomValue()

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
                    GRDBKeyValueStoreMigrator<Any>(label: "store1", keyStore: store1, ydbTransaction: ydbTransaction),
                    GRDBKeyValueStoreMigrator<Any>(label: "store2", keyStore: store2, ydbTransaction: ydbTransaction),
                    GRDBKeyValueStoreMigrator<Any>(label: "store3", keyStore: store3, ydbTransaction: ydbTransaction)
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
            XCTAssertNil(store3.getData("key1", transaction: transaction))
        }
    }

    func testKeyValueString() {
        storageCoordinator.useGRDBForTests()

        let store1 = SDSKeyValueStore(collection: "store1")
        let store2 = SDSKeyValueStore(collection: "store2")
        let store3 = SDSKeyValueStore(collection: "store3")

        let randomValue = {
            return UUID().uuidString
        }
        let value0 = randomValue()
        let value1 = randomValue()
        let value2 = randomValue()
        let value3 = randomValue()
        let value4 = randomValue()

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
                    GRDBKeyValueStoreMigrator<Any>(label: "store1", keyStore: store1, ydbTransaction: ydbTransaction),
                    GRDBKeyValueStoreMigrator<Any>(label: "store2", keyStore: store2, ydbTransaction: ydbTransaction),
                    GRDBKeyValueStoreMigrator<Any>(label: "store3", keyStore: store3, ydbTransaction: ydbTransaction)
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
            XCTAssertNil(store3.getString("key1", transaction: transaction))
        }
    }

    func testKeyValueDate() {
        storageCoordinator.useGRDBForTests()

        let store1 = SDSKeyValueStore(collection: "store1")
        let store2 = SDSKeyValueStore(collection: "store2")
        let store3 = SDSKeyValueStore(collection: "store3")

        // A special store we use for date edge cases.
        let store4 = SDSKeyValueStore(collection: "store4")

        let randomValue = {
            return NSDate.ows_date(withMillisecondsSince1970: UInt64(arc4random()))
        }
        let value0 = randomValue()
        let value1 = randomValue()
        let value2 = randomValue()
        let value3 = randomValue()
        let value4 = randomValue()

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
                    GRDBKeyValueStoreMigrator<Any>(label: "store1", keyStore: store1, ydbTransaction: ydbTransaction),
                    GRDBKeyValueStoreMigrator<Any>(label: "store2", keyStore: store2, ydbTransaction: ydbTransaction),
                    GRDBKeyValueStoreMigrator<Any>(label: "store3", keyStore: store3, ydbTransaction: ydbTransaction),
                    GRDBKeyValueStoreMigrator<Any>(label: "store4", keyStore: store4, ydbTransaction: ydbTransaction)
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
            XCTAssertNil(store3.getDate("key1", transaction: transaction))

            // Date edge cases.
            XCTAssertEqual(2, store4.numberOfKeys(transaction: transaction))
            XCTAssertTrue(store4.hasValue(forKey: "key0", transaction: transaction))
            XCTAssertTrue(store4.hasValue(forKey: "key1", transaction: transaction))
            XCTAssertFalse(store4.hasValue(forKey: "key2", transaction: transaction))
            XCTAssertEqual(value0, store4.getDate("key0", transaction: transaction))
            XCTAssertEqual(value1, store4.getDate("key1", transaction: transaction))
        }
    }

    func testKeyValueObject() {
        storageCoordinator.useGRDBForTests()

        let store1 = SDSKeyValueStore(collection: "store1")
        let store2 = SDSKeyValueStore(collection: "store2")
        let store3 = SDSKeyValueStore(collection: "store3")

        let randomValue = {
            return UUID().uuidString
        }
        let value0: String = randomValue()
        let value1: [String] = [randomValue()]
        let value2: [String: String] =  [ randomValue(): randomValue() ]
        let value3: [String] = [randomValue(), randomValue()]
        let value4: [String: String] = [
            randomValue(): randomValue(),
            randomValue(): randomValue()
        ]

        self.read { transaction in
            XCTAssertEqual(0, store1.numberOfKeys(transaction: transaction))
            XCTAssertEqual(0, store2.numberOfKeys(transaction: transaction))
            XCTAssertEqual(0, store3.numberOfKeys(transaction: transaction))
        }

        self.yapWrite { transaction in
            store1.setObject(value0, key: "key0", transaction: transaction.asAnyWrite)
            store2.setObject(value1, key: "key0", transaction: transaction.asAnyWrite)
            store3.setObject(value2, key: "key0", transaction: transaction.asAnyWrite)
            store1.setObject(value3, key: "key1", transaction: transaction.asAnyWrite)
            store2.setObject(value4, key: "key1", transaction: transaction.asAnyWrite)
        }

        self.read { transaction in
            XCTAssertEqual(0, store1.numberOfKeys(transaction: transaction))
            XCTAssertEqual(0, store2.numberOfKeys(transaction: transaction))
            XCTAssertEqual(0, store3.numberOfKeys(transaction: transaction))
        }

        let migratorGroups = [
            GRDBMigratorGroup { ydbTransaction in
                return [
                    GRDBKeyValueStoreMigrator<Any>(label: "store1", keyStore: store1, ydbTransaction: ydbTransaction),
                    GRDBKeyValueStoreMigrator<Any>(label: "store2", keyStore: store2, ydbTransaction: ydbTransaction),
                    GRDBKeyValueStoreMigrator<Any>(label: "store3", keyStore: store3, ydbTransaction: ydbTransaction)
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

            XCTAssertEqual(value0, store1.getObject(forKey: "key0", transaction: transaction) as! String)
            XCTAssertEqual(value1, store2.getObject(forKey: "key0", transaction: transaction) as! [String])
            XCTAssertEqual(value2, store3.getObject(forKey: "key0", transaction: transaction) as! [String: String])
            XCTAssertEqual(value3, store1.getObject(forKey: "key1", transaction: transaction) as! [String])
            XCTAssertEqual(value4, store2.getObject(forKey: "key1", transaction: transaction) as! [String: String])
            XCTAssertNil(store3.getObject(forKey: "key1", transaction: transaction))
        }
    }
}
