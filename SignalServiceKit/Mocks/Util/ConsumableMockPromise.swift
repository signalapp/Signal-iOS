//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit

#if TESTABLE_BUILD

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
        case let .error(error):
            return Promise(error: error)
        case .unset:
            owsFail("Mock not set!")
        }
    }

    func ensureUnset() {
        switch self {
        case .value, .error:
            owsFail("Mock was set!")
        case .unset:
            break
        }
    }
}

#endif
