// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB

public protocol Migration {
    static var identifier: String { get }
    
    static func migrate(_ db: Database) throws
}
