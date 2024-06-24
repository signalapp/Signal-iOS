//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class AttachmentDownloadManagerImpl: AttachmentDownloadManager {

    private let attachmentDownloadStore: AttachmentDownloadStore
    private let attachmentStore: AttachmentStore
    private let attachmentUpdater: AttachmentUpdater
    private let db: DB
    private let decrypter: Decrypter
    private let downloadQueue: DownloadQueue
    private let progressStates: ProgressStates
    private let queueLoader: PersistedQueueLoader

    public init(
        attachmentDownloadStore: AttachmentDownloadStore,
        attachmentStore: AttachmentStore,
        attachmentValidator: AttachmentContentValidator,
        dateProvider: @escaping DateProvider,
        db: DB,
        orphanedAttachmentCleaner: OrphanedAttachmentCleaner,
        orphanedAttachmentStore: OrphanedAttachmentStore,
        signalService: OWSSignalServiceProtocol
    ) {
        self.attachmentDownloadStore = attachmentDownloadStore
        self.attachmentStore = attachmentStore
        self.db = db
        self.decrypter = Decrypter(
            attachmentValidator: attachmentValidator
        )
        self.progressStates = ProgressStates()
        self.downloadQueue = DownloadQueue(
            progressStates: progressStates,
            signalService: signalService
        )
        self.attachmentUpdater = AttachmentUpdater(
            attachmentStore: attachmentStore,
            db: db,
            decrypter: decrypter,
            orphanedAttachmentCleaner: orphanedAttachmentCleaner,
            orphanedAttachmentStore: orphanedAttachmentStore
        )
        self.queueLoader = PersistedQueueLoader(
            attachmentDownloadStore: attachmentDownloadStore,
            attachmentStore: attachmentStore,
            attachmentUpdater: attachmentUpdater,
            dateProvider: dateProvider,
            db: db,
            decrypter: decrypter,
            downloadQueue: downloadQueue
        )
    }

    public func downloadBackup(metadata: MessageBackupRemoteInfo, authHeaders: [String: String]) -> Promise<URL> {
        let downloadState = DownloadState(type: .backup(metadata, authHeaders: authHeaders))
        return Promise.wrapAsync {
            let maxDownloadSize = MessageBackup.Constants.maxDownloadSizeBytes
            return try await self.downloadQueue.enqueueDownload(
                downloadState: downloadState,
                maxDownloadSizeBytes: maxDownloadSize
            )
        }
    }

    public func downloadTransientAttachment(metadata: AttachmentDownloads.DownloadMetadata) -> Promise<URL> {
        return Promise.wrapAsync {
            // We want to avoid large downloads from a compromised or buggy service.
            let maxDownloadSize = RemoteConfig.maxAttachmentDownloadSizeBytes
            let downloadState = DownloadState(type: .transientAttachment(metadata))

            let encryptedFileUrl = try await self.downloadQueue.enqueueDownload(
                downloadState: downloadState,
                maxDownloadSizeBytes: maxDownloadSize
            )
            return try await self.decrypter.decryptTransientAttachment(encryptedFileUrl: encryptedFileUrl, metadata: metadata)
        }
    }

    public func enqueueDownloadOfAttachmentsForMessage(
        _ message: TSMessage,
        priority: AttachmentDownloadPriority,
        tx: DBWriteTransaction
    ) {
        guard let messageRowId = message.sqliteRowId else {
            owsFailDebug("Downloading attachments for uninserted message!")
            return
        }
        let attachmentIds = attachmentStore
            .fetchReferences(
                owners: AttachmentReference.MessageOwnerTypeRaw.allCases.map {
                    $0.with(messageRowId: messageRowId)
                },
                tx: tx
            )
            .map(\.attachmentRowId)
        attachmentIds.forEach { attachmentId in
            try? attachmentDownloadStore.enqueueDownloadOfAttachment(
                withId: attachmentId,
                source: .transitTier,
                priority: priority,
                tx: tx
            )
        }
        tx.addAsyncCompletion(on: SyncScheduler()) { [weak self] in
            self?.beginDownloadingIfNecessary()
        }
    }

    public func enqueueDownloadOfAttachmentsForStoryMessage(
        _ message: StoryMessage,
        priority: AttachmentDownloadPriority,
        tx: DBWriteTransaction
    ) {
        guard let storyMessageRowId = message.id else {
            owsFailDebug("Downloading attachments for uninserted message!")
            return
        }
        let attachmentIds = attachmentStore
            .fetchReferences(
                owners: AttachmentReference.StoryMessageOwnerTypeRaw.allCases.map {
                    $0.with(storyMessageRowId: storyMessageRowId)
                },
                tx: tx
            )
            .map(\.attachmentRowId)
        attachmentIds.forEach { attachmentId in
            try? attachmentDownloadStore.enqueueDownloadOfAttachment(
                withId: attachmentId,
                source: .transitTier,
                priority: priority,
                tx: tx
            )
        }
        tx.addAsyncCompletion(on: SyncScheduler()) { [weak self] in
            self?.beginDownloadingIfNecessary()
        }
    }

    public func enqueueDownloadOfAttachment(
        id: Attachment.IDType,
        priority: AttachmentDownloadPriority,
        source: QueuedAttachmentDownloadRecord.SourceType,
        tx: DBWriteTransaction
    ) {
        try? attachmentDownloadStore.enqueueDownloadOfAttachment(
            withId: id,
            source: source,
            priority: priority,
            tx: tx
        )
        tx.addAsyncCompletion(on: SyncScheduler()) { [weak self] in
            self?.beginDownloadingIfNecessary()
        }
    }

    public func beginDownloadingIfNecessary() {
        Task { [weak self] in
            try await self?.queueLoader.loadFromQueueIfAble()
        }
    }

    public func cancelDownload(for attachmentId: Attachment.IDType, tx: DBWriteTransaction) {
        progressStates.cancelledAttachmentIds.insert(attachmentId)
        progressStates.states[attachmentId] = nil
        QueuedAttachmentDownloadRecord.SourceType.allCases.forEach { source in
            try? attachmentDownloadStore.removeAttachmentFromQueue(
                withId: attachmentId,
                source: source,
                tx: tx
            )
        }
    }

    public func downloadProgress(for attachmentId: Attachment.IDType, tx: DBReadTransaction) -> CGFloat? {
        return progressStates.states[attachmentId].map { CGFloat($0) }
    }

    // MARK: - Persisted Queue

    private actor PersistedQueueLoader {

        private let attachmentDownloadStore: AttachmentDownloadStore
        private let attachmentStore: AttachmentStore
        private let attachmentUpdater: AttachmentUpdater
        private let dateProvider: DateProvider
        private let db: DB
        private let decrypter: Decrypter
        private let downloadQueue: DownloadQueue

        init(
            attachmentDownloadStore: AttachmentDownloadStore,
            attachmentStore: AttachmentStore,
            attachmentUpdater: AttachmentUpdater,
            dateProvider: @escaping DateProvider,
            db: DB,
            decrypter: Decrypter,
            downloadQueue: DownloadQueue
        ) {
            self.attachmentDownloadStore = attachmentDownloadStore
            self.attachmentStore = attachmentStore
            self.attachmentUpdater = attachmentUpdater
            self.dateProvider = dateProvider
            self.db = db
            self.decrypter = decrypter
            self.downloadQueue = downloadQueue
        }

        private let maxConcurrentDownloads: UInt = 4
        private var currentRecordIds = Set<Int64>()

        /// Load the next N enqueued downloads, and begin downloading any
        /// that are not already downloading.
        /// (N = max concurrent downloads)
        func loadFromQueueIfAble() async throws {
            try Task.checkCancellation()

            if currentRecordIds.count >= maxConcurrentDownloads {
                return
            }

            let recordCandidates = try db.read { tx in
                try attachmentDownloadStore.peek(count: self.maxConcurrentDownloads, tx: tx)
            }

            let records = recordCandidates.filter { record in
                !currentRecordIds.contains(record.id!)
            }
            guard !records.isEmpty else {
                return
            }
            records.lazy.compactMap(\.id).forEach {
                currentRecordIds.insert($0)
            }

            try await withThrowingTaskGroup(of: Void.self) { taskGroup in
                records.forEach { record in
                    taskGroup.addTask {
                        await self.downloadRecord(record)
                        // As soon as we finish any download, start downloading more.
                        try await self.loadFromQueueIfAble()
                    }
                }
                try await taskGroup.waitForAll()
            }
        }

        private func didFinishDownloading(_ record: QueuedAttachmentDownloadRecord) async {
            self.currentRecordIds.remove(record.id!)
            await db.awaitableWrite { tx in
                try? self.attachmentDownloadStore.removeAttachmentFromQueue(
                    withId: record.attachmentId,
                    source: record.sourceType,
                    tx: tx
                )
            }
        }

        private func didFailToDownload(
            _ record: QueuedAttachmentDownloadRecord,
            isRetryable: Bool
        ) async {
            self.currentRecordIds.remove(record.id!)
            if isRetryable, let retryTime = self.retryTime(for: record) {
                await db.awaitableWrite { tx in
                    try? self.attachmentDownloadStore.markQueuedDownloadFailed(
                        withId: record.id!,
                        minRetryTimestamp: retryTime,
                        tx: tx
                    )
                }
            } else {
                // Not retrying; just delete.
                await db.awaitableWrite { tx in
                    try? self.attachmentDownloadStore.removeAttachmentFromQueue(
                        withId: record.attachmentId,
                        source: record.sourceType,
                        tx: tx
                    )
                    try? self.attachmentStore.updateAttachmentAsFailedToDownload(
                        from: record.sourceType,
                        id: record.attachmentId,
                        timestamp: self.dateProvider().ows_millisecondsSince1970,
                        tx: tx
                    )
                }
            }
        }

        /// Returns nil if should not be retried.
        /// Note these are not network-level retries; those happen separately.
        /// These are persisted retries, usually for longer running retry attempts.
        private nonisolated func retryTime(for record: QueuedAttachmentDownloadRecord) -> UInt64? {
            switch record.sourceType {
            case .transitTier:
                // We don't do persistent retries fromt the transit tier.
                return nil
            }
        }

        private nonisolated func downloadRecord(_ record: QueuedAttachmentDownloadRecord) async {
            guard let attachment = db.read(block: { tx in
                attachmentStore.fetch(id: record.attachmentId, tx: tx)
            }) else {
                // Because of the foreign key relationship and cascading deletes, this should
                // only happen if the attachment got deleted between when we fetched the
                // download queue record and now. Regardless, the record should now be deleted.
                owsFailDebug("Attempting to download an attachment that doesn't exist!")
                return
            }

            guard attachment.asStream() == nil else {
                // Already a stream! No need to download.
                await self.didFinishDownloading(record)
                return
            }

            // TODO: use the local sticker pack, if available
            // If not, and priority = localClone, re-enqueue at lower priority.

            if let originalAttachmentIdForQuotedReply = attachment.originalAttachmentIdForQuotedReply {
                let didCopyFromOriginal = await quoteUnquoteDownloadQuotedReplyFromOriginalStream(
                    originalAttachmentIdForQuotedReply: originalAttachmentIdForQuotedReply,
                    record: record
                )
                if didCopyFromOriginal {
                    return
                } else if record.priority == .localClone {
                    // If we were trying for a local clone and failed, fail the whole thing.
                    await self.didFailToDownload(record, isRetryable: false)
                    return
                }
            }

            let downloadMetadata: DownloadMetadata
            switch record.sourceType {
            case .transitTier:
                guard let transitTierInfo = attachment.transitTierInfo else {
                    owsFailDebug("Attempting to download an attachment without cdn info")
                    // Remove the download.
                    await db.awaitableWrite { tx in
                        try? self.attachmentDownloadStore.removeAttachmentFromQueue(
                            withId: attachment.id,
                            source: .transitTier,
                            tx: tx
                        )
                    }
                    return
                }
                downloadMetadata = .init(
                    mimeType: attachment.mimeType,
                    cdnNumber: transitTierInfo.cdnNumber,
                    cdnKey: transitTierInfo.cdnKey,
                    encryptionKey: transitTierInfo.encryptionKey,
                    digest: transitTierInfo.digestSHA256Ciphertext,
                    plaintextLength: transitTierInfo.unencryptedByteCount
                )
            }

            let downloadedFileUrl: URL
            do {
                downloadedFileUrl = try await downloadQueue.enqueueDownload(
                    downloadState: .init(type: .attachment(downloadMetadata, id: attachment.id)),
                    maxDownloadSizeBytes: RemoteConfig.maxAttachmentDownloadSizeBytes
                )
            } catch let error {
                Logger.error("Failed to download: \(error)")
                // We retry all network-level errors (with an exponential backoff).
                // Even if we get e.g. a 404, the file may not be available _yet_
                // but might be in the future.
                await self.didFailToDownload(record, isRetryable: true)
                return
            }

            let pendingAttachment: PendingAttachment
            do {
                pendingAttachment = try await decrypter.validateAndPrepare(
                    encryptedFileUrl: downloadedFileUrl,
                    metadata: downloadMetadata
                )
            } catch let error {
                Logger.error("Failed to validate: \(error)")
                await self.didFailToDownload(record, isRetryable: false)
                return
            }

            let attachmentStream: AttachmentStream
            do {
                attachmentStream = try await attachmentUpdater.updateAttachmentAsDownloaded(
                    attachmentId: attachment.id,
                    pendingAttachment: pendingAttachment,
                    source: record.sourceType
                )
            } catch let error {
                Logger.error("Failed to update attachment: \(error)")
                await self.didFailToDownload(record, isRetryable: true)
                return
            }

            do {
                try await attachmentUpdater.copyThumbnailForQuotedReplyIfNeeded(
                    attachmentStream
                )
            } catch let error {
                // Log error but don't block finishing; the thumbnails
                // can update themselves later.
                Logger.error("Failed to update thumbnails: \(error)")
            }

            await self.didFinishDownloading(record)
        }

        private nonisolated func quoteUnquoteDownloadQuotedReplyFromOriginalStream(
            originalAttachmentIdForQuotedReply: Attachment.IDType,
            record: QueuedAttachmentDownloadRecord
        ) async -> Bool {
            let originalAttachmentStream = db.read { tx in
                attachmentStore.fetch(id: originalAttachmentIdForQuotedReply, tx: tx)?.asStream()
            }
            guard let originalAttachmentStream else {
                return false
            }
            do {
                try await attachmentUpdater.copyThumbnailForQuotedReplyIfNeeded(
                    originalAttachmentStream
                )
                return true
            } catch let error {
                Logger.error("Failed to update thumbnails: \(error)")
                return false
            }
        }
    }

    // MARK: - Downloads

    typealias DownloadMetadata = AttachmentDownloads.DownloadMetadata

    private enum DownloadError: Error {
        case oversize
    }

    private enum DownloadType {
        case backup(MessageBackupRemoteInfo, authHeaders: [String: String])
        case transientAttachment(DownloadMetadata)
        case attachment(DownloadMetadata, id: Attachment.IDType)

        // MARK: - Helpers
        func urlPath() throws -> String {
            switch self {
            case .backup(let info, _):
                return "backups/\(info.backupDir)/\(info.backupName)"
            case .attachment(let metadata, _), .transientAttachment(let metadata):
                guard let encodedKey = metadata.cdnKey.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
                    throw OWSAssertionError("Invalid cdnKey.")
                }
                return "attachments/\(encodedKey)"
            }
        }

        func cdnNumber() -> UInt32 {
            switch self {
            case .backup(let info, _):
                return UInt32(clamping: info.cdn)
            case .attachment(let metadata, _), .transientAttachment(let metadata):
                return metadata.cdnNumber
            }
        }

        func additionalHeaders() -> [String: String] {
            switch self {
            case .backup(_, let authHeaders):
                return authHeaders
            case .attachment, .transientAttachment:
                return [:]
            }
        }
    }

    private class DownloadState {
        let startDate = Date()
        let type: DownloadType

        init(type: DownloadType) {
            self.type = type
        }

        func urlPath() throws -> String {
            return try type.urlPath()
        }

        func cdnNumber() -> UInt32 {
            return type.cdnNumber()
        }

        func additionalHeaders() -> [String: String] {
            return type.additionalHeaders()
        }
    }

    private class ProgressStates {
        var states = [Attachment.IDType: Double]()
        var cancelledAttachmentIds = Set<Attachment.IDType>()

        init() {}
    }

    private actor DownloadQueue {

        private let progressStates: ProgressStates
        private let signalService: OWSSignalServiceProtocol

        init(
            progressStates: ProgressStates,
            signalService: OWSSignalServiceProtocol
        ) {
            self.progressStates = progressStates
            self.signalService = signalService
        }

        private let maxConcurrentDownloads = 4
        private var concurrentDownloads = 0
        private var queue = [CheckedContinuation<Void, Error>]()

        func enqueueDownload(
            downloadState: DownloadState,
            maxDownloadSizeBytes: UInt
        ) async throws -> URL {
            try Task.checkCancellation()

            try await withCheckedThrowingContinuation { continuation in
                queue.append(continuation)
                runNextQueuedDownloadIfPossible()
            }

            defer {
                concurrentDownloads -= 1
                runNextQueuedDownloadIfPossible()
            }
            try Task.checkCancellation()
            return try await performDownloadAttempt(
                downloadState: downloadState,
                maxDownloadSizeBytes: maxDownloadSizeBytes,
                resumeData: nil,
                attemptCount: 0
            )
        }

        private func runNextQueuedDownloadIfPossible() {
            if queue.isEmpty || concurrentDownloads >= maxConcurrentDownloads { return }

            concurrentDownloads += 1
            let continuation = queue.removeFirst()
            continuation.resume()
        }

        private nonisolated func performDownloadAttempt(
            downloadState: DownloadState,
            maxDownloadSizeBytes: UInt,
            resumeData: Data?,
            attemptCount: UInt
        ) async throws -> URL {
            let urlSession = self.signalService.urlSessionForCdn(cdnNumber: downloadState.cdnNumber())
            let urlPath = try downloadState.urlPath()
            var headers = downloadState.additionalHeaders()
            headers["Content-Type"] = MimeType.applicationOctetStream.rawValue

            let attachmentId: Attachment.IDType?
            switch downloadState.type {
            case .backup, .transientAttachment:
                attachmentId = nil
            case .attachment(_, let id):
                attachmentId = id
            }

            let progress = { (task: URLSessionTask, progress: Progress) in
                self.handleDownloadProgress(
                    downloadState: downloadState,
                    maxDownloadSizeBytes: maxDownloadSizeBytes,
                    task: task,
                    progress: progress,
                    attachmentId: attachmentId
                )
            }

            do {
                let downloadResponse: OWSUrlDownloadResponse
                if let resumeData = resumeData {
                    let request = try urlSession.endpoint.buildRequest(urlPath, method: .get, headers: headers)
                    guard let requestUrl = request.url else {
                        throw OWSAssertionError("Request missing url.")
                    }
                    downloadResponse = try await urlSession.downloadTaskPromise(
                        requestUrl: requestUrl,
                        resumeData: resumeData,
                        progress: progress
                    ).awaitable()
                } else {
                    downloadResponse = try await urlSession.downloadTaskPromise(
                        urlPath,
                        method: .get,
                        headers: headers,
                        progress: progress
                    ).awaitable()
                }
                let downloadUrl = downloadResponse.downloadUrl
                guard let fileSize = OWSFileSystem.fileSize(of: downloadUrl) else {
                    throw OWSAssertionError("Could not determine attachment file size.")
                }
                guard fileSize.int64Value <= maxDownloadSizeBytes else {
                    throw OWSGenericError("Attachment download length exceeds max size.")
                }
                return downloadUrl
            } catch let error {
                Logger.warn("Error: \(error)")

                let maxAttemptCount = 16
                guard
                    error.isNetworkFailureOrTimeout,
                    attemptCount < maxAttemptCount
                else {
                    throw error
                }

                // Wait briefly before retrying.
                try await Task.sleep(nanoseconds: 250 * NSEC_PER_MSEC)

                let newResumeData = (error as NSError)
                    .userInfo[NSURLSessionDownloadTaskResumeData]
                    .map { $0 as? Data }
                    .map(\.?.nilIfEmpty)
                    ?? nil
                return try await self.performDownloadAttempt(
                    downloadState: downloadState,
                    maxDownloadSizeBytes: maxDownloadSizeBytes,
                    resumeData: newResumeData,
                    attemptCount: attemptCount + 1
                )
            }
        }

        private nonisolated func handleDownloadProgress(
            downloadState: DownloadState,
            maxDownloadSizeBytes: UInt,
            task: URLSessionTask,
            progress: Progress,
            attachmentId: Attachment.IDType?
        ) {
            if let attachmentId, progressStates.cancelledAttachmentIds.contains(attachmentId) {
                Logger.info("Cancelling download.")
                // Cancelling will inform the URLSessionTask delegate.
                task.cancel()
                return
            }

            // Don't do anything until we've received at least one byte of data.
            guard progress.completedUnitCount > 0 else {
                return
            }

            guard progress.totalUnitCount <= maxDownloadSizeBytes,
                  progress.completedUnitCount <= maxDownloadSizeBytes else {
                // A malicious service might send a misleading content length header,
                // so....
                //
                // If the current downloaded bytes or the expected total byes
                // exceed the max download size, abort the download.
                owsFailDebug("Attachment download exceed expected content length: \(progress.totalUnitCount), \(progress.completedUnitCount).")
                task.cancel()
                return
            }

            // Use a slightly non-zero value to ensure that the progress
            // indicator shows up as quickly as possible.
            let progressTheta: Double = 0.001
            let fractionCompleted = max(progressTheta, progress.fractionCompleted)

            switch downloadState.type {
            case .backup, .transientAttachment:
                break
            case .attachment(_, let attachmentId):
                progressStates.states[attachmentId] = fractionCompleted

                NotificationCenter.default.postNotificationNameAsync(
                    AttachmentDownloads.attachmentDownloadProgressNotification,
                    object: nil,
                    userInfo: [
                        AttachmentDownloads.attachmentDownloadProgressKey: NSNumber(value: fractionCompleted),
                        AttachmentDownloads.attachmentDownloadAttachmentIDKey: attachmentId
                    ]
                )
            }
        }
    }

    private class Decrypter {

        private let attachmentValidator: AttachmentContentValidator

        init(
            attachmentValidator: AttachmentContentValidator
        ) {
            self.attachmentValidator = attachmentValidator
        }

        // Use serialQueue to ensure that we only load into memory
        // & decrypt a single attachment at a time.
        private let decryptionQueue = SerialTaskQueue()

        func decryptTransientAttachment(
            encryptedFileUrl: URL,
            metadata: DownloadMetadata
        ) async throws -> URL {
            return try await decryptionQueue.enqueue(operation: {
                do {
                    // Transient attachments decrypt to a tmp file.
                    let outputUrl = OWSFileSystem.temporaryFileUrl()

                    try Cryptography.decryptAttachment(
                        at: encryptedFileUrl,
                        metadata: EncryptionMetadata(
                            key: metadata.encryptionKey,
                            digest: metadata.digest,
                            plaintextLength: metadata.plaintextLength.map(Int.init)
                        ),
                        output: outputUrl
                    )

                    return outputUrl
                } catch let error {
                    do {
                        try OWSFileSystem.deleteFileIfExists(url: encryptedFileUrl)
                    } catch let deleteFileError {
                        owsFailDebug("Error: \(deleteFileError).")
                    }
                    throw error
                }
            }).value
        }

        func validateAndPrepare(
            encryptedFileUrl: URL,
            metadata: DownloadMetadata
        ) async throws -> PendingAttachment {
            let attachmentValidator = self.attachmentValidator
            return try await decryptionQueue.enqueue(operation: {
                // AttachmentValidator runs synchronously _and_ opens write transactions
                // internally. We can't block on the write lock in the cooperative thread
                // pool, so bridge out of structured concurrency to run the validation.
                return try await withCheckedThrowingContinuation { continuation in
                    DispatchQueue.global().async {
                        do {
                            let pendingAttachment = try attachmentValidator.validateContents(
                                ofEncryptedFileAt: encryptedFileUrl,
                                encryptionKey: metadata.encryptionKey,
                                plaintextLength: metadata.plaintextLength,
                                digestSHA256Ciphertext: metadata.digest,
                                mimeType: metadata.mimeType,
                                renderingFlag: .default,
                                sourceFilename: nil
                            )
                            continuation.resume(with: .success(pendingAttachment))
                        } catch let error {
                            continuation.resume(throwing: error)
                        }
                    }
                }
            }).value
        }

        func prepareQuotedReplyThumbnail(originalAttachmentStream: AttachmentStream) async throws -> PendingAttachment {
            let attachmentValidator = self.attachmentValidator
            return try await decryptionQueue.enqueue(operation: {
                // AttachmentValidator runs synchronously _and_ opens write transactions
                // internally. We can't block on the write lock in the cooperative thread
                // pool, so bridge out of structured concurrency to run the validation.
                return try await withCheckedThrowingContinuation { continuation in
                    DispatchQueue.global().async {
                        do {
                            let pendingAttachment = try attachmentValidator.prepareQuotedReplyThumbnail(
                                fromOriginalAttachmentStream: originalAttachmentStream
                            )
                            continuation.resume(with: .success(pendingAttachment))
                        } catch let error {
                            continuation.resume(throwing: error)
                        }
                    }
                }
            }).value
        }
    }

    private class AttachmentUpdater {

        private let attachmentStore: AttachmentStore
        private let db: DB
        private let decrypter: Decrypter
        private let orphanedAttachmentCleaner: OrphanedAttachmentCleaner
        private let orphanedAttachmentStore: OrphanedAttachmentStore

        public init(
            attachmentStore: AttachmentStore,
            db: DB,
            decrypter: Decrypter,
            orphanedAttachmentCleaner: OrphanedAttachmentCleaner,
            orphanedAttachmentStore: OrphanedAttachmentStore
        ) {
            self.attachmentStore = attachmentStore
            self.db = db
            self.decrypter = decrypter
            self.orphanedAttachmentCleaner = orphanedAttachmentCleaner
            self.orphanedAttachmentStore = orphanedAttachmentStore
        }

        func updateAttachmentAsDownloaded(
            attachmentId: Attachment.IDType,
            pendingAttachment: PendingAttachment,
            source: QueuedAttachmentDownloadRecord.SourceType
        ) async throws -> AttachmentStream {
            return try await db.awaitableWrite { tx in
                guard let existingAttachment = self.attachmentStore.fetch(id: attachmentId, tx: tx) else {
                    throw OWSAssertionError("Missing attachment!")
                }
                if let stream = existingAttachment.asStream() {
                    // Its already a stream?
                    return stream
                }

                do {
                    guard self.orphanedAttachmentStore.orphanAttachmentExists(with: pendingAttachment.orphanRecordId, tx: tx) else {
                        throw OWSAssertionError("Attachment file deleted before creation")
                    }

                    // Try and update the attachment.
                    try self.attachmentStore.updateAttachmentAsDownloaded(
                        from: source,
                        id: attachmentId,
                        streamInfo: .init(
                            sha256ContentHash: pendingAttachment.sha256ContentHash,
                            encryptedByteCount: pendingAttachment.encryptedByteCount,
                            unencryptedByteCount: pendingAttachment.unencryptedByteCount,
                            contentType: pendingAttachment.validatedContentType,
                            digestSHA256Ciphertext: pendingAttachment.digestSHA256Ciphertext,
                            localRelativeFilePath: pendingAttachment.localRelativeFilePath
                        ),
                        tx: tx
                    )
                    // Make sure to clear out the pending attachment from the orphan table so it isn't deleted!
                    try self.orphanedAttachmentCleaner.releasePendingAttachment(withId: pendingAttachment.orphanRecordId, tx: tx)

                    guard let stream = self.attachmentStore.fetch(id: attachmentId, tx: tx)?.asStream() else {
                        throw OWSAssertionError("Not a stream")
                    }
                    return stream

                } catch let AttachmentInsertError.duplicatePlaintextHash(existingAttachmentId) {
                    // Already have an attachment with the same plaintext hash!
                    // Move all existing references to that copy, instead.
                    // Doing so should delete the original attachment pointer.

                    // Just hold all refs in memory; this is a pointer so really there
                    // should only ever be one reference as we don't dedupe pointers.
                    var references = [AttachmentReference]()
                    try self.attachmentStore.enumerateAllReferences(
                        toAttachmentId: attachmentId,
                        tx: tx
                    ) { reference in
                        references.append(reference)
                    }
                    try references.forEach { reference in
                        try self.attachmentStore.removeOwner(
                            reference.owner.id,
                            for: attachmentId,
                            tx: tx
                        )
                        let newOwnerParams = AttachmentReference.ConstructionParams(
                            owner: reference.owner,
                            sourceFilename: reference.sourceFilename,
                            sourceUnencryptedByteCount: reference.sourceUnencryptedByteCount,
                            sourceMediaSizePixels: reference.sourceMediaSizePixels
                        )
                        try self.attachmentStore.addOwner(
                            newOwnerParams,
                            for: existingAttachmentId,
                            tx: tx
                        )
                    }

                    guard let stream = self.attachmentStore.fetch(id: existingAttachmentId, tx: tx)?.asStream() else {
                        throw OWSAssertionError("Not a stream")
                    }
                    return stream
                } catch let error {
                    throw error
                }
            }
        }

        func copyThumbnailForQuotedReplyIfNeeded(_ downloadedAttachment: AttachmentStream) async throws {
            let thumbnailAttachments = try db.read { tx in
                return try self.attachmentStore.allQuotedReplyAttachments(
                    forOriginalAttachmentId: downloadedAttachment.attachment.id,
                    tx: tx
                )
            }
            guard thumbnailAttachments.contains(where: { $0.asStream() == nil }) else {
                // all the referencing thumbnails already have their own streams, nothing to do.
                return
            }
            let pendingThumbnailAttachment = try await self.decrypter.prepareQuotedReplyThumbnail(
                originalAttachmentStream: downloadedAttachment
            )

            try await db.awaitableWrite { tx in
                let thumbnailAttachments = try self.attachmentStore
                    .allQuotedReplyAttachments(
                        forOriginalAttachmentId: downloadedAttachment.attachment.id,
                        tx: tx
                    )
                    .filter({ $0.asStream() == nil })

                // Arbitrarily pick the first thumbnail as the one we will promote to
                // a stream. The others' references will be re-pointed to this one.
                guard let firstThumbnailAttachment = thumbnailAttachments.first else {
                    // Nothing to update.
                    return
                }

                let references = try thumbnailAttachments.flatMap { attachment in
                    var refs = [AttachmentReference]()
                    try self.attachmentStore.enumerateAllReferences(toAttachmentId: attachment.id, tx: tx) {
                        refs.append($0)
                    }
                    return refs
                }

                let thumbnailAttachmentId: Attachment.IDType
                do {
                    guard self.orphanedAttachmentStore.orphanAttachmentExists(with: pendingThumbnailAttachment.orphanRecordId, tx: tx) else {
                        throw OWSAssertionError("Attachment file deleted before creation")
                    }

                    // Try and promote the attachment to a stream.
                    try self.attachmentStore.updateAttachmentAsDownloaded(
                        from: .transitTier,
                        id: firstThumbnailAttachment.id,
                        streamInfo: .init(
                            sha256ContentHash: pendingThumbnailAttachment.sha256ContentHash,
                            encryptedByteCount: pendingThumbnailAttachment.encryptedByteCount,
                            unencryptedByteCount: pendingThumbnailAttachment.unencryptedByteCount,
                            contentType: pendingThumbnailAttachment.validatedContentType,
                            digestSHA256Ciphertext: pendingThumbnailAttachment.digestSHA256Ciphertext,
                            localRelativeFilePath: pendingThumbnailAttachment.localRelativeFilePath
                        ),
                        tx: tx
                    )
                    // Make sure to clear out the pending attachment from the orphan table so it isn't deleted!
                    try self.orphanedAttachmentCleaner.releasePendingAttachment(withId: pendingThumbnailAttachment.orphanRecordId, tx: tx)

                    thumbnailAttachmentId = firstThumbnailAttachment.id
                } catch let AttachmentInsertError.duplicatePlaintextHash(existingAttachmentId) {
                    // Already have an attachment with the same plaintext hash!
                    // We will instead re-point all references to this attachment.
                    thumbnailAttachmentId = existingAttachmentId
                } catch let error {
                    throw error
                }

                // Move all existing references to the new thumbnail stream.
                try references.forEach { reference in
                    if reference.attachmentRowId == thumbnailAttachmentId {
                        // No need to update references already pointing at the right spot.
                        return
                    }

                    try self.attachmentStore.removeOwner(
                        reference.owner.id,
                        for: reference.attachmentRowId,
                        tx: tx
                    )
                    let newOwnerParams = AttachmentReference.ConstructionParams(
                        owner: reference.owner,
                        sourceFilename: reference.sourceFilename,
                        sourceUnencryptedByteCount: reference.sourceUnencryptedByteCount,
                        sourceMediaSizePixels: reference.sourceMediaSizePixels
                    )
                    try self.attachmentStore.addOwner(
                        newOwnerParams,
                        for: thumbnailAttachmentId,
                        tx: tx
                    )
                }
            }
        }
    }

    private static let encryptionOverheadByteLength: UInt32 = /* iv */ 16 + /* hmac */ 32

    private static func estimatedAttachmentDownloadSize(
        plaintextSize: UInt32?,
        source: QueuedAttachmentDownloadRecord.SourceType
    ) -> UInt32 {
        let fallbackSize: UInt = {
            // TODO: thumbnails will have a different expected size (the thumbnail size limit)
            switch source {
            case .transitTier:
                return RemoteConfig.maxAttachmentDownloadSizeBytes
            }
        }()

        // Every sender _will_ give us a plaintext size. Not including one will result
        // in failing to remove padding. So this fallback will never be used in practice,
        // but regardless, this is just an estimate size.
        let plaintextSize: UInt = plaintextSize.map(UInt.init) ?? fallbackSize

        let paddedSize = UInt32(Cryptography.paddedSize(unpaddedSize: plaintextSize))

        let pkcs7PaddingLength = 16 - (paddedSize % 16)
        return paddedSize + pkcs7PaddingLength + encryptionOverheadByteLength
    }
}
