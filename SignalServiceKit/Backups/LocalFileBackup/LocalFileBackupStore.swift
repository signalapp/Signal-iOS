//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

public class LocalFileBackupStore {
    private enum StoreKeys {
        static let bookmarkDataKey = "bookmarkData"
        static let lastEnumeratedAttachmentIdKey = "lastEnumeratedAttachmentId"
        static let shouldPromptUserToEnableLocalBackupsKey = "shouldPromptUserToEnableLocalBackups"
        static let shouldPromptUserToChooseNewLocationKey = "shouldPromptUserToChooseNewLocation"
    }

    private let kvStore: NewKeyValueStore

    init() {
        self.kvStore = NewKeyValueStore(collection: "LocalFileBackups")
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

    func insertExportRecord(attachmentId: Attachment.IDType, tx: DBWriteTransaction) {
        let attachmentToExport = BackupLocalFileAttachmentExportRecord(attachmentRowId: attachmentId)
        failIfThrows {
            try attachmentToExport.insert(tx.database)
        }
    }

    func insertImportRecord(attachmentId: Attachment.IDType, tx: DBWriteTransaction) {
        let localFileBackupAttachmentImport = BackupLocalFileAttachmentImportRecord(attachmentRowId: attachmentId)
        failIfThrows {
            try localFileBackupAttachmentImport.insert(tx.database)
        }
    }

    // MARK: - KVStore

    func fetchLastEnumeratedAttachmentRowId(tx: DBReadTransaction) -> Int64? {
        kvStore.fetchValue(Int64.self, forKey: StoreKeys.lastEnumeratedAttachmentIdKey, tx: tx)
    }

    func clearLastEnumeratedAttachmentRowId(tx: DBWriteTransaction) {
        kvStore.removeValue(forKey: StoreKeys.lastEnumeratedAttachmentIdKey, tx: tx)
    }

    func updateLastEnumeratedAttachmentRowId(_ attachmentId: Attachment.IDType, tx: DBWriteTransaction) {
        kvStore.writeValue(attachmentId, forKey: StoreKeys.lastEnumeratedAttachmentIdKey, tx: tx)
    }

    func fetchBookmarkData(tx: DBReadTransaction) -> SecurityScopedBookmark? {
        guard let data = kvStore.fetchValue(Data.self, forKey: StoreKeys.bookmarkDataKey, tx: tx) else {
            return nil
        }
        return SecurityScopedBookmark(rawValue: data)
    }

    func storeBookmarkData(bookmarkData: SecurityScopedBookmark, tx: DBWriteTransaction) {
        kvStore.writeValue(bookmarkData.rawValue, forKey: StoreKeys.bookmarkDataKey, tx: tx)
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
}
