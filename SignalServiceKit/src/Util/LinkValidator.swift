//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum LinkValidator {
    public static func canParseURLs(in entireMessage: String) -> Bool {
        if entireMessage.unicodeScalars.contains(where: isProblematicCodepoint(_:)) {
            return false
        }
        return true
    }

    private static func isProblematicCodepoint(_ scalar: UnicodeScalar) -> Bool {
        switch scalar {
        case "\u{202C}", // POP DIRECTIONAL FORMATTING
            "\u{202D}", // LEFT-TO-RIGHT OVERRIDE
            "\u{202E}": // RIGHT-TO-LEFT OVERRIDE
            return true
        case "\u{2500}"..."\u{25FF}": // Box Drawing, Block Elements, Geometric Shapes
            return true
        default:
            return false
        }
    }
}
