//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import NaturalLanguage

public extension String {
    var digitsOnly: String {
        return (self as NSString).digitsOnly()
    }

    func substring(from index: Int) -> String {
        return String(self[self.index(self.startIndex, offsetBy: index)...])
    }

    func substring(to index: Int) -> String {
        return String(prefix(index))
    }

    enum StringError: Error {
        case invalidCharacterShift
    }

    /// Converts all non arabic numerals within a string to arabic numerals
    ///
    /// For example: "Hello ١٢٣" would become "Hello 123"
    var ensureArabicNumerals: String {
        return String(map { character in
            // Check if this character is a number between 0-9, if it's not just return it and carry on
            //
            // Some languages (like Chinese) have characters that represent larger numbers (万 = 10^4)
            // These are not easily translatable into arabic numerals at a character by character level,
            // so we ignore them.
            guard let number = character.wholeNumberValue, number <= 9, number >= 0 else { return character }
            return Character("\(number)")
        })
    }
}

public extension NSString {
    @objc
    var ensureArabicNumerals: String {
        return (self as String).ensureArabicNumerals
    }
}

// MARK: - Attributed String Concatentation

public extension NSAttributedString {
    @objc
    func stringByAppendingString(_ string: String, attributes: [NSAttributedString.Key: Any] = [:]) -> NSAttributedString {
        return stringByAppendingString(NSAttributedString(string: string, attributes: attributes))
    }

    @objc
    func stringByAppendingString(_ string: NSAttributedString) -> NSAttributedString {
        let copy = mutableCopy() as! NSMutableAttributedString
        copy.append(string)
        return copy.copy() as! NSAttributedString
    }

    static func + (lhs: NSAttributedString, rhs: NSAttributedString) -> NSAttributedString {
        return lhs.stringByAppendingString(rhs)
    }

    static func + (lhs: NSAttributedString, rhs: String) -> NSAttributedString {
        return lhs.stringByAppendingString(rhs)
    }
}

// MARK: - Natural Text Alignment

public extension String {
    private var dominantLanguage: String? {
        if #available(iOS 12, *) {
            return NLLanguageRecognizer.dominantLanguage(for: self)?.rawValue
        } else if #available(iOS 11, *) {
            return NSLinguisticTagger.dominantLanguage(for: self)
        } else {
            let nsstring = self as NSString
            return nsstring.dominantLanguageWithLegacyLinguisticTagger
        }
    }

    /// The natural text alignment of a given string. This may be different
    /// than the natural alignment of the current system locale depending on
    /// the language of the string, especially for user entered text.
    var naturalTextAlignment: NSTextAlignment {
        guard let dominantLanguage = dominantLanguage else {
            // If we can't identify the strings language, use the system language's natural alignment
            return .natural
        }

        switch NSParagraphStyle.defaultWritingDirection(forLanguage: dominantLanguage) {
        case .leftToRight:
            return .left
        case .rightToLeft:
            return .right
        case .natural:
            return .natural
        @unknown default:
            return .natural
        }
    }
}

public extension NSString {
    /// The natural text alignment of a given string. This may be different
    /// than the natural alignment of the current system locale depending on
    /// the language of the string, especially for user entered text.
    @objc
    var naturalTextAlignment: NSTextAlignment {
        return (self as String).naturalTextAlignment
    }
}

// MARK: - Selector Encoding

private let selectorOffset: UInt32 = 17

public extension String {

    func caesar(shift: UInt32) throws -> String {
        let shiftedScalars: [UnicodeScalar] = try unicodeScalars.map { c in
            guard let shiftedScalar = UnicodeScalar((c.value + shift) % 127) else {
                owsFailDebug("invalidCharacterShift")
                throw StringError.invalidCharacterShift
            }
            return shiftedScalar
        }
        return String(String.UnicodeScalarView(shiftedScalars))
    }

    var encodedForSelector: String? {
        guard let shifted = try? self.caesar(shift: selectorOffset) else {
            owsFailDebug("shifted was unexpectedly nil")
            return nil
        }

        guard let data = shifted.data(using: .utf8) else {
            owsFailDebug("data was unexpectedly nil")
            return nil
        }

        return data.base64EncodedString()
    }

    var decodedForSelector: String? {
        guard let data = Data(base64Encoded: self) else {
            owsFailDebug("data was unexpectedly nil")
            return nil
        }

        guard let shifted = String(data: data, encoding: .utf8) else {
            owsFailDebug("shifted was unexpectedly nil")
            return nil
        }

        return try? shifted.caesar(shift: 127 - selectorOffset)
    }
}

public extension NSString {

    @objc
    var encodedForSelector: String? {
        return (self as String).encodedForSelector
    }

    @objc
    var decodedForSelector: String? {
        return (self as String).decodedForSelector
    }
}

// MARK: - Emoji

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
    //
    // These ranges can be code-generated using:
    //
    // * Scripts/emoji-data.txt
    // * Scripts/emoji_ranges.py
    static let kEmojiRanges = [
        // NOTE: Don't treat Pound Sign # as Jumbomoji.
        //        EmojiRange(rangeStart:0x23, rangeEnd:0x23),
        // NOTE: Don't treat Asterisk * as Jumbomoji.
        //        EmojiRange(rangeStart:0x2A, rangeEnd:0x2A),
        // NOTE: Don't treat Digits 0..9 as Jumbomoji.
        //        EmojiRange(rangeStart:0x30, rangeEnd:0x39),
        // NOTE: Don't treat Copyright Symbol © as Jumbomoji.
        //        EmojiRange(rangeStart:0xA9, rangeEnd:0xA9),
        // NOTE: Don't treat Trademark Sign ® as Jumbomoji.
        //        EmojiRange(rangeStart:0xAE, rangeEnd:0xAE),
        EmojiRange(rangeStart: 0x200D, rangeEnd: 0x200D),
        EmojiRange(rangeStart: 0x203C, rangeEnd: 0x203C),
        EmojiRange(rangeStart: 0x2049, rangeEnd: 0x2049),
        EmojiRange(rangeStart: 0x20D0, rangeEnd: 0x20FF),
        EmojiRange(rangeStart: 0x2122, rangeEnd: 0x2122),
        EmojiRange(rangeStart: 0x2139, rangeEnd: 0x2139),
        EmojiRange(rangeStart: 0x2194, rangeEnd: 0x2199),
        EmojiRange(rangeStart: 0x21A9, rangeEnd: 0x21AA),
        EmojiRange(rangeStart: 0x231A, rangeEnd: 0x231B),
        EmojiRange(rangeStart: 0x2328, rangeEnd: 0x2328),
        EmojiRange(rangeStart: 0x2388, rangeEnd: 0x2388),
        EmojiRange(rangeStart: 0x23CF, rangeEnd: 0x23CF),
        EmojiRange(rangeStart: 0x23E9, rangeEnd: 0x23F3),
        EmojiRange(rangeStart: 0x23F8, rangeEnd: 0x23FA),
        EmojiRange(rangeStart: 0x24C2, rangeEnd: 0x24C2),
        EmojiRange(rangeStart: 0x25AA, rangeEnd: 0x25AB),
        EmojiRange(rangeStart: 0x25B6, rangeEnd: 0x25B6),
        EmojiRange(rangeStart: 0x25C0, rangeEnd: 0x25C0),
        EmojiRange(rangeStart: 0x25FB, rangeEnd: 0x25FE),
        EmojiRange(rangeStart: 0x2600, rangeEnd: 0x27BF),
        EmojiRange(rangeStart: 0x2934, rangeEnd: 0x2935),
        EmojiRange(rangeStart: 0x2B05, rangeEnd: 0x2B07),
        EmojiRange(rangeStart: 0x2B1B, rangeEnd: 0x2B1C),
        EmojiRange(rangeStart: 0x2B50, rangeEnd: 0x2B50),
        EmojiRange(rangeStart: 0x2B55, rangeEnd: 0x2B55),
        EmojiRange(rangeStart: 0x3030, rangeEnd: 0x3030),
        EmojiRange(rangeStart: 0x303D, rangeEnd: 0x303D),
        EmojiRange(rangeStart: 0x3297, rangeEnd: 0x3297),
        EmojiRange(rangeStart: 0x3299, rangeEnd: 0x3299),
        EmojiRange(rangeStart: 0xFE00, rangeEnd: 0xFE0F),
        EmojiRange(rangeStart: 0x1F000, rangeEnd: 0x1F0FF),
        EmojiRange(rangeStart: 0x1F10D, rangeEnd: 0x1F10F),
        EmojiRange(rangeStart: 0x1F12F, rangeEnd: 0x1F12F),
        EmojiRange(rangeStart: 0x1F16C, rangeEnd: 0x1F171),
        EmojiRange(rangeStart: 0x1F17E, rangeEnd: 0x1F17F),
        EmojiRange(rangeStart: 0x1F18E, rangeEnd: 0x1F18E),
        EmojiRange(rangeStart: 0x1F191, rangeEnd: 0x1F19A),
        EmojiRange(rangeStart: 0x1F1AD, rangeEnd: 0x1F1FF),
        EmojiRange(rangeStart: 0x1F201, rangeEnd: 0x1F20F),
        EmojiRange(rangeStart: 0x1F21A, rangeEnd: 0x1F21A),
        EmojiRange(rangeStart: 0x1F22F, rangeEnd: 0x1F22F),
        EmojiRange(rangeStart: 0x1F232, rangeEnd: 0x1F23A),
        EmojiRange(rangeStart: 0x1F23C, rangeEnd: 0x1F23F),
        EmojiRange(rangeStart: 0x1F249, rangeEnd: 0x1F64F),
        EmojiRange(rangeStart: 0x1F680, rangeEnd: 0x1F6FF),
        EmojiRange(rangeStart: 0x1F774, rangeEnd: 0x1F77F),
        EmojiRange(rangeStart: 0x1F7D5, rangeEnd: 0x1F7FF),
        EmojiRange(rangeStart: 0x1F80C, rangeEnd: 0x1F80F),
        EmojiRange(rangeStart: 0x1F848, rangeEnd: 0x1F84F),
        EmojiRange(rangeStart: 0x1F85A, rangeEnd: 0x1F85F),
        EmojiRange(rangeStart: 0x1F888, rangeEnd: 0x1F88F),
        EmojiRange(rangeStart: 0x1F8AE, rangeEnd: 0x1FFFD),
        EmojiRange(rangeStart: 0xE0020, rangeEnd: 0xE007F)
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

public extension String {
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
