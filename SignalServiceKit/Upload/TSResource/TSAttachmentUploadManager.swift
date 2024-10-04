//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol TSAttachmentUploadManager {

    /// Upload a TSAttachment to the given endpoint.
    /// - Parameters:
    ///   - param attachmentId: The id of the TSAttachmentStream to upload
    ///   - param messageIds: A list of TSInteractions representing the message or
    ///   album this attachment is associated with
    func uploadAttachment(attachmentId: String, messageIds: [String]) async throws
}

public actor TSAttachmentUploadManagerImpl: TSAttachmentUploadManager {

    private let db: any DB
    private let interactionStore: InteractionStore
    private let networkManager: NetworkManager
    private let chatConnectionManager: ChatConnectionManager
    private let signalService: OWSSignalServiceProtocol
    private let attachmentEncrypter: Upload.Shims.AttachmentEncrypter
    private let blurHash: TSAttachmentUpload.Shims.BlurHash
    private let fileSystem: Upload.Shims.FileSystem
    private let tsResourceStore: TSResourceUploadStore

    public init(
        db: any DB,
        interactionStore: InteractionStore,
        networkManager: NetworkManager,
        chatConnectionManager: ChatConnectionManager,
        signalService: OWSSignalServiceProtocol,
        attachmentEncrypter: Upload.Shims.AttachmentEncrypter,
        blurHash: TSAttachmentUpload.Shims.BlurHash,
        fileSystem: Upload.Shims.FileSystem,
        tsResourceStore: TSResourceUploadStore
    ) {
        self.db = db
        self.interactionStore = interactionStore
        self.networkManager = networkManager
        self.chatConnectionManager = chatConnectionManager
        self.signalService = signalService
        self.attachmentEncrypter = attachmentEncrypter
        self.blurHash = blurHash
        self.fileSystem = fileSystem
        self.tsResourceStore = tsResourceStore
    }

    /// Entry point for uploading a `TSAttachmentStream`
    /// Fetches the `TSAttachmentStream`, builds the TSAttachmentUpload, begins the
    /// upload, and updates the `TSAttachmentStream` upon success.
    ///
    /// It is assumed any errors that could be retried or otherwise handled will have happend at a lower level,
    /// so any error encountered here is considered unrecoverable and thrown to the caller.
    public func uploadAttachment(attachmentId: String, messageIds: [String]) async throws {
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
            try await self.ensureBlurHash(for: attachmentStream)
        } catch {
            // Swallow these errors; blurHashes are strictly optional.
            logger.warn("Error generating blurHash.")
        }

        do {
            let upload = TSAttachmentUpload(
                db: db,
                signalService: signalService,
                networkManager: networkManager,
                chatConnectionManager: chatConnectionManager,
                attachmentEncrypter: attachmentEncrypter,
                fileSystem: fileSystem,
                sourceURL: sourceURL,
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

    private nonisolated func ensureBlurHash(for attachmentStream: TSAttachmentStream) async throws {
        guard attachmentStream.blurHash == nil else {
            // Attachment already has a blurHash.
            return
        }
        guard attachmentStream.isVisualMediaMimeType else {
            // We only generate a blurHash for visual media.
            return
        }
        guard blurHash.isValidVisualMedia(attachmentStream) else {
            throw OWSAssertionError("Invalid attachment.")
        }
        // Use the smallest available thumbnail; quality doesn't matter.
        // This is important for perf.
        guard let thumbnail: UIImage = blurHash.thumbnailImageSmallSync(attachmentStream) else {
            throw OWSAssertionError("Could not load small thumbnail.")
        }
        let blurHash = try self.blurHash.computeBlurHashSync(for: thumbnail)
        await self.db.awaitableWrite { tx in
            self.blurHash.update(attachmentStream, withBlurHash: blurHash, tx: tx)
        }
    }

    private func fetchAttachmentStream(
        attachmentId: String,
        logger: PrefixedLogger,
        tx: DBReadTransaction
    ) throws -> TSAttachmentStream {
        guard
            let attachment = tsResourceStore.fetch(.legacy(uniqueId: attachmentId), tx: tx)?.asResourceStream()
        else {
            logger.warn("Missing attachment.")
            // Not finding a local attachment is a terminal failure.
            throw OWSUnretryableError()
        }
        switch attachment.concreteStreamType {
        case .legacy(let tsAttachmentStream):
            return tsAttachmentStream
        case .v2:
            throw OWSUnretryableError()
        }
    }

    // Update all the necessary places once the upload succeeds
    private func update(
        attachmentId: String,
        messageIds: [String],
        with result: Upload.Result<Upload.LocalUploadMetadata>,
        logger: PrefixedLogger
    ) async throws {
        try await db.awaitableWrite { tx in

            // Read the attachment fresh from the DB
            let attachmentStream = try self.fetchAttachmentStream(
                attachmentId: attachmentId,
                logger: logger,
                tx: tx
            )

            let transitTierInfo = Attachment.TransitTierInfo(
                cdnNumber: result.cdnNumber,
                cdnKey: result.cdnKey,
                uploadTimestamp: result.beginTimestamp,
                encryptionKey: result.localUploadMetadata.key,
                unencryptedByteCount: result.localUploadMetadata.plaintextDataLength,
                digestSHA256Ciphertext: result.localUploadMetadata.digest,
                incrementalMacInfo: nil,
                lastDownloadAttemptTimestamp: nil
            )
            try self.tsResourceStore.updateAsUploaded(
                attachmentStream: attachmentStream,
                info: transitTierInfo,
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
            Upload.Constants.resourceUploadProgressNotification,
            object: nil,
            userInfo: [
                Upload.Constants.uploadProgressKey: progress,
                Upload.Constants.uploadResourceIDKey: TSResourceId.legacy(uniqueId: id)
            ]
        )
    }
}
