//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

struct KeyValueStoreRenamer {
    let oldCollection: String
    let newCollection: String

    func renameKey(_ oldKey: String, toKey newKey: String, tx: DBWriteTransaction) throws {
        try tx.database.execute(
            sql: "UPDATE keyvalue SET collection = ?, key = ? WHERE collection = ? AND key = ?",
            arguments: [newCollection, newKey, oldCollection, oldKey],
        )
    }
}
