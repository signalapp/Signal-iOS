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
            let upload = AttachmentUpload(
                localMetadata: localUploadMetadata,
                formSource: .local(form),
                signalService: signalService,
                networkManager: networkManager,
                chatConnectionManager: chatConnectionManager,
                fileSystem: fileSystem,
                logger: logger
            )
            return try await upload.start(progress: nil)
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

        do {
            let upload = AttachmentUpload(
                localMetadata: localMetadata,
                formSource: .remote,
                signalService: signalService,
                networkManager: networkManager,
                chatConnectionManager: chatConnectionManager,
                fileSystem: fileSystem,
                logger: logger
            )

            // We don't show progress for transient uploads
            return try await upload.start(progress: nil)
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
    /// Fetches the `AttachmentStream`, builds the AttachmentUpload, begins the
    /// upload, and updates the `AttachmentStream` upon success.
    ///
    /// It is assumed any errors that could be retried or otherwise handled will have happend at a lower level,
    /// so any error encountered here is considered unrecoverable and thrown to the caller.
    public func uploadAttachment(attachmentId: Attachment.IDType) async throws {
        let logger = PrefixedLogger(prefix: "[Upload]", suffix: "[\(attachmentId)]")

        let attachment = try db.read(block: { tx in
            try fetchAttachment(attachmentId: attachmentId, logger: logger, tx: tx)
        })
        let localMetadata: Upload.LocalUploadMetadata
        switch attachment.transitUploadStrategy(dateProvider: dateProvider) {
        case .cannotUpload:
            logger.warn("Attachment is not uploadable.")
            // Can't upload non-stream attachments; terminal failure.
            throw OWSUnretryableError()
        case .reuseExistingUpload:
            logger.debug("Attachment previously uploaded.")
            return
        case .reuseStreamEncryption(let metadata):
            localMetadata = metadata
        case .freshUpload(let stream):
            localMetadata = try buildMetadata(forUploading: stream)
        }

        do {
            let upload = AttachmentUpload(
                localMetadata: localMetadata,
                formSource: .remote,
                signalService: signalService,
                networkManager: networkManager,
                chatConnectionManager: chatConnectionManager,
                fileSystem: fileSystem,
                logger: logger
            )

            let result = try await upload.start {
                self.updateProgress(id: attachmentId, progress: $0.fractionCompleted)
            }

            // Update the attachment and associated messages with the success
            try await update(
                attachmentId: attachmentId,
                with: result,
                logger: logger
            )

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

    // Update all the necessary places once the upload succeeds
    private func update(
        attachmentId: Attachment.IDType,
        with result: Upload.Result<Upload.LocalUploadMetadata>,
        logger: PrefixedLogger
    ) async throws {
        try await db.awaitableWrite { tx in

            // Read the attachment fresh from the DB
            guard let attachmentStream = try? self.fetchAttachment(
                attachmentId: attachmentId,
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
                    toAttachmentId: attachmentId,
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
