// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB

public extension DatabaseMigrator {
    mutating func registerMigration(_ identifier: TargetMigrations.Identifier, migration: Migration.Type, foreignKeyChecks: ForeignKeyChecks = .deferred) {
        self.registerMigration("\(identifier).\(migration.identifier)", migrate: migration.migrate)
    }
}
