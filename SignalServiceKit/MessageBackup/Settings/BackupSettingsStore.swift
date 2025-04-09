//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public enum BackupFrequency: Int, CaseIterable, Identifiable {
    case daily = 1
    case weekly = 2
    case monthly = 3
    case manually = 4

    public var id: Int { rawValue }
}

// MARK: -

public struct BackupSettingsStore {
    private enum Keys {
        static let enabled = "enabled"
        static let lastBackupDate = "lastBackupDate"
        static let backupFrequency = "backupFrequency"
        static let shouldBackUpOnCellular = "shouldBackUpOnCellular"
    }

    private let kvStore: KeyValueStore

    public init() {
        kvStore = KeyValueStore(collection: "BackupSettingsStore")
    }

    // MARK: -

    /// Whether the user has affirmatively enabled or disabled Backups.
    ///
    /// A return value of `nil` indicates that the user has never made a
    /// decision about enabling Backups. Callers should generally treat this as
    /// "not enabled", but may take additional educational steps.
    public func areBackupsEnabled(tx: DBReadTransaction) -> Bool? {
        return kvStore.getBool(Keys.enabled, transaction: tx)
    }

    public func setAreBackupsEnabled(_ areBackupsEnabled: Bool, tx: DBWriteTransaction) {
        kvStore.setBool(areBackupsEnabled, key: Keys.enabled, transaction: tx)
    }

    // MARK: -

    public func lastBackupDate(tx: DBReadTransaction) -> Date? {
        return kvStore.getDate(Keys.lastBackupDate, transaction: tx)
    }

    public func setLastBackupDate(_ lastBackupDate: Date, tx: DBWriteTransaction) {
        kvStore.setDate(lastBackupDate, key: Keys.lastBackupDate, transaction: tx)
    }

    // MARK: -

    public func backupFrequency(tx: DBReadTransaction) -> BackupFrequency {
        if
            let persisted = kvStore.getInt(Keys.backupFrequency, transaction: tx)
                .flatMap({ BackupFrequency(rawValue: $0) })
        {
            return persisted
        }

        return .daily
    }

    public func setBackupFrequency(_ backupFrequency: BackupFrequency, tx: DBWriteTransaction) {
        kvStore.setInt(backupFrequency.rawValue, key: Keys.backupFrequency, transaction: tx)
    }

    // MARK: -

    public func shouldBackUpOnCellular(tx: DBReadTransaction) -> Bool {
        return kvStore.getBool(Keys.shouldBackUpOnCellular, transaction: tx) ?? false
    }

    public func setShouldBackUpOnCellular(_ shouldBackUpOnCellular: Bool, tx: DBWriteTransaction) {
        kvStore.setBool(shouldBackUpOnCellular, key: Keys.shouldBackUpOnCellular, transaction: tx)
    }
}
