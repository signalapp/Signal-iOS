//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import SignalServiceKit
import XCTest

/// A mock value standing in for a promise. Useful when mocking APIs that return
/// promises.
enum ConsumableMockPromise<V> {
    case value(V)
    case error(Error = OWSGenericError("Intentional failure!"))
    case unset

    mutating func consumeIntoPromise() -> Promise<V> {
        defer { self = .unset }

        switch self {
        case .value(let v):
            return .value(v)
        case .error:
            return Promise(error: OWSGenericError("Intentional error"))
        case .unset:
            XCTFail("Mock not set!")
            return Promise(error: OWSGenericError("Mock not set!"))
        }
    }

    func ensureUnset() {
        switch self {
        case .value, .error:
            XCTFail("Mock was set!")
        case .unset:
            break
        }
    }
}
