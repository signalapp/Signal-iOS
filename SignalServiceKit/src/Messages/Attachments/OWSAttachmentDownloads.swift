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

        let contentLength = AtomicOptional<UInt64>(nil)

        required init(job: OWSAttachmentDownloadJob, attachmentPointer: TSAttachmentPointer) {
            self.job = job
            self.attachmentPointer = attachmentPointer
        }

        func addTempFileUrl() -> URL {
            let tempFileUrl = OWSFileSystem.temporaryFileUrl(isAvailableWhileDeviceLocked: true)
            lock.withLock {
                tempFileUrls.append(tempFileUrl)
            }
            Logger.verbose("---- tempFileUrl: \(tempFileUrl)")
            return tempFileUrl
        }

        func totalBytesDownloaded() throws -> UInt64 {
            let tempFileUrls = lock.withLock {
                self.tempFileUrls
            }
            var count: UInt64 = 0
            for url in tempFileUrls {
                guard OWSFileSystem.fileOrFolderExists(url: url) else {
                    Logger.verbose("---- tempFileUrl: \(url) doesn't exist")
                    continue
                }
                guard let nsFileSize: NSNumber = OWSFileSystem.fileSize(of: url) else {
                    throw OWSAssertionError("Can't determine length of file.")
                }
                Logger.verbose("---- nsFileSize.uint64Value: \(nsFileSize.uint64Value)")
                count += nsFileSize.uint64Value
            }
            return count
        }

        func mergeFileUrls() throws -> URL {
            guard let contentLength = contentLength.get() else {
                throw OWSAssertionError("Missing contentLength.")
            }
            Logger.verbose("---- contentLength: \(contentLength)")

            // Collect the segment files, discarding any empty files.
            let tempFileUrls = lock.withLock {
                self.tempFileUrls
            }
            let fileUrlsAndSizes = try tempFileUrls.compactMap { (url: URL) -> (URL, UInt64)? in
                guard OWSFileSystem.fileOrFolderExists(url: url) else {
                    Logger.verbose("---- tempFileUrl: \(url) doesn't exist")
                    return nil
                }
                guard let nsFileSize: NSNumber = OWSFileSystem.fileSize(of: url) else {
                    throw OWSAssertionError("Can't determine length of file.")
                }
                let fileSize = nsFileSize.uint64Value
                guard fileSize > 0 else {
                    return nil
                }
                Logger.verbose("---- fileSize: \(fileSize)")
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
            guard joinedData.count == contentLength else {
                throw OWSAssertionError("Unexpected data size: \(joinedData.count) != \(contentLength)")
            }
            let joinedFileUrl = OWSFileSystem.temporaryFileUrl(isAvailableWhileDeviceLocked: true)
            try joinedData.write(to: joinedFileUrl)
            return joinedFileUrl
        }

        func deleteFileUrls() {
            let tempFileUrls = lock.withLock {
                self.tempFileUrls
            }
            for tempFileUrl in tempFileUrls {
                do {
                    try OWSFileSystem.deleteFileIfExists(url: tempFileUrl)
                } catch {
                    owsFailDebug("Error: \(error)")
                }
            }
        }
    }

    func test() {}

    private class func download(job: OWSAttachmentDownloadJob,
                                attachmentPointer: TSAttachmentPointer) -> Promise<URL> {

        Logger.verbose("---- starting download.")

        let downloadState = DownloadState(job: job, attachmentPointer: attachmentPointer)

        return firstly(on: .global()) { () -> Promise<UInt64> in
            self.getContentLength(downloadState: downloadState)
        }.then(on: .global()) { (contentLength: UInt64) -> Promise<Void> in
            guard contentLength > 0 else {
                throw OWSAssertionError("Empty attachment.")
            }
            guard contentLength <= Self.maxDownloadSize else {
                throw OWSAssertionError("Attachment download length exceeds max size.")
            }
            downloadState.contentLength.set(contentLength)

            return Self.downloadAttempt(downloadState: downloadState)
        }.map(on: .global()) { () -> URL in
            try downloadState.mergeFileUrls()
        }.recover(on: .global()) { (error: Error) -> Promise<URL> in
            downloadState.deleteFileUrls()
            throw error
        }
    }

    private class func downloadAttempt(downloadState: DownloadState,
                                       resumeData: Data? = nil,
                                       attemptIndex: UInt = 0) -> Promise<Void> {

        return firstly(on: .global()) { () -> Promise<Void> in
            guard let contentLength = downloadState.contentLength.get() else {
                throw OWSAssertionError("Missing contentLength.")
            }
            let totalBytesDownloaded = try downloadState.totalBytesDownloaded()
            Logger.verbose("---- totalBytesDownloaded: \(totalBytesDownloaded)")
            guard totalBytesDownloaded < contentLength else {
                // Download is already complete.
                return Promise.value(())
            }

            // The amount of bytes to download during this attempt.
            let segmentStart = totalBytesDownloaded
            let segmentLength = contentLength - totalBytesDownloaded

            let attachmentPointer = downloadState.attachmentPointer
            let segmentUrl = downloadState.addTempFileUrl()

            let promise: Promise<Void> = firstly(on: .global()) { () -> Promise<URL> in
                let sessionManager = self.signalService.cdnSessionManager(forCdnNumber: attachmentPointer.cdnNumber)
                sessionManager.completionQueue = .global()

                let url = try Self.url(for: downloadState, sessionManager: sessionManager)
                let headers: [String: String] = [
                    "Content-Type": OWSMimeTypeApplicationOctetStream,
                    "Range": "bytes=\(segmentStart)-\(segmentStart + segmentLength - 1)"
                ]

                let progress = { (progress: Progress, task: URLSessionDownloadTask) in
                    Logger.verbose("---- progress: \(progress.fractionCompleted), \(progress.completedUnitCount)")
                    Self.handleDownloadProgress(downloadState: downloadState,
                                                task: task,
                                                segmentStart: segmentStart,
                                                segmentLength: segmentLength,
                                                contentLength: contentLength,
                                                progress: progress)
                }

                if let resumeData = resumeData {
                    return sessionManager.resumeDownloadTaskPromise(resumeData: resumeData,
                                                                    dstFileUrl: segmentUrl,
                                                                    progress: progress)
                } else {
                    return sessionManager.downloadTaskPromise(url.absoluteString,
                                                              verb: .get,
                                                              headers: headers,
                                                              dstFileUrl: segmentUrl,
                                                              progress: progress)
                }
            }.map(on: .global()) { (completionUrl: URL) in
                if segmentUrl != completionUrl {
                    throw OWSAssertionError("Unexpected temp file path.")
                }
                guard let fileSize = OWSFileSystem.fileSize(of: segmentUrl) else {
                    throw OWSAssertionError("Could not determine attachment file size.")
                }
                guard fileSize.int64Value <= Self.maxDownloadSize else {
                    throw OWSAssertionError("Attachment download length exceeds max size.")
                }
            }.recover(on: .global()) { (error: Error) -> Promise<Void> in
                Logger.warn("Error: \(error)")

                let maxAttemptCount = 16
                if IsNetworkConnectivityFailure(error),
                    attemptIndex < maxAttemptCount {

                    return firstly {
                        // Wait briefly before trying.
                        after(seconds: 1.0)
                    }.then { () -> Promise<Void> in
                        if let resumeData = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data,
                            !resumeData.isEmpty {
                            Logger.verbose("---- resumeData: \(resumeData.count)")
                            return self.downloadAttempt(downloadState: downloadState, resumeData: resumeData, attemptIndex: attemptIndex + 1)
                        } else {
                            return self.downloadAttempt(downloadState: downloadState, attemptIndex: attemptIndex + 1)
                        }
                    }

//                    let didUploadAnyBytes = { () -> Bool in
//                        guard OWSFileSystem.fileOrFolderExists(url: segmentUrl) else {
//                            return false
//                        }
//                        guard let fileSize = OWSFileSystem.fileSize(of: segmentUrl) else {
//                            owsFailDebug("Can't determine size of file segment.")
//                            return false
//                        }
//                        return fileSize.uint64Value > 0
//                    }()
//
//                    if didUploadAnyBytes {
//                        Logger.warn("Retrying download immediately: \(attemptIndex)")
//                        return self.downloadAttempt(downloadState: downloadState, attemptIndex: attemptIndex + 1)
//                    } else {
//                        Logger.warn("Retrying download after delay: \(attemptIndex)")
//                        return firstly {
//                            // TODO:
//                            after(seconds: 5.0)
//                        }.then {
//                            self.downloadAttempt(downloadState: downloadState, attemptIndex: attemptIndex + 1)
//                        }
//                    }
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

    private class func url(for downloadState: DownloadState,
                           sessionManager: AFHTTPSessionManager) throws -> URL {

        let attachmentPointer = downloadState.attachmentPointer
        let urlPath: String
        if attachmentPointer.cdnKey.count > 0 {
            urlPath = "attachments/(attachmentPointer.cdnKey.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed))"
        } else {
            urlPath = String(format: "attachments/%llu", attachmentPointer.serverId)
        }
        guard let url = URL(string: urlPath, relativeTo: sessionManager.baseURL) else {
            throw OWSAssertionError("Invalid URL.")
        }
        return url
    }

    private class func getContentLength(downloadState: DownloadState,
                                        attemptIndex: UInt = 0) -> Promise<UInt64> {

        return firstly(on: .global()) { () -> Promise<OWSURLSession.Response> in
            let attachmentPointer = downloadState.attachmentPointer
            let sessionManager = self.signalService.cdnSessionManager(forCdnNumber: attachmentPointer.cdnNumber)
            let url = try Self.url(for: downloadState, sessionManager: sessionManager)
            let urlSession = OWSURLSession()
            return urlSession.dataTaskPromise(url.absoluteString, verb: .head)
        }.map(on: .global()) { (response: HTTPURLResponse, _: Data?) -> UInt64 in
            let statusCode = response.statusCode
            guard statusCode >= 200 && statusCode < 300 else {
                throw OWSAssertionError("Invalid statusCode: \(statusCode)")
            }
            for (key, value) in response.allHeaderFields {
                guard let keyString = key as? String else {
                    owsFailDebug("Invalid header: \(key) \(type(of: key))")
                    continue
                }
                guard let valueString = value as? String else {
                    owsFailDebug("Invalid header: \(value) \(type(of: value))")
                    continue
                }
                if keyString.lowercased() == "content-length" {
                    guard let length = UInt64(valueString) else {
                        throw OWSAssertionError("Invalid content length: \(valueString)")
                    }
                    return length
                }
            }
            throw OWSAssertionError("Missing content length.")
        }.recover(on: .global()) { (error: Error) -> Promise<UInt64> in
            Logger.warn("Error: \(error)")
            let maxAttemptCount = 3
            if IsNetworkConnectivityFailure(error),
                attemptIndex < maxAttemptCount {
                Logger.warn("Retrying download: \(attemptIndex)")
                return self.getContentLength(downloadState: downloadState, attemptIndex: attemptIndex + 1)
            } else {
                throw error
            }
        }
    }

    private class func handleDownloadProgress(downloadState: DownloadState,
                                              task: URLSessionDownloadTask,
                                              segmentStart: UInt64,
                                              segmentLength: UInt64,
                                              contentLength: UInt64,
                                              progress: Progress) {
        // Don't do anything until we've received at least one byte of data.
        guard progress.completedUnitCount > 0 else {
            return
        }

        guard progress.totalUnitCount <= segmentLength,
            progress.completedUnitCount <= segmentLength else {
                // A malicious service might send a misleading content length header,
                // so....
                //
                // If the current downloaded bytes or the expected total byes
                // exceed the max download size, abort the download.
                owsFailDebug("Attachment download exceed expected content length: \(progress.totalUnitCount), \(progress.completedUnitCount).")
                task.cancel()
                return
        }

        // The _file_ progress needs to reflect the progress from previous attempts
        // as well as the progress from the current attempt.
        let fileProgress = ((Double(segmentStart) + Double(segmentLength) * progress.fractionCompleted) / Double(contentLength)).clamp01()

        downloadState.job.progress = CGFloat(fileProgress)

        // Use a slightly non-zero value to ensure that the progress
        // indicator shows up as quickly as possible.
        let progressTheta: Double = 0.001
        Self.fireProgressNotification(progress: max(progressTheta, fileProgress),
                                      attachmentId: downloadState.attachmentPointer.uniqueId)
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
