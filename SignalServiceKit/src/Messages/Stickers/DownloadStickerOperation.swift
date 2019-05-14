//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

class DownloadStickerOperation: OWSOperation {

    private let stickerInfo: StickerInfo
    private let success: (Data) -> Void
    private let failure: (Error) -> Void
    private var task: URLSessionDownloadTask?

    @objc public required init(stickerInfo: StickerInfo,
                               success : @escaping (Data) -> Void,
                               failure : @escaping (Error) -> Void) {
        assert(stickerInfo.packId.count > 0)
        assert(stickerInfo.packKey.count > 0)

        self.stickerInfo = stickerInfo
        self.success = success
        self.failure = failure

        super.init()

        self.remainingRetries = 4
    }

    deinit {
        task?.cancel()
    }

    // MARK: Dependencies

    private var cdnSessionManager: AFHTTPSessionManager {
        return OWSSignalService.sharedInstance().cdnSessionManager
    }

    override public func run() {
        if let filePath = StickerManager.filepathForInstalledSticker(stickerInfo: stickerInfo) {
            do {
                let stickerData = try Data(contentsOf: URL(fileURLWithPath: filePath))
                Logger.verbose("Skipping redundant operation: \(stickerInfo).")
                success(stickerData)
                self.reportSuccess()
                return
            } catch let error as NSError {
                owsFailDebug("Could not load installed sticker data: \(error)")
                // Fall through and proceed with download.
            }
        }

        Logger.verbose("Downloading sticker: \(stickerInfo).")

        // https://cdn.signal.org/stickers/<pack_id>/full/<sticker_id>
        let urlPath = "stickers/\(stickerInfo.packId.hexadecimalString)/full/\(stickerInfo.stickerId)"
        guard let baseUrl = cdnSessionManager.baseURL else {
            owsFailDebug("Missing baseUrl.")
            var error = StickerError.assertionFailure
            error.isRetryable = false
            return self.reportError(error)
        }
        guard let url = URL(string: urlPath, relativeTo: baseUrl) else {
            owsFailDebug("Invalid url.")
            var error = StickerError.assertionFailure
            error.isRetryable = false
            return self.reportError(error)
        }

        var errorPointer: NSError?
        let request = cdnSessionManager.requestSerializer.request(withMethod: "GET",
                                                                  urlString: url.absoluteString,
                                                                  parameters: nil,
                                                                  error: &errorPointer)
        if let errorPointer = errorPointer {
            owsFailDebug("Could not create request failed: \(errorPointer)")
            errorPointer.isRetryable = false
            return self.reportError(errorPointer)
        }
        request.setValue(OWSMimeTypeApplicationOctetStream, forHTTPHeaderField: "Content-Type")

        let tempDirPath = OWSTemporaryDirectoryAccessibleAfterFirstAuth()
        let tempFilePath = (tempDirPath as NSString).appendingPathComponent(UUID().uuidString)
        let tempFileURL = URL(fileURLWithPath: tempFilePath)

        let kMaxDownloadSize: UInt = 100 * 1000
        var hasCheckedContentLength = false
        let task = cdnSessionManager.downloadTask(with: request as URLRequest,
                                                  progress: { [weak self] (progress) in
                                                    guard let self = self else {
                                                        return
                                                    }
                                                    guard let task = self.task else {
                                                        return
                                                    }

                                                    // Don't do anything until we've received at least one byte of data.
                                                    guard progress.completedUnitCount > 0 else {
                                                        return
                                                    }

                                                    let abortDownload = { (message: String) -> Void in
                                                        owsFailDebug(message)
                                                        task.cancel()
                                                    }

                                                    // A malicious service might send a misleading content length header,
                                                    // so....
                                                    //
                                                    // If the current downloaded bytes or the expected total byes
                                                    // exceed the max download size, abort the download.
                                                    guard progress.totalUnitCount <= kMaxDownloadSize,
                                                        progress.completedUnitCount <= kMaxDownloadSize else {
                                                        return abortDownload("Attachment download exceed expected content length: \(progress.totalUnitCount), \(progress.completedUnitCount).")
                                                    }

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
                                                        return abortDownload("Invalid or missing response.")
                                                    }
                                                    guard let headers = httpResponse.allHeaderFields as? [String: Any] else {
                                                        return abortDownload("Invalid response headers.")
                                                    }
                                                    guard let contentLengthString = headers["Content-Length"] as? String else {
                                                        return abortDownload("Invalid or missing content length.")
                                                    }
                                                    guard let contentLength = Int64(contentLengthString) else {
                                                        return abortDownload("Invalid content length.")
                                                    }
                                                    guard contentLength < kMaxDownloadSize else {
                                                        return abortDownload("Content length exceeds max download size.")
                                                    }

                                                    // This response has a valid content length that is less
                                                    // than our max download size.  Proceed with the download.
                                                    hasCheckedContentLength = true
        },
                                                  destination: { (_, _) -> URL in
                                                    return tempFileURL
        },
                                                  completionHandler: { [weak self] (_, completionUrl, error) in
                                                    guard let self = self else {
                                                        return
                                                    }
                                                    if let error = error {
                                                        owsFailDebug("Download failed: \(error)")
                                                        let errorCopy = error as NSError
                                                        errorCopy.isRetryable = !errorCopy.hasFatalResponseCode()
                                                        return self.reportError(errorCopy)
                                                    }
                                                    guard completionUrl == tempFileURL else {
                                                        owsFailDebug("Unexpected temp file path.")
                                                        var error = StickerError.assertionFailure
                                                        error.isRetryable = false
                                                        return self.reportError(error)
                                                    }
                                                    guard let fileSize = OWSFileSystem.fileSize(ofPath: tempFilePath) else {
                                                        owsFailDebug("Couldn't determine file size.")
                                                        var error = StickerError.assertionFailure
                                                        error.isRetryable = false
                                                        return self.reportError(error)
                                                    }
                                                    guard fileSize.uint64Value <= kMaxDownloadSize else {
                                                        owsFailDebug("Download length exceeds max size.")
                                                        var error = StickerError.assertionFailure
                                                        error.isRetryable = false
                                                        return self.reportError(error)
                                                    }

                                                    do {
                                                        let data = try Data(contentsOf: tempFileURL)
                                                        let plaintext = try StickerManager.decrypt(ciphertext: data, packKey: self.stickerInfo.packKey)

                                                        self.success(plaintext)
                                                        self.reportSuccess()
                                                    } catch let error as NSError {
                                                        owsFailDebug("Decryption failed: \(error)")

                                                        // Fail immediately; do not retry.
                                                        error.isRetryable = false
                                                        return self.reportError(error)
                                                    }
        })
        self.task = task
        task.resume()
    }

    override public func didFail(error: Error) {
        Logger.error("Download exhausted retries: \(error)")

        failure(error)
    }

    override public func retryInterval() -> TimeInterval {
        // Arbitrary backoff factor...
        // With backOffFactor of 1.9
        // try  1 delay:  0.00s
        // try  2 delay:  0.19s
        // ...
        // try  5 delay:  1.30s
        // ...
        // try 11 delay: 61.31s
        let backoffFactor = 1.9
        let maxBackoff = kHourInterval

        let seconds = 0.1 * min(maxBackoff, pow(backoffFactor, Double(self.errorCount)))
        return seconds
    }
}
