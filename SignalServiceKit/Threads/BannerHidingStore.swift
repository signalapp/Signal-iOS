//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct BannerHidingStore: ThreadRemoverObserver {
    private let keyValueStore: KeyValueStore
    private let keyPrefix: String

    private enum Constants {
        static let hiddenStatePrefix = "hiddenState_"
        static let requestingMembersStatePrefix = "requestingMembersState_"

        static let joinRequestCollection = "BannerHiding_pendingMemberRequests"
        static let nameCollisionCollection = "BannerHiding_messageRequestNameCollision"
    }

    public static let joinRequestHiddenStore = BannerHidingStore(
        keyValueStore: KeyValueStore(collection: Constants.joinRequestCollection),
        keyPrefix: Constants.hiddenStatePrefix,
    )

    public static let joinRequestMembersStore = BannerHidingStore(
        keyValueStore: KeyValueStore(collection: Constants.joinRequestCollection),
        keyPrefix: Constants.requestingMembersStatePrefix,
    )

    public static let nameCollisionHiddenStore = BannerHidingStore(
        keyValueStore: KeyValueStore(collection: Constants.nameCollisionCollection),
        keyPrefix: Constants.hiddenStatePrefix,
    )

    public func writeValueAsJSON<T: Encodable>(
        _ encodableValue: T,
        forThreadUniqueId threadUniqueId: String,
        tx: DBWriteTransaction,
    ) {
        failIfThrows {
            try keyValueStore.setCodable(encodableValue, key: keyPrefix + threadUniqueId, transaction: tx)
        }
    }

    public func fetchJSONAsValue<T: Decodable>(_ type: T.Type, forThreadUniqueId threadUniqueId: String, tx: DBReadTransaction) throws -> T? {
        return try keyValueStore.getCodableValue(forKey: keyPrefix + threadUniqueId, failDebugOnParseError: false, transaction: tx)
    }

    public func didRemoveThread(_ thread: TSThread, tx: DBWriteTransaction) {
        keyValueStore.removeValue(forKey: keyPrefix + thread.uniqueId, transaction: tx)
    }
}
