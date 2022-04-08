// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB

/// This is a convenience wrapper around the GRDB `TableDefinition` class which allows for shorthand
/// when creating tables
public class TypedTableDefinition<T> where T: TableRecord, T: ColumnExpressible {
    let definition: TableDefinition
    
    init(definition: TableDefinition) {
        self.definition = definition
    }
    
    @discardableResult public func column(_ key: T.Columns, _ type: Database.ColumnType? = nil) -> ColumnDefinition {
        return definition.column(key.name, type)
    }
    
    public func primaryKey(_ columns: [T.Columns], onConflict: Database.ConflictResolution? = nil) {
        definition.primaryKey(columns.map { $0.name }, onConflict: onConflict)
    }
    
    public func uniqueKey(_ columns: [T.Columns], onConflict: Database.ConflictResolution? = nil) {
        definition.uniqueKey(columns.map { $0.name }, onConflict: onConflict)
    }
    
    public func foreignKey<Other>(
        _ columns: [T.Columns],
        references table: Other.Type,
        columns destinationColumns: [Other.Columns]? = nil,
        onDelete: Database.ForeignKeyAction? = nil,
        onUpdate: Database.ForeignKeyAction? = nil,
        deferred: Bool = false
    ) where Other: TableRecord, Other: ColumnExpressible {
        return definition.foreignKey(
            columns.map { $0.name },
            references: table.databaseTableName,
            columns: destinationColumns?.map { $0.name },
            onDelete: onDelete,
            onUpdate: onUpdate,
            deferred: deferred
        )
    }
}
