//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest
@testable import SignalServiceKit

class SDSKeyValueStoreTest: SSKBaseTestSwift {

    func test_bool() {
        let store = SDSKeyValueStore(collection: "test")

        self.write { transaction in
            XCTAssertFalse(store.getBool("boolA", defaultValue: false, transaction: transaction))
            XCTAssertTrue(store.getBool("boolA", defaultValue: true, transaction: transaction))
            XCTAssertFalse(store.getBool("boolB", defaultValue: false, transaction: transaction))
            XCTAssertTrue(store.getBool("boolB", defaultValue: true, transaction: transaction))
            XCTAssertEqual(0, store.numberOfKeys(transaction: transaction))

            store.setBool(false, key: "boolA", transaction: transaction)

            XCTAssertFalse(store.getBool("boolA", defaultValue: false, transaction: transaction))
            XCTAssertFalse(store.getBool("boolA", defaultValue: true, transaction: transaction))
            XCTAssertFalse(store.getBool("boolB", defaultValue: false, transaction: transaction))
            XCTAssertTrue(store.getBool("boolB", defaultValue: true, transaction: transaction))
            XCTAssertEqual(1, store.numberOfKeys(transaction: transaction))

            store.setBool(true, key: "boolA", transaction: transaction)

            XCTAssertTrue(store.getBool("boolA", defaultValue: false, transaction: transaction))
            XCTAssertTrue(store.getBool("boolA", defaultValue: true, transaction: transaction))
            XCTAssertFalse(store.getBool("boolB", defaultValue: false, transaction: transaction))
            XCTAssertTrue(store.getBool("boolB", defaultValue: true, transaction: transaction))
            XCTAssertEqual(1, store.numberOfKeys(transaction: transaction))

            store.setBool(false, key: "boolB", transaction: transaction)

            XCTAssertTrue(store.getBool("boolA", defaultValue: false, transaction: transaction))
            XCTAssertTrue(store.getBool("boolA", defaultValue: true, transaction: transaction))
            XCTAssertFalse(store.getBool("boolB", defaultValue: false, transaction: transaction))
            XCTAssertFalse(store.getBool("boolB", defaultValue: true, transaction: transaction))
            XCTAssertEqual(2, store.numberOfKeys(transaction: transaction))

            store.setBool(true, key: "boolB", transaction: transaction)

            XCTAssertTrue(store.getBool("boolA", defaultValue: false, transaction: transaction))
            XCTAssertTrue(store.getBool("boolA", defaultValue: true, transaction: transaction))
            XCTAssertTrue(store.getBool("boolB", defaultValue: false, transaction: transaction))
            XCTAssertTrue(store.getBool("boolB", defaultValue: true, transaction: transaction))
            XCTAssertEqual(2, store.numberOfKeys(transaction: transaction))
        }
    }

    func test_string() {
        let store = SDSKeyValueStore(collection: "test")

        self.write { transaction in
            XCTAssertNil(store.getString("stringA", transaction: transaction))
            XCTAssertNil(store.getString("stringB", transaction: transaction))
            XCTAssertEqual(0, store.numberOfKeys(transaction: transaction))

            store.setString("valueA", key: "stringA", transaction: transaction)

            XCTAssertEqual("valueA", store.getString("stringA", transaction: transaction))
            XCTAssertNil(store.getString("stringB", transaction: transaction))
            XCTAssertEqual(1, store.numberOfKeys(transaction: transaction))

            store.setString("valueB", key: "stringA", transaction: transaction)

            XCTAssertEqual("valueB", store.getString("stringA", transaction: transaction))
            XCTAssertNil(store.getString("stringB", transaction: transaction))
            XCTAssertEqual(1, store.numberOfKeys(transaction: transaction))

            store.setString("valueC", key: "stringB", transaction: transaction)

            XCTAssertEqual("valueB", store.getString("stringA", transaction: transaction))
            XCTAssertEqual("valueC", store.getString("stringB", transaction: transaction))
            XCTAssertEqual(2, store.numberOfKeys(transaction: transaction))

            store.setString(nil, key: "stringA", transaction: transaction)

            XCTAssertNil(store.getString("stringA", transaction: transaction))
            XCTAssertEqual("valueC", store.getString("stringB", transaction: transaction))
            XCTAssertEqual(1, store.numberOfKeys(transaction: transaction))
        }
    }

    func test_data() {
        let store = SDSKeyValueStore(collection: "test")

        let bytesA = Randomness.generateRandomBytes(32)
        let bytesB = Randomness.generateRandomBytes(32)

        self.write { transaction in
            XCTAssertNil(store.getData("dataA", transaction: transaction))
            XCTAssertNil(store.getData("dataB", transaction: transaction))
            XCTAssertEqual(0, store.numberOfKeys(transaction: transaction))

            store.setData(bytesA, key: "dataA", transaction: transaction)

            XCTAssertEqual(bytesA, store.getData("dataA", transaction: transaction))
            XCTAssertNil(store.getData("dataB", transaction: transaction))
            XCTAssertEqual(1, store.numberOfKeys(transaction: transaction))

            store.setData(bytesB, key: "dataA", transaction: transaction)

            XCTAssertEqual(bytesB, store.getData("dataA", transaction: transaction))
            XCTAssertNil(store.getData("dataB", transaction: transaction))
            XCTAssertEqual(1, store.numberOfKeys(transaction: transaction))

            store.setData("valueC".data(using: .utf8)!, key: "dataB", transaction: transaction)

            XCTAssertEqual(bytesB, store.getData("dataA", transaction: transaction))
            XCTAssertEqual("valueC".data(using: .utf8)!, store.getData("dataB", transaction: transaction))
            XCTAssertEqual(2, store.numberOfKeys(transaction: transaction))

            store.setData(nil, key: "dataA", transaction: transaction)

            XCTAssertNil(store.getData("dataA", transaction: transaction))
            XCTAssertEqual("valueC".data(using: .utf8)!, store.getData("dataB", transaction: transaction))
            XCTAssertEqual(1, store.numberOfKeys(transaction: transaction))
        }
    }

    func test_misc() {
        let store = SDSKeyValueStore(collection: "test")

        self.write { transaction in
            let key = "string"
            XCTAssertFalse(store.hasValue(forKey: key, transaction: transaction))
            XCTAssertEqual(0, store.numberOfKeys(transaction: transaction))
            store.setString("value", key: key, transaction: transaction)
            XCTAssertTrue(store.hasValue(forKey: key, transaction: transaction))
            XCTAssertEqual(1, store.numberOfKeys(transaction: transaction))
            store.removeValue(forKey: key, transaction: transaction)
            XCTAssertFalse(store.hasValue(forKey: key, transaction: transaction))
            XCTAssertEqual(0, store.numberOfKeys(transaction: transaction))
        }

        self.write { transaction in
            let key = "date"
            XCTAssertFalse(store.hasValue(forKey: key, transaction: transaction))
            XCTAssertEqual(0, store.numberOfKeys(transaction: transaction))
            store.setDate(Date(), key: key, transaction: transaction)
            XCTAssertTrue(store.hasValue(forKey: key, transaction: transaction))
            XCTAssertEqual(1, store.numberOfKeys(transaction: transaction))
            store.removeValue(forKey: key, transaction: transaction)
            XCTAssertFalse(store.hasValue(forKey: key, transaction: transaction))
            XCTAssertEqual(0, store.numberOfKeys(transaction: transaction))
        }

        self.write { transaction in
            let key = "date edge cases"

            XCTAssertFalse(store.hasValue(forKey: key, transaction: transaction))
            XCTAssertEqual(0, store.numberOfKeys(transaction: transaction))

            let date1 = Date()
            store.setDate(date1, key: key, transaction: transaction)
            XCTAssertTrue(store.hasValue(forKey: key, transaction: transaction))
            XCTAssertEqual(date1.timeIntervalSince1970,
                           store.getDate(key, transaction: transaction)?.timeIntervalSince1970)
            XCTAssertEqual(1, store.numberOfKeys(transaction: transaction))

            store.removeValue(forKey: key, transaction: transaction)
            XCTAssertFalse(store.hasValue(forKey: key, transaction: transaction))
            XCTAssertEqual(0, store.numberOfKeys(transaction: transaction))

            let date2 = Date()
            store.setObject(date2, key: key, transaction: transaction)
            XCTAssertTrue(store.hasValue(forKey: key, transaction: transaction))
            XCTAssertEqual(date2.timeIntervalSince1970,
                           store.getDate(key, transaction: transaction)?.timeIntervalSince1970)
            XCTAssertEqual(1, store.numberOfKeys(transaction: transaction))

            store.removeValue(forKey: key, transaction: transaction)
            XCTAssertFalse(store.hasValue(forKey: key, transaction: transaction))
            XCTAssertEqual(0, store.numberOfKeys(transaction: transaction))
        }

        let bytes = Randomness.generateRandomBytes(32)
        self.write { transaction in
            let key = "data"
            XCTAssertFalse(store.hasValue(forKey: key, transaction: transaction))
            XCTAssertEqual(0, store.numberOfKeys(transaction: transaction))
            store.setData(bytes, key: key, transaction: transaction)
            XCTAssertTrue(store.hasValue(forKey: key, transaction: transaction))
            XCTAssertEqual(1, store.numberOfKeys(transaction: transaction))
            store.removeValue(forKey: key, transaction: transaction)
            XCTAssertFalse(store.hasValue(forKey: key, transaction: transaction))
            XCTAssertEqual(0, store.numberOfKeys(transaction: transaction))
        }

        self.write { transaction in
            let key = "bool"
            XCTAssertFalse(store.hasValue(forKey: key, transaction: transaction))
            XCTAssertEqual(0, store.numberOfKeys(transaction: transaction))
            store.setBool(true, key: key, transaction: transaction)
            XCTAssertTrue(store.hasValue(forKey: key, transaction: transaction))
            XCTAssertEqual(1, store.numberOfKeys(transaction: transaction))
            store.removeValue(forKey: key, transaction: transaction)
            XCTAssertFalse(store.hasValue(forKey: key, transaction: transaction))
            XCTAssertEqual(0, store.numberOfKeys(transaction: transaction))
        }

        self.write { transaction in
            let key = "uint"
            XCTAssertFalse(store.hasValue(forKey: key, transaction: transaction))
            XCTAssertEqual(0, store.numberOfKeys(transaction: transaction))
            store.setUInt(0, key: key, transaction: transaction)
            XCTAssertTrue(store.hasValue(forKey: key, transaction: transaction))
            XCTAssertEqual(1, store.numberOfKeys(transaction: transaction))
            store.removeValue(forKey: key, transaction: transaction)
            XCTAssertFalse(store.hasValue(forKey: key, transaction: transaction))
            XCTAssertEqual(0, store.numberOfKeys(transaction: transaction))
        }
    }
}
