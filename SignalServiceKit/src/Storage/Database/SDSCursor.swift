//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDBCipher
import SignalCoreKit

public class SDSCursor<T> {
    private let statement: SelectStatement
    private let sqliteStatement: SQLiteStatement
    private let deserialize: (SelectStatement) throws -> T

    init (statement: SelectStatement,
          sqliteStatement: SQLiteStatement,
          deserialize: @escaping (SelectStatement) throws -> T) {

        self.statement = statement
        self.sqliteStatement = sqliteStatement
        self.deserialize = deserialize
    }

    // TODO: Revisit error handling in this class.
    public func next() throws -> T? {
        switch sqlite3_step(sqliteStatement) {
        case SQLITE_DONE:
            Logger.verbose("SQLITE_DONE")
            return nil
        case SQLITE_ROW:
            Logger.verbose("SQLITE_ROW")
            let entity = try deserialize(statement)
            return entity
        case let code:
            owsFailDebug("Code: \(code)")
            throw SDSError.invalidResult
        }
    }

    public func all() throws -> [T] {
        var result = [T]()
        while true {
            guard let model = try next() else {
                break
            }
            result.append(model)
        }
        return result
    }
}
