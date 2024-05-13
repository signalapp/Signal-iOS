//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

struct OsExpiry {
    static var `default`: OsExpiry {
        return OsExpiry(
            minimumIosMajorVersion: 15,
            // 2024-10-01 00:00:00 UTC
            enforcedAfter: Date(timeIntervalSince1970: 1727740800)
        )
    }

    public let minimumIosMajorVersion: Int
    public let enforcedAfter: Date
}
