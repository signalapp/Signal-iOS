//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct OrderedSet<Element> where Element: Hashable {
    public private(set) var orderedMembers: [Element] = []
    public private(set) var unorderedMembers: Set<Element> = []

    /// - Complexity: O(n)
    public init(_ members: [Element]) {
        unorderedMembers = []
        orderedMembers = []

        for element in members {
            append(element)
        }
    }

    /// - Complexity: O(1) on average
    @discardableResult
    public mutating func append(_ element: Element) -> (Bool, Element) {
        let (wasInserted, elementAfterInsert) = unorderedMembers.insert(element)

        if wasInserted {
            orderedMembers.append(element)
        }

        return (wasInserted, elementAfterInsert)
    }

    /// - Complexity: O(n)
    public mutating func remove(_ element: Element) {
        if let removedMember = unorderedMembers.remove(element) {
            orderedMembers.removeAll(where: { $0 == removedMember })
        }
    }

    /// - Complexity: O(1)
    public func contains(_ element: Element) -> Bool {
        return unorderedMembers.contains(element)
    }

    /// - Complexity: O(1)
    public var isEmpty: Bool {
        return unorderedMembers.isEmpty
    }

    /// - Complexity: O(1)
    public var count: Int {
        return unorderedMembers.count
    }

    /// - Complexity: O(1)
    public var first: Element? {
        return orderedMembers.first
    }

    // TODO: I only implemented the minimum API that I needed. There's lots more that could
    // reasonably be added to an OrderedSet (union, etc.)
}

extension OrderedSet: ExpressibleByArrayLiteral {
    public typealias ArrayLiteralElement = Element
    public init(arrayLiteral elements: Element...) {
        self.init(elements)
    }
}
