//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit
import XCTest

@testable import SignalServiceKit

/// A mock value standing in for a Guarantee. Useful when mocking APIs that
/// return Guarantees.
enum ConsumableMockGuarantee<V> {
    case value(V)
    case unset

    mutating func consumeIntoGuarantee() -> Guarantee<V> {
        defer { self = .unset }

        switch self {
        case .value(let v):
            return .value(v)
        case .unset:
            XCTFail("Mock not set!")
            fatalError()
        }
    }

    func ensureUnset() {
        switch self {
        case .value:
            XCTFail("Mock was set!")
        case .unset:
            break
        }
    }
}
