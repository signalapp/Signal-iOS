//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc class DisplayableTextFilter: NSObject {

    // don't bother filtering on small text, lest we inadvertently catch legitimate usage of rare code point stacking
    let allowAnyTextLessThanByteSize: Int

    convenience override init() {
        self.init(allowAnyTextLessThanByteSize: 10000)
    }

    required init(allowAnyTextLessThanByteSize: Int) {
        self.allowAnyTextLessThanByteSize = allowAnyTextLessThanByteSize
    }

    @objc(shouldPreventDisplayOfText:)
    func shouldPreventDisplay(text: String?) -> Bool {
        guard let text = text else {
            return false
        }

        let byteCount = text.lengthOfBytes(using: .utf8)

        guard byteCount >= allowAnyTextLessThanByteSize else {
            return false
        }

        let characterCount = text.characters.count
        // discard any zalgo style text, which we detect by enforcing avg bytes per character ratio.
        if byteCount / characterCount > 10 {
            return true
        } else {
            Logger.warn("filtering undisplayable text bytes: \(byteCount), characterCount: \(characterCount)")
            return false
        }
    }
}
