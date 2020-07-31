//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

public extension OWSAttachmentDownloads {

    // MARK: - Dependencies

    private class var signalService: OWSSignalService {
        return .sharedInstance()
    }

    private class var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    // MARK: -

    func downloadAttachmentPointer(_ attachmentPointer: TSAttachmentPointer,
                                   bypassPendingMessageRequest: Bool) -> Promise<TSAttachmentStream> {
        return Promise { resolver in
            self.downloadAttachmentPointer(attachmentPointer,
                                           bypassPendingMessageRequest: bypassPendingMessageRequest,
                                           success: resolver.fulfill,
                                           failure: resolver.reject)
        }.map { attachments in
            assert(attachments.count == 1)
            guard let attachment = attachments.first else {
                throw OWSAssertionError("missing attachment after download")
            }
            return attachment
        }
    }

    // We want to avoid large downloads from a compromised or buggy service.
    private static let maxDownloadSize = 150 * 1024 * 1024

    // Use a slightly non-zero value to ensure that the progress
    // indicator shows up as quickly as possible.
    private static let progressTheta: Double = 0.001

    @objc
    func retrieveAttachment(job: OWSAttachmentDownloadJob,
                            attachmentPointer: TSAttachmentPointer,
                            success: @escaping (TSAttachmentStream) -> Void,
                            failure: @escaping (Error) -> Void) {
        firstly {
            Self.retrieveAttachment(job: job, attachmentPointer: attachmentPointer)
        }.done(on: .global()) { (attachmentStream: TSAttachmentStream) in
            success(attachmentStream)
        }.catch(on: .global()) { (error: Error) in
            failure(error)
        }
    }

    private class func retrieveAttachment(job: OWSAttachmentDownloadJob,
                                          attachmentPointer: TSAttachmentPointer) -> Promise<TSAttachmentStream> {

        var backgroundTask: OWSBackgroundTask? = OWSBackgroundTask(label: "retrieveAttachment")

        return firstly(on: .global()) { () -> Promise<URL> in
            if attachmentPointer.serverId < 100 {
                Logger.warn("Suspicious attachment id: \(attachmentPointer.serverId)")
            }
            return Self.download(job: job, attachmentPointer: attachmentPointer)
        }.then(on: .global()) { (encryptedFileUrl: URL) -> Promise<TSAttachmentStream> in
            Self.decrypt(encryptedFileUrl: encryptedFileUrl,
                         attachmentPointer: attachmentPointer)
        }.ensure(on: .global()) {
            guard backgroundTask != nil else {
                owsFailDebug("Missing backgroundTask.")
                return
            }
            backgroundTask = nil
        }
    }

    private class DownloadState {
        let job: OWSAttachmentDownloadJob
        let attachmentPointer: TSAttachmentPointer

        private let lock = UnfairLock()
        private var tempFileUrls = [URL]()

        let hasCheckedContentLength = AtomicValue<Bool>(false)

        required init(job: OWSAttachmentDownloadJob, attachmentPointer: TSAttachmentPointer) {
            self.job = job
            self.attachmentPointer = attachmentPointer
        }

        func addTempFileUrl() -> URL {
            let tempFileUrl = OWSFileSystem.temporaryFileUrl(isAvailableWhileDeviceLocked: true)
            lock.withLock {
                tempFileUrls.append(tempFileUrl)
            }
            return tempFileUrl
        }

        func mergeFileUrls() throws -> URL {
            // Discard any empty files.
            let fileUrlsAndSizes = tempFileUrls.compactMap { (url: URL) -> (URL, UInt64)? in
                guard OWSFileSystem.fileOrFolderExists(url: url) else {
                    return nil
                }
                guard let nsFileSize: NSNumber = OWSFileSystem.fileSize(of: url) else {
                    return nil
                }
                let fileSize = nsFileSize.uint64Value
                guard fileSize > 0 else {
                    return nil
                }
                return (url, fileSize)
            }
            guard !fileUrlsAndSizes.isEmpty else {
                throw OWSAssertionError("No tempFileUrls.")
            }
            if fileUrlsAndSizes.count == 1,
                let (fileUrl, _) = fileUrlsAndSizes.first {
                // No need to merge if we didn't resume.
                return fileUrl
            }
            var joinedData = Data()
            for (fileUrl, fileSize) in fileUrlsAndSizes {
                let fileData = try Data(contentsOf: fileUrl)
                guard fileData.count == fileSize else {
                    throw OWSAssertionError("Segment has unexpected size.")
                }
                joinedData.append(fileData)
                try OWSFileSystem.deleteFile(url: fileUrl)
            }
            let joinedFileUrl = OWSFileSystem.temporaryFileUrl(isAvailableWhileDeviceLocked: true)
            try joinedData.write(to: joinedFileUrl)
            return joinedFileUrl
        }

        func deleteFileUrls() {
            for tempFileUrl in tempFileUrls {
                do {
                    try OWSFileSystem.deleteFile(url: tempFileUrl)
                } catch {
                    owsFailDebug("Error: \(error)")
                }
            }
        }
    }

    func test() {}

    private class func download(job: OWSAttachmentDownloadJob,
                                attachmentPointer: TSAttachmentPointer) -> Promise<URL> {

        let downloadState = DownloadState(job: job, attachmentPointer: attachmentPointer)

        return firstly(on: .global()) { () -> Promise<Void> in
            Self.downloadAttempt(downloadState: downloadState)
        }.map(on: .global()) { () -> URL in
            try downloadState.mergeFileUrls()
        }.recover(on: .global()) { (error: Error) -> Promise<URL> in
            downloadState.deleteFileUrls()
            throw error
        }
    }

    private class func downloadAttempt(downloadState: DownloadState,
                                       attemptIndex: UInt = 0) -> Promise<Void> {

        return firstly(on: .global()) { () -> Promise<Void> in
            let attachmentPointer = downloadState.attachmentPointer
            let tempFileUrl = downloadState.addTempFileUrl()

            let promise: Promise<Void> = firstly(on: .global()) { () -> Promise<URL> in
                let sessionManager = self.signalService.cdnSessionManager(forCdnNumber: attachmentPointer.cdnNumber)
                sessionManager.completionQueue = .global()

                let urlPath: String
                if attachmentPointer.cdnKey.count > 0 {
                    urlPath = "attachments/(attachmentPointer.cdnKey.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed))"
                } else {
                    urlPath = String(format: "attachments/%llu", attachmentPointer.serverId)
                }
                let headers: [String: String] = [
                    "Content-Type": OWSMimeTypeApplicationOctetStream
                ]
                return sessionManager.downloadTaskPromise(urlPath,
                                                          verb: .get,
                                                          headers: headers,
                                                          dstFileUrl: tempFileUrl,
                                                          progress: { (progress: Progress, task: URLSessionDownloadTask) in
                                                            Self.handleDownloadProgress(downloadState: downloadState,
                                                                                        task: task,
                                                                                        progress: progress)
                })
            }.map(on: .global()) { (completionUrl: URL) in
                if tempFileUrl != completionUrl {
                    throw OWSAssertionError("Unexpected temp file path.")
                }
                guard let fileSize = OWSFileSystem.fileSize(of: tempFileUrl) else {
                    throw OWSAssertionError("Could not determine attachment file size.")
                }
                guard fileSize.int64Value <= Self.maxDownloadSize else {
                    throw OWSAssertionError("Attachment download length exceeds max size.")
                }
            }.recover(on: .global()) { (error: Error) -> Promise<Void> in
                let maxAttemptCount = 16
                if IsNetworkConnectivityFailure(error),
                    attemptIndex < maxAttemptCount {
                    Logger.warn("Retrying download: \(attemptIndex)")
                    return self.downloadAttempt(downloadState: downloadState, attemptIndex: attemptIndex + 1)
                } else {
                    throw error
                }
            }

            promise.catch(on: .global()) { (error: Error) in
                if let statusCode = HTTPStatusCodeForError(error),
                    attachmentPointer.serverId < 100 {
                    // This looks like the symptom of the "frequent 404
                    // downloading attachments with low server ids".
                    owsFailDebug("\(statusCode) Failure with suspicious attachment id: \(attachmentPointer.serverId), \(error)")
                }
            }

            return promise
        }
    }

    private class func handleDownloadProgress(downloadState: DownloadState,
                                              task: URLSessionDownloadTask,
                                              progress: Progress) {
        // Don't do anything until we've received at least one byte of data.
        guard progress.completedUnitCount > 0 else {
            return
        }

        guard progress.totalUnitCount <= maxDownloadSize,
            progress.completedUnitCount <= maxDownloadSize else {
                // A malicious service might send a misleading content length header,
                // so....
                //
                // If the current downloaded bytes or the expected total byes
                // exceed the max download size, abort the download.
                owsFailDebug("Attachment download exceed expected content length: \(progress.totalUnitCount), \(progress.completedUnitCount).")
                task.cancel()
                return
        }

        downloadState.job.progress = CGFloat(progress.fractionCompleted)

        Self.fireProgressNotification(progress: max(progressTheta, progress.fractionCompleted),
                                      attachmentId: downloadState.attachmentPointer.uniqueId)

        // We only need to check the content length header once.
        guard !downloadState.hasCheckedContentLength.get() else {
            return
        }

        // Once we've received some bytes of the download, check the content length
        // header for the download.
        //
        // If the task doesn't exist, or doesn't have a response, or is missing
        // the expected headers, or has an invalid or oversize content length, etc.,
        // abort the download.
        guard let httpResponse = task.response as? HTTPURLResponse else {
            owsFailDebug("Attachment download has missing or invalid response.")
            task.cancel()
            return
        }

        let headers = httpResponse.allHeaderFields
        guard let contentLengthString = headers["Content-Length"] as? String,
            let contentLength = Int64(contentLengthString) else {
                owsFailDebug("Attachment download missing or invalid content length.")
                task.cancel()
                return
        }

        guard contentLength <= maxDownloadSize else {
            owsFailDebug("Attachment download content length exceeds max download size.")
            task.cancel()
            return
        }

        // This response has a valid content length that is less
        // than our max download size.  Proceed with the download.
        downloadState.hasCheckedContentLength.set(true)
    }

    // MARK: -

    private static let decryptQueue = DispatchQueue(label: "OWSAttachmentDownloads.decryptQueue")

    private class func decrypt(encryptedFileUrl: URL,
                               attachmentPointer: TSAttachmentPointer) -> Promise<TSAttachmentStream> {

        // Use decryptQueue to ensure that we only load into memory
        // & decrypt a single attachment at a time.
        return firstly(on: decryptQueue) { () -> TSAttachmentStream in
            return try autoreleasepool { () -> TSAttachmentStream in
                let cipherText = try Data(contentsOf: encryptedFileUrl)
                return try Self.decrypt(cipherText: cipherText,
                                        attachmentPointer: attachmentPointer)
            }
        }.ensure(on: .global()) {
            if !OWSFileSystem.deleteFileIfExists(encryptedFileUrl.path) {
                owsFailDebug("Could not delete encrypted data file.")
            }
        }
    }

    private class func decrypt(cipherText: Data,
                               attachmentPointer: TSAttachmentPointer) throws -> TSAttachmentStream {

        guard let encryptionKey = attachmentPointer.encryptionKey else {
            throw OWSAssertionError("Missing encryptionKey.")
        }
        let plaintext: Data = try Cryptography.decryptAttachment(cipherText,
                                                                 withKey: encryptionKey,
                                                                 digest: attachmentPointer.digest,
                                                                 unpaddedSize: attachmentPointer.byteCount)

        let attachmentStream = databaseStorage.read { transaction in
            TSAttachmentStream(pointer: attachmentPointer, transaction: transaction)
        }
        try attachmentStream.write(plaintext)
        return attachmentStream
    }

    // MARK: -

    @objc
    static let attachmentDownloadProgressNotification = Notification.Name("AttachmentDownloadProgressNotification")
    @objc
    static let attachmentDownloadProgressKey = "attachmentDownloadProgressKey"
    @objc
    static let attachmentDownloadAttachmentIDKey = "attachmentDownloadAttachmentIDKey"

    private class func fireProgressNotification(progress: Double, attachmentId: String) {
        NotificationCenter.default.postNotificationNameAsync(attachmentDownloadProgressNotification,
                                                             object: nil,
                                                             userInfo: [
                                                                attachmentDownloadProgressKey: NSNumber(value: progress),
                                                                attachmentDownloadAttachmentIDKey: attachmentId
        ])
    }
}
