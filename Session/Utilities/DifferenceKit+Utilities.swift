// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import DifferenceKit
import SignalUtilitiesKit

public extension ArraySection {
    init(section: Model, elements: [Element] = []) {
        self.init(model: section, elements: elements)
    }
}
