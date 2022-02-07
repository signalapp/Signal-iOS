// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import SignalCoreKit

public extension String {
    func localized() -> String {
        // If the localized string matches the key provided then the localisation failed
        let localizedString = NSLocalizedString(self, comment: "")
        owsAssertDebug(localizedString != self, "Key \"\(self)\" is not set in Localizable.strings")

        return localizedString
    }
}
