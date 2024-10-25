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

public extension Collection {

    func forEachChunk(chunkSize: Int, _ block: (Self.SubSequence) async throws -> Void) async rethrows {
        guard !isEmpty else { return }
        var startIndex = self.startIndex
        var endIndex = self.index(
            startIndex,
            offsetBy: chunkSize,
            limitedBy: self.endIndex
        ) ?? self.endIndex
        while self.distance(from: startIndex, to: endIndex) > 0 {
            try await block(self[startIndex..<endIndex])
            startIndex = endIndex
            endIndex = self.index(
                startIndex,
                offsetBy: chunkSize,
                limitedBy: self.endIndex
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
