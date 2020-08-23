//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

public struct EmojiWithSkinTones: Hashable {
    let baseEmoji: Emoji
    let skinTones: [Emoji.SkinTone]?

    init(baseEmoji: Emoji, skinTones: [Emoji.SkinTone]? = nil) {
        self.baseEmoji = baseEmoji

        // Deduplicate skin tones, while preserving order. This allows for
        // multi-skin tone emoji, where if you have for example the permutation
        // [.dark, .dark], it is consolidated to just [.dark], to be initialized
        // with either variant and result in the correct emoji.
        self.skinTones = skinTones?.reduce(into: [Emoji.SkinTone]()) { result, skinTone in
            guard !result.contains(skinTone) else { return }
            result.append(skinTone)
        }
    }

    var rawValue: String {
        if let skinTones = skinTones {
            return baseEmoji.emojiPerSkinTonePermutation?[skinTones] ?? baseEmoji.rawValue
        } else {
            return baseEmoji.rawValue
        }
    }
}

extension Emoji {
    private static let keyValueStore = SDSKeyValueStore(collection: "Emoji+PreferredSkinTonePermutation")

    static func allAvailableEmojiByCategoryWithPreferredSkinTones(transaction: SDSAnyReadTransaction) -> [Category: [EmojiWithSkinTones]] {
        return Category.allCases.reduce(into: [Category: [EmojiWithSkinTones]]()) { result, category in
            result[category] = category.emoji.filter { $0.available }.map { $0.withPreferredSkinTones(transaction: transaction) }
        }
    }

    func withPreferredSkinTones(transaction: SDSAnyReadTransaction) -> EmojiWithSkinTones {
        guard let rawSkinTones = Self.keyValueStore.getObject(forKey: rawValue, transaction: transaction) as? [String] else {
            return EmojiWithSkinTones(baseEmoji: self, skinTones: nil)
        }

        return EmojiWithSkinTones(baseEmoji: self, skinTones: rawSkinTones.compactMap { SkinTone(rawValue: $0) })
    }

    func setPreferredSkinTones(_ preferredSkinTonePermutation: [SkinTone]?, transaction: SDSAnyWriteTransaction) {
        if let preferredSkinTonePermutation = preferredSkinTonePermutation {
            Self.keyValueStore.setObject(preferredSkinTonePermutation.map { $0.rawValue }, key: rawValue, transaction: transaction)
        } else {
            Self.keyValueStore.removeValue(forKey: rawValue, transaction: transaction)
        }
    }

    init?(_ string: String) {
        guard let emojiWithSkinTonePermutation = EmojiWithSkinTones(rawValue: string) else { return nil }
        self = emojiWithSkinTonePermutation.baseEmoji
    }
}
