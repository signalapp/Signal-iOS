//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

public struct OrderedSet<Element> where Element: Hashable {
    public private(set) var orderedMembers: [Element] = []
    private var set: Set<Element> = []

    public init(_ members: [Element]) {
        set = []
        orderedMembers = []

        for element in members {
            append(element)
        }
    }

    @discardableResult
    public mutating func append(_ element: Element) -> (Bool, Element) {
        let (wasInserted, elementAfterInsert) = set.insert(element)

        if wasInserted {
            orderedMembers.append(element)
        }

        return (wasInserted, elementAfterInsert)
    }

    public mutating func remove(_ element: Element) {
        set.remove(element)
        orderedMembers = orderedMembers.filter { $0 != element }
    }

    public mutating func remove(_ elements: [Element]) {
        for element in elements {
            remove(element)
        }
    }

    public func contains(_ element: Element) -> Bool {
        return set.contains(element)
    }

    public var isEmpty: Bool {
        return set.isEmpty
    }

    public var count: Int {
        return set.count
    }

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
