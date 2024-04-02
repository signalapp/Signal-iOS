//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// The preferred number when there are multiple possibilities.
///
/// For example, Mexico went through a number contraction operation where
/// "+521…" became "+52…" in some cases. These numbers are equivalent, but
/// either one might be registered on Signal. Because they are equivalent,
/// we canonicalize them during parsing, expand them during CDS lookups, and
/// then pick whichever one exists.
public struct CanonicalPhoneNumber: Equatable, Hashable {
    public let rawValue: E164

    public init(nonCanonicalPhoneNumber phoneNumber: E164) {
        if phoneNumber.stringValue.hasPrefix("+521") {
            self.rawValue = E164("+52" + phoneNumber.stringValue.dropFirst(4))!
        } else {
            self.rawValue = phoneNumber
        }
    }

    public func alternatePhoneNumbers() -> [E164] {
        if rawValue.stringValue.hasPrefix("+52") {
            return [E164("+521" + rawValue.stringValue.dropFirst(3))!]
        }
        return []
    }
}
