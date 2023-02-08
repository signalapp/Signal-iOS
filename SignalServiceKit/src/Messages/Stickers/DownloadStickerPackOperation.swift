//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

class DownloadStickerPackOperation: CDNDownloadOperation {

    private let stickerPackInfo: StickerPackInfo
    private let success: (StickerPack) -> Void
    private let failure: (Error) -> Void

    @objc
    public required init(
        stickerPackInfo: StickerPackInfo,
        success: @escaping (StickerPack) -> Void,
        failure: @escaping (Error) -> Void
    ) {
        owsAssertDebug(stickerPackInfo.packId.count > 0)
        owsAssertDebug(stickerPackInfo.packKey.count > 0)

        self.stickerPackInfo = stickerPackInfo
        self.success = success
        self.failure = failure

        super.init()
    }

    override public func run() {

        if let stickerPack = StickerManager.fetchStickerPack(stickerPackInfo: stickerPackInfo) {
            Logger.verbose("Skipping redundant operation: \(stickerPackInfo).")
            success(stickerPack)
            self.reportSuccess()
            return
        }

        Logger.verbose("Downloading: \(stickerPackInfo).")

        // https://cdn.signal.org/stickers/<pack_id>/manifest.proto
        let urlPath = "stickers/\(stickerPackInfo.packId.hexadecimalString)/manifest.proto"

        firstly {
            try tryToDownload(urlPath: urlPath, maxDownloadSize: kMaxStickerPackDownloadSize)
        }.done(on: DispatchQueue.global()) { [weak self] (url: URL) in
            guard let self = self else {
                return
            }

            do {
                let url = try StickerManager.decrypt(at: url, packKey: self.stickerPackInfo.packKey)
                let plaintext = try Data(contentsOf: url)

                let stickerPack = try self.parseStickerPackManifest(stickerPackInfo: self.stickerPackInfo,
                                                                    manifestData: plaintext)

                self.success(stickerPack)
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
            if error.hasFatalHttpStatusCode() {
                StickerManager.markStickerPackAsMissing(stickerPackInfo: self.stickerPackInfo)
            }
            return self.reportError(withUndefinedRetry: error)
        }
    }

    private func parseStickerPackManifest(stickerPackInfo: StickerPackInfo,
                                          manifestData: Data) throws -> StickerPack {
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

    private func parseOptionalString(_ value: String?) -> String? {
        value?.ows_stripped().nilIfEmpty
    }

    private func parsePackItem(_ proto: SSKProtoPackSticker?) -> StickerPackItem? {
        guard let proto = proto else {
            return nil
        }
        let stickerId = proto.id
        let emojiString = parseOptionalString(proto.emoji) ?? ""
        let contentType = parseOptionalString(proto.contentType) ?? ""
        return StickerPackItem(stickerId: stickerId, emojiString: emojiString, contentType: contentType)
    }

    override public func didFail(error: Error) {
        Logger.error("Download exhausted retries: \(error)")

        failure(error)
    }
}
