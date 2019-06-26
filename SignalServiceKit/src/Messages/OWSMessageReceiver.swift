//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDBCipher

@objc
public extension OWSMessageDecryptJobFinder {

    @objc
    func nextJob(transaction: SDSAnyReadTransaction) -> OWSMessageDecryptJob? {
        switch transaction.readTransaction {
        case .yapRead(let ydbTransaction):
            return nextJob(ydbTransaction: ydbTransaction)
        case .grdbRead(let grdbTransaction):
            return nextJob(grdbTransaction: grdbTransaction)
        }
    }

    private func nextJob(ydbTransaction transaction: YapDatabaseReadTransaction) -> OWSMessageDecryptJob? {
        guard let viewTransaction = transaction.safeViewTransaction(databaseExtensionName()) else {
            owsFailDebug("Could not load view transaction.")
            return nil
        }
        guard let object = viewTransaction.firstObject(inGroup: databaseExtensionGroup()) else {
            return nil
        }
        guard let job = object as? OWSMessageDecryptJob else {
            owsFailDebug("Object has unexpected type: \(type(of: object))")
            return nil
        }
        return job
    }

    private func nextJob(grdbTransaction transaction: GRDBReadTransaction) -> OWSMessageDecryptJob? {
        let sql = """
        SELECT *
        FROM \(MessageDecryptJobRecord.databaseTableName)
        ORDER BY \(messageDecryptJobColumn: .createdAt) DESC
        LIMIT 1
        """
        let arguments: StatementArguments = []
        return OWSMessageDecryptJob.grdbFetchOne(sql: sql, arguments: arguments, transaction: transaction)
    }
}
