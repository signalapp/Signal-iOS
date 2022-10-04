// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import DifferenceKit

public enum IconSize: Differentiable {
    case small
    case medium
    case veryLarge
    
    case fit
    
    public var size: CGFloat {
        switch self {
            case .small: return 24
            case .medium: return 32
            case .veryLarge: return 80
            case .fit: return 0
        }
    }
}
