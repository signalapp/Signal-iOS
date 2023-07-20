//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

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

    static func allSendableEmojiByCategoryWithPreferredSkinTones(transaction: SDSAnyReadTransaction) -> [Category: [EmojiWithSkinTones]] {
        return Category.allCases.reduce(into: [Category: [EmojiWithSkinTones]]()) { result, category in
            result[category] = category.normalizedEmoji.filter { $0.available }.map { $0.withPreferredSkinTones(transaction: transaction) }
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

// MARK: -

extension String {
    // This is slightly more accurate than String.isSingleEmoji,
    // but slower.
    //
    // * This will reject "lone modifiers".
    // * This will reject certain edge cases such as 🌈️.
    var isSingleEmojiUsingEmojiWithSkinTones: Bool {
        EmojiWithSkinTones(rawValue: self) != nil
    }
}

// MARK: - Normalization

extension EmojiWithSkinTones {

    var normalized: EmojiWithSkinTones {
        switch (baseEmoji, skinTones) {
        case (let base, nil) where base.normalized != base:
            return EmojiWithSkinTones(baseEmoji: base.normalized)
        default:
            return self
        }
    }

    var isNormalized: Bool { self == normalized }

}

extension Array where Element == EmojiWithSkinTones {
    /// Removes non-normalized emoji when normalized variants are present.
    ///
    /// Some emoji have two different code points but identical appearances. Let's remove them!
    /// If we normalize to a different emoji than the one currently in our array, we want to drop
    /// the non-normalized variant if the normalized variant already exists. Otherwise, map to the
    /// normalized variant.
    mutating func removeNonNormalizedDuplicates() {
        for (idx, emoji) in self.enumerated().reversed() {
            if !emoji.isNormalized {
                if self.contains(emoji.normalized) {
                    self.remove(at: idx)
                } else {
                    self[idx] = emoji.normalized
                }
            }
        }
    }

    /// Returns a new array removing non-normalized emoji when normalized variants are present.
    ///
    /// Some emoji have two different code points but identical appearances. Let's remove them!
    /// If we normalize to a different emoji than the one currently in our array, we want to drop
    /// the non-normalized variant if the normalized variant already exists. Otherwise, map to the
    /// normalized variant.
    func removingNonNormalizedDuplicates() -> Self {
        var newArray = self
        newArray.removeNonNormalizedDuplicates()
        return newArray
    }
}
