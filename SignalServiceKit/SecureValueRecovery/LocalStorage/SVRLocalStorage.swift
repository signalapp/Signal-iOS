//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Stores state related to SVR; e.g. do we have backups at all, etc.
struct SVRLocalStorage {
    let completedBackupStore = KeyValueStore(collection: "SVR.Completed")

    func getIsMasterKeyBackedUp(_ transaction: DBReadTransaction) -> Bool {
        return !completedBackupStore.allKeys(transaction: transaction).isEmpty
    }
}
