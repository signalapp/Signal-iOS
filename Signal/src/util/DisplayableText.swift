//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation

extension UnicodeScalar {
    class EmojiRange {
        // rangeStart and rangeEnd are inclusive.
        let rangeStart: UInt32
        let rangeEnd: UInt32

        // MARK: Initializers

        init(rangeStart: UInt32, rangeEnd: UInt32) {
            self.rangeStart = rangeStart
            self.rangeEnd = rangeEnd
        }
    }

    // From:
    // https://www.unicode.org/Public/emoji/
    // Current Version:
    // https://www.unicode.org/Public/emoji/6.0/emoji-data.txt
    static let kEmojiRanges = [
    EmojiRange(rangeStart:0x23, rangeEnd:0x23),
    EmojiRange(rangeStart:0x2A, rangeEnd:0x2A),
    EmojiRange(rangeStart:0x30, rangeEnd:0x39),
    EmojiRange(rangeStart:0xA9, rangeEnd:0xA9),
    EmojiRange(rangeStart:0xAE, rangeEnd:0xAE),
    EmojiRange(rangeStart:0x200D, rangeEnd:0x200D),
    EmojiRange(rangeStart:0x203C, rangeEnd:0x203C),
    EmojiRange(rangeStart:0x2049, rangeEnd:0x2049),
    EmojiRange(rangeStart:0x20D0, rangeEnd:0x20E3),
    EmojiRange(rangeStart:0x2122, rangeEnd:0x2122),
    EmojiRange(rangeStart:0x2139, rangeEnd:0x2139),
    EmojiRange(rangeStart:0x2194, rangeEnd:0x2199),
    EmojiRange(rangeStart:0x21A9, rangeEnd:0x21AA),
    EmojiRange(rangeStart:0x231A, rangeEnd:0x231B),
    EmojiRange(rangeStart:0x2328, rangeEnd:0x2328),
    EmojiRange(rangeStart:0x2388, rangeEnd:0x2388),
    EmojiRange(rangeStart:0x23CF, rangeEnd:0x23CF),
    EmojiRange(rangeStart:0x23E9, rangeEnd:0x23F0),
    EmojiRange(rangeStart:0x23F3, rangeEnd:0x23F3),
    EmojiRange(rangeStart:0x23F8, rangeEnd:0x23FA),
    EmojiRange(rangeStart:0x24C2, rangeEnd:0x24C2),
    EmojiRange(rangeStart:0x25AA, rangeEnd:0x25AB),
    EmojiRange(rangeStart:0x25B6, rangeEnd:0x25B6),
    EmojiRange(rangeStart:0x25C0, rangeEnd:0x25C0),
    EmojiRange(rangeStart:0x25FB, rangeEnd:0x25FE),
    EmojiRange(rangeStart:0x2600, rangeEnd:0x260E),
    EmojiRange(rangeStart:0x2611, rangeEnd:0x2611),
    EmojiRange(rangeStart:0x2614, rangeEnd:0x261D),
    EmojiRange(rangeStart:0x2620, rangeEnd:0x2620),
    EmojiRange(rangeStart:0x2622, rangeEnd:0x2623),
    EmojiRange(rangeStart:0x2626, rangeEnd:0x2626),
    EmojiRange(rangeStart:0x262A, rangeEnd:0x262A),
    EmojiRange(rangeStart:0x262E, rangeEnd:0x262F),
    EmojiRange(rangeStart:0x2638, rangeEnd:0x263A),
    EmojiRange(rangeStart:0x2640, rangeEnd:0x2640),
    EmojiRange(rangeStart:0x2642, rangeEnd:0x2642),
    EmojiRange(rangeStart:0x2648, rangeEnd:0x2653),
    EmojiRange(rangeStart:0x2660, rangeEnd:0x2660),
    EmojiRange(rangeStart:0x2663, rangeEnd:0x2663),
    EmojiRange(rangeStart:0x2665, rangeEnd:0x2666),
    EmojiRange(rangeStart:0x2668, rangeEnd:0x2668),
    EmojiRange(rangeStart:0x2670, rangeEnd:0x267B),
    EmojiRange(rangeStart:0x267E, rangeEnd:0x2693),
    EmojiRange(rangeStart:0x2699, rangeEnd:0x2699),
    EmojiRange(rangeStart:0x269B, rangeEnd:0x26AB),
    EmojiRange(rangeStart:0x26B0, rangeEnd:0x26C8),
    EmojiRange(rangeStart:0x26CE, rangeEnd:0x26D1),
    EmojiRange(rangeStart:0x26D3, rangeEnd:0x26D4),
    EmojiRange(rangeStart:0x26E2, rangeEnd:0x26EA),
    EmojiRange(rangeStart:0x26F0, rangeEnd:0x26F3),
    EmojiRange(rangeStart:0x26F5, rangeEnd:0x26F5),
    EmojiRange(rangeStart:0x26F7, rangeEnd:0x26FA),
    EmojiRange(rangeStart:0x26FD, rangeEnd:0x26FD),
    EmojiRange(rangeStart:0x2700, rangeEnd:0x2702),
    EmojiRange(rangeStart:0x2705, rangeEnd:0x2705),
    EmojiRange(rangeStart:0x2708, rangeEnd:0x270F),
    EmojiRange(rangeStart:0x2712, rangeEnd:0x2712),
    EmojiRange(rangeStart:0x2714, rangeEnd:0x2714),
    EmojiRange(rangeStart:0x2716, rangeEnd:0x2716),
    EmojiRange(rangeStart:0x271D, rangeEnd:0x271D),
    EmojiRange(rangeStart:0x2721, rangeEnd:0x2721),
    EmojiRange(rangeStart:0x2728, rangeEnd:0x2728),
    EmojiRange(rangeStart:0x2733, rangeEnd:0x2734),
    EmojiRange(rangeStart:0x2744, rangeEnd:0x2744),
    EmojiRange(rangeStart:0x2747, rangeEnd:0x2747),
    EmojiRange(rangeStart:0x274C, rangeEnd:0x274C),
    EmojiRange(rangeStart:0x274E, rangeEnd:0x274E),
    EmojiRange(rangeStart:0x2753, rangeEnd:0x2755),
    EmojiRange(rangeStart:0x2757, rangeEnd:0x2757),
    EmojiRange(rangeStart:0x2763, rangeEnd:0x2767),
    EmojiRange(rangeStart:0x2795, rangeEnd:0x2797),
    EmojiRange(rangeStart:0x27A1, rangeEnd:0x27A1),
    EmojiRange(rangeStart:0x27B0, rangeEnd:0x27B0),
    EmojiRange(rangeStart:0x27BF, rangeEnd:0x27BF),
    EmojiRange(rangeStart:0x2934, rangeEnd:0x2935),
    EmojiRange(rangeStart:0x2B05, rangeEnd:0x2B07),
    EmojiRange(rangeStart:0x2B1B, rangeEnd:0x2B1C),
    EmojiRange(rangeStart:0x2B50, rangeEnd:0x2B50),
    EmojiRange(rangeStart:0x2B55, rangeEnd:0x2B55),
    EmojiRange(rangeStart:0x3030, rangeEnd:0x3030),
    EmojiRange(rangeStart:0x303D, rangeEnd:0x303D),
    EmojiRange(rangeStart:0x3297, rangeEnd:0x3297),
    EmojiRange(rangeStart:0x3299, rangeEnd:0x3299),
    EmojiRange(rangeStart:0xFE00, rangeEnd:0xFE0F),
    EmojiRange(rangeStart:0x1F000, rangeEnd:0x1F004),
    EmojiRange(rangeStart:0x1F02C, rangeEnd:0x1F0FF),
    EmojiRange(rangeStart:0x1F10D, rangeEnd:0x1F10F),
    EmojiRange(rangeStart:0x1F12F, rangeEnd:0x1F12F),
    EmojiRange(rangeStart:0x1F16C, rangeEnd:0x1F171),
    EmojiRange(rangeStart:0x1F17E, rangeEnd:0x1F17F),
    EmojiRange(rangeStart:0x1F18E, rangeEnd:0x1F18E),
    EmojiRange(rangeStart:0x1F191, rangeEnd:0x1F19A),
    EmojiRange(rangeStart:0x1F1AD, rangeEnd:0x1F1FF),
    EmojiRange(rangeStart:0x1F201, rangeEnd:0x1F20F),
    EmojiRange(rangeStart:0x1F21A, rangeEnd:0x1F21A),
    EmojiRange(rangeStart:0x1F22F, rangeEnd:0x1F22F),
    EmojiRange(rangeStart:0x1F232, rangeEnd:0x1F23A),
    EmojiRange(rangeStart:0x1F23C, rangeEnd:0x1F23F),
    EmojiRange(rangeStart:0x1F249, rangeEnd:0x1F385),
    EmojiRange(rangeStart:0x1F394, rangeEnd:0x1F397),
    EmojiRange(rangeStart:0x1F399, rangeEnd:0x1F39B),
    EmojiRange(rangeStart:0x1F39E, rangeEnd:0x1F3C7),
    EmojiRange(rangeStart:0x1F3CA, rangeEnd:0x1F3F4),
    EmojiRange(rangeStart:0x1F3F7, rangeEnd:0x1F450),
    EmojiRange(rangeStart:0x1F466, rangeEnd:0x1F469),
    EmojiRange(rangeStart:0x1F46E, rangeEnd:0x1F46E),
    EmojiRange(rangeStart:0x1F470, rangeEnd:0x1F478),
    EmojiRange(rangeStart:0x1F47C, rangeEnd:0x1F47C),
    EmojiRange(rangeStart:0x1F481, rangeEnd:0x1F483),
    EmojiRange(rangeStart:0x1F485, rangeEnd:0x1F487),
    EmojiRange(rangeStart:0x1F4AA, rangeEnd:0x1F4AA),
    EmojiRange(rangeStart:0x1F4F8, rangeEnd:0x1F570),
    EmojiRange(rangeStart:0x1F573, rangeEnd:0x1F575),
    EmojiRange(rangeStart:0x1F57A, rangeEnd:0x1F587),
    EmojiRange(rangeStart:0x1F58A, rangeEnd:0x1F58D),
    EmojiRange(rangeStart:0x1F590, rangeEnd:0x1F590),
    EmojiRange(rangeStart:0x1F595, rangeEnd:0x1F596),
    EmojiRange(rangeStart:0x1F5A4, rangeEnd:0x1F5A8),
    EmojiRange(rangeStart:0x1F5B1, rangeEnd:0x1F5B2),
    EmojiRange(rangeStart:0x1F5BC, rangeEnd:0x1F5BC),
    EmojiRange(rangeStart:0x1F5C2, rangeEnd:0x1F5C4),
    EmojiRange(rangeStart:0x1F5D1, rangeEnd:0x1F5D3),
    EmojiRange(rangeStart:0x1F5DC, rangeEnd:0x1F5DE),
    EmojiRange(rangeStart:0x1F5E1, rangeEnd:0x1F5E1),
    EmojiRange(rangeStart:0x1F5E3, rangeEnd:0x1F5E3),
    EmojiRange(rangeStart:0x1F5E8, rangeEnd:0x1F5E8),
    EmojiRange(rangeStart:0x1F5EF, rangeEnd:0x1F5EF),
    EmojiRange(rangeStart:0x1F5F3, rangeEnd:0x1F5F3),
    EmojiRange(rangeStart:0x1F5FA, rangeEnd:0x1F64F),
    EmojiRange(rangeStart:0x1F680, rangeEnd:0x1F6A3),
    EmojiRange(rangeStart:0x1F6B4, rangeEnd:0x1F6B6),
    EmojiRange(rangeStart:0x1F6C0, rangeEnd:0x1F6C0),
    EmojiRange(rangeStart:0x1F6C6, rangeEnd:0x1F6CC),
    EmojiRange(rangeStart:0x1F6D0, rangeEnd:0x1F6E9),
    EmojiRange(rangeStart:0x1F6EB, rangeEnd:0x1F6FF),
    EmojiRange(rangeStart:0x1F774, rangeEnd:0x1F77F),
    EmojiRange(rangeStart:0x1F7D5, rangeEnd:0x1F7FF),
    EmojiRange(rangeStart:0x1F80C, rangeEnd:0x1F80F),
    EmojiRange(rangeStart:0x1F848, rangeEnd:0x1F84F),
    EmojiRange(rangeStart:0x1F85A, rangeEnd:0x1F85F),
    EmojiRange(rangeStart:0x1F888, rangeEnd:0x1F88F),
    EmojiRange(rangeStart:0x1F8AE, rangeEnd:0x1F926),
    EmojiRange(rangeStart:0x1F928, rangeEnd:0x1F93A),
    EmojiRange(rangeStart:0x1F93C, rangeEnd:0x1F945),
    EmojiRange(rangeStart:0x1F947, rangeEnd:0x1F9DD),
    EmojiRange(rangeStart:0x1F9E7, rangeEnd:0x1FFFD),
    EmojiRange(rangeStart:0xE0020, rangeEnd:0xE007F)
    ]

    var isEmoji: Bool {

        // Binary search.
        var left: Int = 0
        var right = Int(UnicodeScalar.kEmojiRanges.count - 1)
        while true {
            let mid = (left + right) / 2
            let midRange = UnicodeScalar.kEmojiRanges[mid]
            if value < midRange.rangeStart {
                if mid == left {
                    return false
                }
                right = mid - 1
            } else if value > midRange.rangeEnd {
                if mid == right {
                    return false
                }
                left = mid + 1
            } else {
                return true
            }
        }
    }

    var isZeroWidthJoiner: Bool {

        return value == 8205
    }
}

extension String {

    var glyphCount: Int {
        let richText = NSAttributedString(string: self)
        let line = CTLineCreateWithAttributedString(richText)
        return CTLineGetGlyphCount(line)
    }

    var isSingleEmoji: Bool {

        return glyphCount == 1 && containsEmoji
    }

    var containsEmoji: Bool {

        return unicodeScalars.contains { $0.isEmoji }
    }

    var containsOnlyEmoji: Bool {

        return !isEmpty
            && !unicodeScalars.contains(where: {
                !$0.isEmoji
                    && !$0.isZeroWidthJoiner
            })
    }
}

@objc class DisplayableText: NSObject {

    static let TAG = "[DisplayableText]"

    let fullText: String
    let displayText: String
    let isTextTruncated: Bool
    let jumbomojiCount: UInt

    static let kMaxJumbomojiCount: UInt = 5
    // This value is a bit arbitrary since we don't need to be 100% correct about 
    // rendering "Jumbomoji".  It allows us to place an upper bound on worst-case
    // performacne.
    static let kMaxCharactersPerEmojiCount: UInt = 10

    // MARK: Initializers

    init(fullText: String, displayText: String, isTextTruncated: Bool) {
        self.fullText = fullText
        self.displayText = displayText
        self.isTextTruncated = isTextTruncated
        self.jumbomojiCount = DisplayableText.jumbomojiCount(in:fullText)
    }

    // MARK: Emoji

    // If the string is...
    //
    // * Non-empty
    // * Only contains emoji
    // * Contains <= kMaxJumbomojiCount emoji
    //
    // ...return the number of emoji (to be treated as "Jumbomoji") in the string.
    private class func jumbomojiCount(in string: String) -> UInt {
        if string == "" {
            return 0
        }
        if string.characters.count > Int(kMaxJumbomojiCount * kMaxCharactersPerEmojiCount) {
            return 0
        }
        guard string.containsOnlyEmoji else {
            return 0
        }
        let emojiCount = string.glyphCount
        if UInt(emojiCount) > kMaxJumbomojiCount {
            return 0
        }
        return UInt(emojiCount)
    }

    // MARK: Filter Methods

    @objc
    class func displayableText(_ text: String?) -> String? {
        guard let text = text?.ows_stripped() else {
            return nil
        }

        if (self.hasExcessiveDiacriticals(text: text)) {
            Logger.warn("\(TAG) filtering text for excessive diacriticals.")
            let filteredText = text.folding(options: .diacriticInsensitive, locale: .current)
            return filteredText.ows_stripped()
        }

        return text.ows_stripped()
    }

    private class func hasExcessiveDiacriticals(text: String) -> Bool {
        // discard any zalgo style text, by detecting maximum number of glyphs per character
        for char in text.characters.enumerated() {
            let scalarCount = String(char.element).unicodeScalars.count
            if scalarCount > 4 {
                Logger.warn("\(TAG) detected excessive diacriticals at \(char.element) scalarCount: \(scalarCount)")
                return true
            }
        }

        return false
    }
}
