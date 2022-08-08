// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB

public protocol ColumnExpressible {
    associatedtype Columns: ColumnExpression
}

public extension ColumnExpressible where Columns: CaseIterable {
    /// Note: Where possible the `TableRecord.numberOfSelectedColumns(_:)` function should be used instead as
    /// it has proper validation
    static func numberOfSelectedColumns() -> Int {
        return Self.Columns.allCases.count
    }
}
