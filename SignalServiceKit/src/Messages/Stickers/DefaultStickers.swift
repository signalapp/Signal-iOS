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
        let packs = [
            // Bandit the Cat
            DefaultStickerPack(packIdHex: "ceba4fbc5736a48bdce4dfb85e368b09", packKeyHex: "fc8a61d7b8c44de0450801978dd9bf382f741f06ac0fef9048433f4da52f8d01", shouldAutoInstall: true)!,
            // Zozo the French Bulldog
            DefaultStickerPack(packIdHex: "fb535407d2f6497ec074df8b9c51dd1d", packKeyHex: "17e971c134035622781d2ee249e6473b774583750b68c11bb82b7509c68b6dfd", shouldAutoInstall: true)!
        ]
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
