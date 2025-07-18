//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import Testing

@testable import SignalServiceKit

struct RemoteConfigTests {
    @Test(arguments: [
        ("research.megaphone.1", "15b9729c-51ea-4ddb-b516-652befe78062", 1_000_000, 243_315),
        ("research.megaphone.2", "15b9729c-51ea-4ddb-b516-652befe78062", 1_000_000, 551_742),
        ("research.megaphone.1", "5f5b28bb-f485-4a0a-a85c-13fc047524b1", 1_000_000, 365_381),
        ("research.megaphone.1", "15b9729c-51ea-4ddb-b516-652befe78062", 100_000, 43_315),
    ])
    func bucketCalculation(testCase: (key: String, uuidString: String, bucketSize: UInt64, expectedBucket: UInt64)) {
        let actualBucket = RemoteConfig.bucket(key: testCase.key, aci: Aci.constantForTesting(testCase.uuidString), bucketSize: testCase.bucketSize)
        #expect(actualBucket == testCase.expectedBucket)
    }

    @Test(arguments: [
        ("1", true),
        ("true", true),
        ("TRUE", true),
        ("false", false),
        ("", false),
        ("11", false),
    ])
    func isEnabledFlag(testCase: (rawValue: String, isEnabled: Bool)) {
        let remoteConfig = RemoteConfig(clockSkew: 0, valueFlags: ["global.gifSearch": testCase.rawValue])
        #expect(remoteConfig.enableGifSearch == testCase.isEnabled)
    }

    @Test
    func testHotSwapping() {
        let remoteConfig = RemoteConfig(clockSkew: 0, valueFlags: [
            "test.hotSwappable.enabled": "false",
            "test.nonSwappable.enabled": "false",
            "test.hotSwappable.value": "abc",
            "test.nonSwappable.value": "abc",
        ])
        #expect(remoteConfig.testHotSwappable == false)
        #expect(remoteConfig.testNonSwappable == false)
        #expect(remoteConfig.testHotSwappableValue == "abc")
        #expect(remoteConfig.testNonSwappableValue == "abc")
        #expect(remoteConfig.lastKnownClockSkew == 0)

        let unchangedConfig = remoteConfig.merging(
            newValueFlags: nil,
            newClockSkew: 1,
        )
        #expect(unchangedConfig.testHotSwappable == false)
        #expect(unchangedConfig.testNonSwappable == false)
        #expect(unchangedConfig.testHotSwappableValue == "abc")
        #expect(unchangedConfig.testNonSwappableValue == "abc")
        #expect(unchangedConfig.lastKnownClockSkew == 1)

        let mergedEmptyConfig = remoteConfig.merging(
            newValueFlags: [:],
            newClockSkew: 2,
        )
        #expect(mergedEmptyConfig.testHotSwappable == nil)
        #expect(mergedEmptyConfig.testNonSwappable == false)
        #expect(mergedEmptyConfig.testHotSwappableValue == nil)
        #expect(mergedEmptyConfig.testNonSwappableValue == "abc")
        #expect(mergedEmptyConfig.lastKnownClockSkew == 2)

        let mergedConfig = remoteConfig.merging(
            newValueFlags: [
                "test.hotSwappable.enabled": "true",
                "test.nonSwappable.enabled": "true",
                "test.hotSwappable.value": "123",
                "test.nonSwappable.value": "123",
            ],
            newClockSkew: 3,
        )
        #expect(mergedConfig.testHotSwappable == true)
        #expect(mergedConfig.testNonSwappable == false)
        #expect(mergedConfig.testHotSwappableValue == "123")
        #expect(mergedConfig.testNonSwappableValue == "abc")
        #expect(mergedConfig.lastKnownClockSkew == 3)
    }
}

struct RemoteConfigStoreTests {
    let db = InMemoryDB()
    let keyValueStore = KeyValueStore(collection: "")
    let store: RemoteConfigStore

    init() {
        self.store = RemoteConfigStore(keyValueStore: self.keyValueStore)
    }

    @Test
    func migrationFallback() {
        self.db.write { tx in
            let isEnabledFlags: [String: Bool] = [
                "ios.abc": true,
                "ios.123": false,
            ]
            self.keyValueStore.setObject(isEnabledFlags, key: "remoteConfigKey", transaction: tx)
        }
        let valueFlags = self.db.read { tx in
            return self.store.loadValueFlags(tx: tx)
        }
        #expect(valueFlags == ["ios.abc": "true", "ios.123": "false"])
    }

    @Test
    func migrationMerge() {
        self.db.write { tx in
            let valueFlags: [String: String] = [
                "ios.abc": "def",
                "ios.def": "ghi",
            ]
            let isEnabledFlags: [String: Bool] = [
                "ios.ghi": true,
                "ios.jkl": false,
            ]
            let timeGatedFlags: [String: Date] = [
                "ios.mno": Date(timeIntervalSince1970: 0),
                "ios.pqr": Date(timeIntervalSince1970: 1),
            ]
            self.keyValueStore.setObject(isEnabledFlags, key: "remoteConfigKey", transaction: tx)
            self.keyValueStore.setObject(valueFlags, key: "remoteConfigValueFlags", transaction: tx)
            self.keyValueStore.setObject(timeGatedFlags, key: "remoteConfigTimeGatedFlags", transaction: tx)
        }
        let valueFlags = self.db.read { tx in
            return self.store.loadValueFlags(tx: tx)
        }
        #expect(valueFlags == [
            "ios.abc": "def",
            "ios.def": "ghi",
            "ios.ghi": "true",
            "ios.jkl": "false",
            "ios.mno": "0.0",
            "ios.pqr": "1.0",
        ])
    }

    @Test
    func nilResult() {
        let valueFlags = self.db.read { tx in
            return self.store.loadValueFlags(tx: tx)
        }
        #expect(valueFlags == nil)
    }
}
