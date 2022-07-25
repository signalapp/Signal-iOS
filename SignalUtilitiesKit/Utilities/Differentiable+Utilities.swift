// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import DifferenceKit

extension Int: ContentEquatable {
    public func isContentEqual(to source: Int) -> Bool {
        return (self == source)
    }
}
