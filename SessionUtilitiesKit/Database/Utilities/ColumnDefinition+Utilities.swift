// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB

public extension ColumnDefinition {
    @discardableResult func references<T>(
        _ table: T.Type,
        column: T.Columns? = nil,
        onDelete deleteAction: Database.ForeignKeyAction? = nil,
        onUpdate updateAction: Database.ForeignKeyAction? = nil,
        deferred: Bool = false
    ) -> Self where T: TableRecord, T: ColumnExpressible {
        return references(
            T.databaseTableName,
            column: column?.name,
            onDelete: deleteAction,
            onUpdate: updateAction,
            deferred: deferred
        )
    }
}
