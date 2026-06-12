//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

struct BlockedReleaseNotesStore {
    private let kvStore: NewKeyValueStore = NewKeyValueStore(collection: "BlockedReleaseNotes")
    private let isBlockedKey = "isBlocked"

    func isBlocked(tx: DBReadTransaction) -> Bool {
        return kvStore.fetchValue(Bool.self, forKey: isBlockedKey, tx: tx) ?? false
    }

    func setBlocked(_ isBlocked: Bool, tx: DBWriteTransaction) {
        kvStore.writeValue(isBlocked, forKey: isBlockedKey, tx: tx)
    }
}
