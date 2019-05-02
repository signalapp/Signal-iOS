//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

class DefaultStickerPacks {
    private init() {}

    private class func parse(packIdHex: String, packKeyHex: String) -> StickerPackInfo? {
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

        return StickerPackInfo(packId: packId, packKey: packKey)
    }

    // TODO: Replace with production values.
    static let all: [StickerPackInfo] = [
        parse(packIdHex: "0123456789abcdef0123456789abcdef",
              packKeyHex: "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789"),
        parse(packIdHex: "aaaaaaaabbbbbbbb",
              packKeyHex: "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789"),
        parse(packIdHex: "aaaaaaaacccccccc",
              packKeyHex: "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789")
        ].compactMap { $0 }

    class func isDefaultStickerPack(stickerPackInfo: StickerPackInfo) -> Bool {
        return all.contains(stickerPackInfo)
    }
}
