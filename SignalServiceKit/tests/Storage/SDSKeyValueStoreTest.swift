//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import XCTest
@testable import SignalServiceKit

class SDSKeyValueStoreTest: SSKBaseTestSwift {

    func test_bool() {
        let store = SDSKeyValueStore(collection: "test")

        XCTAssertFalse(store.getBool("boolA"))
        XCTAssertFalse(store.getBool("boolA", defaultValue: false))
        XCTAssertTrue(store.getBool("boolA", defaultValue: true))
        XCTAssertFalse(store.getBool("boolB"))
        XCTAssertFalse(store.getBool("boolB", defaultValue: false))
        XCTAssertTrue(store.getBool("boolB", defaultValue: true))

        store.setBool(false, key: "boolA")

        XCTAssertFalse(store.getBool("boolA"))
        XCTAssertFalse(store.getBool("boolA", defaultValue: false))
        XCTAssertFalse(store.getBool("boolA", defaultValue: true))
        XCTAssertFalse(store.getBool("boolB"))
        XCTAssertFalse(store.getBool("boolB", defaultValue: false))
        XCTAssertTrue(store.getBool("boolB", defaultValue: true))

        store.setBool(true, key: "boolA")

        XCTAssertTrue(store.getBool("boolA"))
        XCTAssertTrue(store.getBool("boolA", defaultValue: false))
        XCTAssertTrue(store.getBool("boolA", defaultValue: true))
        XCTAssertFalse(store.getBool("boolB"))
        XCTAssertFalse(store.getBool("boolB", defaultValue: false))
        XCTAssertTrue(store.getBool("boolB", defaultValue: true))

        store.setBool(false, key: "boolB")

        XCTAssertTrue(store.getBool("boolA"))
        XCTAssertTrue(store.getBool("boolA", defaultValue: false))
        XCTAssertTrue(store.getBool("boolA", defaultValue: true))
        XCTAssertFalse(store.getBool("boolB"))
        XCTAssertFalse(store.getBool("boolB", defaultValue: false))
        XCTAssertFalse(store.getBool("boolB", defaultValue: true))

        store.setBool(true, key: "boolB")

        XCTAssertTrue(store.getBool("boolA"))
        XCTAssertTrue(store.getBool("boolA", defaultValue: false))
        XCTAssertTrue(store.getBool("boolA", defaultValue: true))
        XCTAssertTrue(store.getBool("boolB"))
        XCTAssertTrue(store.getBool("boolB", defaultValue: false))
        XCTAssertTrue(store.getBool("boolB", defaultValue: true))
    }

    func test_string() {
        let store = SDSKeyValueStore(collection: "test")

        XCTAssertNil(store.getString("stringA"))
        XCTAssertNil(store.getString("stringB"))

        store.setString("valueA", key: "stringA")

        XCTAssertEqual("valueA", store.getString("stringA"))
        XCTAssertNil(store.getString("stringB"))

        store.setString("valueB", key: "stringA")

        XCTAssertEqual("valueB", store.getString("stringA"))
        XCTAssertNil(store.getString("stringB"))

        store.setString("valueC", key: "stringB")

        XCTAssertEqual("valueB", store.getString("stringA"))
        XCTAssertEqual("valueC", store.getString("stringB"))

        store.setString(nil, key: "stringA")

        XCTAssertNil(store.getString("stringA"))
        XCTAssertEqual("valueC", store.getString("stringB"))
    }

    func test_data() {
        let store = SDSKeyValueStore(collection: "test")

        let bytesA = Randomness.generateRandomBytes(32)
        let bytesB = Randomness.generateRandomBytes(32)

        XCTAssertNil(store.getData("dataA"))
        XCTAssertNil(store.getData("dataB"))

        store.setData(bytesA, key: "dataA")

        XCTAssertEqual(bytesA, store.getData("dataA"))
        XCTAssertNil(store.getData("dataB"))

        store.setData(bytesB, key: "dataA")

        XCTAssertEqual(bytesB, store.getData("dataA"))
        XCTAssertNil(store.getData("dataB"))

        store.setData("valueC", key: "dataB")

        XCTAssertEqual(bytesB, store.getData("dataA"))
        XCTAssertEqual("valueC", store.getData("dataB"))

        store.setData(nil, key: "dataA")

        XCTAssertNil(store.getData("dataA"))
        XCTAssertEqual("valueC", store.getData("dataB"))
    }
}
