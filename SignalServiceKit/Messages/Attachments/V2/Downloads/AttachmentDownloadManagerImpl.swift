//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class AttachmentDownloadManagerImpl: AttachmentDownloadManager {

    private let audioWaveformManager: AudioWaveformManager
    private let downloadQueue: DownloadQueue
    private let schedulers: Schedulers
    private let videoDurationHelper: VideoDurationHelper

    public init(
        audioWaveformManager: AudioWaveformManager,
        schedulers: Schedulers,
        signalService: OWSSignalServiceProtocol,
        videoDurationHelper: VideoDurationHelper
    ) {
        self.audioWaveformManager = audioWaveformManager
        self.downloadQueue = DownloadQueue(signalService: signalService)
        self.schedulers = schedulers
        self.videoDurationHelper = videoDurationHelper
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
        // TODO: this should enqueue the download and all that. For now this class
        // only does the transient download so do it immediately.
        return Promise.wrapAsync {
            return try await self.retrieveAttachment(metadata: metadata)
        }
    }

    public func enqueueDownloadOfAttachmentsForMessage(
        _ message: TSMessage,
        priority: AttachmentDownloadPriority,
        tx: DBWriteTransaction
    ) {
        fatalError("Unimplemented")
    }

    public func enqueueDownloadOfAttachmentsForStoryMessage(
        _ message: StoryMessage,
        priority: AttachmentDownloadPriority,
        tx: DBWriteTransaction
    ) {
        fatalError("Unimplemented")
    }

    public func beginDownloadingIfNecessary() {
        fatalError("Unimplemented")
    }

    public func cancelDownload(for attachmentId: Attachment.IDType, tx: DBWriteTransaction) {
        fatalError("Unimplemented")
    }

    public func downloadProgress(for attachmentId: Attachment.IDType, tx: DBReadTransaction) -> CGFloat? {
        fatalError("Unimplemented")
    }

    // MARK: - Downloads

    typealias DownloadMetadata = AttachmentDownloads.DownloadMetadata

    private enum DownloadError: Error {
        case oversize
    }

    private enum DownloadType {
        case backup(MessageBackupRemoteInfo, authHeaders: [String: String])
        case attachment(DownloadMetadata)

        // MARK: - Helpers
        func urlPath() throws -> String {
            switch self {
            case .backup(let info, _):
                return "backups/\(info.backupDir)/\(info.backupName)"
            case .attachment(let metadata):
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
            case .attachment(let metadata):
                return metadata.cdnNumber
            }
        }

        func additionalHeaders() -> [String: String] {
            switch self {
            case .backup(_, let authHeaders):
                return authHeaders
            case .attachment:
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

    private func retrieveAttachment(
        metadata: DownloadMetadata
    ) async throws -> URL {

        // We want to avoid large downloads from a compromised or buggy service.
        let maxDownloadSize = RemoteConfig.maxAttachmentDownloadSizeBytes
        let downloadState = DownloadState(type: .attachment(metadata))

        let encryptedFileUrl = try await self.downloadQueue.enqueueDownload(
            downloadState: downloadState,
            maxDownloadSizeBytes: maxDownloadSize
        )
        return try await self.decrypt(encryptedFileUrl: encryptedFileUrl, metadata: metadata)
    }

    private actor DownloadQueue {

        private let signalService: OWSSignalServiceProtocol

        init(
            signalService: OWSSignalServiceProtocol
        ) {
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

            let progress = { (task: URLSessionTask, progress: Progress) in
                self.handleDownloadProgress(
                    downloadState: downloadState,
                    maxDownloadSizeBytes: maxDownloadSizeBytes,
                    task: task,
                    progress: progress
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
            progress: Progress
        ) {
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

            // TODO: update progress for non-transient downloads
        }
    }

    // Use serialQueue to ensure that we only load into memory
    // & decrypt a single attachment at a time.
    private let decryptionQueue = SerialTaskQueue()

    private func decrypt(
        encryptedFileUrl: URL,
        metadata: DownloadMetadata
    ) async throws -> URL {
        return try await decryptionQueue.enqueue(operation: {
            do {
                // TODO: attachment downloads should decrypt for verification purposes
                // but can discard the decrypted file afterwards.
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

    func copyThumbnailForQuotedReplyIfNeeded(_ downloadedAttachment: AttachmentStream) {
        /// Here's what this method needs to do:
        /// 1. Figure out what attachment to actually use
        ///   1a. If the passed in stream is not an image or video, use it directly.
        ///   1b. If the passed in stream is a video, make a thumbnail still image copy and insert it
        ///   1c. If its an image, make a thumbnail copy and insert it. (if its small, can reuse the same attachment, no insertion)
        ///
        /// 2. Create the edge between the attachment and this link preview
        ///   2a. Find the row for this message in AttachmentReferences with quoted message thumnail ref type
        ///   2b. Validate that the contentType column is null (its undownloaded). If its downloaded, exit early.
        ///   2c. Update the attachmentId column for the row to the attachment from step 1. (possibly the same attachment)
        ///
        /// 3. As with any AttachmentReferences update, delete any now-orphaned attachments
        ///   3a. Note the passed-in attachment itself may be orphaned, if it got enqueued with no other owners and wasn't used
        ///      for the quoted reply.
        ///
        /// FYI nothing needs to be updated on the TSQuotedMessage or the parent message.
        fatalError("Unimplemented")
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
