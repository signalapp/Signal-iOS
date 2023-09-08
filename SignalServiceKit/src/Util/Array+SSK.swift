//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public extension Array where Element == String? {
    func toMaybeStrings() -> [SSKMaybeString] {
        return map {
            if let value = $0 {
                return value as NSString
            }
            return NSNull()
        }
    }
}

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

public extension Array where Element == SSKMaybeString {
    var sequenceWithNils: AnySequence<String?> {
        return AnySequence(lazy.map { $0.stringOrNil })
    }
}

public extension Array {

    /// Returns an array of only non-nil elements.
    func compacted<T>() -> [T] where Element == T? {
        return self.compactMap({ $0 })
    }
}
