// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB

/// This is a convenience wrapper around the GRDB `TableAlteration` class which allows for shorthand
/// when creating tables
public class TypedTableAlteration<T> where T: TableRecord, T: ColumnExpressible {
    let alteration: TableAlteration
    
    init(alteration: TableAlteration) {
        self.alteration = alteration
    }
    
    @discardableResult public func add(_ key: T.Columns, _ type: Database.ColumnType? = nil) -> ColumnDefinition {
        return alteration.add(column: key.name, type)
    }
    
    public func rename(column: String, to key: T.Columns) {
        alteration.rename(column: column, to: key.name)
    }
    
    public func drop(_ key: T.Columns) {
        return alteration.drop(column: key.name)
    }
}
