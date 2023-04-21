//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

public class MockAppExpiry: AppExpiry {
    public var expirationDate = Date().addingTimeInterval(30 * kDayInterval)

    public var isExpired: Bool { expirationDate < Date() }

    public func warmCaches(with: DBReadTransaction) {}

    public func setHasAppExpiredAtCurrentVersion(db: DB) {}

    public func setExpirationDateForCurrentVersion(_ newExpirationDate: Date?, db: DB) {}

    public init() {}
}

#endif
