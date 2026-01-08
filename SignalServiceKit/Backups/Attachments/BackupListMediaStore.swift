//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public struct BackupListMediaStore {
    private let kvStore: KeyValueStore

    public init() {
        self.kvStore = KeyValueStore(collection: "ListBackupMediaManager")
    }

    // MARK: -

    public func setLastFailingIntegrityCheckResult(
        _ newValue: ListMediaIntegrityCheckResult?,
        tx: DBWriteTransaction,
    ) {
        if
            let newValue,
            let serializedValue = try? JSONEncoder().encode(newValue)
        {
            kvStore.setData(serializedValue, key: Constants.lastNonEmptyIntegrityCheckResultKey, transaction: tx)
        } else {
            kvStore.removeValue(forKey: Constants.lastNonEmptyIntegrityCheckResultKey, transaction: tx)
        }
    }

    public func getLastFailingIntegrityCheckResult(tx: DBReadTransaction) -> ListMediaIntegrityCheckResult? {
        return kvStore.getData(Constants.lastNonEmptyIntegrityCheckResultKey, transaction: tx)
            .flatMap { serializedValue in
                try? JSONDecoder().decode(ListMediaIntegrityCheckResult.self, from: serializedValue)
            }
    }

    // MARK: -

    public func setMostRecentIntegrityCheckResult(
        _ newValue: ListMediaIntegrityCheckResult?,
        tx: DBWriteTransaction,
    ) {
        if
            let newValue,
            let serializedValue = try? JSONEncoder().encode(newValue)
        {
            kvStore.setData(serializedValue, key: Constants.lastIntegrityCheckResultKey, transaction: tx)
        } else {
            kvStore.removeValue(forKey: Constants.lastIntegrityCheckResultKey, transaction: tx)
        }
    }

    public func getMostRecentIntegrityCheckResult(tx: DBReadTransaction) -> ListMediaIntegrityCheckResult? {
        return kvStore.getData(Constants.lastIntegrityCheckResultKey, transaction: tx)
            .flatMap { serializedValue in
                try? JSONDecoder().decode(ListMediaIntegrityCheckResult.self, from: serializedValue)
            }
    }

    // MARK: -

    public func setManualNeedsListMedia(_ newValue: Bool, tx: DBWriteTransaction) {
        kvStore.setBool(newValue, key: Constants.manuallySetNeedsListMediaKey, transaction: tx)
    }

    public func getManualNeedsListMedia(tx: DBReadTransaction) -> Bool {
        return kvStore.getBool(Constants.manuallySetNeedsListMediaKey, defaultValue: false, transaction: tx)
    }

    // MARK: -

    private enum Constants {
        static let manuallySetNeedsListMediaKey = "manuallySetNeedsListMediaKey"

        static let lastNonEmptyIntegrityCheckResultKey = "lastNonEmptyIntegrityCheckResultKey"
        static let lastIntegrityCheckResultKey = "lastIntegrityCheckResultKey"
    }
}
