//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

open class CDNDownloadOperation: OWSOperation {

    // MARK: - Dependencies

    private func buildUrlSession(maxResponseSize: UInt) -> OWSURLSessionProtocol {
        signalService.urlSessionForCdn(cdnNumber: 0, maxResponseSize: maxResponseSize)
    }

    // MARK: -

    private let _task = AtomicOptional<URLSessionTask>(nil, lock: .sharedGlobal)
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

    public func tryToDownload(urlPath: String, maxDownloadSize: UInt) throws -> Promise<URL> {
        guard !isCorrupt(urlPath: urlPath) else {
            Logger.warn("Skipping download of corrupt data.")
            throw StickerError.corruptData
        }

        return firstly(on: DispatchQueue.global()) { () -> Promise<OWSUrlDownloadResponse> in
            let headers = ["Content-Type": MimeType.applicationOctetStream.rawValue]
            let urlSession = self.buildUrlSession(maxResponseSize: maxDownloadSize)
            return urlSession.downloadTaskPromise(urlPath,
                                                  method: .get,
                                                  headers: headers) { [weak self] (task: URLSessionTask, progress: Progress) in
                guard let self = self else {
                    return
                }
                self.task = task
            }
        }.map(on: DispatchQueue.global()) { [weak self] (response: OWSUrlDownloadResponse) -> URL in
            guard self != nil else {
                throw OWSAssertionError("Operation has been deallocated.")
            }
            let downloadUrl = response.downloadUrl
            do {
                let temporaryFileUrl = OWSFileSystem.temporaryFileUrl(isAvailableWhileDeviceLocked: true)
                try OWSFileSystem.moveFile(from: downloadUrl, to: temporaryFileUrl)
                return temporaryFileUrl
            } catch {
                owsFailDebug("Could not move to temporary file: \(error)")
                // Fail immediately; do not retry.
                throw SSKUnretryableError.downloadCouldNotMoveFile
            }
        }.recover(on: DispatchQueue.global()) { error -> Promise<URL> in
            Logger.warn("Download failed: \(error)")
            throw error
        }
    }

    public func tryToDownload(urlPath: String, maxDownloadSize: UInt) throws -> Promise<Data> {
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

    override public func retryInterval() -> TimeInterval {
        return OWSOperation.retryIntervalForExponentialBackoff(failureCount: errorCount)
    }

    // MARK: - Corrupt Data

    // We track corrupt downloads, to avoid retrying them more than once per launch.
    //
    // TODO: We could persist this state.
    private static let serialQueue = DispatchQueue(label: "org.signal.cdn-download")
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
