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
    
    func alter<T>(
        table: T.Type,
        body: (TypedTableAlteration<T>) -> Void
    ) throws where T: TableRecord, T: ColumnExpressible {
        try alter(table: T.databaseTableName) { tableAlteration in
            let typedAlteration: TypedTableAlteration<T> = TypedTableAlteration(alteration: tableAlteration)
            
            body(typedAlteration)
        }
    }
    
    func makeFTS5Pattern<T>(rawPattern: String, forTable table: T.Type) throws -> FTS5Pattern where T: TableRecord, T: ColumnExpressible {
        return try makeFTS5Pattern(rawPattern: rawPattern, forTable: table.databaseTableName)
    }
    
    func interrupt() {
        guard sqliteConnection != nil else { return }
        
        sqlite3_interrupt(sqliteConnection)
    }
}
