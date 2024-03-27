//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

class DefaultStickerPack {
    public let info: StickerPackInfo
    public let shouldAutoInstall: Bool

    private init?(packIdHex: String, packKeyHex: String, shouldAutoInstall: Bool) {
        guard let info = StickerPackInfo.parse(packIdHex: packIdHex, packKeyHex: packKeyHex) else {
            owsFailDebug("Invalid info")
            return nil
        }

        self.info = info
        self.shouldAutoInstall = shouldAutoInstall
    }

    private class func parseAll() -> [Data: DefaultStickerPack] {
        guard TSConstants.isUsingProductionService else {
            return [:]
        }
        let packs = [
            // Bandit the Cat
            DefaultStickerPack(packIdHex: "9acc9e8aba563d26a4994e69263e3b25",
                               packKeyHex: "5a6dff3948c28efb9b7aaf93ecc375c69fc316e78077ed26867a14d10a0f6a12",
                               shouldAutoInstall: true)!,
            // Zozo the French Bulldog
            DefaultStickerPack(packIdHex: "fb535407d2f6497ec074df8b9c51dd1d",
                               packKeyHex: "17e971c134035622781d2ee249e6473b774583750b68c11bb82b7509c68b6dfd",
                               shouldAutoInstall: true)!,
            // Swoon Hands
            DefaultStickerPack(packIdHex: "e61fa0867031597467ccc036cc65d403",
                               packKeyHex: "13ae7b1a7407318280e9b38c1261ded38e0e7138b9f964a6ccbb73e40f737a9b",
                               shouldAutoInstall: false)!,
            // Swoon Faces
            DefaultStickerPack(packIdHex: "cca32f5b905208b7d0f1e17f23fdc185",
                               packKeyHex: "8bf8e95f7a45bdeafe0c8f5b002ef01ab95b8f1b5baac4019ccd6b6be0b1837a",
                               shouldAutoInstall: false)!,
            // Day by Day
            DefaultStickerPack(packIdHex: "cfc50156556893ef9838069d3890fe49",
                               packKeyHex: "5f5beab7d382443cb00a1e48eb95297b6b8cadfd0631e5d0d9dc949e6999ff4b",
                               shouldAutoInstall: true)!,
            // My Daily Life (animated)
            DefaultStickerPack(packIdHex: "ccc89a05dc077856b57351e90697976c",
                               packKeyHex: "45730e60f09d5566115223744537a6b7d9ea99ceeacb77a1fbd6801b9607fbcf",
                               shouldAutoInstall: true)!
        ]

        var result = [Data: DefaultStickerPack]()
        for pack in packs {
            result[pack.info.packId] = pack
        }

        return result
    }

    private static let all = DefaultStickerPack.parseAll()

    static var packsToAutoInstall: [StickerPackInfo] {
        all.values.filter {
            $0.shouldAutoInstall
        }.map {
            $0.info
        }
    }

    static var packsToNotAutoInstall: [StickerPackInfo] {
        all.values.filter {
            !$0.shouldAutoInstall
        }.map {
            $0.info
        }
    }

    class func isDefaultStickerPack(packId: Data) -> Bool {
        all[packId] != nil
    }
}
