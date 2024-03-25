//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

struct OsExpiry {
    static var `default`: OsExpiry {
        return OsExpiry(
            minimumIosMajorVersion: 13,
            // 2023-08-24
            enforcedAfter: Date(timeIntervalSince1970: 1692853200)
        )
    }

    public let minimumIosMajorVersion: Int
    public let enforcedAfter: Date
}
