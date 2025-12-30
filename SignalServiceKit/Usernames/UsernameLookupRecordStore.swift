//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import LibSignalClient

struct UsernameLookupRecordStore {
    init() {}

    // MARK: -

    /// The `aci` column of `UsernameLookupRecord` is the primary key and
    /// therefore unique, so there can only be one record for a given ACI.
    func fetchOne(forAci aci: Aci, tx: DBReadTransaction) -> UsernameLookupRecord? {
        return failIfThrows {
            try UsernameLookupRecord.fetchOne(tx.database, key: aci.rawUUID)
        }
    }

    /// Fetch the `UsernameLookupRecord` with the given username
    /// (case-insensitive, via `COLLATE NOCASE`), if one exists.
    ///
    /// The `username` column of `UsernameLookupRecord` store is
    /// case-insensitively unique, so there can only be one record for a given
    /// username.
    func fetchOne(forUsernameCaseInsensitive username: String, tx: DBReadTransaction) -> UsernameLookupRecord? {
        return failIfThrows {
            try UsernameLookupRecord
                .filter(
                    Column(UsernameLookupRecord.CodingKeys.username)
                        .collating(.nocase) == username,
                )
                .fetchOne(tx.database)
        }
    }

    func enumerateAll(tx: DBReadTransaction, block: (UsernameLookupRecord) -> Void) {
        failIfThrows {
            let cursor = try UsernameLookupRecord.all().fetchCursor(tx.database)
            while let value = try cursor.next() {
                block(value)
            }
        }
    }

    // MARK: -

    func insertOne(_ usernameLookupRecord: UsernameLookupRecord, tx: DBWriteTransaction) {
        failIfThrows {
            try usernameLookupRecord.insert(tx.database)
        }
    }

    func deleteOne(forAci aci: Aci, tx: DBWriteTransaction) {
        failIfThrows {
            _ = try UsernameLookupRecord.deleteOne(tx.database, key: aci.rawUUID)
        }
    }
}
