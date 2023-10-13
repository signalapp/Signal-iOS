//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import SignalCoreKit

class NSELogger: PrefixedLogger {
    static let uncorrelated = NSELogger(prefix: "uncorrelated")

    convenience init() {
        self.init(
            prefix: "[NSE]",
            suffix: "{{\(UUID().uuidString)}}"
        )
    }
}
