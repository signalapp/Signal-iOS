//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

public class MockAppExpiry: AppExpiry {
    public var dateProvider: DateProvider = { Date() }

    public var expirationDate = Date().addingTimeInterval(30 * kDayInterval)

    public var isExpired: Bool { expirationDate < dateProvider() }

    public func warmCaches(with: DBReadTransaction) {}

    public func setHasAppExpiredAtCurrentVersion(db: any DB) {}

    public func setExpirationDateForCurrentVersion(_ newExpirationDate: Date?, db: any DB) {}

    public init() {}
}

#endif
