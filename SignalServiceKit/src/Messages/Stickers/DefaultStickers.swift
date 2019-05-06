//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

class DefaultStickerPack {
    public let info: StickerPackInfo
    public let shouldAutoInstall: Bool

    private init?(packIdHex: String, packKeyHex: String, shouldAutoInstall: Bool) {
        guard let packId = Data.data(fromHex: packIdHex) else {
            owsFailDebug("Invalid packId")
            return nil
        }
        assert(packId.count > 0)
        guard let packKey = Data.data(fromHex: packKeyHex) else {
            owsFailDebug("Invalid packKey")
            return nil
        }
        assert(packKey.count == StickerManager.packKeyLength)

        self.info = StickerPackInfo(packId: packId, packKey: packKey)
        self.shouldAutoInstall = shouldAutoInstall
    }

    private class func parseAll() -> [StickerPackInfo: DefaultStickerPack] {
        // TODO: Replace with production values.
        let packs = [
        DefaultStickerPack(packIdHex: "0123456789abcdef0123456789abcdef",
        packKeyHex: "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789",
        shouldAutoInstall: true),
        DefaultStickerPack(packIdHex: "aaaaaaaabbbbbbbb",
                           packKeyHex: "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789",
                           shouldAutoInstall: false),
        DefaultStickerPack(packIdHex: "aaaaaaaacccccccc",
                           packKeyHex: "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789",
                           shouldAutoInstall: true)
        ].compactMap { $0 }

        var result = [StickerPackInfo: DefaultStickerPack]()
        for pack in packs {
            result[pack.info] = pack
        }

        return result
    }

    private static let all = DefaultStickerPack.parseAll()

    static var packsToAutoInstall: [StickerPackInfo] {
        return all.values.filter {
            $0.shouldAutoInstall
            }.map {
                $0.info
        }
    }

    static var packsToNotAutoInstall: [StickerPackInfo] {
        return all.values.filter {
            !$0.shouldAutoInstall
            }.map {
                $0.info
        }
    }

    class func isDefaultStickerPack(stickerPackInfo: StickerPackInfo) -> Bool {
        return all[stickerPackInfo] != nil
    }
}
