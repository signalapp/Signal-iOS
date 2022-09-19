// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

enum _009_OpenGroupPermission: Migration {
    static let target: TargetMigrations.Identifier = .messagingKit
    static let identifier: String = "OpenGroupPermission"
    static let needsConfigSync: Bool = false
    static let minExpectedRunDuration: TimeInterval = 0.1
    
    static func migrate(_ db: GRDB.Database) throws {
        try db.alter(table: OpenGroup.self) { t in
            t.add(.permissions, .integer)
                .defaults(to: OpenGroup.Permissions.all)
        }
        
        // When modifying OpenGroup behaviours we should always look to reset the `infoUpdates`
        // value for all OpenGroups to ensure they all have the correct state for newly
        // added/changed fields
        _ = try OpenGroup
            .updateAll(db, OpenGroup.Columns.infoUpdates.set(to: 0))
        
        Storage.update(progress: 1, for: self, in: target) // In case this is the last migration
    }
}
