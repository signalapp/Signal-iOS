//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol AttachmentUploadManager {
    /// Upload a transient backup file that isn't an attachment (not saved to the database or sent).
    func uploadBackup(localUploadMetadata: Upload.EncryptedBackupUploadMetadata, form: Upload.Form) async throws -> Upload.Result<Upload.EncryptedBackupUploadMetadata>

    /// Upload a transient attachment that isn't saved to the database for sending.
    func uploadTransientAttachment(dataSource: DataSource) async throws -> Upload.Result<Upload.LocalUploadMetadata>

    /// Upload an Attachment to the given endpoint.
    /// Will fail if the attachment doesn't exist or isn't available locally.
    func uploadAttachment(attachmentId: Attachment.IDType) async throws
}

public actor AttachmentUploadManagerImpl: AttachmentUploadManager {

    private let attachmentEncrypter: Upload.Shims.AttachmentEncrypter
    private let attachmentStore: AttachmentUploadStore
    private let chatConnectionManager: ChatConnectionManager
    private let dateProvider: DateProvider
    private let db: DB
    private let fileSystem: Upload.Shims.FileSystem
    private let interactionStore: InteractionStore
    private let networkManager: NetworkManager
    private let signalService: OWSSignalServiceProtocol
    private let storyStore: StoryStore

    // Map of active upload tasks.
    private var activeUploads = [Attachment.IDType: Task<Void, Error>]()

    public init(
        attachmentEncrypter: Upload.Shims.AttachmentEncrypter,
        attachmentStore: AttachmentUploadStore,
        chatConnectionManager: ChatConnectionManager,
        dateProvider: @escaping DateProvider,
        db: DB,
        fileSystem: Upload.Shims.FileSystem,
        interactionStore: InteractionStore,
        networkManager: NetworkManager,
        signalService: OWSSignalServiceProtocol,
        storyStore: StoryStore
    ) {
        self.attachmentEncrypter = attachmentEncrypter
        self.attachmentStore = attachmentStore
        self.chatConnectionManager = chatConnectionManager
        self.dateProvider = dateProvider
        self.db = db
        self.fileSystem = fileSystem
        self.interactionStore = interactionStore
        self.networkManager = networkManager
        self.signalService = signalService
        self.storyStore = storyStore
    }

    public func uploadBackup(localUploadMetadata: Upload.EncryptedBackupUploadMetadata, form: Upload.Form) async throws -> Upload.Result<Upload.EncryptedBackupUploadMetadata> {
        let logger = PrefixedLogger(prefix: "[Upload]", suffix: "[backup]")
        do {
            let attempt = try await AttachmentUpload.buildAttempt(
                for: localUploadMetadata,
                form: form,
                signalService: signalService,
                fileSystem: fileSystem,
                logger: logger
            )
            return try await AttachmentUpload.start(attempt: attempt, progress: nil)
        } catch {
            if error.isNetworkFailureOrTimeout {
                logger.warn("Upload failed due to network error")
            } else if error is CancellationError {
                logger.warn("Upload cancelled")
            } else {
                if let statusCode = error.httpStatusCode {
                    logger.warn("Unexpected upload error [status: \(statusCode)]")
                } else {
                    logger.warn("Unexpected upload error")
                }
            }
            throw error
        }
    }

    public func uploadTransientAttachment(dataSource: DataSource) async throws -> Upload.Result<Upload.LocalUploadMetadata> {
        let logger = PrefixedLogger(prefix: "[Upload]", suffix: "[transient]")

        let temporaryFile = fileSystem.temporaryFileUrl()
        guard let sourceURL = dataSource.dataUrl else {
            throw OWSAssertionError("Failed to access data source file")
        }
        let metadata = try attachmentEncrypter.encryptAttachment(at: sourceURL, output: temporaryFile)
        let localMetadata = try Upload.LocalUploadMetadata.validateAndBuild(fileUrl: temporaryFile, metadata: metadata)
        let form = try await Upload.FormRequest(
            signalService: signalService,
            networkManager: networkManager,
            chatConnectionManager: chatConnectionManager
        ).start()

        do {
            // We don't show progress for transient uploads
            let attempt = try await AttachmentUpload.buildAttempt(
                for: localMetadata,
                form: form,
                signalService: signalService,
                fileSystem: fileSystem,
                logger: logger
            )
            return try await AttachmentUpload.start(attempt: attempt, progress: nil)
        } catch {
            if error.isNetworkFailureOrTimeout {
                logger.warn("Upload failed due to network error")
            } else if error is CancellationError {
                logger.warn("Upload cancelled")
            } else {
                if let statusCode = error.httpStatusCode {
                    logger.warn("Unexpected upload error [status: \(statusCode)]")
                } else {
                    logger.warn("Unexpected upload error")
                }
            }
            throw error
        }
    }

    /// Entry point for uploading an `AttachmentStream`
    /// Fetches the `AttachmentStream`, fetches an upload form, builds the AttachmentUpload, begins the
    /// upload, and updates the `AttachmentStream` upon success.
    ///
    /// It is assumed any errors that could be retried or otherwise handled will have happend at a lower level,
    /// so any error encountered here is considered unrecoverable and thrown to the caller.
    ///
    /// Resumption of an active upload can be handled at a lower level, but if the endpoint returns an
    /// error that requires a full restart, this is the method that will be called to fetch a new upload form and
    /// rebuild the endpoint and upload state before trying again.
    public func uploadAttachment(attachmentId: Attachment.IDType) async throws {
        let logger = PrefixedLogger(prefix: "[Upload]", suffix: "[\(attachmentId)]")

        if let activeUpload = activeUploads[attachmentId] {
            // If this fails, it means the internal retry logic has given up, so don't 
            // attempt any retries here
            do {
                return try await activeUpload.value
            } catch {
                return try await uploadAttachment(attachmentId: attachmentId)
            }
        }

        let attachment = try db.read(block: { tx in
            try fetchAttachment(attachmentId: attachmentId, logger: logger, tx: tx)
        })

        let uploadTask = Task {
            defer {
                // Clear out the active upload task once it finishes running.
                activeUploads[attachmentId] = nil
            }

            // This task will only fail if a non-recoverable error is encountered, or the
            // max number of retries is exhausted.
            try await self.upload(attachment: attachment, sourceType: .transit, logger: logger)
        }

        // Add the active task to allow any additional uploads to ta
        activeUploads[attachmentId] = uploadTask
        return try await uploadTask.value
    }

    private func upload(
        attachment: Attachment,
        sourceType: AttachmentUploadRecord.SourceType,
        logger: PrefixedLogger
    ) async throws {
        let attachmentId = attachment.id
        var updateRecord = false
        var cleanupMetadata = false

        // Fetch the record if it exists, or create a new one.
        // Note this record isn't persisted in this method, so it will need to be saved later.
        var attachmentUploadRecord = try self.fetchOrCreateAttachmentRecord(
            for: attachmentId,
            sourceType: sourceType,
            db: db
        )

        // Fetch or build the LocalUploadMetadata.
        // See `Attachment.transitUploadStrategy(dateProvider:)` for details on when metadata
        // is reused vs. constructed new.
        let localMetadata: Upload.LocalUploadMetadata
        switch try getOrFetchUploadMetadata(
            attachment: attachment,
            record: attachmentUploadRecord,
            logger: logger
        ) {
        case .existing(let metadata), .reuse(let metadata):
            // Cached metadata is still good to use
            localMetadata = metadata
        case .new(let metadata):
            localMetadata = metadata
            updateRecord = true
            cleanupMetadata = true

            // New metadata was constructed, so clear out the stale upload form.
            attachmentUploadRecord.localMetadata = metadata
            attachmentUploadRecord.uploadForm = nil
            attachmentUploadRecord.uploadFormTimestamp = nil
            attachmentUploadRecord.uploadSessionUrl = nil
        case .alreadyUploaded:
            // No need to upload - Cleanup the upload record and return
            await db.awaitableWrite { tx in
                self.cleanup(record: attachmentUploadRecord, logger: logger, tx: tx)
            }
            return
        }

        let uploadForm: Upload.Form
        switch try await getOrFetchUploadForm(record: attachmentUploadRecord) {
        case .existing(let form):
            uploadForm = form
        case .new(let form):
            updateRecord = true
            uploadForm = form

            attachmentUploadRecord.uploadForm = form
            attachmentUploadRecord.uploadFormTimestamp = Date().ows_millisecondsSince1970
            attachmentUploadRecord.uploadSessionUrl = nil
        }

        do {
            let attempt = try await AttachmentUpload.buildAttempt(
                for: localMetadata,
                form: uploadForm,
                existingSessionUrl: attachmentUploadRecord.uploadSessionUrl,
                signalService: self.signalService,
                fileSystem: self.fileSystem,
                logger: logger
            )

            // The upload record has modified the metadata, upload form,
            // or upload session URL, so persist it before beginning the upload.
            if updateRecord || attachmentUploadRecord.uploadSessionUrl == nil {
                try await db.awaitableWrite { tx in
                    attachmentUploadRecord.uploadSessionUrl = attempt.uploadLocation
                    try self.attachmentStore.upsert(record: attachmentUploadRecord, tx: tx)
                }
            }

            let result = try await AttachmentUpload.start(attempt: attempt) {
                self.updateProgress(id: attachmentId, progress: $0.fractionCompleted)
            }

            // Update the attachment and associated messages with the success
            // and clean up and left over upload state
            try await update(
                record: attachmentUploadRecord,
                with: result,
                logger: logger
            )

            // On success, cleanup the temp file.  Temp files are only created for
            // new local metadata, otherwise the existing attachment file location is used.
            // TODO: Tie this in with OrphanedAttachmentRecord to track this
            if cleanupMetadata {
                do {
                    try fileSystem.deleteFile(url: localMetadata.fileUrl)
                } catch {
                    owsFailDebug("Error: \(error)")
                }
            }
        } catch {

            // If the max number of upload failures was hit, give up and throw an error
            if attachmentUploadRecord.attempt >= Upload.Constants.maxUploadAttempts {
                await db.awaitableWrite { tx in
                    self.cleanup(record: attachmentUploadRecord, logger: logger, tx: tx)
                }
                throw error
            }

            // Anything besides 'restart' should be handled below this method,
            // or is an unhandled error that should be thrown to the caller
            if case Upload.Error.uploadFailure(let recoveryMode) = error {
                switch recoveryMode {
                case .noMoreRetries:
                    break
                case .resume(let backOff):
                    owsFailDebug("Received unexptected error during upload")
                    fallthrough
                case .restart(let backOff):
                    switch backOff {
                    case .immediately:
                        break
                    case .afterDelay(let delay):
                        try await Upload.sleep(for: delay)
                    }
                }

                // Only bump the attempt count if the upload failed.  Don't bump for things
                // like network issues
                attachmentUploadRecord.attempt += 1

                // If the error has made it here, something was encountered during upload that requires
                // a full restart of the upload.
                // This means at least throwing away the upload form, and just to be sure,
                // throw away the local metadata as well.
                attachmentUploadRecord.localMetadata = nil
                attachmentUploadRecord.uploadForm = nil
                attachmentUploadRecord.uploadSessionUrl = nil

                try await db.awaitableWrite { tx in
                    try self.attachmentStore.upsert(record: attachmentUploadRecord, tx: tx)
                }
                return try await upload(attachment: attachment, sourceType: sourceType, logger: logger)
            } else {
                // Some other non-upload error was encountered - exit from the upload for now.
                // Network failures or task cancellation shouldn't bump the attempt count, but
                // any other error type should
                if error.isNetworkFailureOrTimeout {
                    logger.warn("Upload failed due to network error")
                } else if error is CancellationError {
                    logger.warn("Upload cancelled")
                } else {
                    attachmentUploadRecord.attempt += 1
                    try await db.awaitableWrite { tx in
                        try self.attachmentStore.upsert(record: attachmentUploadRecord, tx: tx)
                    }
                    if let statusCode = error.httpStatusCode {
                        logger.warn("Unexpected upload error [status: \(statusCode)]")
                    } else {
                        logger.warn("Unexpected upload error")
                    }
                    throw error
                }
            }
        }
    }

    // MARK: - Helpers

    private func fetchOrCreateAttachmentRecord(
        for attachmentId: Attachment.IDType,
        sourceType: AttachmentUploadRecord.SourceType,
        db: DB
    ) throws -> AttachmentUploadRecord {
        var attachmentUploadRecord: AttachmentUploadRecord
        if let record = try db.read(block: { tx in
            try self.attachmentStore.fetchAttachmentUploadRecord(for: attachmentId, sourceType: sourceType, tx: tx)
        }) {
            attachmentUploadRecord = record
        } else {
            attachmentUploadRecord = AttachmentUploadRecord(sourceType: .transit, attachmentId: attachmentId)
        }
        return attachmentUploadRecord
    }

    private enum MetadataResult {
        case new(Upload.LocalUploadMetadata)
        case existing(Upload.LocalUploadMetadata)
        case reuse(Upload.LocalUploadMetadata)
        case alreadyUploaded
    }

    private func getOrFetchUploadMetadata(
        attachment: Attachment,
        record: AttachmentUploadRecord,
        logger: PrefixedLogger
    ) throws -> MetadataResult {
        switch attachment.transitUploadStrategy(dateProvider: dateProvider) {
        case .cannotUpload:
            logger.warn("Attachment is not uploadable.")
            // Can't upload non-stream attachments; terminal failure.
            throw OWSUnretryableError()
        case .reuseExistingUpload:
            logger.debug("Attachment previously uploaded.")
            return .alreadyUploaded
        case .reuseStreamEncryption(let metadata):
            return .reuse(metadata)
        case .freshUpload(let stream):
            // Attempting to upload an existing attachment that's older than 3 days requires
            // the attachment to be re-encrypted before upload.
            // If this exists in the upload record from a prior attempt, use 
            // that file if it still exists.
            if
                let metadata = record.localMetadata,
                // TODO: 
                // Currently, the file url is in a temp directory and doesn't
                // persist across launches, so this will never be hit. The fix for this
                // is to store the temporary file in a more persistent location, and
                // register the file with the OrphanedAttachmentCleaner
                OWSFileSystem.fileOrFolderExists(url: metadata.fileUrl)
            {
                return .existing(metadata)
            } else {
                let metadata = try buildMetadata(forUploading: stream)
                return .new(metadata)
            }
        }
    }

    private enum FormResult {
        case new(Upload.Form)
        case existing(Upload.Form)
    }

    /// Check for a cached upload form
    /// This can be up to ~7 days old from the point of upload starting. Just to avoid running into any fuzzieness around the 7 day expiration, expire the form after 6 days
    /// If the upload hasn't started, the form shouldnt' be cached
    private func getOrFetchUploadForm(
        record: AttachmentUploadRecord
    ) async throws -> FormResult {
        if
            let form = record.uploadForm,
            let formTimestamp = record.uploadFormTimestamp,
            // And we are still in the window to reuse it
            dateProvider().timeIntervalSince(
                Date(millisecondsSince1970: formTimestamp)
            ) <= Upload.Constants.uploadFormReuseWindow
        {
            return .existing(form)
        }
        let form = try await Upload.FormRequest(
            signalService: signalService,
            networkManager: networkManager,
            chatConnectionManager: chatConnectionManager
        ).start()
        return .new(form)
    }

    private func fetchAttachment(
        attachmentId: Attachment.IDType,
        logger: PrefixedLogger,
        tx: DBReadTransaction
    ) throws -> Attachment {
        guard let attachment = attachmentStore.fetch(id: attachmentId, tx: tx) else {
            logger.warn("Missing attachment.")
            // Not finding a local attachment is a terminal failure.
            throw OWSUnretryableError()
        }
        return attachment
    }

    private func cleanup(record: AttachmentUploadRecord, logger: PrefixedLogger, tx: DBWriteTransaction) {
        do {
            try self.attachmentStore.removeRecord(for: record.attachmentId, sourceType: record.sourceType, tx: tx)
        } catch {
            logger.warn("Failed to clean existing upload record for (\(record.attachmentId))")
        }
    }

    // Update all the necessary places once the upload succeeds
    private func update(
        record: AttachmentUploadRecord,
        with result: Upload.Result<Upload.LocalUploadMetadata>,
        logger: PrefixedLogger
    ) async throws {
        try await db.awaitableWrite { tx in

            // Read the attachment fresh from the DB
            guard let attachmentStream = try? self.fetchAttachment(
                attachmentId: record.attachmentId,
                logger: logger,
                tx: tx
            ).asStream() else {
                logger.warn("Attachment deleted while uploading")
                return
            }

            let transitTierInfo = Attachment.TransitTierInfo(
                cdnNumber: result.cdnNumber,
                cdnKey: result.cdnKey,
                uploadTimestamp: result.beginTimestamp,
                encryptionKey: result.localUploadMetadata.key,
                unencryptedByteCount: result.localUploadMetadata.plaintextDataLength,
                digestSHA256Ciphertext: result.localUploadMetadata.digest,
                lastDownloadAttemptTimestamp: nil
            )

            try self.attachmentStore.markUploadedToTransitTier(
                attachmentStream: attachmentStream,
                info: transitTierInfo,
                tx: tx
            )

            do {
                try self.attachmentStore.enumerateAllReferences(
                    toAttachmentId: record.attachmentId,
                    tx: tx
                ) { attachmentReference in
                    switch attachmentReference.owner {
                    case .message(let messageSource):
                        guard
                            let interaction = self.interactionStore.fetchInteraction(
                                rowId: messageSource.messageRowId,
                                tx: tx
                            )
                        else {
                            logger.warn("Missing interaction.")
                            return
                        }
                        self.db.touch(interaction, shouldReindex: false, tx: tx)
                    case .storyMessage(let storyMessageSource):
                        guard
                            let storyMessage = self.storyStore.fetchStoryMessage(
                                rowId: storyMessageSource.storyMsessageRowId,
                                tx: tx
                            )
                        else {
                            logger.warn("Missing story message.")
                            return
                        }
                        self.db.touch(storyMessage, tx: tx)
                    case .thread:
                        break
                    }
                }
            } catch {
                Logger.error("Failed to enumerate references: \(error)")
            }

            self.cleanup(record: record, logger: logger, tx: tx)
        }
    }

    func buildMetadata(forUploading attachmentStream: AttachmentStream) throws -> Upload.LocalUploadMetadata {
        // First we need to decrypt, so we can re-encrypt for upload.
        let tmpDecryptedFile = fileSystem.temporaryFileUrl()
        let decryptionMedatata = EncryptionMetadata(
            key: attachmentStream.attachment.encryptionKey,
            digest: attachmentStream.info.digestSHA256Ciphertext,
            length: Int(clamping: attachmentStream.info.encryptedByteCount),
            plaintextLength: Int(clamping: attachmentStream.info.unencryptedByteCount)
        )
        try attachmentEncrypter.decryptAttachment(at: attachmentStream.fileURL, metadata: decryptionMedatata, output: tmpDecryptedFile)

        // Now re-encrypt with a fresh set of keys.
        // We use a tmp file on purpose; we already have the source file for the attachment
        // and don't need to keep around this copy encrypted with different keys; its useful
        // for upload only and can cleaned up by the OS after.
        let tmpReencryptedFile = fileSystem.temporaryFileUrl()
        let reencryptedMetadata = try attachmentEncrypter.encryptAttachment(at: tmpDecryptedFile, output: tmpReencryptedFile)

        // we upload the re-encrypted file.
        return try .validateAndBuild(fileUrl: tmpReencryptedFile, metadata: reencryptedMetadata)
    }

    private func updateProgress(id: Attachment.IDType, progress: Double) {
        NotificationCenter.default.postNotificationNameAsync(
            Upload.Constants.attachmentUploadProgressNotification,
            object: nil,
            userInfo: [
                Upload.Constants.uploadProgressKey: progress,
                Upload.Constants.uploadAttachmentIDKey: id
            ]
        )
    }
}
