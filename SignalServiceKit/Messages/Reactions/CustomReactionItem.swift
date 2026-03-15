//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// Users can select the set of emoji/stickers that appear in the pop up reaction
/// menu (with all others available in the full menu). These are used to represent
/// each item in that selection.
public struct CustomReactionItem: Codable, Equatable, Hashable {
    public let emoji: String
    public let sticker: StickerInfo?

    public init(emoji: String, sticker: StickerInfo?) {
        self.emoji = emoji
        self.sticker = sticker
    }

    public var isStickerReaction: Bool {
        sticker != nil
    }

    public enum CodingKeys: CodingKey {
        case emoji
        case stickerPackId
        case stickerPackKey
        case stickerId
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.emoji = try container.decode(String.self, forKey: .emoji)
        if
            let stickerPackId = try container.decodeIfPresent(Data.self, forKey: .stickerPackId),
            let stickerPackKey = try container.decodeIfPresent(Data.self, forKey: .stickerPackKey),
            let stickerId = try container.decodeIfPresent(UInt32.self, forKey: .stickerId)
        {
            self.sticker = StickerInfo(
                packId: stickerPackId,
                packKey: stickerPackKey,
                stickerId: stickerId
            )
        } else {
            self.sticker = nil
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(emoji, forKey: .emoji)
        if let sticker {
            try container.encode(sticker.packId, forKey: .stickerPackId)
            try container.encode(sticker.packKey, forKey: .stickerPackKey)
            try container.encode(sticker.stickerId, forKey: .stickerId)
        }
    }

    public static func ==(_ lhs: CustomReactionItem, _ rhs: CustomReactionItem) -> Bool {
        return lhs.emoji == rhs.emoji
            && lhs.sticker?.packId == rhs.sticker?.packId
            && lhs.sticker?.packKey == rhs.sticker?.packKey
            && lhs.sticker?.stickerId == rhs.sticker?.stickerId
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(emoji)
        hasher.combine(sticker?.packId)
        hasher.combine(sticker?.packKey)
        hasher.combine(sticker?.stickerId)
    }
}
