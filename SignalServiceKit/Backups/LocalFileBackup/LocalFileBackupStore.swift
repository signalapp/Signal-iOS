//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

extension NSNotification.Name {
    public static let lastLocalBackupDetailsDidChange = Notification.Name("LocalFileBackupStore.lastLocalBackupDetailsDidChange")
}

public struct LocalFileBackupStore {
    private enum StoreKeys {
        static let archiveBookmarkDataKey = "archiveBookmarkData"
        static let restoreBookmarkDataKey = "restoreBookmarkData"
        static let lastEnumeratedAttachmentIdKey = "lastEnumeratedAttachmentId"
        static let shouldPromptUserToEnableLocalBackupsKey = "shouldPromptUserToEnableLocalBackups"
        static let shouldPromptUserToChooseNewLocationKey = "shouldPromptUserToChooseNewLocation"
        static let haveEverBeenEnabled = "haveEverBeenEnabledKey"
        static let isEnabled = "isEnabledKey"
        static let shouldOverrideShowBackupsOnboarding = "shouldOverrideShowBackupsOnboardingKey"
        static let lastBackupDate = "lastBackupDateKey"
        static let lastBackupSizeBytes = "lastBackupSizeBytesKey"
        static let lastLocalFileBackupEnabledDate = "lastBackupEnabledDate"

        static let backgroundLocalFileBackupErrorCount = "backgroundLocalFileBackupErrorCount"
        static let interactiveLocalFileBackupErrorCount = "interactiveLocalFileBackupErrorCount"
    }

    private let kvStore: NewKeyValueStore
    private let errorStateStore: NewKeyValueStore

    public init() {
        self.kvStore = NewKeyValueStore(collection: "LocalFileBackups")
        self.errorStateStore = NewKeyValueStore(collection: "LocalFileBackupsErrors")
    }

    func importRecords(batchSize: Int, tx: DBReadTransaction) -> [BackupLocalFileAttachmentImportRecord] {
        failIfThrows {
            try BackupLocalFileAttachmentImportRecord
                .limit(batchSize)
                .fetchAll(tx.database)
        }
    }

    func exportRecords(batchSize: Int, tx: DBReadTransaction) -> [BackupLocalFileAttachmentExportRecord] {
        failIfThrows {
            try BackupLocalFileAttachmentExportRecord
                .limit(batchSize)
                .fetchAll(tx.database)
        }
    }

    func exportRecordsCount(tx: DBReadTransaction) -> Int {
        failIfThrows {
            try BackupLocalFileAttachmentExportRecord
                .fetchCount(tx.database)
        }
    }

    func attachmentCountSinceLastFetched(tx: DBReadTransaction) -> Int {
        failIfThrows {
            var query = Attachment.Record
                .filter(Column(Attachment.Record.CodingKeys.plaintextHash) != nil)
            if let lastId = fetchLastEnumeratedAttachmentRowId(tx: tx) {
                query = query.filter(Column(Attachment.Record.CodingKeys.sqliteId) > lastId)
            }
            return try query.fetchCount(tx.database)
        }
    }

    func metadataRecord(attachmentId: Attachment.IDType, failIfNotExists: Bool, tx: DBReadTransaction) -> BackupLocalFileAttachmentMetadataRecord? {
        failIfThrows {
            guard
                let metadata = try BackupLocalFileAttachmentMetadataRecord
                    .filter(key: attachmentId)
                    .fetchOne(tx.database)
            else {
                if failIfNotExists {
                    // TODO: Store error to present to beta user
                    owsFailBeta("Local file backup attachment in the import queue is missing metadata")
                }
                return nil
            }
            return metadata
        }
    }

    func insertNewMetadataIfNeeded(attachmentId: Attachment.IDType, unencryptedByteCount: UInt32, localKey: Data?, tx: DBWriteTransaction) {
        let existingMetadata = metadataRecord(attachmentId: attachmentId, failIfNotExists: false, tx: tx)
        if existingMetadata == nil {
            let localKeyToInsert: Data
            if let localKey {
                localKeyToInsert = localKey
            } else {
                localKeyToInsert = Randomness.generateRandomBytes(64)
            }
            let metadataToInsert = BackupLocalFileAttachmentMetadataRecord(
                attachmentRowId: attachmentId,
                localKey: localKeyToInsert,
                unencryptedByteCount: unencryptedByteCount,
            )
            failIfThrows {
                try metadataToInsert.insert(tx.database)
            }
        }
    }

    func totalUnencryptedByteCountOfQueuedImports(tx: DBReadTransaction) -> UInt64 {
        let importTable = BackupLocalFileAttachmentImportRecord.databaseTableName
        let metadataTable = BackupLocalFileAttachmentMetadataRecord.databaseTableName
        let idColumn = BackupLocalFileAttachmentMetadataRecord.CodingKeys.attachmentRowId.stringValue
        let byteCountColumn = BackupLocalFileAttachmentMetadataRecord.CodingKeys.unencryptedByteCount.stringValue

        let sql = """
        SELECT SUM("\(metadataTable)"."\(byteCountColumn)")
        FROM "\(metadataTable)"
        INNER JOIN "\(importTable)"
            ON "\(metadataTable)"."\(idColumn)" = "\(importTable)"."\(idColumn)"
        """

        return failIfThrows {
            UInt64(try Int64.fetchOne(tx.database, sql: sql) ?? 0)
        }
    }

    func totalUnencryptedByteCountOfQueuedExports(tx: DBReadTransaction) -> UInt64 {
        let exportTable = BackupLocalFileAttachmentExportRecord.databaseTableName
        let metadataTable = BackupLocalFileAttachmentMetadataRecord.databaseTableName
        let idColumn = BackupLocalFileAttachmentMetadataRecord.CodingKeys.attachmentRowId.stringValue
        let byteCountColumn = BackupLocalFileAttachmentMetadataRecord.CodingKeys.unencryptedByteCount.stringValue

        let sql = """
        SELECT SUM("\(metadataTable)"."\(byteCountColumn)")
        FROM "\(metadataTable)"
        INNER JOIN "\(exportTable)"
            ON "\(metadataTable)"."\(idColumn)" = "\(exportTable)"."\(idColumn)"
        """

        return failIfThrows {
            UInt64(try Int64.fetchOne(tx.database, sql: sql) ?? 0)
        }
    }

    func insertExportRecord(attachmentId: Attachment.IDType, tx: DBWriteTransaction) {
        failIfThrows {
            let attachmentExists = try Attachment.Record
                .filter(key: attachmentId)
                .fetchCount(tx.database) > 0
            guard attachmentExists else {
                Logger.warn("Skipping export queue insert; attachment \(attachmentId) was deleted after backup proto was created")
                return
            }
            let attachmentToExport = BackupLocalFileAttachmentExportRecord(attachmentRowId: attachmentId)
            try attachmentToExport.insert(tx.database)
        }
    }

    func insertImportRecord(attachmentId: Attachment.IDType, tx: DBWriteTransaction) {
        let localFileBackupAttachmentImport = BackupLocalFileAttachmentImportRecord(attachmentRowId: attachmentId)
        failIfThrows {
            try localFileBackupAttachmentImport.insert(tx.database)
        }
    }

    func hasPendingImportRecord(attachmentId: Attachment.IDType, tx: DBReadTransaction) -> Bool {
        failIfThrows {
            try BackupLocalFileAttachmentImportRecord
                .filter(key: attachmentId)
                .fetchOne(tx.database) != nil
        }
    }

    // MARK: - KVStore

    func fetchLastEnumeratedAttachmentRowId(tx: DBReadTransaction) -> Int64? {
        kvStore.fetchValue(Int64.self, forKey: StoreKeys.lastEnumeratedAttachmentIdKey, tx: tx)
    }

    public func clearLastEnumeratedAttachmentRowId(tx: DBWriteTransaction) {
        kvStore.removeValue(forKey: StoreKeys.lastEnumeratedAttachmentIdKey, tx: tx)
    }

    func updateLastEnumeratedAttachmentRowId(_ attachmentId: Attachment.IDType, tx: DBWriteTransaction) {
        kvStore.writeValue(attachmentId, forKey: StoreKeys.lastEnumeratedAttachmentIdKey, tx: tx)
    }

    func fetchArchiveBookmarkData(tx: DBReadTransaction) -> SecurityScopedBookmark? {
        guard let data = kvStore.fetchValue(Data.self, forKey: StoreKeys.archiveBookmarkDataKey, tx: tx) else {
            return nil
        }
        return SecurityScopedBookmark(rawValue: data)
    }

    func storeArchiveBookmarkData(bookmarkData: SecurityScopedBookmark, tx: DBWriteTransaction) {
        kvStore.writeValue(bookmarkData.rawValue, forKey: StoreKeys.archiveBookmarkDataKey, tx: tx)
    }

    public func clearArchiveBookmarkData(tx: DBWriteTransaction) {
        kvStore.removeValue(forKey: StoreKeys.archiveBookmarkDataKey, tx: tx)
    }

    func fetchRestoreBookmarkData(tx: DBReadTransaction) -> SecurityScopedBookmark? {
        guard let data = kvStore.fetchValue(Data.self, forKey: StoreKeys.restoreBookmarkDataKey, tx: tx) else {
            return nil
        }
        return SecurityScopedBookmark(rawValue: data)
    }

    func storeRestoreBookmarkData(bookmarkData: SecurityScopedBookmark, tx: DBWriteTransaction) {
        kvStore.writeValue(bookmarkData.rawValue, forKey: StoreKeys.restoreBookmarkDataKey, tx: tx)
    }

    // MARK: - Prompt user to enable local backups, e.g. after restoring

    public func shouldPromptUserToEnableLocalBackups(tx: DBReadTransaction) -> Bool {
        return kvStore.fetchValue(Bool.self, forKey: StoreKeys.shouldPromptUserToEnableLocalBackupsKey, tx: tx) ?? false
    }

    public func clearShouldPromptUserToEnableLocalBackups(tx: DBWriteTransaction) {
        kvStore.removeValue(forKey: StoreKeys.shouldPromptUserToEnableLocalBackupsKey, tx: tx)
    }

    public func setShouldPromptUserToEnableLocalBackups(tx: DBWriteTransaction) {
        kvStore.writeValue(true, forKey: StoreKeys.shouldPromptUserToEnableLocalBackupsKey, tx: tx)
    }

    // MARK: - Prompt user to choose new local backup location, e.g. if there was an error archiving

    public func shouldPromptUserToChooseNewLocalBackupLocation(tx: DBReadTransaction) -> Bool {
        return kvStore.fetchValue(Bool.self, forKey: StoreKeys.shouldPromptUserToChooseNewLocationKey, tx: tx) ?? false
    }

    public func clearChooseNewLocalBackupLocation(tx: DBWriteTransaction) {
        kvStore.removeValue(forKey: StoreKeys.shouldPromptUserToChooseNewLocationKey, tx: tx)
    }

    public func setChooseNewLocalBackupLocation(tx: DBWriteTransaction) {
        kvStore.writeValue(true, forKey: StoreKeys.shouldPromptUserToChooseNewLocationKey, tx: tx)
    }

    // MARK: - EverBeenEnabled

    /// Whether Local Backups have ever been enabled, regardless of whether they are
    /// enabled currently.
    public func haveLocalBackupsEverBeenEnabled(tx: DBReadTransaction) -> Bool {
        return kvStore.fetchValue(Bool.self, forKey: StoreKeys.haveEverBeenEnabled, tx: tx) ?? false
    }

    // MARK: - IsEnabled

    /// Whether Local Backups is currently enabled.
    public func localBackupsEnabled(tx: DBReadTransaction) -> Bool {
        return kvStore.fetchValue(Bool.self, forKey: StoreKeys.isEnabled, tx: tx) ?? false
    }

    public func setLocalBackupsEnabled(value: Bool, tx: DBWriteTransaction) {
        kvStore.writeValue(value, forKey: StoreKeys.isEnabled, tx: tx)
        if value {
            kvStore.writeValue(true, forKey: StoreKeys.haveEverBeenEnabled, tx: tx)
            kvStore.writeValue(Date(), forKey: StoreKeys.lastLocalFileBackupEnabledDate, tx: tx)
        }
    }

    // MARK: - Internal: Show Local Backups Onboarding

    /// Whether to force showing Local Backups onboarding.
    ///
    /// Not intended for production use.
    public func shouldOverrideShowLocalBackupsOnboarding(tx: DBReadTransaction) -> Bool {
        return kvStore.fetchValue(Bool.self, forKey: StoreKeys.shouldOverrideShowBackupsOnboarding, tx: tx) ?? false
    }

    /// Set an override to show Local Backups onboarding.
    ///
    /// Not intended for production use.
    public func setShouldOverrideShowLocalBackupsOnboarding(_ value: Bool, tx: DBWriteTransaction) {
        kvStore.writeValue(value, forKey: StoreKeys.shouldOverrideShowBackupsOnboarding, tx: tx)
    }

    // MARK: - Last backup details

    public struct LastBackupDetails {
        /// The date of our last backup.
        public let date: Date
        /// The total size of our most recent backup, including the Backup proto
        /// file and all backed-up media.
        public let backupTotalSizeBytes: UInt64

        public init(
            date: Date,
            backupTotalSizeBytes: UInt64,
        ) {
            self.date = date
            self.backupTotalSizeBytes = backupTotalSizeBytes
        }
    }

    public func lastBackupDetails(tx: DBReadTransaction) -> LastBackupDetails? {
        guard
            let lastBackupDate = kvStore.fetchValue(Date.self, forKey: StoreKeys.lastBackupDate, tx: tx),
            let backupTotalSizeBytes = kvStore.fetchValue(UInt64.self, forKey: StoreKeys.lastBackupSizeBytes, tx: tx)
        else {
            return nil
        }

        return LastBackupDetails(
            date: lastBackupDate,
            backupTotalSizeBytes: backupTotalSizeBytes,
        )
    }

    public func setLastBackupDetails(
        date: Date,
        backupSizeBytes: UInt64,
        tx: DBWriteTransaction,
    ) {
        kvStore.writeValue(date, forKey: StoreKeys.lastBackupDate, tx: tx)
        kvStore.writeValue(backupSizeBytes, forKey: StoreKeys.lastBackupSizeBytes, tx: tx)

        tx.addSyncCompletion {
            NotificationCenter.default.postOnMainThread(name: .lastLocalBackupDetailsDidChange, object: nil)
        }

        // We did a backup, so clear all error state.
        clearErrorStateStore(tx: tx)
    }

    public func clearLastBackupDetails(
        tx: DBWriteTransaction,
    ) {
        kvStore.removeValue(forKey: StoreKeys.lastBackupDate, tx: tx)
        kvStore.removeValue(forKey: StoreKeys.lastBackupSizeBytes, tx: tx)
    }

    // MARK: - LastBackupEnabledTime

    public func lastLocalFileBackupEnabledDate(
        tx: DBReadTransaction,
    ) -> Date? {
        kvStore.fetchValue(Date.self, forKey: StoreKeys.lastLocalFileBackupEnabledDate, tx: tx)
    }

    public func clearLastBackupEnabledDetails(tx: DBWriteTransaction) {
        kvStore.removeValue(forKey: StoreKeys.lastLocalFileBackupEnabledDate, tx: tx)
    }

    // MARK: - Local File Backup Errors

    public func getInteractiveLocalFileBackupErrorCount(tx: DBReadTransaction) -> UInt64 {
        errorStateStore.fetchValue(UInt64.self, forKey: StoreKeys.interactiveLocalFileBackupErrorCount, tx: tx) ?? 0
    }

    public func incrementInteractiveLocalFileBackupErrorCount(tx: DBWriteTransaction) {
        let nextCount = getInteractiveLocalFileBackupErrorCount(tx: tx) + 1
        errorStateStore.writeValue(nextCount, forKey: StoreKeys.interactiveLocalFileBackupErrorCount, tx: tx)
    }

    public func getBackgroundLocalFileBackupErrorCount(tx: DBReadTransaction) -> UInt64 {
        errorStateStore.fetchValue(UInt64.self, forKey: StoreKeys.backgroundLocalFileBackupErrorCount, tx: tx) ?? 0
    }

    public func incrementBackgroundLocalFileBackupErrorCount(tx: DBWriteTransaction) {
        let nextCount = getBackgroundLocalFileBackupErrorCount(tx: tx) + 1
        errorStateStore.writeValue(nextCount, forKey: StoreKeys.backgroundLocalFileBackupErrorCount, tx: tx)
    }

    public func clearErrorStateStore(tx: DBWriteTransaction) {
        errorStateStore.removeAll(tx: tx)
    }
}
