//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDBCipher
import SignalCoreKit

public class SDSInsertState {
    private var keyValues = [(columnName: String, value: DatabaseValueConvertible)]()

    public init() {}

    public func append(columnName: String, value: DatabaseValueConvertible?) {
        // Discard nil values.
        guard let value = value else {
            return
        }
        keyValues.append((columnName: columnName, value: value))
    }

    var columnNames: [String] {
        return keyValues.map { $0.columnName }
    }

    var values: [DatabaseValueConvertible] {
        return keyValues.map { $0.value }
    }
}

@objc
public class SDSSerialization: NSObject {

    // MARK: - Save (Upsert)

    public class func insert(tableMetadata: SDSTableMetadata,
                             insertState: SDSInsertState,
                             database: Database) throws {
        let tableName = tableMetadata.tableName
        let columnNames: [String] = insertState.columnNames
        let columnValues: [DatabaseValueConvertible] = insertState.values
        let columnsSQL = columnNames.map { $0.quotedDatabaseIdentifier }.joined(separator: ", ")
        let valuesSQL = databaseQuestionMarks(count: columnValues.count)
        let sql: String = "INSERT INTO \(tableName.quotedDatabaseIdentifier) (\(columnsSQL)) VALUES (\(valuesSQL))"

        let statement = try database.cachedUpdateStatement(sql: sql)
        guard let arguments = StatementArguments(columnValues) else {
            owsFail("Could not convert values.")
        }
        // TODO: We could use setArgumentsWithValidation for more safety.
        statement.unsafeSetArguments(arguments)
        try statement.execute()
    }

    // MARK: - Remove

    public class func delete(entity: SDSSerializable,
                             transaction: GRDBWriteTransaction) {
        let serializer = entity.serializer
        let database = transaction.database

        do {
            try delete(entity: entity,
                       uniqueIdColumnName: serializer.uniqueIdColumnName(),
                       uniqueIdColumnValue: serializer.uniqueIdColumnValue(),
                       database: database)
        } catch {
            // TODO:
            owsFail("Write failed: \(error)")
        }
    }

    fileprivate class func delete(entity: SDSSerializable,
                                  uniqueIdColumnName: String,
                                  uniqueIdColumnValue: DatabaseValueConvertible,
                                  database: Database) throws {
        let serializer = entity.serializer
        let tableMetadata = serializer.serializableColumnTableMetadata()
        let tableName = tableMetadata.tableName
        let whereSQL = "\(uniqueIdColumnName.quotedDatabaseIdentifier)=?"
        let sql: String = "DELETE FROM \(tableName.quotedDatabaseIdentifier) WHERE \(whereSQL)"

        let statement = try database.cachedUpdateStatement(sql: sql)
        guard let arguments = StatementArguments([uniqueIdColumnValue]) else {
            owsFail("Could not convert values.")
        }
        // TODO: We could use setArgumentsWithValidation for more safety.
        statement.unsafeSetArguments(arguments)
        try statement.execute()
    }
}
