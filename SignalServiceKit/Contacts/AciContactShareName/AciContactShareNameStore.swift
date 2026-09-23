//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB

/// Reads and writes ``AciContactShareName`` records in the database.
struct AciContactShareNameStore {
    init() {}

    // MARK: Read

    /// `recipientRowID` is the primary key, so there is at most one record per
    /// recipient.
    func fetchOne(forRecipientRowID recipientRowID: SignalRecipient.RowId, tx: DBReadTransaction) -> AciContactShareName? {
        return failIfThrows {
            try AciContactShareName.fetchOne(tx.database, key: recipientRowID)
        }
    }

    func enumerateAll(tx: DBReadTransaction, block: (AciContactShareName) -> Void) {
        failIfThrows {
            let cursor = try AciContactShareName.all().fetchCursor(tx.database)
            while let value = try cursor.next() {
                block(value)
            }
        }
    }

    // MARK: Insert

    func insertOne(_ aciContactShareName: AciContactShareName, tx: DBWriteTransaction) {
        failIfThrows {
            try aciContactShareName.insert(tx.database)
        }
    }

    // MARK: Delete

    func deleteOne(forRecipientRowID recipientRowID: SignalRecipient.RowId, tx: DBWriteTransaction) {
        failIfThrows {
            _ = try AciContactShareName.deleteOne(tx.database, key: recipientRowID)
        }
    }
}
