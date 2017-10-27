//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc class DisplayableText: NSObject {

    static let TAG = "[DisplayableText]"

    let fullText: String
    let displayText: String
    let isTextTruncated: Bool

    // MARK: Initializers

    init(fullText: String, displayText: String, isTextTruncated: Bool) {
        self.fullText = fullText
        self.displayText = displayText
        self.isTextTruncated = isTextTruncated
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
