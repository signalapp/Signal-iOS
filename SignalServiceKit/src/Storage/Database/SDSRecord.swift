//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDB

public protocol SDSRecord: Codable, FetchableRecord, PersistableRecord {
    var delegate: SDSRecordDelegate? { get set }
    var id: Int64? { get set }
    var uniqueId: String { get }
    var tableMetadata: SDSTableMetadata { get }
}

// MARK: - Save (Upsert)

public enum SDSSaveMode {
    case insert
    case update
}

public extension SDSRecord {

    private var uniqueIdColumnName: String {
        return "uniqueId"
    }

    private var uniqueIdColumnValue: String {
        return self.uniqueId
    }

    // This is a "fault-tolerant" save method that will upsert in production.
    // In DEBUG builds it will fail if the intention (insert v. update)
    // doesn't match the database contents.
    func sdsSave(saveMode: SDSSaveMode,
                 transaction: GRDBWriteTransaction) {
        // GRDB TODO: the record has an id property, but we can't use it here
        //            until we modify the upsert logic.
        //            grdbIdByUniqueId() verifies that the model hasn't been
        //            deleted from the db.
        if let grdbId: Int64 = grdbIdByUniqueId(transaction: transaction) {
            if saveMode == .insert {
                owsFailDebug("Could not insert existing record.")
            }
            sdsUpdate(grdbId: grdbId, transaction: transaction)
        } else {
            if saveMode == .update {
                owsFailDebug("Could not update missing record.")
            }
            sdsInsert(transaction: transaction)
        }
    }

    private func sdsUpdate(grdbId: Int64, transaction: GRDBWriteTransaction) {
        do {
            var recordCopy = self
            recordCopy.id = grdbId
            try recordCopy.update(transaction.database)
        } catch {
            owsFail("Update failed: \(error.grdbErrorForLogging)")
        }
    }

    private func sdsInsert(transaction: GRDBWriteTransaction) {
        do {
            try self.insert(transaction.database)
        } catch {
            owsFail("Insert failed: \(error.grdbErrorForLogging)")
        }
    }

    func sdsRemove(transaction: GRDBWriteTransaction) {
        do {
            let tableName = tableMetadata.tableName
            let whereSQL = "\(uniqueIdColumnName.quotedDatabaseIdentifier)=?"
            let sql: String = "DELETE FROM \(tableName.quotedDatabaseIdentifier) WHERE \(whereSQL)"

            let statement = try transaction.database.cachedUpdateStatement(sql: sql)
            guard let arguments = StatementArguments([uniqueIdColumnValue]) else {
                owsFail("Could not convert values.")
            }
            // TODO: We could use setArgumentsWithValidation for more safety.
            statement.unsafeSetArguments(arguments)
            try statement.execute()
        } catch {
            owsFail("Write failed: \(error.grdbErrorForLogging)")
        }
    }
}

// MARK: -

fileprivate extension SDSRecord {

    func grdbIdByUniqueId(transaction: GRDBReadTransaction) -> Int64? {
        BaseModel.grdbIdByUniqueId(tableMetadata: tableMetadata,
                                   uniqueIdColumnName: uniqueIdColumnName,
                                   uniqueIdColumnValue: uniqueIdColumnValue,
                                   transaction: transaction)
    }
}

// MARK: -

extension BaseModel {

    static func grdbIdByUniqueId(tableMetadata: SDSTableMetadata,
                                 uniqueIdColumnName: String,
                                 uniqueIdColumnValue: String,
                                 transaction: GRDBReadTransaction) -> Int64? {
        do {
            let tableName = tableMetadata.tableName
            let sql = "SELECT id FROM \(tableName.quotedDatabaseIdentifier) WHERE \(uniqueIdColumnName.quotedDatabaseIdentifier)=?"
            guard let value = try Int64.fetchOne(transaction.database, sql: sql, arguments: [uniqueIdColumnValue]) else {
                return nil
            }
            return value
        } catch {
            owsFailDebug("Could not find grdb id: \(error)")
            return nil
        }
    }
}
