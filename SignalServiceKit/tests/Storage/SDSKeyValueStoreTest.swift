//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest
@testable import SignalServiceKit

class KeyValueStoreTest: SSKBaseTest {

    func test_bool() {
        let store = KeyValueStore(collection: "test")

        self.write { transaction in
            XCTAssertFalse(store.getBool("boolA", defaultValue: false, transaction: transaction.asV2Read))
            XCTAssertTrue(store.getBool("boolA", defaultValue: true, transaction: transaction.asV2Read))
            XCTAssertFalse(store.getBool("boolB", defaultValue: false, transaction: transaction.asV2Read))
            XCTAssertTrue(store.getBool("boolB", defaultValue: true, transaction: transaction.asV2Read))
            XCTAssertEqual(0, store.numberOfKeys(transaction: transaction.asV2Read))

            store.setBool(false, key: "boolA", transaction: transaction.asV2Write)

            XCTAssertFalse(store.getBool("boolA", defaultValue: false, transaction: transaction.asV2Read))
            XCTAssertFalse(store.getBool("boolA", defaultValue: true, transaction: transaction.asV2Read))
            XCTAssertFalse(store.getBool("boolB", defaultValue: false, transaction: transaction.asV2Read))
            XCTAssertTrue(store.getBool("boolB", defaultValue: true, transaction: transaction.asV2Read))
            XCTAssertEqual(1, store.numberOfKeys(transaction: transaction.asV2Read))

            store.setBool(true, key: "boolA", transaction: transaction.asV2Write)

            XCTAssertTrue(store.getBool("boolA", defaultValue: false, transaction: transaction.asV2Read))
            XCTAssertTrue(store.getBool("boolA", defaultValue: true, transaction: transaction.asV2Read))
            XCTAssertFalse(store.getBool("boolB", defaultValue: false, transaction: transaction.asV2Read))
            XCTAssertTrue(store.getBool("boolB", defaultValue: true, transaction: transaction.asV2Read))
            XCTAssertEqual(1, store.numberOfKeys(transaction: transaction.asV2Read))

            store.setBool(false, key: "boolB", transaction: transaction.asV2Write)

            XCTAssertTrue(store.getBool("boolA", defaultValue: false, transaction: transaction.asV2Read))
            XCTAssertTrue(store.getBool("boolA", defaultValue: true, transaction: transaction.asV2Read))
            XCTAssertFalse(store.getBool("boolB", defaultValue: false, transaction: transaction.asV2Read))
            XCTAssertFalse(store.getBool("boolB", defaultValue: true, transaction: transaction.asV2Read))
            XCTAssertEqual(2, store.numberOfKeys(transaction: transaction.asV2Read))

            store.setBool(true, key: "boolB", transaction: transaction.asV2Write)

            XCTAssertTrue(store.getBool("boolA", defaultValue: false, transaction: transaction.asV2Read))
            XCTAssertTrue(store.getBool("boolA", defaultValue: true, transaction: transaction.asV2Read))
            XCTAssertTrue(store.getBool("boolB", defaultValue: false, transaction: transaction.asV2Read))
            XCTAssertTrue(store.getBool("boolB", defaultValue: true, transaction: transaction.asV2Read))
            XCTAssertEqual(2, store.numberOfKeys(transaction: transaction.asV2Read))
        }
    }

    func test_string() {
        let store = KeyValueStore(collection: "test")

        self.write { transaction in
            XCTAssertNil(store.getString("stringA", transaction: transaction.asV2Read))
            XCTAssertNil(store.getString("stringB", transaction: transaction.asV2Read))
            XCTAssertEqual(0, store.numberOfKeys(transaction: transaction.asV2Read))

            store.setString("valueA", key: "stringA", transaction: transaction.asV2Write)

            XCTAssertEqual("valueA", store.getString("stringA", transaction: transaction.asV2Read))
            XCTAssertNil(store.getString("stringB", transaction: transaction.asV2Read))
            XCTAssertEqual(1, store.numberOfKeys(transaction: transaction.asV2Read))

            store.setString("valueB", key: "stringA", transaction: transaction.asV2Write)

            XCTAssertEqual("valueB", store.getString("stringA", transaction: transaction.asV2Read))
            XCTAssertNil(store.getString("stringB", transaction: transaction.asV2Read))
            XCTAssertEqual(1, store.numberOfKeys(transaction: transaction.asV2Read))

            store.setString("valueC", key: "stringB", transaction: transaction.asV2Write)

            XCTAssertEqual("valueB", store.getString("stringA", transaction: transaction.asV2Read))
            XCTAssertEqual("valueC", store.getString("stringB", transaction: transaction.asV2Read))
            XCTAssertEqual(2, store.numberOfKeys(transaction: transaction.asV2Read))

            store.setString(nil, key: "stringA", transaction: transaction.asV2Write)

            XCTAssertNil(store.getString("stringA", transaction: transaction.asV2Read))
            XCTAssertEqual("valueC", store.getString("stringB", transaction: transaction.asV2Read))
            XCTAssertEqual(1, store.numberOfKeys(transaction: transaction.asV2Read))
        }
    }

    func test_data() {
        let store = KeyValueStore(collection: "test")

        let bytesA = Randomness.generateRandomBytes(32)
        let bytesB = Randomness.generateRandomBytes(32)

        self.write { transaction in
            XCTAssertNil(store.getData("dataA", transaction: transaction.asV2Read))
            XCTAssertNil(store.getData("dataB", transaction: transaction.asV2Read))
            XCTAssertEqual(0, store.numberOfKeys(transaction: transaction.asV2Read))

            store.setData(bytesA, key: "dataA", transaction: transaction.asV2Write)

            XCTAssertEqual(bytesA, store.getData("dataA", transaction: transaction.asV2Read))
            XCTAssertNil(store.getData("dataB", transaction: transaction.asV2Read))
            XCTAssertEqual(1, store.numberOfKeys(transaction: transaction.asV2Read))

            store.setData(bytesB, key: "dataA", transaction: transaction.asV2Write)

            XCTAssertEqual(bytesB, store.getData("dataA", transaction: transaction.asV2Read))
            XCTAssertNil(store.getData("dataB", transaction: transaction.asV2Read))
            XCTAssertEqual(1, store.numberOfKeys(transaction: transaction.asV2Read))

            store.setData("valueC".data(using: .utf8)!, key: "dataB", transaction: transaction.asV2Write)

            XCTAssertEqual(bytesB, store.getData("dataA", transaction: transaction.asV2Read))
            XCTAssertEqual("valueC".data(using: .utf8)!, store.getData("dataB", transaction: transaction.asV2Read))
            XCTAssertEqual(2, store.numberOfKeys(transaction: transaction.asV2Read))

            store.setData(nil, key: "dataA", transaction: transaction.asV2Write)

            XCTAssertNil(store.getData("dataA", transaction: transaction.asV2Read))
            XCTAssertEqual("valueC".data(using: .utf8)!, store.getData("dataB", transaction: transaction.asV2Read))
            XCTAssertEqual(1, store.numberOfKeys(transaction: transaction.asV2Read))
        }
    }

    func test_misc() {
        let store = KeyValueStore(collection: "test")

        self.write { transaction in
            let key = "string"
            XCTAssertFalse(store.hasValue(key, transaction: transaction.asV2Read))
            XCTAssertEqual(0, store.numberOfKeys(transaction: transaction.asV2Read))
            store.setString("value", key: key, transaction: transaction.asV2Write)
            XCTAssertTrue(store.hasValue(key, transaction: transaction.asV2Read))
            XCTAssertEqual(1, store.numberOfKeys(transaction: transaction.asV2Read))
            store.removeValue(forKey: key, transaction: transaction.asV2Write)
            XCTAssertFalse(store.hasValue(key, transaction: transaction.asV2Read))
            XCTAssertEqual(0, store.numberOfKeys(transaction: transaction.asV2Read))
        }

        self.write { transaction in
            let key = "date"
            XCTAssertFalse(store.hasValue(key, transaction: transaction.asV2Read))
            XCTAssertEqual(0, store.numberOfKeys(transaction: transaction.asV2Read))
            store.setDate(Date(), key: key, transaction: transaction.asV2Write)
            XCTAssertTrue(store.hasValue(key, transaction: transaction.asV2Read))
            XCTAssertEqual(1, store.numberOfKeys(transaction: transaction.asV2Read))
            store.removeValue(forKey: key, transaction: transaction.asV2Write)
            XCTAssertFalse(store.hasValue(key, transaction: transaction.asV2Read))
            XCTAssertEqual(0, store.numberOfKeys(transaction: transaction.asV2Read))
        }

        self.write { transaction in
            let key = "date edge cases"

            XCTAssertFalse(store.hasValue(key, transaction: transaction.asV2Read))
            XCTAssertEqual(0, store.numberOfKeys(transaction: transaction.asV2Read))

            let date1 = Date()
            store.setDate(date1, key: key, transaction: transaction.asV2Write)
            XCTAssertTrue(store.hasValue(key, transaction: transaction.asV2Read))
            XCTAssertEqual(date1.timeIntervalSince1970,
                           store.getDate(key, transaction: transaction.asV2Read)?.timeIntervalSince1970)
            XCTAssertEqual(1, store.numberOfKeys(transaction: transaction.asV2Read))

            store.removeValue(forKey: key, transaction: transaction.asV2Write)
            XCTAssertFalse(store.hasValue(key, transaction: transaction.asV2Read))
            XCTAssertEqual(0, store.numberOfKeys(transaction: transaction.asV2Read))

            let date2 = Date()
            store.setObject(date2, key: key, transaction: transaction.asV2Write)
            XCTAssertTrue(store.hasValue(key, transaction: transaction.asV2Read))
            XCTAssertEqual(date2.timeIntervalSince1970,
                           store.getDate(key, transaction: transaction.asV2Read)?.timeIntervalSince1970)
            XCTAssertEqual(1, store.numberOfKeys(transaction: transaction.asV2Read))

            store.removeValue(forKey: key, transaction: transaction.asV2Write)
            XCTAssertFalse(store.hasValue(key, transaction: transaction.asV2Read))
            XCTAssertEqual(0, store.numberOfKeys(transaction: transaction.asV2Read))
        }

        let bytes = Randomness.generateRandomBytes(32)
        self.write { transaction in
            let key = "data"
            XCTAssertFalse(store.hasValue(key, transaction: transaction.asV2Read))
            XCTAssertEqual(0, store.numberOfKeys(transaction: transaction.asV2Read))
            store.setData(bytes, key: key, transaction: transaction.asV2Write)
            XCTAssertTrue(store.hasValue(key, transaction: transaction.asV2Read))
            XCTAssertEqual(1, store.numberOfKeys(transaction: transaction.asV2Read))
            store.removeValue(forKey: key, transaction: transaction.asV2Write)
            XCTAssertFalse(store.hasValue(key, transaction: transaction.asV2Read))
            XCTAssertEqual(0, store.numberOfKeys(transaction: transaction.asV2Read))
        }

        self.write { transaction in
            let key = "bool"
            XCTAssertFalse(store.hasValue(key, transaction: transaction.asV2Read))
            XCTAssertEqual(0, store.numberOfKeys(transaction: transaction.asV2Read))
            store.setBool(true, key: key, transaction: transaction.asV2Write)
            XCTAssertTrue(store.hasValue(key, transaction: transaction.asV2Read))
            XCTAssertEqual(1, store.numberOfKeys(transaction: transaction.asV2Read))
            store.removeValue(forKey: key, transaction: transaction.asV2Write)
            XCTAssertFalse(store.hasValue(key, transaction: transaction.asV2Read))
            XCTAssertEqual(0, store.numberOfKeys(transaction: transaction.asV2Read))
        }

        self.write { transaction in
            let key = "uint"
            XCTAssertFalse(store.hasValue(key, transaction: transaction.asV2Read))
            XCTAssertEqual(0, store.numberOfKeys(transaction: transaction.asV2Read))
            store.setUInt(0, key: key, transaction: transaction.asV2Write)
            XCTAssertTrue(store.hasValue(key, transaction: transaction.asV2Read))
            XCTAssertEqual(1, store.numberOfKeys(transaction: transaction.asV2Read))
            store.removeValue(forKey: key, transaction: transaction.asV2Write)
            XCTAssertFalse(store.hasValue(key, transaction: transaction.asV2Read))
            XCTAssertEqual(0, store.numberOfKeys(transaction: transaction.asV2Read))
        }
    }
}
