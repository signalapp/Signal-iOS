// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import PromiseKit
import SessionUtilitiesKit

class SynchronousStorage: Storage {
    override func writeAsync<T>(updates: @escaping (Database) throws -> T) {
        super.write(updates: updates)
    }
    
    override func writeAsync<T>(updates: @escaping (Database) throws -> T, completion: @escaping (Database, Swift.Result<T, Error>) throws -> Void) {
        super.write { db in
            do {
                var result: T?
                try db.inTransaction {
                    result = try updates(db)
                    return .commit
                }
                try? completion(db, .success(result!))
            }
            catch {
                try? completion(db, .failure(error))
            }
        }
    }
}
