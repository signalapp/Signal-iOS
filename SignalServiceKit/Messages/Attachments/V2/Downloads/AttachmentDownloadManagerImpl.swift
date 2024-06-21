//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class AttachmentDownloadManagerImpl: AttachmentDownloadManager {

    private let audioWaveformManager: AudioWaveformManager
    private let schedulers: Schedulers
    private let signalService: OWSSignalServiceProtocol
    private let videoDurationHelper: VideoDurationHelper

    public init(
        audioWaveformManager: AudioWaveformManager,
        schedulers: Schedulers,
        signalService: OWSSignalServiceProtocol,
        videoDurationHelper: VideoDurationHelper
    ) {
        self.audioWaveformManager = audioWaveformManager
        self.schedulers = schedulers
        self.signalService = signalService
        self.videoDurationHelper = videoDurationHelper
    }

    public func downloadBackup(metadata: MessageBackupRemoteInfo, authHeaders: [String: String]) -> Promise<URL> {
        let downloadState = DownloadState(type: .backup(metadata, authHeaders: authHeaders))
        return firstly(on: schedulers.sync) { () -> Promise<URL> in
            let maxDownloadSize = MessageBackup.Constants.maxDownloadSizeBytes
            return self.download(downloadState: downloadState, maxDownloadSizeBytes: maxDownloadSize)
        }
    }

    public func downloadTransientAttachment(metadata: AttachmentDownloads.DownloadMetadata) -> Promise<URL> {
        // TODO: this should enqueue the download and all that. For now this class
        // only does the transient download so do it immediately.
        return retrieveAttachment(metadata: metadata)
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
    ) -> Promise<URL> {

        // We want to avoid large downloads from a compromised or buggy service.
        let maxDownloadSize = RemoteConfig.maxAttachmentDownloadSizeBytes
        let downloadState = DownloadState(type: .attachment(metadata))

        return firstly(on: schedulers.sync) { () -> Promise<URL> in
            self.download(
                downloadState: downloadState,
                maxDownloadSizeBytes: maxDownloadSize
            )
        }.then(on: schedulers.sync) { (encryptedFileUrl: URL) -> Promise<URL> in
            // This dispatches to its own queue
            Self.decrypt(encryptedFileUrl: encryptedFileUrl, metadata: metadata)
        }
    }

    private func download(
        downloadState: DownloadState,
        maxDownloadSizeBytes: UInt
    ) -> Promise<URL> {
        return firstly(on: schedulers.sync) { () -> Promise<URL> in
            self.downloadAttempt(
                downloadState: downloadState,
                maxDownloadSizeBytes: maxDownloadSizeBytes
            )
        }
    }

    private func downloadAttempt(
        downloadState: DownloadState,
        maxDownloadSizeBytes: UInt,
        resumeData: Data? = nil,
        attemptIndex: UInt = 0
    ) -> Promise<URL> {

        let (promise, future) = Promise<URL>.pending()

        firstly(on: schedulers.global()) { () -> Promise<OWSUrlDownloadResponse> in
            let urlSession = self.signalService.urlSessionForCdn(cdnNumber: downloadState.cdnNumber())
            let urlPath = try downloadState.urlPath()
            var headers = downloadState.additionalHeaders()
            headers["Content-Type"] = MimeType.applicationOctetStream.rawValue

            let progress = { (task: URLSessionTask, progress: Progress) in
                self.handleDownloadProgress(
                    downloadState: downloadState,
                    maxDownloadSizeBytes: maxDownloadSizeBytes,
                    task: task,
                    progress: progress,
                    future: future
                )
            }

            if let resumeData = resumeData {
                let request = try urlSession.endpoint.buildRequest(urlPath, method: .get, headers: headers)
                guard let requestUrl = request.url else {
                    return Promise(error: OWSAssertionError("Request missing url."))
                }
                return urlSession.downloadTaskPromise(requestUrl: requestUrl,
                                                      resumeData: resumeData,
                                                      progress: progress)
            } else {
                return urlSession.downloadTaskPromise(urlPath,
                                                      method: .get,
                                                      headers: headers,
                                                      progress: progress)
            }
        }.map(on: schedulers.global()) { (response: OWSUrlDownloadResponse) in
            let downloadUrl = response.downloadUrl
            guard let fileSize = OWSFileSystem.fileSize(of: downloadUrl) else {
                throw OWSAssertionError("Could not determine attachment file size.")
            }
            guard fileSize.int64Value <= maxDownloadSizeBytes else {
                throw OWSGenericError("Attachment download length exceeds max size.")
            }
            return downloadUrl
        }.recover(on: schedulers.sync) { [schedulers] (error: Error) -> Promise<URL> in
            Logger.warn("Error: \(error)")

            let maxAttemptCount = 16
            if error.isNetworkFailureOrTimeout,
               attemptIndex < maxAttemptCount {

                return firstly(on: schedulers.sync) { [schedulers] in
                    // Wait briefly before retrying.
                    Guarantee.after(on: schedulers.global(), seconds: 0.25)
                }.then(on: schedulers.sync) { () -> Promise<URL> in
                    if let resumeData = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data,
                       !resumeData.isEmpty {
                        return self.downloadAttempt(
                            downloadState: downloadState,
                            maxDownloadSizeBytes: maxDownloadSizeBytes,
                            resumeData: resumeData,
                            attemptIndex: attemptIndex + 1
                        )
                    } else {
                        return self.downloadAttempt(
                            downloadState: downloadState,
                            maxDownloadSizeBytes: maxDownloadSizeBytes,
                            attemptIndex: attemptIndex + 1
                        )
                    }
                }
            } else {
                throw error
            }
        }.done(on: schedulers.sync) { url in
            future.resolve(url)
        }.catch(on: schedulers.sync) { error in
            future.reject(error)
        }

        return promise
    }

    private func handleDownloadProgress(
        downloadState: DownloadState,
        maxDownloadSizeBytes: UInt,
        task: URLSessionTask,
        progress: Progress,
        future: Future<URL>
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
            future.reject(DownloadError.oversize)
            return
        }

        // TODO: update progress for non-transient downloads
    }

    static let serialDecryptionQueue: DispatchQueue = {
        return DispatchQueue(
            label: "org.signal.attachment.download.v2",
            qos: .utility,
            autoreleaseFrequency: .workItem
        )
    }()

    private class func decrypt(
        encryptedFileUrl: URL,
        metadata: DownloadMetadata
    ) -> Promise<URL> {
        let (promise, future) = Promise<URL>.pending()

        // Use serialQueue to ensure that we only load into memory
        // & decrypt a single attachment at a time.
        Self.serialDecryptionQueue.async {
            autoreleasepool {
                do {
                    // TODO: attachment downloads should decrypt for verification purposes
                    // but can discard the decrypted file afterwards.
                    let outputUrl = OWSFileSystem.temporaryFileUrl()

                    try Cryptography.decryptAttachment(
                        at: encryptedFileUrl,
                        metadata: EncryptionMetadata(
                            key: metadata.encryptionKey,
                            digest: metadata.digest,
                            plaintextLength: Int(metadata.plaintextLength)
                        ),
                        output: outputUrl
                    )

                    future.resolve(outputUrl)
                } catch let error {
                    do {
                        try OWSFileSystem.deleteFileIfExists(url: encryptedFileUrl)
                    } catch let deleteFileError {
                        owsFailDebug("Error: \(deleteFileError).")
                    }
                    future.reject(error)
                }
            }
        }
        return promise
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
}
