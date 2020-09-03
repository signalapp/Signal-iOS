//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

class DownloadStickerOperation: CDNDownloadOperation {

    // MARK: - Dependencies

    private var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    // MARK: - Cache

    private static let cache: NSCache<NSString, NSData> = {
        let cache = NSCache<NSString, NSData>()
        // Limits are imprecise/not strict.
        cache.countLimit = 50
        return cache
    }()
    private static let maxCacheDataLength: UInt = 100 * 1000

    public class func cachedData(for stickerInfo: StickerInfo) -> Data? {
        guard let stickerData = cache.object(forKey: stickerInfo.asKey() as NSString) else {
            return nil
        }
        return stickerData as Data
    }

    private class func setCachedData(_ data: Data,
                                     for stickerInfo: StickerInfo) {
        guard data.count <= maxCacheDataLength else {
            return
        }
        cache.setObject(data as NSData, forKey: stickerInfo.asKey() as NSString)
    }

    // MARK: -

    private let stickerInfo: StickerInfo
    private let success: (Data) -> Void
    private let failure: (Error) -> Void

    @objc public required init(stickerInfo: StickerInfo,
                               success : @escaping (Data) -> Void,
                               failure : @escaping (Error) -> Void) {
        assert(stickerInfo.packId.count > 0)
        assert(stickerInfo.packKey.count > 0)

        self.stickerInfo = stickerInfo
        self.success = success
        self.failure = failure

        super.init()
    }

    override public func run() {
        if let stickerData = DownloadStickerOperation.cachedData(for: stickerInfo) {
            Logger.verbose("Using cached value: \(stickerInfo).")
            success(stickerData)
            self.reportSuccess()
            return
        }

        if let stickerData = loadInstalledStickerData() {
            Logger.verbose("Skipping redundant operation: \(stickerInfo).")
            success(stickerData)
            self.reportSuccess()
            return
        }

        Logger.verbose("Downloading sticker: \(stickerInfo).")

        // https://cdn.signal.org/stickers/<pack_id>/full/<sticker_id>
        let urlPath = "stickers/\(stickerInfo.packId.hexadecimalString)/full/\(stickerInfo.stickerId)"

        firstly {
            return try tryToDownload(urlPath: urlPath, maxDownloadSize: kMaxStickerDataDownloadSize)
        }.done(on: DispatchQueue.global()) { [weak self] data in
            guard let self = self else {
                return
            }

            do {
                let plaintext = try StickerManager.decrypt(ciphertext: data, packKey: self.stickerInfo.packKey)

                DownloadStickerOperation.setCachedData(plaintext, for: self.stickerInfo)

                self.success(plaintext)

                self.reportSuccess()
            } catch {
                owsFailDebug("Decryption failed: \(error)")

                self.markUrlPathAsCorrupt(urlPath)

                // Fail immediately; do not retry.
                return self.reportError(error.asUnretryableError)
            }
        }.catch(on: DispatchQueue.global()) { [weak self] error in
            guard let self = self else {
                return
            }
            return self.reportError(withUndefinedRetry: error)
        }
    }

    private func loadInstalledStickerData() -> Data? {
        guard let stickerDataUrl = StickerManager.stickerDataUrlWithSneakyTransaction(stickerInfo: stickerInfo,
                                                                                      verifyExists: true) else {
                                                                                        return nil
        }
        do {
            return try Data(contentsOf: stickerDataUrl)
        } catch let error as NSError {
            owsFailDebug("Could not load installed sticker data: \(error)")
            return nil
        }
    }

    override public func didFail(error: Error) {
        Logger.error("Download exhausted retries: \(error)")

        failure(error)
    }
}
