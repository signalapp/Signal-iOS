//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension Array {
    /// Analogous to Swift.Collection's built-in `allSatisfy`.
    func anySatisfy(_ predicate: (Element) throws -> Bool) rethrows -> Bool {
        return try first(where: predicate) != nil
    }

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

    mutating func removeFirst(where predicate: (Element) throws -> Bool) rethrows -> Element? {
        guard let index = try firstIndex(where: predicate) else {
            return nil
        }
        let result = self[index]
        remove(at: index)
        return result
    }

    /// Returns an array of only non-nil elements.
    public func compacted<T>() -> [T] where Element == T? {
        return self.compactMap({ $0 })
    }

    public func mapAsync<T>(_ fn: (Element) async throws -> T) async rethrows -> [T] {
        var results = [T]()
        for element in self {
            try await results.append(fn(element))
        }
        return results
    }
}

extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        return self.removingDuplicates(uniquingElementsBy: { $0 })
    }
}

extension Collection where Self: RandomAccessCollection {
    /// Computes the index for a new element in an already-sorted collection.
    ///
    /// Elements are inserted just before the first element that's larger.
    /// (Therefore, duplicate elements are inserted after existing elements.)
    ///
    /// For example, if `self` is `["B", "D", "D", "F"]` and the comparison is `<`:
    /// - an `element` of "A" would return `startIndex + 0`
    /// - an `element` of "D" would return `startIndex + 3`
    /// - an `element` of "E" would return `startIndex + 3`
    /// - an `element` of "G" would return `startIndex + 4` (aka `endIndex`)
    ///
    /// - Complexity: O(lg n)
    public func insertionIndex(
        for element: Element,
        inCollectionAlreadySortedBy areInIncreasingOrder: (Element, Element) -> Bool,
    ) -> Index {
        var remainingElements = self[...]
        while !remainingElements.isEmpty {
            let idx = remainingElements.index(
                remainingElements.startIndex,
                offsetBy: remainingElements.distance(from: remainingElements.startIndex, to: remainingElements.endIndex) / 2,
            )
            if areInIncreasingOrder(element, remainingElements[idx]) {
                remainingElements = remainingElements[...idx].dropLast()
            } else {
                remainingElements = remainingElements[idx...].dropFirst()
            }
        }
        return remainingElements.startIndex
    }
}

public extension Collection {

    func forEachChunk(chunkSize: Int, _ block: (Self.SubSequence) async throws -> Void) async rethrows {
        guard !isEmpty else { return }
        var startIndex = self.startIndex
        var endIndex = self.index(
            startIndex,
            offsetBy: chunkSize,
            limitedBy: self.endIndex,
        ) ?? self.endIndex
        while self.distance(from: startIndex, to: endIndex) > 0 {
            try await block(self[startIndex..<endIndex])
            startIndex = endIndex
            endIndex = self.index(
                startIndex,
                offsetBy: chunkSize,
                limitedBy: self.endIndex,
            ) ?? self.endIndex
        }
    }
}

#if TESTABLE_BUILD

public extension Array {
    /// Removes and returns the first element of the array, if there is one.
    ///
    /// - Important
    /// This method runs in O(N), and consequently should not be used outside
    /// test code.
    mutating func popFirst() -> Element? {
        let firstElement = first
        self = Array(dropFirst())
        return firstElement
    }
}

#endif
