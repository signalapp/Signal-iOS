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

    // TODO: I only implemented the minimum API that I needed. There's lots more that could
    // reasonably be added to an OrderedSet (remove, union, etc.)
}

extension OrderedSet: ExpressibleByArrayLiteral {
    public typealias ArrayLiteralElement = Element
    public init(arrayLiteral elements: Element...) {
        self.init(elements)
    }
}
