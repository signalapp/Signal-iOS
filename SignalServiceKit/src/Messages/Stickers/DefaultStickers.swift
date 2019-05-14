//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

class DefaultStickerPack {
    public let info: StickerPackInfo
    public let shouldAutoInstall: Bool

    private init?(packIdHex: String, packKeyHex: String, shouldAutoInstall: Bool) {
        guard let info = StickerPackInfo.parsePackIdHex(packIdHex, packKeyHex: packKeyHex) else {
            owsFailDebug("Invalid info")
            return nil
        }

        self.info = info
        self.shouldAutoInstall = shouldAutoInstall
    }

    private class func parseAll() -> [StickerPackInfo: DefaultStickerPack] {
        guard OWSIsDebugBuild() else {
            return [:]
        }

        // TODO: Replace with production values.
        let packs = [
        DefaultStickerPack(packIdHex: "0123456789abcdef0123456789abcdef",
        packKeyHex: "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789",
        shouldAutoInstall: true),
        DefaultStickerPack(packIdHex: "aaaaaaaabbbbbbbbcccccccc00000000",
                           packKeyHex: "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789",
                           shouldAutoInstall: false),
        DefaultStickerPack(packIdHex: "aaaaaaaabbbbbbbbcccccccc11111111",
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
