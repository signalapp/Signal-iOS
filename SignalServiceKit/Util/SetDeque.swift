//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct SetDeque<Element> where Element: Hashable {
    private var orderedMembers: [Element?] = Array(repeating: nil, count: 8)
    private var unorderedMembers = Set<Element>()

    /// - Complexity: O(1)
    public func contains(_ element: Element) -> Bool {
        return unorderedMembers.contains(element)
    }

    /// - Complexity: O(1)
    public var count: Int {
        return self.unorderedMembers.count
    }

    private var nextIndexToPush = 0

    /// - Complexity: O(1) on average
    public mutating func pushBack(_ element: Element) {
        guard unorderedMembers.insert(element).inserted else {
            return
        }
        if self.orderedMembers[self.nextIndexToPush] != nil {
            assert(self.nextIndexToPush == self.nextIndexToPop)
            assert(self.orderedMembers.allSatisfy({ $0 != nil }))
            self.nextIndexToPush = self.orderedMembers.count
            self.orderedMembers = Array(
                self.orderedMembers[self.nextIndexToPop...]
                    + self.orderedMembers[..<self.nextIndexToPop]
                    + Array(repeating: nil, count: self.orderedMembers.count),
            )
            self.nextIndexToPop = 0
        }
        self.orderedMembers[self.nextIndexToPush] = element
        self.nextIndexToPush += 1
        self.nextIndexToPush %= self.orderedMembers.count
    }

    private var nextIndexToPop = 0

    /// - Complexity: O(1)
    public mutating func popFront() -> Element? {
        let result = self.orderedMembers[self.nextIndexToPop]
        if let result {
            self.unorderedMembers.remove(result)
            self.orderedMembers[self.nextIndexToPop] = nil
            self.nextIndexToPop += 1
            self.nextIndexToPop %= self.orderedMembers.count
        }
        return result
    }
}
