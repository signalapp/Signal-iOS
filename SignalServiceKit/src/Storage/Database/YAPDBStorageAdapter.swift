//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

struct YAPDBStorageAdapter {
    let storage: OWSPrimaryStorage
}

// MARK: -

extension YAPDBStorageAdapter: SDSDatabaseStorageAdapter {
    func uiReadThrows(block: @escaping (YapDatabaseReadTransaction) throws -> Void) throws {
        var errorToRaise: Error?
        storage.uiDatabaseConnection.read { yapTransaction in
            do {
                try block(yapTransaction)
            } catch {
                errorToRaise = error
            }
        }
        if let error = errorToRaise {
            throw error
        }
    }

    func uiRead(block: @escaping (YapDatabaseReadTransaction) -> Void) {
        storage.uiDatabaseConnection.read { yapTransaction in
            block(yapTransaction)
        }
    }

    func read(block: @escaping (YapDatabaseReadTransaction) -> Void) {
        storage.dbReadConnection.read { yapTransaction in
            block(yapTransaction)
        }
    }

    func write(block: @escaping (YapDatabaseReadWriteTransaction) -> Void) {
        storage.dbReadWriteConnection.readWrite { yapTransaction in
            block(yapTransaction)
        }
    }

    func newDatabaseQueue() -> YAPDBDatabaseQueue {
        return YAPDBDatabaseQueue(databaseConnection: storage.newDatabaseConnection())
    }
}
