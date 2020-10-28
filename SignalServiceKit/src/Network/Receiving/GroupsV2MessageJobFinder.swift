//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDB

@objc
public class GRDBGroupsV2MessageJobFinder: NSObject {
    typealias ReadTransaction = GRDBReadTransaction
    typealias WriteTransaction = GRDBWriteTransaction

    @objc
    public func addJob(envelopeData: Data,
                       plaintextData: Data?,
                       groupId: Data,
                       wasReceivedByUD: Bool,
                       serverDeliveryTimestamp: UInt64,
                       transaction: GRDBWriteTransaction) {
        let job = IncomingGroupsV2MessageJob(envelopeData: envelopeData,
                                             plaintextData: plaintextData,
                                             groupId: groupId,
                                             wasReceivedByUD: wasReceivedByUD,
                                             serverDeliveryTimestamp: serverDeliveryTimestamp)
        job.anyInsert(transaction: transaction.asAnyWrite)
    }

    @objc
    public func allEnqueuedGroupIds(transaction: GRDBReadTransaction) -> [Data] {
        let sql = """
            SELECT DISTINCT \(incomingGroupsV2MessageJobColumn: .groupId)
            FROM \(IncomingGroupsV2MessageJobRecord.databaseTableName)
        """
        var result = [Data]()
        do {
            result = try Data.fetchAll(transaction.database, sql: sql)
        } catch {
            owsFailDebug("error: \(error)")
        }
        return result
    }

    @objc
    public func nextJobs(batchSize: UInt, transaction: GRDBReadTransaction) -> [IncomingGroupsV2MessageJob] {
        let sql = """
            SELECT *
            FROM \(IncomingGroupsV2MessageJobRecord.databaseTableName)
            ORDER BY \(incomingGroupsV2MessageJobColumn: .id)
            LIMIT \(batchSize)
        """
        let cursor = IncomingGroupsV2MessageJob.grdbFetchCursor(sql: sql,
                                                                transaction: transaction)

        return try! cursor.all()
    }

    @objc
    public func nextJobs(forGroupId groupId: Data,
                         batchSize: UInt,
                         transaction: GRDBReadTransaction) -> [IncomingGroupsV2MessageJob] {
        let sql = """
            SELECT *
            FROM \(IncomingGroupsV2MessageJobRecord.databaseTableName)
            WHERE \(incomingGroupsV2MessageJobColumn: .groupId) = ?
            ORDER BY \(incomingGroupsV2MessageJobColumn: .id)
            LIMIT \(batchSize)
        """
        let cursor = IncomingGroupsV2MessageJob.grdbFetchCursor(sql: sql,
                                                                arguments: [groupId],
                                                                transaction: transaction)

        return try! cursor.all()
    }

    @objc
    public func jobCount(forGroupId groupId: Data, transaction: GRDBReadTransaction) -> UInt {
        let sql = """
            SELECT COUNT(*)
            FROM \(IncomingGroupsV2MessageJobRecord.databaseTableName)
            WHERE \(incomingGroupsV2MessageJobColumn: .groupId) = ?
        """
        return try! UInt.fetchOne(transaction.database, sql: sql, arguments: [groupId]) ?? 0
    }

    @objc
    public func removeJobs(withUniqueIds uniqueIds: [String], transaction: GRDBWriteTransaction) {
        guard uniqueIds.count > 0 else {
            return
        }

        let commaSeparatedIds = uniqueIds.map { "\"\($0)\"" }.joined(separator: ", ")
        let sql = """
            DELETE
            FROM \(IncomingGroupsV2MessageJobRecord.databaseTableName)
            WHERE \(incomingGroupsV2MessageJobColumn: .uniqueId) in (\(commaSeparatedIds))
        """
        transaction.executeUpdate(sql: sql)
    }

    @objc
    public func jobCount(transaction: SDSAnyReadTransaction) -> UInt {
        return IncomingGroupsV2MessageJob.anyCount(transaction: transaction)
    }
}
