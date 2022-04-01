// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB

enum _001_InitialSetupMigration: Migration {
    static let identifier: String = "initialSetup"
    
    static func migrate(_ db: Database) throws {
        try db.create(table: Identity.self) { t in
            t.column(.variant, .text)
                .notNull()
                .unique()
                .primaryKey()
            t.column(.data, .blob).notNull()
        }
        
        try db.create(table: Setting.self) { t in
            t.column(.key, .text)
                .notNull()
                .unique()
                .primaryKey()
            t.column(.value, .blob).notNull()
        }
    }
}
