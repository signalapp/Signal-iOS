//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation

extension UnicodeScalar {

    // From:
    // https://www.unicode.org/Public/emoji/
    // Current Version:
    // https://www.unicode.org/Public/emoji/6.0/emoji-data.txt
    var isEmoji: Bool {

        switch value {
        case
        0x23...0x23, // 1 Emotions
        0x2A...0x2A, // 1 Emotions
        0x30...0x39, // 10 Emotions
        0xA9...0xA9, // 1 Emotions
        0xAE...0xAE, // 1 Emotions
        0x200D...0x200D, // 1 Emotions
        0x203C...0x203C, // 1 Emotions
        0x2049...0x2049, // 1 Emotions
        0x20D0...0x20E3, // 20 Emotions
        0x2122...0x2122, // 1 Emotions
        0x2139...0x2139, // 1 Emotions
        0x2194...0x2199, // 6 Emotions
        0x21A9...0x21AA, // 2 Emotions
        0x231A...0x231B, // 2 Emotions
        0x2328...0x2328, // 1 Emotions
        0x2388...0x2388, // 1 Emotions
        0x23CF...0x23CF, // 1 Emotions
        0x23E9...0x23F0, // 8 Emotions
        0x23F3...0x23F3, // 1 Emotions
        0x23F8...0x23FA, // 3 Emotions
        0x24C2...0x24C2, // 1 Emotions
        0x25AA...0x25AB, // 2 Emotions
        0x25B6...0x25B6, // 1 Emotions
        0x25C0...0x25C0, // 1 Emotions
        0x25FB...0x25FE, // 4 Emotions
        0x2600...0x260E, // 15 Emotions
        0x2611...0x2611, // 1 Emotions
        0x2614...0x261D, // 10 Emotions
        0x2620...0x2620, // 1 Emotions
        0x2622...0x2623, // 2 Emotions
        0x2626...0x2626, // 1 Emotions
        0x262A...0x262A, // 1 Emotions
        0x262E...0x262F, // 2 Emotions
        0x2638...0x263A, // 3 Emotions
        0x2640...0x2640, // 1 Emotions
        0x2642...0x2642, // 1 Emotions
        0x2648...0x2653, // 12 Emotions
        0x2660...0x2660, // 1 Emotions
        0x2663...0x2663, // 1 Emotions
        0x2665...0x2666, // 2 Emotions
        0x2668...0x2668, // 1 Emotions
        0x2670...0x267B, // 12 Emotions
        0x267E...0x2693, // 22 Emotions
        0x2699...0x2699, // 1 Emotions
        0x269B...0x26AB, // 17 Emotions
        0x26B0...0x26C8, // 25 Emotions
        0x26CE...0x26D1, // 4 Emotions
        0x26D3...0x26D4, // 2 Emotions
        0x26E2...0x26EA, // 9 Emotions
        0x26F0...0x26F3, // 4 Emotions
        0x26F5...0x26F5, // 1 Emotions
        0x26F7...0x26FA, // 4 Emotions
        0x26FD...0x26FD, // 1 Emotions
        0x2700...0x2702, // 3 Emotions
        0x2705...0x2705, // 1 Emotions
        0x2708...0x270F, // 8 Emotions
        0x2712...0x2712, // 1 Emotions
        0x2714...0x2714, // 1 Emotions
        0x2716...0x2716, // 1 Emotions
        0x271D...0x271D, // 1 Emotions
        0x2721...0x2721, // 1 Emotions
        0x2728...0x2728, // 1 Emotions
        0x2733...0x2734, // 2 Emotions
        0x2744...0x2744, // 1 Emotions
        0x2747...0x2747, // 1 Emotions
        0x274C...0x274C, // 1 Emotions
        0x274E...0x274E, // 1 Emotions
        0x2753...0x2755, // 3 Emotions
        0x2757...0x2757, // 1 Emotions
        0x2763...0x2767, // 5 Emotions
        0x2795...0x2797, // 3 Emotions
        0x27A1...0x27A1, // 1 Emotions
        0x27B0...0x27B0, // 1 Emotions
        0x27BF...0x27BF, // 1 Emotions
        0x2934...0x2935, // 2 Emotions
        0x2B05...0x2B07, // 3 Emotions
        0x2B1B...0x2B1C, // 2 Emotions
        0x2B50...0x2B50, // 1 Emotions
        0x2B55...0x2B55, // 1 Emotions
        0x3030...0x3030, // 1 Emotions
        0x303D...0x303D, // 1 Emotions
        0x3297...0x3297, // 1 Emotions
        0x3299...0x3299, // 1 Emotions
        0xFE00...0xFE0F, // 16 Emotions
        0x1F000...0x1F004, // 5 Emotions
        0x1F02C...0x1F0FF, // 212 Emotions
        0x1F10D...0x1F10F, // 3 Emotions
        0x1F12F...0x1F12F, // 1 Emotions
        0x1F16C...0x1F171, // 6 Emotions
        0x1F17E...0x1F17F, // 2 Emotions
        0x1F18E...0x1F18E, // 1 Emotions
        0x1F191...0x1F19A, // 10 Emotions
        0x1F1AD...0x1F1FF, // 83 Emotions
        0x1F201...0x1F20F, // 15 Emotions
        0x1F21A...0x1F21A, // 1 Emotions
        0x1F22F...0x1F22F, // 1 Emotions
        0x1F232...0x1F23A, // 9 Emotions
        0x1F23C...0x1F23F, // 4 Emotions
        0x1F249...0x1F385, // 317 Emotions
        0x1F394...0x1F397, // 4 Emotions
        0x1F399...0x1F39B, // 3 Emotions
        0x1F39E...0x1F3C7, // 42 Emotions
        0x1F3CA...0x1F3F4, // 43 Emotions
        0x1F3F7...0x1F450, // 90 Emotions
        0x1F466...0x1F469, // 4 Emotions
        0x1F46E...0x1F46E, // 1 Emotions
        0x1F470...0x1F478, // 9 Emotions
        0x1F47C...0x1F47C, // 1 Emotions
        0x1F481...0x1F483, // 3 Emotions
        0x1F485...0x1F487, // 3 Emotions
        0x1F4AA...0x1F4AA, // 1 Emotions
        0x1F4F8...0x1F570, // 121 Emotions
        0x1F573...0x1F575, // 3 Emotions
        0x1F57A...0x1F587, // 14 Emotions
        0x1F58A...0x1F58D, // 4 Emotions
        0x1F590...0x1F590, // 1 Emotions
        0x1F595...0x1F596, // 2 Emotions
        0x1F5A4...0x1F5A8, // 5 Emotions
        0x1F5B1...0x1F5B2, // 2 Emotions
        0x1F5BC...0x1F5BC, // 1 Emotions
        0x1F5C2...0x1F5C4, // 3 Emotions
        0x1F5D1...0x1F5D3, // 3 Emotions
        0x1F5DC...0x1F5DE, // 3 Emotions
        0x1F5E1...0x1F5E1, // 1 Emotions
        0x1F5E3...0x1F5E3, // 1 Emotions
        0x1F5E8...0x1F5E8, // 1 Emotions
        0x1F5EF...0x1F5EF, // 1 Emotions
        0x1F5F3...0x1F5F3, // 1 Emotions
        0x1F5FA...0x1F64F, // 86 Emotions
        0x1F680...0x1F6A3, // 36 Emotions
        0x1F6B4...0x1F6B6, // 3 Emotions
        0x1F6C0...0x1F6C0, // 1 Emotions
        0x1F6C6...0x1F6CC, // 7 Emotions
        0x1F6D0...0x1F6E9, // 26 Emotions
        0x1F6EB...0x1F6FF, // 21 Emotions
        0x1F774...0x1F77F, // 12 Emotions
        0x1F7D5...0x1F7FF, // 43 Emotions
        0x1F80C...0x1F80F, // 4 Emotions
        0x1F848...0x1F84F, // 8 Emotions
        0x1F85A...0x1F85F, // 6 Emotions
        0x1F888...0x1F88F, // 8 Emotions
        0x1F8AE...0x1F926, // 121 Emotions
        0x1F928...0x1F93A, // 19 Emotions
        0x1F93C...0x1F945, // 10 Emotions
        0x1F947...0x1F9DD, // 151 Emotions
        0x1F9E7...0x1FFFD, // 1559 Emotions
        0xE0020...0xE007F: // 96 Emotions
            return true

        default: return false
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

    // The next tricks are mostly to demonstrate how tricky it can be to determine emoji's
    // If anyone has suggestions how to improve this, please let me know
    var emojiString: String {

        return emojiScalars.map { String($0) }.reduce("", +)
    }

    var emojis: [String] {

        var scalars: [[UnicodeScalar]] = []
        var currentScalarSet: [UnicodeScalar] = []
        var previousScalar: UnicodeScalar?

        for scalar in emojiScalars {

            if let prev = previousScalar, !prev.isZeroWidthJoiner && !scalar.isZeroWidthJoiner {

                scalars.append(currentScalarSet)
                currentScalarSet = []
            }
            currentScalarSet.append(scalar)

            previousScalar = scalar
        }

        scalars.append(currentScalarSet)

        return scalars.map { $0.map { String($0) } .reduce("", +) }
    }

    fileprivate var emojiScalars: [UnicodeScalar] {

        var chars: [UnicodeScalar] = []
        var previous: UnicodeScalar?
        for cur in unicodeScalars {

            if let previous = previous, previous.isZeroWidthJoiner && cur.isEmoji {
                chars.append(previous)
                chars.append(cur)

            } else if cur.isEmoji {
                chars.append(cur)
            }

            previous = cur
        }

        return chars
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
