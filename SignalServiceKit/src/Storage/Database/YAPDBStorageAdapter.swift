//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

struct YAPDBStorageAdapter {
    let storage: OWSPrimaryStorage
}

// MARK: -

extension YAPDBStorageAdapter: SDSDatabaseStorageAdapter {
    func readThrows(block: (YapDatabaseReadTransaction) throws -> Void) throws {
        try withoutActuallyEscaping(block) { block in
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
    }

    func uiRead(block: (YapDatabaseReadTransaction) -> Void) {
        withoutActuallyEscaping(block) { block in
            owsFailDebug("YDB UI read.")
            storage.dbReadConnection.read { yapTransaction in
                block(yapTransaction)
            }
        }
    }

    func read(block: (YapDatabaseReadTransaction) -> Void) {
        withoutActuallyEscaping(block) { block in
            storage.dbReadConnection.read { yapTransaction in
                block(yapTransaction)
            }
        }
    }

    func write(block: (YapDatabaseReadWriteTransaction) -> Void) {
        withoutActuallyEscaping(block) { block in
            storage.dbReadWriteConnection.readWrite { yapTransaction in
                block(yapTransaction)
            }
        }
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
