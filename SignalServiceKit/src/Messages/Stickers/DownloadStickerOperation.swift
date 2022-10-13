//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

class DownloadStickerOperation: CDNDownloadOperation {

    // MARK: - Cache

    private static let cache = LRUCache<String, URL>(maxSize: 256)

    public class func cachedUrl(for stickerInfo: StickerInfo) -> URL? {
        guard let stickerUrl = cache.object(forKey: stickerInfo.asKey()) else {
            return nil
        }
        guard OWSFileSystem.fileOrFolderExists(url: stickerUrl) else { return nil }
        return stickerUrl
    }

    private class func setCachedUrl(_ url: URL, for stickerInfo: StickerInfo) {
        cache.setObject(url, forKey: stickerInfo.asKey())
    }

    // MARK: -

    private let stickerInfo: StickerInfo
    private let success: (URL) -> Void
    private let failure: (Error) -> Void

    @objc
    public required init(
        stickerInfo: StickerInfo,
        success: @escaping (URL) -> Void,
        failure: @escaping (Error) -> Void
    ) {
        assert(stickerInfo.packId.count > 0)
        assert(stickerInfo.packKey.count > 0)

        self.stickerInfo = stickerInfo
        self.success = success
        self.failure = failure

        super.init()
    }

    override public func run() {
        if let stickerUrl = DownloadStickerOperation.cachedUrl(for: stickerInfo) {
            Logger.verbose("Using cached value: \(stickerInfo).")
            success(stickerUrl)
            self.reportSuccess()
            return
        }

        if let stickerUrl = loadInstalledStickerUrl() {
            Logger.verbose("Skipping redundant operation: \(stickerInfo).")
            success(stickerUrl)
            self.reportSuccess()
            return
        }

        Logger.verbose("Downloading sticker: \(stickerInfo).")

        // https://cdn.signal.org/stickers/<pack_id>/full/<sticker_id>
        let urlPath = "stickers/\(stickerInfo.packId.hexadecimalString)/full/\(stickerInfo.stickerId)"

        firstly {
            return try tryToDownload(urlPath: urlPath, maxDownloadSize: kMaxStickerDataDownloadSize)
        }.done(on: DispatchQueue.global()) { [weak self] (url: URL) in
            guard let self = self else {
                return
            }

            do {
                let url = try StickerManager.decrypt(at: url, packKey: self.stickerInfo.packKey)

                DownloadStickerOperation.setCachedUrl(url, for: self.stickerInfo)

                self.success(url)

                self.reportSuccess()
            } catch {
                owsFailDebug("Decryption failed: \(error)")

                self.markUrlPathAsCorrupt(urlPath)

                // Fail immediately; do not retry.
                return self.reportError(SSKUnretryableError.stickerDecryptionFailure)
            }
        }.catch(on: DispatchQueue.global()) { [weak self] error in
            guard let self = self else {
                return
            }
            return self.reportError(withUndefinedRetry: error)
        }
    }

    private func loadInstalledStickerUrl() -> URL? {
        return StickerManager.stickerDataUrlWithSneakyTransaction(stickerInfo: stickerInfo, verifyExists: true)
    }

    override public func didFail(error: Error) {
        Logger.error("Download exhausted retries: \(error)")

        failure(error)
    }
}
