//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension StickerPackInfo {
    @objc(parsePackIdHex:packKeyHex:)
    public class func parse(packIdHex: String?, packKeyHex: String?) -> StickerPackInfo? {
        guard let packIdHex, !packIdHex.isEmpty else {
            Logger.warn("Invalid packIdHex")
            Logger.debug("Invalid packIdHex: \(packIdHex ?? "nil")")
            return nil
        }
        guard let packKeyHex, !packKeyHex.isEmpty else {
            Logger.warn("Invalid packKeyHex")
            Logger.debug("Invalid packKeyHex: \(packKeyHex ?? "nil")")
            return nil
        }
        return parse(packId: Data.data(fromHex: packIdHex), packKey: Data.data(fromHex: packKeyHex))
    }

    public class func parse(packId: Data?, packKey: Data?) -> StickerPackInfo? {
        guard let packId, !packId.isEmpty else {
            Logger.warn("Invalid packId")
            Logger.debug("Invalid packId: \(String(describing: packId))")
            return nil
        }
        guard let packKey, packKey.count == StickerManager.packKeyLength else {
            Logger.warn("Invalid packKey")
            Logger.debug("Invalid packKey: \(String(describing: packKey))")
            return nil
        }
        return StickerPackInfo(packId: packId, packKey: packKey)
    }

    public func shareUrl() -> String {
        let packIdHex = packId.hexadecimalString
        let packKeyHex = packKey.hexadecimalString
        return "https://signal.art/addstickers/#pack_id=\(packIdHex)&pack_key=\(packKeyHex)"
    }
}
