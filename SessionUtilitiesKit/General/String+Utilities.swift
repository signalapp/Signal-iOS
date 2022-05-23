// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import SignalCoreKit

public extension String {
    func localized() -> String {
        // If the localized string matches the key provided then the localisation failed
        let localizedString = NSLocalizedString(self, comment: "")
        owsAssertDebug(localizedString != self, "Key \"\(self)\" is not set in Localizable.strings")

        return localizedString
    }
    
    func ranges(of substring: String, options: CompareOptions = [], locale: Locale? = nil) -> [Range<Index>] {
        var ranges: [Range<Index>] = []
        
        while
            (ranges.last.map({ $0.upperBound < self.endIndex }) ?? true),
            let range = self.range(
                of: substring,
                options: options,
                range: (ranges.last?.upperBound ?? self.startIndex)..<self.endIndex,
                locale: locale
            )
        {
            ranges.append(range)
        }
        
        return ranges
    }
}
