//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

class DownloadStickerPackOperation: OWSOperation {

    private let stickerPackInfo: StickerPackInfo
    private let success: (StickerPack) -> Void
    private let failure: (Error) -> Void

    @objc public required init(stickerPackInfo: StickerPackInfo,
                               success : @escaping (StickerPack) -> Void,
                               failure : @escaping (Error) -> Void) {
        assert(stickerPackInfo.packId.count > 0)
        assert(stickerPackInfo.packKey.count > 0)

        self.stickerPackInfo = stickerPackInfo
        self.success = success
        self.failure = failure

        super.init()

        self.remainingRetries = 10
    }

    // MARK: Dependencies

    private var cdnSessionManager: AFHTTPSessionManager {
        return OWSSignalService.sharedInstance().cdnSessionManager
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
        cdnSessionManager.get(urlPath,
                              parameters: nil,
                              progress: { (_) in
                                // Do nothing.
        },
                              success: { [weak self] (_, response) in
                                guard let self = self else {
                                    return
                                }
                                guard let data = response as? Data else {
                                    owsFailDebug("Unexpected response: \(type(of: response))")
                                    return
                                }

                                do {
                                    let plaintext = try StickerManager.decrypt(ciphertext: data, packKey: self.stickerPackInfo.packKey)

                                    let stickerPack = try self.parseStickerPackManifest(stickerPackInfo: self.stickerPackInfo,
                                                                                        manifestData: plaintext)

                                    self.success(stickerPack)
                                    self.reportSuccess()
                                } catch let error as NSError {
                                    owsFailDebug("Decryption failed: \(error)")

                                    // Fail immediately; do not retry.
                                    error.isRetryable = false
                                    return self.reportError(error)
                                }
            },
                              failure: { [weak self] (_, error) in
                                guard let self = self else {
                                    return
                                }
                                Logger.error("Download failed: \(error)")

                                let errorCopy = error as NSError

                                // We do not retry 4xx and 5xx.
                                errorCopy.isRetryable = !errorCopy.has4xxOr5xxResponseCode()

                                self.reportError(errorCopy)
        })
    }

    private func parseStickerPackManifest(stickerPackInfo: StickerPackInfo,
                                          manifestData: Data) throws -> StickerPack {
        assert(manifestData.count > 0)

        let manifestProto: SSKProtoPack
        do {
            manifestProto = try SSKProtoPack.parseData(manifestData)
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
        guard let value = value?.ows_stripped(), value.count > 0 else {
            return nil
        }
        return value
    }

    private func parsePackItem(_ proto: SSKProtoPackSticker?) -> StickerPackItem? {
        guard let proto = proto else {
            return nil
        }
        let stickerId = proto.id
        let emojiString = parseOptionalString(proto.emoji) ?? ""
        return StickerPackItem(stickerId: stickerId, emojiString: emojiString)
    }

    override public func didFail(error: Error) {
        Logger.error("Download exhausted retries: \(error)")

        failure(error)
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
}
