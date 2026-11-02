//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

private class FakeAdapter: ModelCacheAdapter<String, String> {
    var storage = [String: String]()

    override func read(key: String, transaction: DBReadTransaction) -> String? {
        return self.storage[key]
    }

    override func key(forValue value: String) -> String {
        return String(value.first!)
    }

    override func cacheKey(forKey key: String) -> ModelCacheKey<String> {
        return ModelCacheKey(key: key)
    }

    override func copy(value: String) throws -> String {
        return value
    }
}

class ModelReadCacheTest: XCTestCase {
    private var adapter: FakeAdapter!
    private var cache: ModelReadCache<String, String>!
    private var db: InMemoryDB!

    override func setUp() {
        super.setUp()

        let appReadiness = AppReadinessMock()
        appReadiness.isAppReady = true

        self.adapter = FakeAdapter(cacheName: "fake", cacheCountLimit: 1024)
        self.cache = ModelReadCache(adapter: adapter, appReadiness: appReadiness)
        self.db = InMemoryDB()
    }

    // MARK: - Test ModelReadCache.getValues(for:, transaction:)

    func testGetUncachedMultipleValuesThatExist() {
        let storage = [
            "1": "1:one",
            "2": "2:two",
        ]
        self.adapter.storage = storage
        self.db.read { tx in
            let keys = storage.keys.sorted().map { adapter.cacheKey(forKey: $0) }
            let actual = cache.getValues(for: keys, transaction: tx)
            XCTAssertEqual(actual, ["1:one", "2:two"])
        }
    }

    func testGetMultipleValuesThatDoNotExist() {
        let storage = [
            "1": "1:one",
            "2": "2:two",
        ]
        self.db.read { tx in
            let keys = storage.keys.sorted().map { adapter.cacheKey(forKey: $0) }
            let actual = cache.getValues(for: keys, transaction: tx)
            XCTAssertEqual(actual, [nil, nil])
        }
    }

    func testGetCachedMultipleValues() {
        let storage = [
            "1": "1:one",
            "2": "2:two",
        ]
        let keys = ["1", "2", "3"]
        self.adapter.storage = storage
        self.db.read { tx in
            let keys = keys.map { adapter.cacheKey(forKey: $0) }
            let actual = cache.getValues(for: keys, transaction: tx)
            XCTAssertEqual(actual, ["1:one", "2:two", nil])
            cache.didRead(value: "1:one", transaction: tx)
            cache.didRead(value: "2:two", transaction: tx)
        }
        self.adapter.storage = [
            "1": "1:one-prime",
            "2": "2:two-prime",
            "3": "3:three-prime",
        ]
        self.db.read { tx in
            let keys = keys.map { adapter.cacheKey(forKey: $0) }
            let actual = cache.getValues(for: keys, transaction: tx)
            // The values should come from the cache and shouldn't be re-fetched.
            XCTAssertEqual(actual, ["1:one", "2:two", nil])
        }
    }

    func testExclusion() {
        let key = "1"
        let keys = [adapter.cacheKey(forKey: key)]
        self.db.write { tx in
            // Mark it as changed to disable the cache.
            cache.didInsertOrUpdate(value: "1:one-prime", transaction: tx)

            // The existing transaction can't read from the cache.
            adapter.storage = ["1": "1:old"]
            XCTAssertEqual(cache.getValues(for: keys, transaction: tx), ["1:old"])
        }
        self.db.read { tx in
            // A new transaction reads from the cache, not the storage.
            XCTAssertEqual(cache.getValues(for: keys, transaction: tx), ["1:one-prime"])
        }
    }
}
