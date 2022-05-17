// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB

public extension TableRecord where Self: ColumnExpressible {
    static var fullTextSearchTableName: String { "\(self.databaseTableName)_fts" }
    
    static func select(_ selection: Columns...) -> QueryInterfaceRequest<Self> {
        return all().select(selection)
    }
}
