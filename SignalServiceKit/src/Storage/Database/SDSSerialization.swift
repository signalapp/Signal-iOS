//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDBCipher
import SignalCoreKit

@objc
public class SDSSerialization: NSObject {

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
