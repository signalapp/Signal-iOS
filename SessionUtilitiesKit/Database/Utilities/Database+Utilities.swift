// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB

public extension Database {
    func create<T>(
        table: T.Type,
        options: TableOptions = [],
        body: (TypedTableDefinition<T>) throws -> Void
    ) throws where T: TableRecord, T: ColumnExpressible {
        try create(table: T.databaseTableName, options: options) { tableDefinition in
            let typedDefinition: TypedTableDefinition<T> = TypedTableDefinition(definition: tableDefinition)
            
            try body(typedDefinition)
        }
    }
    
    func makeFTS5Pattern<T>(rawPattern: String, forTable table: T.Type) throws -> FTS5Pattern where T: TableRecord, T: ColumnExpressible {
        return try makeFTS5Pattern(rawPattern: rawPattern, forTable: table.databaseTableName)
    }
}
