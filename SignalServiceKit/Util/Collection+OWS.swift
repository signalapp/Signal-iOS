//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public extension Collection {

    /// Returns the element at the specified index iff it is within bounds, otherwise nil.
    @inlinable
    subscript(safe index: Index) -> Element? {
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
