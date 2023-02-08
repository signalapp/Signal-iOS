//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Used to stub out dates in tests.
public typealias DateProvider = () -> Date

extension Date {
    public static var provider: DateProvider {
        return { Date() }
    }
}
