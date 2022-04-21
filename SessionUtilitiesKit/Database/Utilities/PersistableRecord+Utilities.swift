// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB

public extension Array where Element: PersistableRecord {
    @discardableResult func deleteAll(_ db: Database) throws -> Bool {
        return try self.reduce(true) { prev, next in
            try (prev && next.delete(db))
        }
    }
    
    @discardableResult func saveAll(_ db: Database) throws {
        try forEach { try $0.save(db) }
    }
}
