//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

struct DisplayableAccountEntropyPool {
    let rawValue: AccountEntropyPool

    init(aep: AccountEntropyPool) {
        self.rawValue = aep
    }

    init(displayString: String) throws {
        let swizzledString = String(displayString.map { char in
            return switch char {
            case "=": "0"
            case "#": "O"
            default: char
            }
        })

        self.init(aep: try AccountEntropyPool(key: swizzledString))
    }

    var displayString: String {
        String(
            rawValue.rawString
                .uppercased()
                .map { char in
                    switch char {
                    // TODO: Reenable this once support is available for all platforms
                    // case "0": "="
                    // case "O", "o": "#"
                    default: char
                    }
                },
        )
    }

    // MARK: -

    static let allowedCharacters = FormattedNumberField.AllowedCharacters(
        keyboardType: .asciiCapable,
        stringFilter: {
            return $0.isAsciiAlphanumeric || $0 == "=" || $0 == "#"
        },
    )
}

// MARK: -

extension AccountEntropyPool {
    var forDisplay: DisplayableAccountEntropyPool {
        DisplayableAccountEntropyPool(aep: self)
    }
}
