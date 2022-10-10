// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import DifferenceKit

protocol SessionTableSection: Differentiable {
    var title: String? { get }
    var style: SessionTableSectionStyle { get }
}

extension SessionTableSection {
    var title: String? { nil }
    var style: SessionTableSectionStyle { .none }
}

public enum SessionTableSectionStyle: Differentiable {
    case none
    case title
    case padding
}
