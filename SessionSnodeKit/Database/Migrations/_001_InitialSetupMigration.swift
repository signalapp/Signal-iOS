// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

enum _001_InitialSetupMigration: Migration {
    static let identifier: String = "initialSetup"
    
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
                onDelete: .cascade
            )
            t.primaryKey([.key, .nodeIndex])
        }
        
        try db.create(table: SnodeReceivedMessageInfo.self) { t in
            t.column(.key, .text)
                .notNull()
                .indexed()
            t.column(.hash, .text).notNull()
            t.column(.expirationDateMs, .integer)
                .notNull()
                .indexed()
            
            t.primaryKey([.key, .hash])
        }
    }
}
