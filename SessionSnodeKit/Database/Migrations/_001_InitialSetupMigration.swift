// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

enum _001_InitialSetupMigration: Migration {
    static let target: TargetMigrations.Identifier = .snodeKit
    static let identifier: String = "initialSetup"
    static let needsConfigSync: Bool = false
    static let minExpectedRunDuration: TimeInterval = 0.1
    
    static func migrate(_ db: Database) throws {
        try db.create(table: Snode.self) { t in
            t.column(.address, .text).notNull()
            t.column(.port, .integer).notNull()
            t.column(.ed25519PublicKey, .text).notNull()
            t.column(.x25519PublicKey, .text).notNull()
            
            t.primaryKey([.address, .port])
        }
        
        try db.create(table: SnodeSet.self) { t in
            t.column(.key, .text).notNull()
            t.column(.nodeIndex, .integer).notNull()
            t.column(.address, .text).notNull()
            t.column(.port, .integer).notNull()
            
            t.foreignKey(
                [.address, .port],
                references: Snode.self,
                columns: [.address, .port],
                onDelete: .cascade                                    // Delete if Snode deleted
            )
            t.primaryKey([.key, .nodeIndex])
        }
        
        try db.create(table: SnodeReceivedMessageInfo.self) { t in
            t.column(.id, .integer)
                .notNull()
                .primaryKey(autoincrement: true)
            t.column(.key, .text)
                .notNull()
                .indexed()                                            // Quicker querying
            t.column(.hash, .text)
                .notNull()
                .indexed()                                            // Quicker querying
            t.column(.expirationDateMs, .integer)
                .notNull()
                .indexed()                                            // Quicker querying
            
            t.uniqueKey([.key, .hash])
        }
        
        Storage.update(progress: 1, for: self, in: target) // In case this is the last migration
    }
}
