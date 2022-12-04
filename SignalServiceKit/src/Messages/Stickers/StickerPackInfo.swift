//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension StickerPackInfo {
    public func shareUrl() -> String {
        let packIdHex = packId.hexadecimalString
        let packKeyHex = packKey.hexadecimalString
        return "https://signal.art/addstickers/#pack_id=\(packIdHex)&pack_key=\(packKeyHex)"
    }
}
