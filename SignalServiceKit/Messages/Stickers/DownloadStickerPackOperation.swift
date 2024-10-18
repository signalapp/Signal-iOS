//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

enum DownloadStickerPackOperation {
    static func run(stickerPackInfo: StickerPackInfo) async throws -> StickerPack {
        return try await Retry.performWithBackoff(maxAttempts: 4) {
            return try await self._run(stickerPackInfo: stickerPackInfo)
        }
    }

    private static func _run(stickerPackInfo: StickerPackInfo) async throws -> StickerPack {
        owsAssertDebug(stickerPackInfo.packId.count > 0)
        owsAssertDebug(stickerPackInfo.packKey.count > 0)

        if let stickerPack = StickerManager.fetchStickerPack(stickerPackInfo: stickerPackInfo) {
            return stickerPack
        }

        // https://cdn.signal.org/stickers/<pack_id>/manifest.proto
        let urlPath = "stickers/\(stickerPackInfo.packId.hexadecimalString)/manifest.proto"

        do {
            let encryptedFileUrl: URL = try await CDNDownloadOperation.tryToDownload(
                urlPath: urlPath,
                maxDownloadSize: CDNDownloadOperation.kMaxStickerPackDownloadSize
            )
            do {
                let decryptedFileUrl = try StickerManager.decrypt(at: encryptedFileUrl, packKey: stickerPackInfo.packKey)
                let manifestData = try Data(contentsOf: decryptedFileUrl)

                return try self.parseStickerPackManifest(
                    stickerPackInfo: stickerPackInfo,
                    manifestData: manifestData
                )
            } catch {
                owsFailDebug("Decryption failed: \(error)")
                CDNDownloadOperation.markUrlPathAsCorrupt(urlPath)
                // Fail immediately; do not retry.
                throw SSKUnretryableError.stickerDecryptionFailure
            }
        } catch {
            if error.hasFatalHttpStatusCode() {
                StickerManager.markStickerPackAsMissing(stickerPackInfo: stickerPackInfo)
            }
            throw error
        }
    }

    private static func parseStickerPackManifest(stickerPackInfo: StickerPackInfo, manifestData: Data) throws -> StickerPack {
        owsAssertDebug(manifestData.count > 0)

        let manifestProto: SSKProtoPack
        do {
            manifestProto = try SSKProtoPack(serializedData: manifestData)
        } catch let error as NSError {
            owsFailDebug("Couldn't parse protos: \(error)")
            throw StickerError.invalidInput
        }
        let title = parseOptionalString(manifestProto.title)
        let author = parseOptionalString(manifestProto.author)
        let manifestCover = parsePackItem(manifestProto.cover)
        var items = [StickerPackItem]()
        for stickerProto in manifestProto.stickers {
            if let item = parsePackItem(stickerProto) {
                items.append(item)
            }
        }
        guard let firstItem = items.first else {
            owsFailDebug("Invalid manifest, no stickers")
            throw StickerError.invalidInput
        }
        let cover = manifestCover ?? firstItem

        let stickerPack = StickerPack(info: stickerPackInfo, title: title, author: author, cover: cover, stickers: items)
        return stickerPack
    }

    private static func parseOptionalString(_ value: String?) -> String? {
        return value?.ows_stripped().nilIfEmpty
    }

    private static func parsePackItem(_ proto: SSKProtoPackSticker?) -> StickerPackItem? {
        guard let proto else {
            return nil
        }
        let stickerId = proto.id
        let emojiString = parseOptionalString(proto.emoji) ?? ""
        let contentType = parseOptionalString(proto.contentType) ?? ""
        return StickerPackItem(stickerId: stickerId, emojiString: emojiString, contentType: contentType)
    }
}
