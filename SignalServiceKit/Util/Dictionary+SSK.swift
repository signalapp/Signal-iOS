//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// MARK: -

extension Dictionary {
    func mapKeys<T: Hashable>(injectiveTransform: (Key) throws -> T) rethrows -> [T: Value] {
        return [T: Value](uniqueKeysWithValues: try self.lazy.map { k, v in (try injectiveTransform(k), v) })
    }
}

// MARK: - Array values

public extension Dictionary {
    mutating func append<T>(
        additionalElement: T,
        forKey key: Key
    ) where Value == [T] {
        if let existingValue: [T] = self[key] {
            self[key] = existingValue + [additionalElement]
        } else {
            self[key] = [additionalElement]
        }
    }
}
