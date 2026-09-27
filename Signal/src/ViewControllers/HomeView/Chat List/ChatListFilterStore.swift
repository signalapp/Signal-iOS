//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

struct ChatListFilterStore {
    private enum Constants {
        static let inboxFilterKey = "inboxFilter"
    }

    private let store = NewKeyValueStore(collection: "ChatListFilterStore")

    func inboxFilter(transaction: DBReadTransaction) -> InboxFilter? {
        let rawValue = store.fetchValue(Int64.self, forKey: Constants.inboxFilterKey, tx: transaction) ?? 0
        guard let inboxFilter = InboxFilter(rawValue: rawValue) else {
            owsFailDebug("Unknown inbox filter (rawValue \(rawValue))")
            return nil
        }
        return inboxFilter
    }

    func setInboxFilter(_ inboxFilter: InboxFilter, transaction: DBWriteTransaction) {
        store.writeValue(inboxFilter.rawValue, forKey: Constants.inboxFilterKey, tx: transaction)
    }
}
