// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

// TODO: Remove/Move these
struct Place: Codable, FetchableRecord, PersistableRecord, ColumnExpressible {
    static var databaseTableName: String { "place" }
    
    public enum Columns: String, CodingKey, ColumnExpression {
        case id
        case name
    }
    
    let id: String
    let name: String
}

struct Setting: Codable, FetchableRecord, PersistableRecord, TableRecord, ColumnExpressible {
    static var databaseTableName: String { "settings" }
    
    public enum Columns: String, CodingKey, ColumnExpression {
        case key
        case value
    }
    
    let key: String
    let value: Data
}

enum _001_InitialSetupMigration: Migration {
    static let identifier: String = "initialSetup"
    
    static func migrate(_ db: Database) throws {
        try db.create(table: Setting.self) { t in
            t.column(.key, .text)
                .notNull()
                .unique(onConflict: .abort)
                .primaryKey()
            t.column(.value, .blob).notNull()
        }
        
        try db.create(table: Place.self) { t in
            t.column(.id, .text).notNull().primaryKey()
            t.column(.name, .text).notNull()
        }
    }
}
