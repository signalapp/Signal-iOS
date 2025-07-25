//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

extension Optional {

    public func mapAsync<T>(_ fn: (Wrapped) async throws -> T) async rethrows -> T? {
        switch self {
        case .none:
            return nil
        case .some(let v):
            return try await fn(v)
        }
    }
}
