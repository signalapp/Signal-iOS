//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

public protocol JobRecordFinder<JobRecordType> {
    associatedtype JobRecordType: JobRecord

    /// Fetches a single JobRecord from the database.
    ///
    /// Returns `nil` a JobRecord doesn't exist for `rowId`.
    func fetchJob(rowId: JobRecord.RowId, tx: DBReadTransaction) throws -> JobRecordType?

    /// Removes a single JobRecord from the database.
    func removeJob(_ jobRecord: JobRecordType, tx: DBWriteTransaction)

    /// Fetches all runnable jobs.
    ///
    /// This method may use multiple transactions, may use write transactions,
    /// may delete jobs that can't ever be run, etc.
    ///
    /// It returns all jobs that can be run (and invokes the block for each job).
    ///
    /// Conforming types should avoid long-running write transactions.
    func loadRunnableJobs(updateRunnableJobRecord: @escaping (JobRecordType, DBWriteTransaction) -> Void) async throws -> [JobRecordType]

    func enumerateJobRecords(
        transaction: DBReadTransaction,
        block: (JobRecordType, inout Bool) -> Void
    ) throws

    func enumerateJobRecords(
        status: JobRecord.Status,
        transaction: DBReadTransaction,
        block: (JobRecordType, inout Bool) -> Void
    ) throws
}

public extension JobRecordFinder {
    func allRecords(status: JobRecord.Status, transaction: DBReadTransaction) throws -> [JobRecordType] {
        var result: [JobRecordType] = []
        try enumerateJobRecords(status: status, transaction: transaction) { jobRecord, _ in
            result.append(jobRecord)
        }
        return result
    }
}

private enum Constants {
    /// The number of JobRecords to fetch in a batch.
    ///
    /// Most job queues won't ever have more than a few records at the same
    /// time. Other times, a job queue may build up a huge backlog, and this
    /// value can help prune it efficiently.
    static let batchSize = 400
}

public class JobRecordFinderImpl<JobRecordType>: JobRecordFinder where JobRecordType: JobRecord {
    private let db: any DB

    public init(db: any DB) {
        self.db = db
    }

    private func iterateJobsWith(
        sql: String,
        arguments: StatementArguments,
        database: Database,
        block: (JobRecordType, inout Bool) -> Void
    ) throws {
        let cursor = try JobRecordType.fetchCursor(
            database,
            sql: sql,
            arguments: arguments
        )

        var stop = false
        while let nextJobRecord = try cursor.next() {
            block(nextJobRecord, &stop)

            if stop {
                return
            }
        }
    }

    public func enumerateJobRecords(
        transaction: DBReadTransaction,
        block: (JobRecordType, inout Bool) -> Void
    ) throws {
        let transaction = SDSDB.shimOnlyBridge(transaction)

        let sql = """
            SELECT * FROM \(JobRecord.databaseTableName)
            WHERE \(JobRecord.columnName(.label)) = ?
            ORDER BY \(JobRecord.columnName(.id))
        """

        try iterateJobsWith(
            sql: sql,
            arguments: [JobRecordType.jobRecordType.jobRecordLabel],
            database: transaction.unwrapGrdbRead.database,
            block: block
        )
    }

    public func enumerateJobRecords(
        status: JobRecord.Status,
        transaction: DBReadTransaction,
        block: (JobRecordType, inout Bool) -> Void
    ) throws {
        let transaction = SDSDB.shimOnlyBridge(transaction)

        let sql = """
            SELECT * FROM \(JobRecord.databaseTableName)
            WHERE \(JobRecord.columnName(.status)) = ?
              AND \(JobRecord.columnName(.label)) = ?
            ORDER BY \(JobRecord.columnName(.id))
        """

        try iterateJobsWith(
            sql: sql,
            arguments: [status.rawValue, JobRecordType.jobRecordType.jobRecordLabel],
            database: transaction.unwrapGrdbRead.database,
            block: block
        )
    }

    public func fetchJob(rowId: JobRecord.RowId, tx: DBReadTransaction) throws -> JobRecordType? {
        do {
            let db = tx.databaseConnection
            return try JobRecordType.fetchOne(db, key: rowId)
        } catch {
            throw error.grdbErrorForLogging
        }
    }

    public func removeJob(_ jobRecord: JobRecordType, tx: DBWriteTransaction) {
        jobRecord.anyRemove(transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func loadRunnableJobs(updateRunnableJobRecord: @escaping (JobRecordType, DBWriteTransaction) -> Void) async throws -> [JobRecordType] {
        var allRunnableJobs = [JobRecordType]()
        var afterRowId: JobRecord.RowId?
        while true {
            let (runnableJobs, hasMoreAfterRowId) = try await db.awaitableWrite { tx in
                try self.fetchAndPruneSomePersistedJobs(afterRowId: afterRowId, updateRunnableJobRecord: updateRunnableJobRecord, tx: tx)
            }
            allRunnableJobs.append(contentsOf: runnableJobs)
            guard let hasMoreAfterRowId else {
                break
            }
            afterRowId = hasMoreAfterRowId
        }
        return allRunnableJobs
    }

    private func fetchAndPruneSomePersistedJobs(
        afterRowId: JobRecord.RowId?,
        updateRunnableJobRecord: (JobRecordType, DBWriteTransaction) -> Void,
        tx: DBWriteTransaction
    ) throws -> ([JobRecordType], hasMoreAfterRowId: JobRecord.RowId?) {
        let (jobs, hasMore) = try fetchSomeJobs(afterRowId: afterRowId, tx: tx)
        var runnableJobs = [JobRecordType]()
        for job in jobs {
            let canRunJob: Bool = {
                // TODO: Schedule a DB migration to fully obsolete these properties.

                // This property is deprecated. If it's set, it means the job was created
                // for a prior version of the application, and that version definitely
                // can't be the current process.
                if job.exclusiveProcessIdentifier != nil {
                    return false
                }
                // This property is deprecated. If it's set, it means that the job is for a
                // deprecated type of message that doesn't need to be sent.
                if (job as? MessageSenderJobRecord)?.removeMessageAfterSending == true {
                    return false
                }
                // If a job has failed or is obsolete, we can remove it. We previously
                // distinguished `.ready` from `.running`, but now they're treated exactly
                // the same when we restart existing jobs.
                switch job.status {
                case .unknown, .permanentlyFailed, .obsolete:
                    return false
                case .ready, .running:
                    break
                }
                return true
            }()
            if canRunJob {
                updateRunnableJobRecord(job, tx)
                runnableJobs.append(job)
            } else {
                removeJob(job, tx: tx)
            }
        }
        return (runnableJobs, hasMore ? jobs.last!.id! : nil)
    }

    private func fetchSomeJobs(
        afterRowId: JobRecord.RowId?,
        tx: DBReadTransaction
    ) throws -> ([JobRecordType], hasMore: Bool) {
        var sql = """
            SELECT * FROM \(JobRecordType.databaseTableName)
            WHERE "\(JobRecordType.columnName(.label))" = ?
        """
        var arguments: StatementArguments = [JobRecordType.jobRecordType.jobRecordLabel]
        if let afterRowId {
            sql += """
                AND \(JobRecordType.columnName(.id)) > ?
            """
            arguments += [afterRowId]
        }
        sql += """
            ORDER BY "\(JobRecordType.columnName(.id))"
            LIMIT \(Constants.batchSize)
        """
        do {
            let db = tx.databaseConnection
            let results = try JobRecordType.fetchAll(db, sql: sql, arguments: arguments)
            return (results, results.count == Constants.batchSize)
        } catch {
            throw error.grdbErrorForLogging
        }
    }
}
