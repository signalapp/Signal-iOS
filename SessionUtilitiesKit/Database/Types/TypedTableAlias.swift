// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB

public class TypedTableAlias<T> where T: TableRecord, T: ColumnExpressible {
    let alias: TableAlias = TableAlias(name: T.databaseTableName)
    
    public init() {}
    
    public subscript(_ column: T.Columns) -> SQLExpression {
        return alias[column.name]
    }
}
