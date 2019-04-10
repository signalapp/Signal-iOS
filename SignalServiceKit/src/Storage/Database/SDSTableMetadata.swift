//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDBCipher
import SignalCoreKit

// TODO: We need to revise this.
@objc
public enum SDSColumnType: Int32 {
    case unicodeString
    case blob
    case bool
    case int
    case int64
}

@objc
public class SDSColumnMetadata: NSObject {

    @objc
    public let columnName: String

    @objc
    public let columnType: SDSColumnType

    @objc
    public let isOptional: Bool

    // If true, this column isn't needed for deserialization and can be skipped in SELECT statements.
    @objc
    public let skipSelect: Bool

    @objc
    public let columnIndex: Int32

    @objc
    public init(columnName: String, columnType: SDSColumnType, isOptional: Bool = false, skipSelect: Bool = false, columnIndex: Int32 = 0) {
        self.columnName = columnName
        self.columnType = columnType
        self.isOptional = isOptional
        self.skipSelect = skipSelect
        self.columnIndex = columnIndex
    }
}

// MARK: -

// TODO: Consider adding uniqueIdColumn field.
@objc
public class SDSTableMetadata: NSObject {

    @objc
    public let tableName: String

    @objc
    public let columns: [SDSColumnMetadata]

    public let databaseSelectionColumns: [Column]

    public let selectColumnNames: [String]

    @objc
    public init(tableName: String, columns: [SDSColumnMetadata]) {
        self.tableName = tableName
        self.columns = columns

        databaseSelectionColumns = columns.filter { (columMetaData) in
            return !columMetaData.skipSelect
            }.map { (columMetaData) in
                Column(columMetaData.columnName)
        }

        selectColumnNames = columns.filter { !$0.skipSelect }.map { $0.columnName }
    }

    public var columnNames: [String] {
        return columns.map { $0.columnName }
    }

    // MARK: - Table Creation

    private var hasCheckedTable = false

    // This method can only be called on the main thread, but it avoids
    // a transaction altogether.
    public func ensureTableExistsIfNecessary(databaseStorage: SDSDatabaseStorage) {
        AssertIsOnMainThread()

        guard !hasCheckedTable else {
            return
        }
        hasCheckedTable = true

        databaseStorage.writeSwallowingErrors { (transaction) in
            do {
                try self.ensureTableExists(transaction: transaction)
            } catch let error {
                // TODO:
                owsFail("Table creation failed: \(error)")
            }
        }
    }

    // This method can only be called on the main thread, but it avoids
    // a transaction altogether.
    public func ensureTableExists(transaction: SDSAnyWriteTransaction) throws {
        guard let database = transaction.transitional_grdbWriteTransaction else {
            throw SDSError.invalidTransaction
        }

        try ensureTableExists(database: database)
    }

    public func ensureTableExists(database: Database) throws {
        // TODO: Assert that table name is valid.

        try database.create(table: tableName, ifNotExists: true) { (table) in
            // TODO: Do we want this column on every table?
            table.autoIncrementedPrimaryKey("id")

            for columnMetadata in self.columns {
                switch columnMetadata.columnType {
                case .unicodeString:
                    // TODO: How to make column optional?
                    table.column(columnMetadata.columnName, .text)
                case .blob:
                    // TODO: How to make column optional?
                    table.column(columnMetadata.columnName, .blob)
                //                            t.column("email", .text).unique(onConflict: .replace) // <--
                case .bool:
                    // TODO: How to make column optional?
                    table.column(columnMetadata.columnName, .boolean)
                case .int:
                    // TODO: How to make column optional?
                    table.column(columnMetadata.columnName, .integer)
                case .int64:
                    // TODO: How to make column optional?
                    // TODO: What's the right column type here?
                    table.column(columnMetadata.columnName, .integer)
                }
            }
        }
    }
}
