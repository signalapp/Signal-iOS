//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

protocol MessageContentJobFinder {
    associatedtype ReadTransaction
    associatedtype WriteTransaction

    func addJob(envelopeData: Data, plaintextData: Data?, wasReceivedByUD: Bool, serverDeliveryTimestamp: UInt64, transaction: WriteTransaction)
    func nextJobs(batchSize: UInt, transaction: ReadTransaction) -> [OWSMessageContentJob]
    func allJobs(transaction: ReadTransaction) -> [OWSMessageContentJob]
    func removeJobs(withUniqueIds uniqueIds: [String], transaction: WriteTransaction)
}

@objc
public class AnyMessageContentJobFinder: NSObject, MessageContentJobFinder {
    typealias ReadTransaction = SDSAnyReadTransaction
    typealias WriteTransaction = SDSAnyWriteTransaction

    let grdbAdapter = GRDBMessageContentJobFinder()

    @objc
    public func addJob(envelopeData: Data, plaintextData: Data?, wasReceivedByUD: Bool, serverDeliveryTimestamp: UInt64, transaction: SDSAnyWriteTransaction) {
        switch transaction.writeTransaction {
        case .grdbWrite(let grdbWrite):
            grdbAdapter.addJob(envelopeData: envelopeData, plaintextData: plaintextData, wasReceivedByUD: wasReceivedByUD, serverDeliveryTimestamp: serverDeliveryTimestamp, transaction: grdbWrite)
        }
    }

    @objc
    public func nextJobs(batchSize: UInt, transaction: SDSAnyReadTransaction) -> [OWSMessageContentJob] {
        switch transaction.readTransaction {
        case .grdbRead(let grdbRead):
            return grdbAdapter.nextJobs(batchSize: batchSize, transaction: grdbRead)
        }
    }

    @objc
    func allJobs(transaction: SDSAnyReadTransaction) -> [OWSMessageContentJob] {
        switch transaction.readTransaction {
        case .grdbRead(let grdbRead):
            return grdbAdapter.allJobs(transaction: grdbRead)
        }
    }

    @objc
    public func removeJobs(withUniqueIds uniqueIds: [String], transaction: SDSAnyWriteTransaction) {
        switch transaction.writeTransaction {
        case .grdbWrite(let grdbWrite):
            grdbAdapter.removeJobs(withUniqueIds: uniqueIds, transaction: grdbWrite)
        }
    }

    @objc
    public func jobCount(transaction: SDSAnyReadTransaction) -> UInt {
        return OWSMessageContentJob.anyCount(transaction: transaction)
    }
}

class GRDBMessageContentJobFinder: MessageContentJobFinder {
    typealias ReadTransaction = GRDBReadTransaction
    typealias WriteTransaction = GRDBWriteTransaction

    func addJob(envelopeData: Data, plaintextData: Data?, wasReceivedByUD: Bool, serverDeliveryTimestamp: UInt64, transaction: GRDBWriteTransaction) {
        let job = OWSMessageContentJob(envelopeData: envelopeData, plaintextData: plaintextData, wasReceivedByUD: wasReceivedByUD, serverDeliveryTimestamp: serverDeliveryTimestamp)
        job.anyInsert(transaction: transaction.asAnyWrite)
    }

    func nextJobs(batchSize: UInt, transaction: GRDBReadTransaction) -> [OWSMessageContentJob] {
        let sql = """
            SELECT *
            FROM \(MessageContentJobRecord.databaseTableName)
            ORDER BY \(messageContentJobColumn: .id)
            LIMIT \(batchSize)
        """
        let cursor = OWSMessageContentJob.grdbFetchCursor(sql: sql,
                                                          transaction: transaction)

        return try! cursor.all()
    }

    func allJobs(transaction: GRDBReadTransaction) -> [OWSMessageContentJob] {
        let sql = """
            SELECT *
            FROM \(MessageContentJobRecord.databaseTableName)
            ORDER BY \(messageContentJobColumn: .id)
        """
        let cursor = OWSMessageContentJob.grdbFetchCursor(sql: sql,
                                                          transaction: transaction)

        return try! cursor.all()
    }

    func removeJobs(withUniqueIds uniqueIds: [String], transaction: GRDBWriteTransaction) {
        guard uniqueIds.count > 0 else {
            return
        }

        let commaSeparatedIds = uniqueIds.map { "\"\($0)\"" }.joined(separator: ", ")
        let sql = """
            DELETE
            FROM \(MessageContentJobRecord.databaseTableName)
            WHERE \(messageContentJobColumn: .uniqueId) in (\(commaSeparatedIds))
        """

        transaction.execute(sql: sql)
    }
}
