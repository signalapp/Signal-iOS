//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

protocol InterleavableCursor<Element> {
    associatedtype Element

    /// Returns the next value from the cursor, if any remain.
    mutating func nextElement() throws -> Element?
}

class InterleavingCompositeCursor<CursorType: InterleavableCursor> {
    typealias Element = CursorType.Element

    /// Compare two elements for sorting. Returns `true` if the first argument
    /// should be ordered before the second argument. `false` otherwise.
    typealias ElementSortComparator = (_ lhs: Element, _ rhs: Element) -> Bool

    private let nextElementComparator: ElementSortComparator

    private var cursors: [Int: CursorType]
    private var nextElements: [Int: Element?]

    /// Create a composite cursor that interleaves the given component cursors.
    ///
    /// - Parameter interleaving
    /// The cursors this composite cursor will interleave.
    /// - Parameter nextElementComparator
    /// A comparator used to determine which component cursor this composite
    /// cursor should return a value from next.
    init(
        interleaving cursors: [CursorType],
        nextElementComparator: @escaping ElementSortComparator
    ) throws {
        self.nextElementComparator = nextElementComparator

        self.cursors = [:]
        self.nextElements = [:]

        for (id, var cursor) in cursors.enumerated() {
            let element = try cursor.nextElement()

            self.cursors[id] = cursor
            self.nextElements[id] = element
        }
    }

    /// Returns the next value with the minimum value across
    func next() throws -> Element? {
        /// Get the min element from the "next" elements for each of our
        /// component cursors, which represents the next element the composite
        /// cursor should return.
        ///
        /// Note that if all cursors are depleted the min element is `nil`.
        guard
            let (nextCursorId, nextCursorElement) = nextElements.min(by: { (lhs, rhs) in
                if let lhsElement = lhs.value, let rhsElement = rhs.value {
                    // The comparator returns true if LHS is ordered first,
                    // which matches how min(by:) works.
                    return nextElementComparator(lhsElement, rhsElement)
                } else if lhs.value != nil {
                    // Treat a nil RHS as infinite, so LHS < RHS.
                    return true
                } else if rhs.value != nil {
                    // Treat a nil LHS as infinite, so LHS !< RHS.
                    return false
                } else {
                    // If both are nil, arbitrarily say LHS < RHS.
                    return true
                }
            }),
            let nextCursorElement
        else {
            return nil
        }

        // Get the new "next" for the cursor from which we're taking a value.
        nextElements[nextCursorId] = try cursors[nextCursorId]!.nextElement()

        return nextCursorElement
    }
}
