//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public struct BackupListMediaStore {
    private let kvStore: NewKeyValueStore

    public init() {
        self.kvStore = NewKeyValueStore(collection: "ListBackupMediaManager")
    }

    // MARK: -

    func removeAll(tx: DBWriteTransaction) {
        kvStore.removeAll(tx: tx)
    }

    // MARK: -

    public func setLastFailingIntegrityCheckResult(
        _ newValue: ListMediaIntegrityCheckResult?,
        tx: DBWriteTransaction,
    ) {
        kvStore.writeValueAsJSON(newValue, forKey: Constants.lastNonEmptyIntegrityCheckResultKey, tx: tx)
    }

    public func getLastFailingIntegrityCheckResult(tx: DBReadTransaction) -> ListMediaIntegrityCheckResult? {
        return try? kvStore.fetchJSONAsValue(
            ListMediaIntegrityCheckResult.self,
            forKey: Constants.lastNonEmptyIntegrityCheckResultKey,
            tx: tx,
        )
    }

    // MARK: -

    public func setMostRecentIntegrityCheckResult(
        _ newValue: ListMediaIntegrityCheckResult?,
        tx: DBWriteTransaction,
    ) {
        kvStore.writeValueAsJSON(newValue, forKey: Constants.lastIntegrityCheckResultKey, tx: tx)
    }

    public func getMostRecentIntegrityCheckResult(tx: DBReadTransaction) -> ListMediaIntegrityCheckResult? {
        return try? kvStore.fetchJSONAsValue(
            ListMediaIntegrityCheckResult.self,
            forKey: Constants.lastIntegrityCheckResultKey,
            tx: tx,
        )
    }

    // MARK: -

    public func setManualNeedsListMedia(_ newValue: Bool, tx: DBWriteTransaction) {
        kvStore.writeValue(newValue, forKey: Constants.manuallySetNeedsListMediaKey, tx: tx)
    }

    public func getManualNeedsListMedia(tx: DBReadTransaction) -> Bool {
        return kvStore.fetchValue(Bool.self, forKey: Constants.manuallySetNeedsListMediaKey, tx: tx) ?? false
    }

    // MARK: -

    private enum Constants {
        static let manuallySetNeedsListMediaKey = "manuallySetNeedsListMediaKey"

        static let lastNonEmptyIntegrityCheckResultKey = "lastNonEmptyIntegrityCheckResultKey"
        static let lastIntegrityCheckResultKey = "lastIntegrityCheckResultKey"
    }
}
