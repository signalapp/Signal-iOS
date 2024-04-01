//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol AttachmentUploadManager {

    /// Upload a transient attachment that isn't saved to the database for sending.
    func uploadTransientAttachment(dataSource: DataSource) async throws -> Upload.Result

    /// Upload an Attachment to the given endpoint.
    /// Will fail if the attachment doesn't exist or isn't available locally.
    func uploadAttachment(attachmentId: Attachment.IDType) async throws
}

public actor AttachmentUploadManagerImpl: AttachmentUploadManager {

    private let attachmentEncrypter: Upload.Shims.AttachmentEncrypter
    private let attachmentStore: AttachmentUploadStore
    private let chatConnectionManager: ChatConnectionManager
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
        self.db = db
        self.fileSystem = fileSystem
        self.interactionStore = interactionStore
        self.networkManager = networkManager
        self.signalService = signalService
        self.storyStore = storyStore
    }

    public func uploadTransientAttachment(dataSource: DataSource) async throws -> Upload.Result {
        let logger = PrefixedLogger(prefix: "[Upload]", suffix: "[transient]")

        let uploadBuilder = TransientUploadBuilder(
            source: dataSource,
            attachmentEncrypter: attachmentEncrypter,
            fileSystem: fileSystem
        )

        do {
            let upload = AttachmentUpload(
                builder: uploadBuilder,
                signalService: signalService,
                networkManager: networkManager,
                chatConnectionManager: chatConnectionManager,
                fileSystem: fileSystem,
                logger: logger
            )

            // We don't show progress for transient uploads
            let result = try await upload.start(progress: nil)

            return result

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

        let attachmentStream = try db.read(block: { tx in
            try fetchAttachmentStream(attachmentId: attachmentId, logger: logger, tx: tx)
        })
        guard attachmentRequiresUpload(attachmentStream) else {
            logger.debug("Attachment previously uploaded.")
            return
        }
        let uploadBuilder = AttachmentUploadBuilder(attachmentStream: attachmentStream)

        do {
            let upload = AttachmentUpload(
                builder: uploadBuilder,
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

    private func fetchAttachmentStream(
        attachmentId: Attachment.IDType,
        logger: PrefixedLogger,
        tx: DBReadTransaction
    ) throws -> AttachmentStream {
        guard let attachment = attachmentStore.fetch(id: attachmentId, tx: tx) else {
            logger.warn("Missing attachment.")
            // Not finding a local attachment is a terminal failure.
            throw OWSUnretryableError()
        }
        guard let attachmentStream = attachment.asStream() else {
            logger.warn("Attachment is not a stream.")
            // Can't upload non-stream attachments; terminal failure.
            throw OWSUnretryableError()
        }
        return attachmentStream
    }

    // Update all the necessary places once the upload succeeds
    private func update(
        attachmentId: Attachment.IDType,
        with result: Upload.Result,
        logger: PrefixedLogger
    ) async throws {
        try await db.awaitableWrite { tx in

            // Read the attachment fresh from the DB
            let attachmentStream = try self.fetchAttachmentStream(
                attachmentId: attachmentId,
                logger: logger,
                tx: tx
            )

            self.attachmentStore.markUploadedToTransitTier(
                attachmentStream: attachmentStream,
                cdnKey: result.cdnKey,
                cdnNumber: result.cdnNumber,
                uploadTimestamp: result.beginTimestamp,
                tx: tx
            )

            self.attachmentStore.enumerateAllReferences(
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
        }
    }

    private func attachmentRequiresUpload(_ attachmentStream: AttachmentStream) -> Bool {
        return attachmentStream.transitUploadTimestamp == nil
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
