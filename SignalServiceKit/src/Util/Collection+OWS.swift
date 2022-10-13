//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public extension Collection {

    /// Returns the element at the specified index iff it is within bounds, otherwise nil.
    @inlinable
    subscript (safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

public extension BidirectionalCollection {
    @inlinable
    func suffix(while predicate: (Element) throws -> Bool) rethrows -> Self.SubSequence {
        guard let startIndex = try self.lastIndex(where: { try !predicate($0) }) else {
            return self[...]
        }
        return self[startIndex...].dropFirst()
    }
}

public extension RandomAccessCollection {
    func chunked(by chunkSize: Int) -> [SubSequence] {
        stride(from: 0, to: count, by: chunkSize).map {
            dropFirst($0).prefix(chunkSize)
        }
    }

    @inlinable var nilIfEmpty: Self? {
        isEmpty ? nil : self
    }
}

/// Like the built-in `zip` but works with arbitrarily many arrays.
/*
     let input = [[a1, a2, a3, a4],
                  [b1, b2, b3, b4],
                  [c1, c2, c3, c4]]

     transpose(input)
         -> [[a1, b1, c1],
             [a2, b2, c2],
             [a3, b3, c3],
             [a4, b4, c4]]
 */
public func transpose<T>(_ arrays: [[T]]) -> [[T]] {
    guard let firstArray = arrays.first else {
        return [[]]
    }

    var minCount: Int = firstArray.count
    for array in arrays {
        // we could remove this check and zip to the shortest length
        // but typically we want to zip identical length arrays.
        assert(minCount == array.count)
        minCount = min(minCount, array.count)
    }

    var output: [[T]] = []
    for i in 0..<minCount {
        output.append(arrays.map { $0[i] })
    }

    return output
}
