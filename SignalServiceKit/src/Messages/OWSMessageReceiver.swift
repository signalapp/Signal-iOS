//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDB

@objc
public extension OWSMessageDecryptJobFinder {

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
        owsFailDebug("We should be using SSKMessageDecryptJobQueue instead of this method.")

        let sql = """
        SELECT *
        FROM \(MessageDecryptJobRecord.databaseTableName)
        ORDER BY \(messageDecryptJobColumn: .createdAt)
        LIMIT 1
        """
        return OWSMessageDecryptJob.grdbFetchOne(sql: sql, transaction: transaction)
    }

    func enumerateJobs(transaction: SDSAnyReadTransaction, block: @escaping (OWSMessageDecryptJob, UnsafeMutablePointer<ObjCBool>) -> Void) throws {
        switch transaction.readTransaction {
        case .yapRead(let yapRead):
            return try enumerateJobs(ydbTransaction: yapRead, block: block)
        case .grdbRead(let grdbRead):
            return try enumerateJobs(grdbTransaction: grdbRead, block: block)
        }
    }

    private func enumerateJobs(ydbTransaction transaction: YapDatabaseReadTransaction, block: @escaping (OWSMessageDecryptJob, UnsafeMutablePointer<ObjCBool>) -> Void) throws {
        guard let view = transaction.safeViewTransaction(databaseExtensionName()) else {
            owsFailDebug("Could not load view transaction.")
            return
        }
        view.safe_enumerateKeysAndObjects(inGroup: databaseExtensionGroup(),
                                          extensionName: databaseExtensionName()) { (_, _, object, _, stopPtr) in
                                            guard let job = object as? OWSMessageDecryptJob else {
                                                owsFailDebug("unexpected job: \(type(of: object))")
                                                return
                                            }
                                            block(job, stopPtr)
        }
    }

    private func enumerateJobs(grdbTransaction transaction: GRDBReadTransaction, block: @escaping (OWSMessageDecryptJob, UnsafeMutablePointer<ObjCBool>) -> Void) throws {
        owsFailDebug("We should be using SSKMessageDecryptJobQueue instead of this method.")

        let sql = """
        SELECT uniqueId
        FROM \(MessageDecryptJobRecord.databaseTableName)
        ORDER BY \(messageDecryptJobColumn: .createdAt)
        """
        let cursor = try String.fetchCursor(transaction.database,
                                            sql: sql,
                                            arguments: [])
        while let jobId = try cursor.next() {
            guard let job = OWSMessageDecryptJob.anyFetch(uniqueId: jobId,
                                                          transaction: transaction.asAnyRead) else {
                                                            owsFailDebug("Missing job")
                                                            continue
            }

            var stop: ObjCBool = false
            block(job, &stop)
            if stop.boolValue {
                return
            }
        }
    }
}
