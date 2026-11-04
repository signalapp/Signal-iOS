//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol StickerDownloader {
    func downloadStickerPack(stickerPackInfo: StickerPackInfo) async throws -> StickerPackRecord
    func downloadSticker(stickerInfo: StickerInfo) async throws -> Data
}

class StickerDownloaderImpl: StickerDownloader {
    private let packOperationQueue = ConcurrentTaskQueue(concurrentLimit: 3)
    private let stickerDownloads = AtomicValue<[String: StickerDownload]>([:], lock: .init())

    private struct StickerDownload {
        let promise: Promise<Data>
        let future: Future<Data>

        init() {
            let (promise, future) = Promise<Data>.pending()
            self.promise = promise
            self.future = future
        }
    }

    private func tryToDownloadStickerPack(stickerPackInfo: StickerPackInfo) -> Promise<StickerPackRecord> {
        return Promise.wrapAsync { [packOperationQueue] in
            return try await packOperationQueue.runWithThrowingTask {
                return try await DownloadStickerPackOperation.run(stickerPackInfo: stickerPackInfo)
            }
        }
    }

    private func tryToDownloadSticker(stickerInfo: StickerInfo) -> Promise<Data> {
        let (stickerDownload, shouldStartTask) = stickerDownloads.update {
            if let stickerDownload = $0[stickerInfo.asKey()] {
                return (stickerDownload, false)
            }
            let stickerDownload = StickerDownload()
            $0[stickerInfo.asKey()] = stickerDownload
            return (stickerDownload, true)
        }
        if shouldStartTask {
            Task { [stickerDownloads] in
                let result = await Result {
                    try await DownloadStickerOperation.run(stickerInfo: stickerInfo)
                }
                stickerDownloads.update { $0.removeValue(forKey: stickerInfo.asKey()) }
                switch result {
                case .success(let stickerMetadata):
                    stickerDownload.future.resolve(stickerMetadata)
                case .failure(let error):
                    stickerDownload.future.reject(error)
                }
            }
        }
        return stickerDownload.promise
    }

    func downloadStickerPack(stickerPackInfo: StickerPackInfo) async throws -> StickerPackRecord {
        return try await tryToDownloadStickerPack(stickerPackInfo: stickerPackInfo).awaitable()
    }

    func downloadSticker(stickerInfo: StickerInfo) async throws -> Data {
        return try await tryToDownloadSticker(stickerInfo: stickerInfo).awaitable()
    }
}

#if TESTABLE_BUILD

public final class MockStickerDownloader: StickerDownloader {
    static let emojiString = "⭐️"
    /// Manifests returned by this mock list sticker ids `0..<manifestStickerCount`.
    static let manifestStickerCount: UInt32 = 64

    let stickerData: Data
    let packFetchCount = AtomicValue(0, lock: .init())
    let stickerFetchCount = AtomicValue(0, lock: .init())

    init(stickerData: Data) {
        self.stickerData = stickerData
    }

    public func downloadStickerPack(stickerPackInfo: StickerPackInfo) async throws -> StickerPackRecord {
        packFetchCount.update { $0 += 1 }
        let items = (0..<Self.manifestStickerCount).map {
            StickerPackItem(stickerId: $0, emojiString: Self.emojiString, contentType: MimeType.imagePng.rawValue)
        }
        return StickerPackRecord(info: stickerPackInfo, title: nil, author: nil, cover: items[0], items: items)
    }

    public func downloadSticker(stickerInfo: StickerInfo) async throws -> Data {
        stickerFetchCount.update { $0 += 1 }
        return stickerData
    }
}

#endif
