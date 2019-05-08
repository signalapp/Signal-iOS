//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDBCipher

protocol MessageContentJobFinder {
    associatedtype ReadTransaction
    associatedtype WriteTransaction

    func addJob(envelopeData: Data, plaintextData: Data?, wasReceivedByUD: Bool, transaction: WriteTransaction)
    func nextJobs(batchSize: UInt, transaction: ReadTransaction) -> [OWSMessageContentJob]
    func removeJobs(withUniqueIds uniqueIds: [String], transaction: WriteTransaction)
}

@objc
public class AnyMessageContentJobFinder: NSObject, MessageContentJobFinder {
    typealias ReadTransaction = SDSAnyReadTransaction
    typealias WriteTransaction = SDSAnyWriteTransaction

    let yapAdapter = YAPDBMessageContentJobFinder()
    let grdbAdapter = GRDBMessageContentJobFinder()

    @objc
    public func addJob(envelopeData: Data, plaintextData: Data?, wasReceivedByUD: Bool, transaction: SDSAnyWriteTransaction) {
        switch transaction.writeTransaction {
        case .yapWrite(let yapWrite):
            yapAdapter.addJob(withEnvelopeData: envelopeData, plaintextData: plaintextData, wasReceivedByUD: wasReceivedByUD, transaction: yapWrite)
        case .grdbWrite(let grdbWrite):
            grdbAdapter.addJob(envelopeData: envelopeData, plaintextData: plaintextData, wasReceivedByUD: wasReceivedByUD, transaction: grdbWrite)
        }
    }

    @objc
    public func nextJobs(batchSize: UInt, transaction: SDSAnyReadTransaction) -> [OWSMessageContentJob] {
        switch transaction.readTransaction {
        case .yapRead(let yapRead):
            return yapAdapter.nextJobs(forBatchSize: batchSize, transaction: yapRead)
        case .grdbRead(let grdbRead):
            return grdbAdapter.nextJobs(batchSize: batchSize, transaction: grdbRead)
        }
    }

    @objc
    public func removeJobs(withUniqueIds uniqueIds: [String], transaction: SDSAnyWriteTransaction) {
        switch transaction.writeTransaction {
        case .yapWrite(let yapWrite):
            yapAdapter.removeJobs(withIds: uniqueIds, transaction: yapWrite)
        case .grdbWrite(let grdbWrite):
            grdbAdapter.removeJobs(withUniqueIds: uniqueIds, transaction: grdbWrite)
        }
    }
}

class GRDBMessageContentJobFinder: MessageContentJobFinder {
    typealias ReadTransaction = GRDBReadTransaction
    typealias WriteTransaction = GRDBWriteTransaction

    func addJob(envelopeData: Data, plaintextData: Data?, wasReceivedByUD: Bool, transaction: GRDBWriteTransaction) {
        let job = OWSMessageContentJob(envelopeData: envelopeData, plaintextData: plaintextData, wasReceivedByUD: wasReceivedByUD)
        SDSSerialization.save(entity: job, transaction: transaction)
    }

    func nextJobs(batchSize: UInt, transaction: GRDBReadTransaction) -> [OWSMessageContentJob] {
        let sql = """
            SELECT *
            FROM \(MessageContentJobRecord.databaseTableName)
            ORDER BY \(messageContentJobColumn: .id)
            LIMIT \(batchSize)
        """
        let cursor = OWSMessageContentJob.grdbFetchCursor(sql: sql,
                                                          arguments: [],
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

        try! transaction.database.execute(sql: sql)
    }
}
