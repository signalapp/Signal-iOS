//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest

@testable import SignalServiceKit

class LRUCacheTest: SSKBaseTestSwift {
    func testStringString() {
        let cache = LRUCache<String, String>(maxSize: 16)
        let key1 = "a"
        let key2 = "b"
        let key3 = "c"
        let value1 = "d"
        let value2 = "e"

        XCTAssertNil(cache.get(key: key1))
        XCTAssertNil(cache.get(key: key2))
        XCTAssertNil(cache.get(key: key3))

        cache.set(key: key1, value: value1)

        XCTAssertEqual(value1, cache.get(key: key1))
        XCTAssertNil(cache.get(key: key2))
        XCTAssertNil(cache.get(key: key3))

        cache.set(key: key2, value: value2)

        XCTAssertEqual(value1, cache.get(key: key1))
        XCTAssertEqual(value2, cache.get(key: key2))
        XCTAssertNil(cache.get(key: key3))

        cache.clear()

        XCTAssertNil(cache.get(key: key1))
        XCTAssertNil(cache.get(key: key2))
        XCTAssertNil(cache.get(key: key3))
    }

    func testStructStruct() {
        struct TestStruct: CustomStringConvertible, Hashable {
            let payload: String

            // MARK: - CustomStringConvertible

            public var description: String { payload }

            // MARK: - Hashable

            func hash(into hasher: inout Hasher) {
                payload.hash(into: &hasher)
            }
        }

        let cache = LRUCache<TestStruct, TestStruct>(maxSize: 16)
        let key1a = TestStruct(payload: "a")
        let key1b = TestStruct(payload: "a")
        let key2 = TestStruct(payload: "b")
        let key3 = TestStruct(payload: "c")
        let value1 = TestStruct(payload: "d")
        let value2 = TestStruct(payload: "e")

        XCTAssertNil(cache.get(key: key1a))
        XCTAssertNil(cache.get(key: key1b))
        XCTAssertNil(cache.get(key: key2))
        XCTAssertNil(cache.get(key: key3))

        cache.set(key: key1a, value: value1)

        XCTAssertEqual(value1, cache.get(key: key1a))
        XCTAssertEqual(value1, cache.get(key: key1b))
        XCTAssertNil(cache.get(key: key2))
        XCTAssertNil(cache.get(key: key3))

        cache.set(key: key2, value: value2)

        XCTAssertEqual(value1, cache.get(key: key1a))
        XCTAssertEqual(value1, cache.get(key: key1b))
        XCTAssertEqual(value2, cache.get(key: key2))
        XCTAssertNil(cache.get(key: key3))

        cache.clear()

        XCTAssertNil(cache.get(key: key1a))
        XCTAssertNil(cache.get(key: key1b))
        XCTAssertNil(cache.get(key: key2))
        XCTAssertNil(cache.get(key: key3))
    }

    func testIntInt() {

        let cache = LRUCache<Int, Int>(maxSize: 16)
        let key1a: Int = 1
        let key1b: Int = 1
        let key2: Int = 2
        let key3: Int = 3
        let value1: Int = 4
        let value2: Int = 5

        XCTAssertNil(cache.get(key: key1a))
        XCTAssertNil(cache.get(key: key1b))
        XCTAssertNil(cache.get(key: key2))
        XCTAssertNil(cache.get(key: key3))

        cache.set(key: key1a, value: value1)

        XCTAssertEqual(value1, cache.get(key: key1a))
        XCTAssertEqual(value1, cache.get(key: key1b))
        XCTAssertNil(cache.get(key: key2))
        XCTAssertNil(cache.get(key: key3))

        cache.set(key: key2, value: value2)

        XCTAssertEqual(value1, cache.get(key: key1a))
        XCTAssertEqual(value1, cache.get(key: key1b))
        XCTAssertEqual(value2, cache.get(key: key2))
        XCTAssertNil(cache.get(key: key3))

        cache.clear()

        XCTAssertNil(cache.get(key: key1a))
        XCTAssertNil(cache.get(key: key1b))
        XCTAssertNil(cache.get(key: key2))
        XCTAssertNil(cache.get(key: key3))
    }
}
