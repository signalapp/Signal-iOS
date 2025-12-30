//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public class BackupListMediaStore {

    private let kvStore: KeyValueStore

    public init() {
        self.kvStore = KeyValueStore(collection: "ListBackupMediaManager")
    }

    public func setLastFailingIntegrityCheckResult(
        _ newValue: ListMediaIntegrityCheckResult?,
        tx: DBWriteTransaction,
    ) throws {
        if let newValue {
            try kvStore.setCodable(
                newValue,
                key: Constants.lastNonEmptyIntegrityCheckResultKey,
                transaction: tx,
            )
        } else {
            kvStore.removeValue(
                forKey: Constants.lastNonEmptyIntegrityCheckResultKey,
                transaction: tx,
            )
        }
    }

    public func getLastFailingIntegrityCheckResult(tx: DBReadTransaction) throws -> ListMediaIntegrityCheckResult? {
        try kvStore.getCodableValue(forKey: Constants.lastNonEmptyIntegrityCheckResultKey, transaction: tx)
    }

    public func setMostRecentIntegrityCheckResult(
        _ newValue: ListMediaIntegrityCheckResult?,
        tx: DBWriteTransaction,
    ) throws {
        if let newValue {
            try kvStore.setCodable(
                newValue,
                key: Constants.lastIntegrityCheckResultKey,
                transaction: tx,
            )
        } else {
            kvStore.removeValue(
                forKey: Constants.lastIntegrityCheckResultKey,
                transaction: tx,
            )
        }
    }

    public func getMostRecentIntegrityCheckResult(tx: DBReadTransaction) throws -> ListMediaIntegrityCheckResult? {
        try kvStore.getCodableValue(forKey: Constants.lastIntegrityCheckResultKey, transaction: tx)
    }

    public func setManualNeedsListMedia(_ newValue: Bool, tx: DBWriteTransaction) {
        kvStore.setBool(newValue, key: Constants.manuallySetNeedsListMediaKey, transaction: tx)
    }

    public func getManualNeedsListMedia(tx: DBReadTransaction) -> Bool {
        return kvStore.getBool(Constants.manuallySetNeedsListMediaKey, defaultValue: false, transaction: tx)
    }

    private enum Constants {
        static let manuallySetNeedsListMediaKey = "manuallySetNeedsListMediaKey"

        static let lastNonEmptyIntegrityCheckResultKey = "lastNonEmptyIntegrityCheckResultKey"
        static let lastIntegrityCheckResultKey = "lastIntegrityCheckResultKey"
    }
}
