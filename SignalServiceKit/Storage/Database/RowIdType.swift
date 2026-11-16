//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import GRDB

public struct RowIdType<T>: Codable, Comparable, CustomStringConvertible, DatabaseValueConvertible, Equatable, Hashable, Sendable {
    public let rawValue: Int64

    public init(rawValue: Int64) {
        self.rawValue = rawValue
    }

#if TESTABLE_BUILD

    static func constantForTesting(_ rawValue: Int64) -> Self {
        return Self(rawValue: rawValue)
    }

#endif

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.rawValue = try container.decode(Int64.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.rawValue)
    }

    public var description: String { "\(rawValue)" }

    public static func <(lhs: Self, rhs: Self) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }

    public var databaseValue: DatabaseValue {
        return rawValue.databaseValue
    }

    public static func fromDatabaseValue(_ dbValue: DatabaseValue) -> Self? {
        return Int64.fromDatabaseValue(dbValue).map { Self(rawValue: $0) }
    }
}
