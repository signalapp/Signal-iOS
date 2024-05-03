//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension TSResourceStream {

    public func asStickerMetadata(
        stickerInfo: StickerInfo,
        stickerType: StickerType,
        emojiString: String?
    ) -> (any StickerMetadata)? {
        switch self.concreteStreamType {
        case .legacy(let tsAttachment):
            guard let url = tsAttachment.originalMediaURL else {
                return nil
            }
            return DecryptedStickerMetadata(
                stickerInfo: stickerInfo,
                stickerType: stickerType,
                stickerDataUrl: url,
                emojiString: emojiString
            )
        case .v2(let attachment):
            return EncryptedStickerMetadata.from(
                attachment: attachment,
                stickerInfo: stickerInfo,
                stickerType: stickerType,
                emojiString: emojiString
            )
        }
    }
}
