// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB

public enum Position: Int, Decodable, Equatable, Hashable, DatabaseValueConvertible {
    case top
    case middle
    case bottom
    
    case individual
}
