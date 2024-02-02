//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol UploadManager {

    /// Upload a TSAttachment to the given endpoint.
    /// - Parameters:
    ///   - param attachmentId: The id of the TSAttachmentStream to upload
    ///   - param messageIds: A list of TSInteractions representing the message or
    ///   album this attachment is associated with
    ///   - param version: The upload endpoint to use for creating an upload form
    func uploadAttachment(attachmentId: String, messageIds: [String], version: Upload.FormVersion) async throws
}

public actor UploadManagerImpl: UploadManager {

    private let db: DB
    private let attachmentStore: AttachmentStore
    private let interactionStore: InteractionStore
    private let networkManager: NetworkManager
    private let socketManager: SocketManager
    private let signalService: OWSSignalServiceProtocol
    private let attachmentEncrypter: Upload.Shims.AttachmentEncrypter
    private let blurHash: Upload.Shims.BlurHash
    private let fileSystem: Upload.Shims.FileSystem

    public init(
        db: DB,
        attachmentStore: AttachmentStore,
        interactionStore: InteractionStore,
        networkManager: NetworkManager,
        socketManager: SocketManager,
        signalService: OWSSignalServiceProtocol,
        attachmentEncrypter: Upload.Shims.AttachmentEncrypter,
        blurHash: Upload.Shims.BlurHash,
        fileSystem: Upload.Shims.FileSystem
    ) {
        self.db = db
        self.attachmentStore = attachmentStore
        self.interactionStore = interactionStore
        self.networkManager = networkManager
        self.socketManager = socketManager
        self.signalService = signalService
        self.attachmentEncrypter = attachmentEncrypter
        self.blurHash = blurHash
        self.fileSystem = fileSystem
    }

    /// Entry point for uploading a `TSAttachmentStream`
    /// Fetches the `TSAttachmentStream`, builds the AttachmentUpload, begins the
    /// upload, and updates the `TSAttachmentStream` upon success.
    ///
    /// It is assumed any errors that could be retried or otherwise handled will have happend at a lower level,
    /// so any error encountered here is considered unrecoverable and thrown to the caller.
    public func uploadAttachment(attachmentId: String, messageIds: [String], version: Upload.FormVersion) async throws {
        let logger = PrefixedLogger(prefix: "[Upload]", suffix: "[\(attachmentId)]")

        let attachmentStream = try db.read(block: { tx in
            try fetchAttachmentStream(attachmentId: attachmentId, logger: logger, tx: tx)
        })
        guard attachmentRequiresUpload(attachmentStream) else {
            logger.debug("Attachment previously uploaded.")
            return
        }
        guard let sourceURL = attachmentStream.originalMediaURL else {
            logger.debug("Attachment missing source URL.")
            throw OWSUnretryableError()
        }

        do {
            try await blurHash.ensureBlurHash(attachmentStream: attachmentStream)
        } catch {
            // Swallow these errors; blurHashes are strictly optional.
            logger.warn("Error generating blurHash.")
        }

        do {
            let upload = AttachmentUpload(
                db: db,
                signalService: signalService,
                networkManager: networkManager,
                socketManager: socketManager,
                attachmentEncrypter: attachmentEncrypter,
                fileSystem: fileSystem,
                sourceURL: sourceURL,
                version: version,
                logger: logger
            )

            let result = try await upload.start {
                self.updateProgress(id: attachmentId, progress: $0.fractionCompleted)
            }

            // Update the attachment and associated messages with the success
            try await update(
                attachmentId: attachmentId,
                messageIds: messageIds,
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
        attachmentId: String,
        logger: PrefixedLogger,
        tx: DBReadTransaction
    ) throws -> TSAttachmentStream {
        guard
            let attachmentStream = attachmentStore.fetchAttachmentStream(uniqueId: attachmentId, tx: tx)
        else {
            logger.warn("Missing attachment.")
            // Not finding a local attachment is a terminal failure.
            throw OWSUnretryableError()
        }
        return attachmentStream
    }

    // Update all the necessary places once the upload succeeds
    private func update(
        attachmentId: String,
        messageIds: [String],
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

            self.attachmentStore.updateAsUploaded(
                attachmentStream: attachmentStream,
                encryptionKey: result.localUploadMetadata.key,
                digest: result.localUploadMetadata.digest,
                cdnKey: result.cdnKey,
                cdnNumber: result.cdnNumber,
                uploadTimestamp: result.beginTimestamp,
                tx: tx
            )

            messageIds.forEach { messageId in
                guard let interaction = self.interactionStore.fetchInteraction(uniqueId: messageId, tx: tx) else {
                    logger.warn("Missing interaction.")
                    return
                }

                self.db.touch(interaction, shouldReindex: false, tx: tx)
            }
        }
    }

    private func attachmentRequiresUpload(_ attachmentStream: TSAttachmentStream) -> Bool {
        return !attachmentStream.isUploaded
    }

    private func updateProgress(id: String, progress: Double) {
        NotificationCenter.default.postNotificationNameAsync(
            Upload.Constants.uploadProgressNotification,
            object: nil,
            userInfo: [
                Upload.Constants.uploadProgressKey: progress,
                Upload.Constants.uploadAttachmentIDKey: id
            ]
        )
    }
}
