//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

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
        tx: DBWriteTransaction,
    ) {
        kvStore.writeValue(
            value,
            forKey: StoreKeys.lastChallengeDateKey,
            tx: tx,
        )
    }

    public func lastChallengeWithinTimeframe(
        lastChallengeFloor: Date,
        tx: DBReadTransaction,
    ) -> Bool {
        guard
            let lastChallengeDate = kvStore.fetchValue(
                Date.self,
                forKey: StoreKeys.lastChallengeDateKey,
                tx: tx,
            )
        else {
            return false
        }

        return lastChallengeDate > lastChallengeFloor
    }
}
