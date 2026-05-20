//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// Tracks errors that occur during Backup archive/restore.
/// - Important
/// Errors are only tracked for internal users, and result in presenting
/// internal-only UI. Take care if expanding this beyond internal.
public struct BackupArchiveErrorStore {

    private let kvStore: KeyValueStore
    private static let hasPendingErrorsKey = "hasPendingErrors"

    public init() {
        kvStore = KeyValueStore(collection: "BackupArchiveErrorStore")
    }

    public func setHasError(_ value: Bool, tx: DBWriteTransaction) {
        guard BuildFlags.Backups.archiveErrorDisplay else {
            return
        }

        kvStore.setBool(value, key: Self.hasPendingErrorsKey, transaction: tx)
    }

    public func hasError(tx: DBReadTransaction) -> Bool {
        guard BuildFlags.Backups.archiveErrorDisplay else {
            return false
        }

        return kvStore.getBool(Self.hasPendingErrorsKey, defaultValue: false, transaction: tx)
    }
}
