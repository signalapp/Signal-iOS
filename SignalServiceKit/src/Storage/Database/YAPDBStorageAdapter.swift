//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

struct YAPDBStorageAdapter {
    let storage: OWSPrimaryStorage
}

// MARK: -

extension YAPDBStorageAdapter: SDSDatabaseStorageAdapter {
    func readThrows(block: @escaping (YapDatabaseReadTransaction) throws -> Void) throws {
        var errorToRaise: Error?
        storage.dbReadConnection.read { yapTransaction in
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
        owsFailDebug("YDB UI read.")
        storage.dbReadConnection.read { yapTransaction in
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

// MARK: - Reporting

extension YAPDBStorageAdapter {
    var databaseFileSize: UInt64 {
        return OWSPrimaryStorage.shared?.databaseFileSize() ?? 0
    }

    var databaseWALFileSize: UInt64 {
        return OWSPrimaryStorage.shared?.databaseWALFileSize() ?? 0
    }

    var databaseSHMFileSize: UInt64 {
        return OWSPrimaryStorage.shared?.databaseSHMFileSize() ?? 0
    }
}
