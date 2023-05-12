//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Just a container for simple static helper methods on SVR
/// that can be shared with other classes (incl. objc classes).
@objc
public final class SVRUtil: NSObject {

    @objc
    public static func normalizePin(_ pin: String) -> String {
        // Trim leading and trailing whitespace
        var normalizedPin = pin.ows_stripped()

        // If this pin contains only numerals, ensure they are arabic numerals.
        if pin.digitsOnly() == normalizedPin { normalizedPin = normalizedPin.ensureArabicNumerals }

        // NFKD unicode normalization.
        return normalizedPin.decomposedStringWithCompatibilityMapping
    }
}
