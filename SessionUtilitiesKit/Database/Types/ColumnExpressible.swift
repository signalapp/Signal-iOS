// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB

public protocol ColumnExpressible {
    associatedtype Columns: ColumnExpression
}
