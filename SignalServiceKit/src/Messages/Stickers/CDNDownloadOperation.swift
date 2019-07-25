//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

class CDNDownloadOperation: OWSOperation {

    // MARK: - Dependencies

    private var cdnSessionManager: AFHTTPSessionManager {
        return OWSSignalService.sharedInstance().cdnSessionManager
    }

    // MARK: -

    private var task: URLSessionDownloadTask?

    private var tempFilePath: String?

    public override init() {
        super.init()

        self.remainingRetries = 4
    }

    deinit {
        task?.cancel()

        if let tempFilePath = tempFilePath {
            DispatchQueue.global(qos: .background).async {
                OWSFileSystem.deleteFileIfExists(tempFilePath)
            }
        }
    }

    let kMaxStickerDownloadSize: UInt = 100 * 1000

    func tryToDownload(urlPath: String, maxDownloadSize: UInt) throws -> Promise<Data> {
        guard !isCorrupt(urlPath: urlPath) else {
            Logger.warn("Skipping download of corrupt data.")
            throw StickerError.corruptData
        }
        guard let baseUrl = cdnSessionManager.baseURL else {
            owsFailDebug("Missing baseUrl.")
            throw StickerError.assertionFailure
        }
        guard let url = URL(string: urlPath, relativeTo: baseUrl) else {
            owsFailDebug("Invalid url.")
            throw StickerError.assertionFailure
        }

        var requestError: NSError?
        let request = cdnSessionManager.requestSerializer.request(withMethod: "GET",
                                                                  urlString: url.absoluteString,
                                                                  parameters: nil,
                                                                  error: &requestError)
        if let error = requestError {
            owsFailDebug("Could not create request failed: \(error)")
            error.isRetryable = false
            throw error
        }
        request.setValue(OWSMimeTypeApplicationOctetStream, forHTTPHeaderField: "Content-Type")

        let tempDirPath = OWSTemporaryDirectoryAccessibleAfterFirstAuth()
        let tempFilePath = (tempDirPath as NSString).appendingPathComponent(UUID().uuidString)
        self.tempFilePath = tempFilePath
        let tempFileURL = URL(fileURLWithPath: tempFilePath)

        var hasCheckedContentLength = false
        let (promise, resolver) = Promise<Data>.pending()
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
                                                        resolver.reject(StickerError.assertionFailure)
                                                    }

                                                    // A malicious service might send a misleading content length header,
                                                    // so....
                                                    //
                                                    // If the current downloaded bytes or the expected total byes
                                                    // exceed the max download size, abort the download.
                                                    guard progress.totalUnitCount <= maxDownloadSize,
                                                        progress.completedUnitCount <= maxDownloadSize else {
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
                                                    guard contentLength < maxDownloadSize else {
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
                                                    guard let _ = self else {
                                                        return
                                                    }
                                                    if let error = error {
                                                        owsFailDebug("Download failed: \(error)")
                                                        let errorCopy = error as NSError
                                                        errorCopy.isRetryable = !errorCopy.hasFatalResponseCode()
                                                        return resolver.reject(errorCopy)
                                                    }
                                                    guard completionUrl == tempFileURL else {
                                                        owsFailDebug("Unexpected temp file path.")
                                                        return resolver.reject(StickerError.assertionFailure)
                                                    }
                                                    guard let fileSize = OWSFileSystem.fileSize(ofPath: tempFilePath) else {
                                                        owsFailDebug("Couldn't determine file size.")
                                                        return resolver.reject(StickerError.assertionFailure)
                                                    }
                                                    guard fileSize.uint64Value <= maxDownloadSize else {
                                                        owsFailDebug("Download length exceeds max size.")
                                                        return resolver.reject(StickerError.assertionFailure)
                                                    }

                                                    do {
                                                        let data = try Data(contentsOf: tempFileURL)
                                                        resolver.fulfill(data)
                                                    } catch let error as NSError {
                                                        owsFailDebug("Could not load data failed: \(error)")

                                                        // Fail immediately; do not retry.
                                                        error.isRetryable = false
                                                        return resolver.reject(error)
                                                    }
        })
        self.task = task
        task.resume()
        return promise
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

    // MARK: - Corrupt Data

    // We track corrupt downloads, to avoid retrying them more than once per launch.
    //
    // TODO: We could persist this state.
    private static let serialQueue = DispatchQueue(label: "org.signal.cdnDownloadOperation")
    private static var corruptDataKeys = Set<String>()

    func markUrlPathAsCorrupt(_ urlPath: String) {
        _ = CDNDownloadOperation.serialQueue.sync {
            CDNDownloadOperation.corruptDataKeys.insert(urlPath)
        }
    }

    func isCorrupt(urlPath: String) -> Bool {
        var result = false
        CDNDownloadOperation.serialQueue.sync {
            result = CDNDownloadOperation.corruptDataKeys.contains(urlPath)
        }
        return result
    }
}
