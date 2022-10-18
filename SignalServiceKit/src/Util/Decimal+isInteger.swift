//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public extension Decimal {
    /// Is this decimal a whole number?
    ///
    /// - Returns: `true` if the value is a whole number, `false` otherwise.
    var isInteger: Bool {
        (isZero || isNormal) && rounded() == self
    }
}
