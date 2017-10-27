//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc class DisplayableText: NSObject {

    static let TAG = "[DisplayableText]"

    let fullText: String
    let displayText: String
    let isTextTruncated: Bool
    let jumbomojiCount: NSNumber?

    static let kMaxJumbomojiCount: UInt = 5

    // MARK: Initializers

    init(fullText: String, displayText: String, isTextTruncated: Bool, jumbomojiCount: NSNumber?) {
        self.fullText = fullText
        self.displayText = displayText
        self.isTextTruncated = isTextTruncated
        self.jumbomojiCount = jumbomojiCount
    }

    // MARK: Emoji

    private class func canDetectEmoji() -> Bool {
        if #available(iOS 10.0, *) {
            return true
        } else {
            return false
        }
    }

    // If the string is...
    //
    // * Non-empty
    // * Only contains emoji
    // * Contains <= maxEmojiCount emoji
    //
    // ...return the number of emoji in the string.  Otherwise return nil.
    //
    // On iOS 9 and earler, always returns nil.
    @objc public class func jumbomojiCount(to string: String) -> NSNumber? {
        if string == "" {
            return nil
        }
        if string.characters.count > Int(kMaxJumbomojiCount) {
            return nil
        }
        if !canDetectEmoji() {
            return nil
        }
        var didFail = false
        var emojiCount: UInt = 0
        let attributes = [NSFontAttributeName: UIFont.systemFont(ofSize:12)]
        let attributedString = NSMutableAttributedString(string: string, attributes: attributes)
        let range = NSRange(location: 0, length: string.characters.count)
        attributedString.fixAttributes(in: range)
        attributedString.enumerateAttribute(NSFontAttributeName,
                                            in: range,
                                            options: [],
                                            using: {(_ value: Any?, range: NSRange, stop: UnsafeMutablePointer<ObjCBool>) -> Void in
                                                guard emojiCount < kMaxJumbomojiCount else {
                                                    didFail = true
                                                    stop.pointee = true
                                                    return
                                                }
                                                guard let rangeFont = value as? UIFont else {
                                                    didFail = true
                                                    stop.pointee = true
                                                    return
                                                }
                                                guard rangeFont.fontName == ".AppleColorEmojiUI" else {
                                                    didFail = true
                                                    stop.pointee = true
                                                    return
                                                }
                                                if rangeFont.fontName == ".AppleColorEmojiUI" {
                                                    Logger.verbose("Detected Emoji at location: \(range.location), for length: \(range.length)")
                                                    emojiCount += UInt(range.length)
                                                }
        })

        guard !didFail else {
            return nil
        }
        return NSNumber(value: emojiCount)
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
