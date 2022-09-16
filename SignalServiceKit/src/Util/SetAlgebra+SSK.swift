//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

public extension SetAlgebra {
    /// Returns `true` if `self` and `other` have any elements in common.
    @inlinable
    func intersects(_ other: Self) -> Bool {
        !self.isDisjoint(with: other)
    }

    /// Inserts `element` into the set if `present` is `true`; otherwise removes it.
    ///
    /// Returns the equivalent element that was previously in the set, if there was one.
    @discardableResult @inlinable
    mutating func update(_ element: Element, present: Bool) -> Element? {
        if present {
            return self.update(with: element)
        } else {
            return self.remove(element)
        }
    }
}
