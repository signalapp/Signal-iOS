// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

/// This migration recreates the interaction FTS table and adds the threadId so we can do a performant in-conversation
/// searh (currently it's much slower than the global search)
enum _009_AddThreadIdToFTS: Migration {
    static let target: TargetMigrations.Identifier = .messagingKit
    static let identifier: String = "AddThreadIdToFTS"
    static let needsConfigSync: Bool = false
    static let minExpectedRunDuration: TimeInterval = 3
    
    static func migrate(_ db: Database) throws {
        // Can't actually alter a virtual table in SQLite so we need to drop and recreate it,
        // luckily this is actually pretty quick
        if try db.tableExists(Interaction.fullTextSearchTableName) {
            try db.drop(table: Interaction.fullTextSearchTableName)
            try db.dropFTS5SynchronizationTriggers(forTable: Interaction.fullTextSearchTableName)
        }
        
        try db.create(virtualTable: Interaction.fullTextSearchTableName, using: FTS5()) { t in
            t.synchronize(withTable: Interaction.databaseTableName)
            t.tokenizer = _001_InitialSetupMigration.fullTextSearchTokenizer

            t.column(Interaction.Columns.body.name)
            t.column(Interaction.Columns.threadId.name)
        }
        
        Storage.update(progress: 1, for: self, in: target) // In case this is the last migration
    }
}
