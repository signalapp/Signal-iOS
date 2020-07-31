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

    private class func download(job: OWSAttachmentDownloadJob,
                                attachmentPointer: TSAttachmentPointer) -> Promise<URL> {

        return firstly(on: .global()) { () -> Promise<URL> in
            let sessionManager = self.signalService.cdnSessionManager(forCdnNumber: attachmentPointer.cdnNumber)
            sessionManager.completionQueue = .global()
            let urlPath: String
            if attachmentPointer.cdnKey.count > 0 {
                urlPath = "attachments/(attachmentPointer.cdnKey.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed))"
            } else {
                urlPath = String(format: "attachments/%llu", attachmentPointer.serverId)
            }
            guard let url = URL(string: urlPath, relativeTo: sessionManager.baseURL) else {
                throw OWSAssertionError("Invalid URL.")
            }

            var hasCheckedContentLength = false

            let tempDirPath = OWSTemporaryDirectoryAccessibleAfterFirstAuth()
            let tempFilePath = (tempDirPath as NSString).appendingPathComponent(UUID().uuidString)
            let tempFileURL = URL(fileURLWithPath: tempFilePath)

            var taskReference: URLSessionDownloadTask?

            let method = "GET"
            var nsError: NSError?
            let request = sessionManager.requestSerializer.request(withMethod: method,
                                                                   urlString: url.absoluteString,
                                                                   parameters: nil,
                                                                   error: &nsError)
            if let error = nsError {
                throw error
            }
            request.setValue(OWSMimeTypeApplicationOctetStream, forHTTPHeaderField: "Content-Type")

            let (promise, resolver) = Promise<URL>.pending()
            let task = sessionManager.downloadTask(with: request as URLRequest,
                                                   progress: { (progress: Progress) in
                                                    Self.handleDownloadProgress(job: job,
                                                                                attachmentPointer: attachmentPointer,
                                                                                progress: progress,
                                                                                task: taskReference,
                                                                                hasCheckedContentLength: &hasCheckedContentLength)
            },
                                                   destination: { (_: URL, _: URLResponse) -> URL in
                                                    tempFileURL
            },
                                                   completionHandler: { (_: URLResponse, completionUrl: URL?, error: Error?) in
                                                    if let error = error {
                                                        resolver.reject(error)
                                                        return
                                                    }
                                                    if tempFileURL != completionUrl {
                                                        resolver.reject(OWSAssertionError("Unexpected temp file path."))
                                                        return
                                                    }
                                                    guard let fileSize = OWSFileSystem.fileSize(of: tempFileURL) else {
                                                        resolver.reject(OWSAssertionError("Could not determine attachment file size."))
                                                        return
                                                    }
                                                    guard fileSize.int64Value <= Self.maxDownloadSize else {
                                                        resolver.reject(OWSAssertionError("Attachment download length exceeds max size."))
                                                        return
                                                    }
                                                    resolver.fulfill(tempFileURL)
            })
            taskReference = task
            task.resume()

            promise.catch(on: .global()) { (error: Error) in
                OWSFileSystem.deleteFileIfExists(tempFilePath)

                if attachmentPointer.serverId < 100 {
                    // This looks like the symptom of the "frequent 404
                    // downloading attachments with low server ids".
                    guard let httpResponse = task.response as? HTTPURLResponse else {
                        owsFailDebug("Invalid response.")
                        return
                    }
                    owsFailDebug("\(httpResponse.statusCode) Failure with suspicious attachment id: \(attachmentPointer.serverId), \(error)")
                }
            }

            return promise
        }
    }

    private class func handleDownloadProgress(job: OWSAttachmentDownloadJob,
                                              attachmentPointer: TSAttachmentPointer,
                                              progress: Progress,
                                              task: URLSessionDownloadTask?,
                                              hasCheckedContentLength: inout Bool) {
        guard let task = task else {
            owsFailDebug("Missing task.")
            return
        }
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

        job.progress = CGFloat(progress.fractionCompleted)

        Self.fireProgressNotification(progress: max(progressTheta, progress.fractionCompleted),
                                 attachmentId: attachmentPointer.uniqueId)

        // We only need to check the content length header once.
        guard !hasCheckedContentLength else {
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
        hasCheckedContentLength = true
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
