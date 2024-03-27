//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension Dictionary {
    func mapKeys<T: Hashable>(injectiveTransform: (Key) throws -> T) rethrows -> [T: Value] {
        return [T: Value](uniqueKeysWithValues: try self.lazy.map { k, v in (try injectiveTransform(k), v) })
    }
}
