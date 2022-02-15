// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

public extension Set {
    func inserting(_ other: Element) -> Set<Element> {
        var updatedSet: Set<Element> = self
        updatedSet.insert(other)

        return updatedSet
    }
}
