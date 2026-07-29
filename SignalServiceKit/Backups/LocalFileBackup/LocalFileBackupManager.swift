//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CryptoKit
import LibSignalClient

public enum LocalFileBackupError: Error {
    public enum AccessFailureReason {
        case stale
        case missing
        case noAccess
    }

    case unableToAccessLocalFile(AccessFailureReason)
}

/// Manager to handle local file backup logic, including file I/O, UIDocumentPicker logic, and security-scoped bookmark handling.
/// Actual archiving of the backup is handled by BackupArchiveManager.
public class LocalFileBackupManager: NSObject, UIDocumentPickerDelegate {
    public enum FileStructure: String {
        case rootDirectory = "SignalBackups"
        case attachmentDirectory = "files"
        case backupFile = "main"
        case metadataFile = "metadata"

        static let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
            return formatter
        }()

        static func backupDirectory(date: Date) -> String {
            return "signal-backups-\(dateFormatter.string(from: date))"
        }
    }

    struct AttachmentWithMetadata {
        let attachment: Attachment
        let metadata: BackupLocalFileAttachmentMetadataRecord
    }

    private let logger: PrefixedLogger
    private let db: DB
    private let dateProvider: DateProvider
    private let attachmentStore: AttachmentStore
    private let attachmentValidator: AttachmentContentValidator
    private let orphanedAttachmentCleaner: OrphanedAttachmentCleaner
    private nonisolated let localFileBackupStore: LocalFileBackupStore
    private let securityScopedBookmarkAccess: SecurityScopedBookmarkAccess

    private static let maxAllowedNumberOfBackups: Int = 2

    init(
        db: DB,
        dateProvider: @escaping DateProvider,
        attachmentStore: AttachmentStore,
        attachmentValidator: AttachmentContentValidator,
        orphanedAttachmentCleaner: OrphanedAttachmentCleaner,
        localFileBackupStore: LocalFileBackupStore,
        securityScopedBookmarkAccess: SecurityScopedBookmarkAccess,
    ) {
        self.db = db
        self.dateProvider = dateProvider
        self.attachmentStore = attachmentStore
        self.attachmentValidator = attachmentValidator
        self.orphanedAttachmentCleaner = orphanedAttachmentCleaner
        self.logger = PrefixedLogger(prefix: "[LocalFileBackups]")
        self.localFileBackupStore = localFileBackupStore
        self.securityScopedBookmarkAccess = securityScopedBookmarkAccess
    }

    /*
     ---- DIRECTORY STRUCTURE ----

     SignalBackups/
     ├─ signal-backup-{year}-{month}-{day}-{hr}-{min}-{sec}/
          ├─ metadata
          ├─ main
          └─ files
     └─ files/
       └─ <fileName prefix>
          └─ <fileName 1>
       └─ <fileName prefix>
          ├─ <fileName 2>
          └─ <fileName 3>
       ...
       └─ <fileName prefix>
          └─ <fileName N>
     */

    // MARK: - Restoring

    func restoreLocalFileBackupAttachments() async throws {
        let resolvedURL: URL?
        do {
            resolvedURL = try getSavedSecurityScopedBookmark()
        } catch {
            throw LocalFileBackupError.unableToAccessLocalFile(.noAccess)
        }

        guard let resolvedURL else {
            // No local file backup location stored.
            return
        }

        let hasAccess = securityScopedBookmarkAccess.startAccessToSecurityScopedBookmark(url: resolvedURL)
        guard hasAccess else {
            throw LocalFileBackupError.unableToAccessLocalFile(.noAccess)
        }

        defer {
            securityScopedBookmarkAccess.stopAccessToSecurityScopedBookmark(url: resolvedURL)
        }

        try await _restoreLocalFileBackupAttachments(resolvedURL: resolvedURL)
    }

    private func fetchImportRecordsAndAssociatedAttachmentRecords() -> [(AttachmentWithMetadata, BackupLocalFileAttachmentImportRecord)] {
        let attachmentBatchSize = 50
        return db.read { tx in
            let imports = localFileBackupStore.importRecords(batchSize: attachmentBatchSize, tx: tx)
            let attachments = attachmentStore.fetch(ids: imports.map({ $0.attachmentRowId }), tx: tx)
            let attachmentsByID = Dictionary(uniqueKeysWithValues: attachments.map { ($0.id, $0) })

            return imports.compactMap { importRecord in
                let attachment = attachmentsByID[importRecord.attachmentRowId].owsFailUnwrap("FOREIGN KEYs mean this must exist.")
                guard let metadata = localFileBackupStore.metadataRecord(attachmentId: importRecord.attachmentRowId, failIfNotExists: true, tx: tx) else {
                    return nil
                }
                return (AttachmentWithMetadata(attachment: attachment, metadata: metadata), importRecord)
            }
        }
    }

    func _restoreLocalFileBackupAttachments(resolvedURL: URL) async throws {
        while true {
            let attachmentsWithMetadata: [(AttachmentWithMetadata, BackupLocalFileAttachmentImportRecord)] = fetchImportRecordsAndAssociatedAttachmentRecords()
            if attachmentsWithMetadata.isEmpty {
                break
            }

            let attachmentsDir = resolvedURL.appendingPathComponent(FileStructure.attachmentDirectory.rawValue)
            for (attachmentWithMetadata, localFileImport) in attachmentsWithMetadata {
                guard let plaintextHash = attachmentWithMetadata.attachment.plaintextHash else {
                    // TODO: Store error to present to beta user
                    owsFailBeta("Missing plaintext hash for a local file attachment")
                    continue
                }
                // The files dir is divided into subdirectories based on the first 2 characters of the media name
                let mediaName = mediaNameForAttachment(localKey: attachmentWithMetadata.metadata.localKey, plaintextHash: plaintextHash)
                let attachmentSubDirectory = attachmentsDir.appendingPathComponent(String(mediaName.prefix(2)))

                let destination = attachmentSubDirectory.appendingPathComponent(mediaName)

                let attachmentKey = try AttachmentKey(combinedKey: attachmentWithMetadata.metadata.localKey)

                let pendingAttachment = try await attachmentValidator.validateDownloadedContents(
                    ofEncryptedFileAt: destination,
                    attachmentKey: attachmentKey,
                    plaintextLength: attachmentWithMetadata.metadata.unencryptedByteCount,
                    integrityCheck: .plaintextHash(plaintextHash),
                    mimeType: attachmentWithMetadata.attachment.mimeType,
                    renderingFlag: .default,
                    sourceFilename: nil,
                )

                try db.write { tx in
                    try attachmentStore.updateLocalFileBackupAttachmentAsTransferred(
                        attachment: attachmentWithMetadata.attachment,
                        streamInfo: Attachment.StreamInfo(pendingAttachment: pendingAttachment),
                        tx: tx,
                    )
                    orphanedAttachmentCleaner.releasePendingAttachment(
                        withId: pendingAttachment.orphanRecordId,
                        tx: tx,
                    )

                    try localFileImport.delete(tx.database)
                }
            }
        }
    }

    // MARK: - Archiving

    /// - Parameter backupsRootDirectory
    /// The SignalBackups directory.
    private func existingFilesInBackupDirectory(backupsRootDirectory: URL) throws -> [String: Int] {
        let fileCoordinator = NSFileCoordinator()

        var existingFiles: [String: Int] = [:]
        try fileCoordinator.coordinateThrows(
            readingItemAt: backupsRootDirectory,
            options: .withoutChanges,
            by: { temporaryFileUrl in
                let filesDirectoryUrl = temporaryFileUrl.appendingPathComponent(FileStructure.attachmentDirectory.rawValue)
                guard
                    let enumerator = FileManager.default.enumerator(
                        at: filesDirectoryUrl,
                        includingPropertiesForKeys: [.fileSizeKey, .nameKey],
                        options: [],
                    )
                else {
                    return
                }
                while let fileURL = enumerator.nextObject() as? URL {
                    let fileValues = try fileURL.resourceValues(forKeys: [.fileSizeKey, .nameKey, .isDirectoryKey])
                    if let isDir = fileValues.isDirectory, isDir {
                        continue
                    }
                    if
                        let size = fileValues.fileSize,
                        let name = fileValues.name
                    {
                        existingFiles[name] = size
                    } else {
                        owsFailDebug("Unexpectedly missing size/name from resource keys!")
                    }
                }
            },
        )
        return existingFiles
    }

    /// - Parameter backupsRootDirectory
    /// The SignalBackups directory.
    func writeQueuedAttachmentsToDisk(backupsRootDirectory: URL, currentBackupDirectoryName: String) throws {
        let fileCoordinator = NSFileCoordinator()

        let existingFiles = try existingFilesInBackupDirectory(backupsRootDirectory: backupsRootDirectory)

        let attachmentBatchSize = 50
        while true {
            let (attachmentsWithMetadata, localFileExports) = db.read { tx in
                failIfThrows {
                    let localFileExports = localFileBackupStore.exportRecords(batchSize: attachmentBatchSize, tx: tx)
                    let ids = localFileExports.map({ $0.attachmentRowId })
                    let attachments = attachmentStore.fetch(ids: ids, tx: tx)
                    let attachmentsWithMetadata: [AttachmentWithMetadata] = attachments.compactMap {
                        guard let metadata = localFileBackupStore.metadataRecord(attachmentId: $0.id, failIfNotExists: true, tx: tx) else {
                            return nil
                        }
                        return AttachmentWithMetadata(attachment: $0, metadata: metadata)
                    }

                    return (attachmentsWithMetadata, localFileExports)
                }
            }
            if localFileExports.isEmpty { break }

            let attachmentMetadataFile = backupsRootDirectory
                .appendingPathComponent(currentBackupDirectoryName)
                .appendingPathComponent(FileStructure.attachmentDirectory.rawValue)

            guard let outputStream = OutputStream(url: attachmentMetadataFile, append: false) else {
                throw OWSAssertionError("Unable to initalize output stream")
            }
            outputStream.open()

            let manifestStream = TransformingOutputStream(
                transforms: [ChunkedOutputStreamTransform()],
                outputStream: outputStream,
            )

            for attachmentWithMetadata in attachmentsWithMetadata {
                guard let attachmentStream = attachmentWithMetadata.attachment.asStream() else {
                    continue
                }

                let localKey = attachmentWithMetadata.metadata.localKey
                let localFileBackupMediaName = mediaNameForAttachment(
                    localKey: localKey,
                    plaintextHash: attachmentStream.plaintextHash,
                )

                if let _ = existingFiles[localFileBackupMediaName] {
                    // Already exists on disk, can skip copying.
                    // TODO: [KC] also check encrypted byte count is what we expect

                    var fileProto = LocalBackupProto_FilesFrame()
                    fileProto.item = .mediaName(localFileBackupMediaName)
                    try manifestStream.write(data: fileProto.serializedData())
                    continue
                }

                let encryptedFileHandle = try Cryptography.encryptedAttachmentFileHandle(
                    at: attachmentStream.fileURL,
                    plaintextLength: UInt64(safeCast: attachmentStream.unencryptedByteCount),
                    attachmentKey: AttachmentKey(combinedKey: attachmentStream.attachment.encryptionKey),
                )

                let attachmentKey = try AttachmentKey(combinedKey: localKey)

                // The files dir is divided into subdirectories based on the first 2 characters of the media name
                let attachmentSubDirectory = backupsRootDirectory
                    .appendingPathComponent(FileStructure.attachmentDirectory.rawValue)
                    .appendingPathComponent(String(localFileBackupMediaName.prefix(2)))

                try fileCoordinator.coordinateThrows(
                    writingItemAt: attachmentSubDirectory,
                    options: [],
                    writingItemAt: attachmentMetadataFile,
                    options: [],
                ) { attachmentDirUrl, metadataURL in
                    try FileManager.default.createDirectory(at: attachmentDirUrl, withIntermediateDirectories: true)
                    let destination = attachmentDirUrl.appendingPathComponent(localFileBackupMediaName)

                    let _ = try Cryptography.reencryptFileHandle(
                        at: encryptedFileHandle,
                        attachmentKey: attachmentKey,
                        encryptedOutputUrl: destination,
                        applyExtraPadding: true,
                    )

                    var fileProto = LocalBackupProto_FilesFrame()
                    fileProto.item = .mediaName(localFileBackupMediaName)
                    try manifestStream.write(data: fileProto.serializedData())
                }
            }

            try manifestStream.close()

            failIfThrows {
                try db.write { tx in
                    for localFileExport in localFileExports {
                        try localFileExport.delete(tx.database)
                    }
                }
            }
        }
    }

    func mediaNameForAttachment(localKey: Data, plaintextHash: Data) -> String {
        let value = plaintextHash + localKey
        var sha = SHA256()
        sha.update(data: value)
        let hash = Data(sha.finalize())
        return hash.hexadecimalString
    }

    func queueLocalBackupAttachmentsForExport(localFileBackupAttachmentCollector: LocalFileBackupAttachmentCollector) async throws(CancellationError) {
        try await TimeGatedBatch.processAll(
            db: db,
            processBatch: { tx throws(CancellationError) in
                if Task.isCancelled {
                    throw CancellationError()
                }
                guard let attachmentId = localFileBackupAttachmentCollector.removeLast() else {
                    return .done(())
                }
                localFileBackupStore.insertExportRecord(attachmentId: attachmentId, tx: tx)
                return .more
            },
        )
    }

    private func buildMetadataProto(messageRootBackupKey: MessageRootBackupKey) throws -> LocalBackupProto_Metadata {
        let localBackupMetadataKey = messageRootBackupKey.backupKey.deriveLocalBackupMetadataKey()
        let backupIdBytes = messageRootBackupKey.backupId
        let iv = Randomness.generateRandomBytes(12)
        let nonce = iv + Data(count: 4) // Last 4 bytes are 0 for the counter.
        var encryptedBackupId = backupIdBytes
        try Aes256Ctr32.process(&encryptedBackupId, key: localBackupMetadataKey, nonce: nonce)

        var metadataProto = LocalBackupProto_Metadata()
        metadataProto.version = 1

        var encryptedBackupIdProto = LocalBackupProto_Metadata.EncryptedBackupId()
        encryptedBackupIdProto.iv = iv
        encryptedBackupIdProto.encryptedID = encryptedBackupId

        metadataProto.backupID = encryptedBackupIdProto

        return metadataProto
    }

    func ensureAttachmentMetadataExists() async {
        struct TxContextAttachmentMetadata {
            var cursor: FailIfThrowsRecordCursor<Attachment.Record>
            var lastEnumeratedAttachmentId: Attachment.IDType?
            var didFinish: Bool
        }
        await TimeGatedBatch.processAll(
            db: db,
            buildTxContext: { tx -> TxContextAttachmentMetadata in
                let lastEnumeratedAttachmentId: Attachment.IDType? = localFileBackupStore.fetchLastEnumeratedAttachmentRowId(tx: tx)

                return TxContextAttachmentMetadata(
                    cursor: FailIfThrowsRecordCursor {
                        return try attachmentStore.attachmentRecordsWithPlaintextHash(
                            lastEnumeratedAttachmentId: lastEnumeratedAttachmentId,
                            tx: tx,
                        )
                    },
                    lastEnumeratedAttachmentId: lastEnumeratedAttachmentId,
                    didFinish: false,
                )
            },
            processBatch: { tx, txContext -> TimeGatedBatch.ProcessBatchResult<Void> in
                guard let nextAttachmentRecord = txContext.cursor.next() else {
                    txContext.didFinish = true
                    return .done(())
                }

                let attachmentRecordId = nextAttachmentRecord.sqliteId!
                txContext.lastEnumeratedAttachmentId = attachmentRecordId

                guard let unencryptedByteCount = nextAttachmentRecord.unencryptedByteCount else {
                    return .more
                }

                localFileBackupStore.insertNewMetadataIfNeeded(
                    attachmentId: attachmentRecordId,
                    unencryptedByteCount: unencryptedByteCount,
                    // Create a new local key if it doesn't exist.
                    localKey: nil,
                    tx: tx,
                )

                return .more

            },
            concludeTx: { tx, txContext in
                if txContext.didFinish {
                    localFileBackupStore.clearLastEnumeratedAttachmentRowId(tx: tx)
                } else if let lastEnumeratedAttachmentId = txContext.lastEnumeratedAttachmentId {
                    localFileBackupStore.updateLastEnumeratedAttachmentRowId(lastEnumeratedAttachmentId, tx: tx)
                }
            },
        )
    }

    /// - Parameter localBackupURL
    /// The location chosen by the user to store the top level SignalBackups file.
    func copyBackupToDisk(
        backupTempFileURL: URL,
        messageRootBackupKey: MessageRootBackupKey,
        localBackupURL: URL,
    ) async throws -> (URL, String) {
        let metadataProtoData = try buildMetadataProto(messageRootBackupKey: messageRootBackupKey).serializedData()

        try makeInitialDirectoryStructureIfNeeded(at: localBackupURL)

        let backupsRootDirectory = localBackupURL.appendingPathComponent(LocalFileBackupManager.FileStructure.rootDirectory.rawValue)

        let fileCoordinator = NSFileCoordinator()
        let currentBackupDirectoryName = FileStructure.backupDirectory(date: dateProvider())
        try fileCoordinator.coordinateThrows(writingItemAt: backupsRootDirectory, options: [], by: { writeURL in
            let currentBackupDirectory = writeURL
                .appendingPathComponent(currentBackupDirectoryName)
            let backupFileURL = currentBackupDirectory.appendingPathComponent(LocalFileBackupManager.FileStructure.backupFile.rawValue)
            let metadataFileURL = currentBackupDirectory.appendingPathComponent(LocalFileBackupManager.FileStructure.metadataFile.rawValue)

            try FileManager.default.createDirectory(
                at: currentBackupDirectory,
                withIntermediateDirectories: true,
                attributes: nil,
            )

            try FileManager.default.copyItem(at: backupTempFileURL, to: backupFileURL)

            try metadataProtoData.write(to: metadataFileURL)
        })

        return (backupsRootDirectory, currentBackupDirectoryName)
    }

    private func makeInitialDirectoryStructureIfNeeded(at url: URL) throws {
        let fileCoordinator = NSFileCoordinator()

        let outerDirectoryName = FileStructure.rootDirectory.rawValue
        let outerDirectoryURL = url.appendingPathComponent(outerDirectoryName, isDirectory: true)

        try fileCoordinator.coordinateThrows(writingItemAt: outerDirectoryURL, options: [], by: { writeURL in
            try FileManager.default.createDirectory(
                at: writeURL,
                withIntermediateDirectories: true,
                attributes: nil,
            )

            let filesDirectoryURL = writeURL.appendingPathComponent(FileStructure.attachmentDirectory.rawValue, isDirectory: true)
            try FileManager.default.createDirectory(
                at: filesDirectoryURL,
                withIntermediateDirectories: true,
                attributes: nil,
            )
        })
    }

    /// - Parameter backupsRootDirectory
    /// The SignalBackups directory.
    func cleanUpOldBackupsAndOrphanedAttachments(backupsRootDirectory: URL) async throws {
        let fileCoordinator = NSFileCoordinator()

        try fileCoordinator.coordinateThrows(writingItemAt: backupsRootDirectory, options: [.forDeleting], by: { writeURL in
            let attachmentDirectory = writeURL.appendingPathComponent(FileStructure.attachmentDirectory.rawValue)

            let contents = try FileManager.default.contentsOfDirectory(
                at: writeURL,
                includingPropertiesForKeys: [.isDirectoryKey],
            )

            var sortedBackupDirectories = contents
                .filter { $0.lastPathComponent.hasPrefix("signal-backups-") }
                .sorted { $0.lastPathComponent > $1.lastPathComponent }

            var directoriesToPrune: [URL] = []
            while sortedBackupDirectories.count > Self.maxAllowedNumberOfBackups {
                directoriesToPrune += [sortedBackupDirectories.removeLast()]
            }
            for url in directoriesToPrune {
                try FileManager.default.removeItem(at: url)
            }

            var attachmentMediaNames: Set<String> = []
            for backupDirectory in sortedBackupDirectories {

                let filesMetadataURL = backupDirectory.appendingPathComponent(FileStructure.attachmentDirectory.rawValue)

                guard let rawInputStream = InputStream(url: filesMetadataURL) else {
                    throw OWSAssertionError("Unable to open filestream")
                }
                rawInputStream.open()
                defer { rawInputStream.close() }

                let inputStream = TransformingInputStream(
                    transforms: [ChunkedInputStreamTransform()],
                    inputStream: rawInputStream,
                )

                while inputStream.hasBytesAvailable {
                    let data = try inputStream.read(maxLength: 65_536)
                    if data.isEmpty { break }
                    let frame = try LocalBackupProto_FilesFrame(serializedBytes: data)
                    switch frame.item {
                    case .mediaName(let mediaName):
                        attachmentMediaNames.insert(mediaName)
                    case nil:
                        owsFailDebug("Unexpectedly missing mediaName from local file backup attachment frame")
                    }
                }
            }
            guard
                let enumerator = FileManager.default.enumerator(
                    at: attachmentDirectory,
                    includingPropertiesForKeys: [.nameKey],
                    options: [],
                )
            else {
                return
            }
            while let fileURL = enumerator.nextObject() as? URL {
                let fileValues = try fileURL.resourceValues(forKeys: [.nameKey, .isDirectoryKey])
                if let isDir = fileValues.isDirectory, isDir {
                    continue
                }
                if let name = fileValues.name {
                    if !attachmentMediaNames.contains(name) {
                        try FileManager.default.removeItem(at: fileURL)
                        let parentDirectory = fileURL.deletingLastPathComponent()
                        if try FileManager.default.contentsOfDirectory(atPath: parentDirectory.path).isEmpty {
                            try FileManager.default.removeItem(at: parentDirectory)
                        }
                    }
                } else {
                    owsFailDebug("Unexpectedly missing name from resource keys!")
                }
            }
        })
    }

    // MARK: - Choosing backup location

    public func promptUserToChooseFileLocation(fromViewController: UIViewController) {
        let pickerController = UIDocumentPickerViewController(
            forOpeningContentTypes: [.folder],
            asCopy: false,
        )
        pickerController.delegate = self

        fromViewController.present(pickerController, animated: true)
    }

    public func getSavedSecurityScopedBookmark() throws -> URL? {
        guard let bookmarkData = db.read(block: { tx in localFileBackupStore.fetchBookmarkData(tx: tx) }) else {
            return nil
        }

        var resolvedURL: URL
        var isStale = false
        do {
            resolvedURL = try securityScopedBookmarkAccess.urlForBookmarkData(bookmarkData, isStale: &isStale)
        } catch NSFileProviderError.noSuchItem {
            throw LocalFileBackupError.unableToAccessLocalFile(.missing)
        } catch {
            throw OWSAssertionError("Unable to resolve bookmark data: \(error)")
        }

        if isStale {
            throw LocalFileBackupError.unableToAccessLocalFile(.stale)
        }

        return resolvedURL
    }

    public func saveSecurityScopedBookmark(url: URL) throws {
        let bookmarkData = try securityScopedBookmarkAccess.bookmarkDataForURL(url)
        db.write { tx in
            localFileBackupStore.storeBookmarkData(bookmarkData: bookmarkData, tx: tx)
        }
    }

    // MARK: - UIDocumentPickerDelegate

    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentAt url: URL) {
        // The bookmark data has to be written when we have access to the security scoped resource.
        guard securityScopedBookmarkAccess.startAccessToSecurityScopedBookmark(url: url) else {
            Logger.error("Failed to start security scoped access")
            return
        }

        defer { securityScopedBookmarkAccess.stopAccessToSecurityScopedBookmark(url: url) }

        do {
            try saveSecurityScopedBookmark(url: url)
        } catch {
            // TODO: [KC] show error screen.
            logger.error("Failed to save bookmark: \(error)")
        }
    }

    // MARK: - Prompt user to enable local backups, e.g. after restoring

    public nonisolated func shouldPromptUserToEnableLocalBackups(tx: DBReadTransaction) -> Bool {
        localFileBackupStore.shouldPromptUserToEnableLocalBackups(tx: tx)
    }

    public nonisolated func clearShouldPromptUserToEnableLocalBackups(tx: DBWriteTransaction) {
        localFileBackupStore.clearShouldPromptUserToEnableLocalBackups(tx: tx)
    }

    public nonisolated func setShouldPromptUserToEnableLocalBackups(tx: DBWriteTransaction) {
        localFileBackupStore.setShouldPromptUserToEnableLocalBackups(tx: tx)
    }

    // MARK: - Prompt user to choose new local backup location, e.g. if there was an error archiving

    public nonisolated func shouldPromptUserToChooseNewLocalBackupLocation(tx: DBReadTransaction) -> Bool {
        localFileBackupStore.shouldPromptUserToChooseNewLocalBackupLocation(tx: tx)
    }

    public nonisolated func clearChooseNewLocalBackupLocation(tx: DBWriteTransaction) {
        localFileBackupStore.clearChooseNewLocalBackupLocation(tx: tx)
    }

    public nonisolated func setChooseNewLocalBackupLocation(tx: DBWriteTransaction) {
        localFileBackupStore.setChooseNewLocalBackupLocation(tx: tx)
    }
}
