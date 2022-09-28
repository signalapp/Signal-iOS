// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB

public enum Position: Int, Decodable, Equatable, Hashable, DatabaseValueConvertible {
    case top
    case middle
    case bottom
    
    case individual
    
    public static func with(_ index: Int, count: Int) -> Position {
        guard count > 1 else { return .individual }
        
        switch index {
            case 0: return .top
            case (count - 1): return .bottom
            default: return .middle
        }
    }
}
