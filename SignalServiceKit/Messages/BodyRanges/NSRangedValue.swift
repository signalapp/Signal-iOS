//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct NSRangedValue<T> {
    public var range: NSRange
    public let value: T

    public init(_ value: T, range: NSRange) {
        self.range = range
        self.value = value
    }
}

extension NSRangedValue: Equatable where T: Equatable {}

extension NSRangedValue: Hashable where T: Hashable {}

extension NSRangedValue: Codable where T: Codable {}

extension NSRangedValue {
    public func offset(by offset: Int) -> Self {
        return Self(
            value,
            range: self.range.offset(by: offset),
        )
    }
}
