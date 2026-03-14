//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

// Every story reaction has an emoji; it may also have a sticker
// (if it does, the sticker's associated emoji will be set).
public struct StoryReaction {
    public let emoji: String
    public let sticker: ReferencedAttachment?
    public let stickerInfo: StickerInfo?

    public init(emoji: String, sticker: ReferencedAttachment?, stickerInfo: StickerInfo?) {
        self.emoji = emoji
        self.sticker = sticker
        self.stickerInfo = stickerInfo
    }
}

extension StoryReaction: Equatable {
    public static func ==(
        lhs: StoryReaction,
        rhs: StoryReaction
    ) -> Bool {
        return lhs.emoji == rhs.emoji
            && lhs.sticker?.attachment.id == rhs.sticker?.attachment.id
            && lhs.sticker?.reference.owner.id == rhs.sticker?.reference.owner.id
            && lhs.stickerInfo == rhs.stickerInfo
    }
}
