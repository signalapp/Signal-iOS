//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import SignalServiceKit

public class SupportKeyValueStore {
    private enum StoreKeys {
        static let lastChallengeDateKey: String = "lastChallengeDateKey"
    }

    private let kvStore: NewKeyValueStore

    public init() {
        self.kvStore = NewKeyValueStore(collection: "ComposeSupportEmailOperation")
    }

    public func setLastChallengeDate(
        value: Date,
        transaction: DBWriteTransaction,
    ) {
        kvStore.writeValue(
            value,
            forKey: StoreKeys.lastChallengeDateKey,
            tx: transaction,
        )
    }

    public func lastChallengeWithinTimeframe(
        transaction: DBReadTransaction,
        lastChallengeFloor: Date,
    ) -> Bool {
        return kvStore.fetchValue(Date.self, forKey: StoreKeys.lastChallengeDateKey, tx: transaction) ?? Date.distantPast > lastChallengeFloor
    }
}
