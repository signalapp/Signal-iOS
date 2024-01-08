//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension Array {
    func removingDuplicates<T: Hashable>(uniquingElementsBy uniqueValue: (Element) -> T) -> [Element] {
        var result = [Element]()
        var uniqueValues = Set<T>()
        for element in self {
            guard uniqueValues.insert(uniqueValue(element)).inserted else {
                continue
            }
            result.append(element)
        }
        return result
    }
}

extension Array {
    mutating func removeFirst(where predicate: (Element) throws -> Bool) rethrows -> Element? {
        guard let index = try firstIndex(where: predicate) else {
            return nil
        }
        let result = self[index]
        remove(at: index)
        return result
    }
}

public extension Array {

    /// Returns an array of only non-nil elements.
    func compacted<T>() -> [T] where Element == T? {
        return self.compactMap({ $0 })
    }
}
