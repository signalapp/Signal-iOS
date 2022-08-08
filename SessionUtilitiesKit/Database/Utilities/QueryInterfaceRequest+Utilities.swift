// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB

public extension QueryInterfaceRequest {
    /// Returns true if the request matches a row in the database.
    ///
    ///     try Player.filter(Column("name") == "Arthur").isEmpty(db)
    ///
    /// - parameter db: A database connection.
    /// - returns: Whether the request matches a row in the database.
    func isNotEmpty(_ db: Database) throws -> Bool {
        return ((try? SQLRequest("SELECT \(exists())").fetchOne(db)) ?? false)
    }
}

public extension QueryInterfaceRequest where RowDecoder: ColumnExpressible {
    func select(_ selection: RowDecoder.Columns...) -> Self {
        select(selection)
    }
    
    func order(_ orderings: RowDecoder.Columns...) -> QueryInterfaceRequest {
        order(orderings)
    }
}
