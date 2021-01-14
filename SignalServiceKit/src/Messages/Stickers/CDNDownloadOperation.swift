//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

open class CDNDownloadOperation: OWSOperation {

    // MARK: - Dependencies

    private var signalService: OWSSignalService {
        OWSSignalService.shared()
    }

    private var cdn0urlSession: OWSURLSession {
        signalService.urlSessionForCdn(cdnNumber: 0)
    }

    // MARK: -

    private let _task = AtomicOptional<URLSessionTask>(nil)
    private var task: URLSessionTask? {
        get {
            _task.get()
        }
        set {
            _task.set(newValue)
        }
    }

    public override init() {
        super.init()

        self.remainingRetries = 4
    }

    deinit {
        task?.cancel()
    }

    let kMaxStickerDataDownloadSize: UInt = 1000 * 1000
    let kMaxStickerPackDownloadSize: UInt = 1000 * 1000

    public func tryToDownload(urlPath: String, maxDownloadSize: UInt?) throws -> Promise<Data> {
        guard !isCorrupt(urlPath: urlPath) else {
            Logger.warn("Skipping download of corrupt data.")
            throw StickerError.corruptData
        }

        // We use a seperate promise so that we can cancel from the progress block.
        let (promise, resolver) = Promise<Data>.pending()

        let hasCheckedContentLength = AtomicBool(false)
        firstly(on: .global()) { () -> Promise<OWSUrlDownloadResponse> in
            let headers = ["Content-Type": OWSMimeTypeApplicationOctetStream]
            let urlSession = self.cdn0urlSession
            return urlSession.urlDownloadTaskPromise(urlPath,
                                                     method: .get,
                                                     headers: headers) { [weak self] (task: URLSessionTask, progress: Progress) in
                                                        guard let self = self else {
                                                            return
                                                        }
                                                        self.task = task
                                                        self.handleDownloadProgress(task: task,
                                                                                    progress: progress,
                                                                                    resolver: resolver,
                                                                                    maxDownloadSize: maxDownloadSize,
                                                                                    hasCheckedContentLength: hasCheckedContentLength)
            }
        }.recover(on: .global()) { (error: Error) -> Promise<OWSUrlDownloadResponse> in
            throw error.withDefaultRetry
        }.map(on: .global()) { [weak self] (response: OWSUrlDownloadResponse) -> Void in
            guard let _ = self else {
                throw OWSAssertionError("Operation has been deallocated.").asUnretryableError
            }
            let downloadUrl = response.downloadUrl
            guard let fileSize = OWSFileSystem.fileSize(of: downloadUrl) else {
                owsFailDebug("Couldn't determine file size.")
                throw StickerError.assertionFailure.asUnretryableError
            }
            if let maxDownloadSize = maxDownloadSize {
                guard fileSize.uint64Value <= maxDownloadSize else {
                    owsFailDebug("Download length exceeds max size.")
                    throw StickerError.assertionFailure.asUnretryableError
                }
            }

            do {
                let data = try Data(contentsOf: downloadUrl)
                try OWSFileSystem.deleteFile(url: downloadUrl)
                resolver.fulfill(data)
            } catch {
                owsFailDebug("Could not load data failed: \(error)")
                // Fail immediately; do not retry.
                throw error.asUnretryableError
            }
        }.catch(on: .global()) { (error: Error) in
            Logger.warn("Download failed: \(error)")
            resolver.reject(error)
        }

        return promise
    }

    private func handleDownloadProgress(task: URLSessionTask,
                                        progress: Progress,
                                        resolver: Resolver<Data>,
                                        maxDownloadSize: UInt?,
                                        hasCheckedContentLength: AtomicBool) {
        // Don't do anything until we've received at least one byte of data.
        guard progress.completedUnitCount > 0 else {
            return
        }

        let abortDownload = { (message: String) -> Void in
            owsFailDebug(message)
            resolver.reject(StickerError.assertionFailure)
            task.cancel()
        }

        // A malicious service might send a misleading content length header,
        // so....
        //
        // If the current downloaded bytes or the expected total byes
        // exceed the max download size, abort the download.
        if let maxDownloadSize = maxDownloadSize {
            guard progress.totalUnitCount <= maxDownloadSize,
                progress.completedUnitCount <= maxDownloadSize else {
                    return abortDownload("Attachment download exceed expected content length: \(progress.totalUnitCount), \(progress.completedUnitCount).")
            }
        }

        // We only need to check the content length header once.
        guard !hasCheckedContentLength.get() else {
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
        if let maxDownloadSize = maxDownloadSize {
            guard contentLength < maxDownloadSize else {
                return abortDownload("Content length exceeds max download size.")
            }
        }

        // This response has a valid content length that is less
        // than our max download size.  Proceed with the download.
        hasCheckedContentLength.set(true)
    }

    override public func retryInterval() -> TimeInterval {
        return OWSOperation.retryIntervalForExponentialBackoff(failureCount: errorCount)
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
