//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

enum DownloadStickerOperation {

    // MARK: - Cache

    private static let cache = LRUCache<String, URL>(maxSize: 256)

    public static func cachedUrl(for stickerInfo: StickerInfo) -> URL? {
        guard let stickerUrl = cache.object(forKey: stickerInfo.asKey()) else {
            return nil
        }
        guard OWSFileSystem.fileOrFolderExists(url: stickerUrl) else { return nil }
        return stickerUrl
    }

    private static func setCachedUrl(_ url: URL, for stickerInfo: StickerInfo) {
        cache.setObject(url, forKey: stickerInfo.asKey())
    }

    public static func run(stickerInfo: StickerInfo) async throws -> URL {
        return try await Retry.performWithBackoff(maxAttempts: 4) {
            return try await _run(stickerInfo: stickerInfo)
        }
    }

    private static func _run(stickerInfo: StickerInfo) async throws -> URL {
        assert(stickerInfo.packId.count > 0)
        assert(stickerInfo.packKey.count > 0)

        if let stickerUrl = DownloadStickerOperation.cachedUrl(for: stickerInfo) {
            return stickerUrl
        }

        if let stickerUrl = loadInstalledStickerUrl(stickerInfo: stickerInfo) {
            return stickerUrl
        }

        // https://cdn.signal.org/stickers/<pack_id>/full/<sticker_id>
        let urlPath = "stickers/\(stickerInfo.packId.hexadecimalString)/full/\(stickerInfo.stickerId)"

        let encryptedFileUrl: URL = try await CDNDownloadOperation.tryToDownload(
            urlPath: urlPath,
            maxDownloadSize: CDNDownloadOperation.kMaxStickerDataDownloadSize
        )

        let decryptedFileUrl: URL
        do {
            decryptedFileUrl = try StickerManager.decrypt(at: encryptedFileUrl, packKey: stickerInfo.packKey)
        } catch {
            owsFailDebug("Decryption failed: \(error)")
            CDNDownloadOperation.markUrlPathAsCorrupt(urlPath)
            throw SSKUnretryableError.stickerDecryptionFailure
        }

        DownloadStickerOperation.setCachedUrl(decryptedFileUrl, for: stickerInfo)
        return decryptedFileUrl

    }

    private static func loadInstalledStickerUrl(stickerInfo: StickerInfo) -> URL? {
        return StickerManager.stickerDataUrlWithSneakyTransaction(stickerInfo: stickerInfo, verifyExists: true)
    }
}
