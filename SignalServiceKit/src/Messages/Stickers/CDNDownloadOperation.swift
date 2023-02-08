//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

open class CDNDownloadOperation: OWSOperation {

    // MARK: - Dependencies

    private var cdn0urlSession: OWSURLSessionProtocol {
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

    public func tryToDownload(urlPath: String, maxDownloadSize: UInt?) throws -> Promise<URL> {
        guard !isCorrupt(urlPath: urlPath) else {
            Logger.warn("Skipping download of corrupt data.")
            throw StickerError.corruptData
        }

        // We use a separate promise so that we can cancel from the progress block.
        let (promise, future) = Promise<URL>.pending()

        let hasCheckedContentLength = AtomicBool(false)
        firstly(on: DispatchQueue.global()) { () -> Promise<OWSUrlDownloadResponse> in
            let headers = ["Content-Type": OWSMimeTypeApplicationOctetStream]
            let urlSession = self.cdn0urlSession
            return urlSession.downloadTaskPromise(urlPath,
                                                  method: .get,
                                                  headers: headers) { [weak self] (task: URLSessionTask, progress: Progress) in
                guard let self = self else {
                    return
                }
                self.task = task
                self.handleDownloadProgress(task: task,
                                            progress: progress,
                                            future: future,
                                            maxDownloadSize: maxDownloadSize,
                                            hasCheckedContentLength: hasCheckedContentLength)
            }
        }.map(on: DispatchQueue.global()) { [weak self] (response: OWSUrlDownloadResponse) -> Void in
            guard self != nil else {
                throw OWSAssertionError("Operation has been deallocated.")
            }
            let downloadUrl = response.downloadUrl
            guard let fileSize = OWSFileSystem.fileSize(of: downloadUrl) else {
                owsFailDebug("Couldn't determine file size.")
                throw SSKUnretryableError.stickerMissingFile
            }
            if let maxDownloadSize = maxDownloadSize {
                guard fileSize.uint64Value <= maxDownloadSize else {
                    owsFailDebug("Download length exceeds max size.")
                    throw SSKUnretryableError.stickerOversizeFile
                }
            }

            do {
                let temporaryFileUrl = OWSFileSystem.temporaryFileUrl(isAvailableWhileDeviceLocked: true)
                try OWSFileSystem.moveFile(from: downloadUrl, to: temporaryFileUrl)
                future.resolve(temporaryFileUrl)
            } catch {
                owsFailDebug("Could not move to temporary file: \(error)")
                // Fail immediately; do not retry.
                throw SSKUnretryableError.downloadCouldNotMoveFile
            }
        }.catch(on: DispatchQueue.global()) { (error: Error) in
            Logger.warn("Download failed: \(error)")
            future.reject(error)
        }

        return promise
    }

    public func tryToDownload(urlPath: String, maxDownloadSize: UInt?) throws -> Promise<Data> {
        return try tryToDownload(urlPath: urlPath, maxDownloadSize: maxDownloadSize).map { (downloadUrl: URL) in
            do {
                let data = try Data(contentsOf: downloadUrl)
                try OWSFileSystem.deleteFile(url: downloadUrl)
                return data
            } catch {
                owsFailDebug("Could not load data failed: \(error)")
                // Fail immediately; do not retry.
                throw SSKUnretryableError.downloadCouldNotDeleteFile
            }
        }
    }

    private func handleDownloadProgress(task: URLSessionTask,
                                        progress: Progress,
                                        future: Future<URL>,
                                        maxDownloadSize: UInt?,
                                        hasCheckedContentLength: AtomicBool) {
        // Don't do anything until we've received at least one byte of data.
        guard progress.completedUnitCount > 0 else {
            return
        }

        let abortDownload = { (message: String) -> Void in
            owsFailDebug(message)
            future.reject(StickerError.assertionFailure)
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
