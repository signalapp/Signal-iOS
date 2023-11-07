//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import SignalCoreKit
import SignalServiceKit

final class AuthorMergeHelperBuilder {
    private let appContext: AppContext
    private let authorMergeHelper: AuthorMergeHelper
    private let db: DB
    private let dbFromTx: (DBReadTransaction) -> Database
    private let modelReadCaches: Shims.ModelReadCaches
    private let recipientDatabaseTable: RecipientDatabaseTable

    init(
        appContext: AppContext,
        authorMergeHelper: AuthorMergeHelper,
        db: DB,
        dbFromTx: @escaping (DBReadTransaction) -> Database,
        modelReadCaches: Shims.ModelReadCaches,
        recipientDatabaseTable: RecipientDatabaseTable
    ) {
        self.appContext = appContext
        self.authorMergeHelper = authorMergeHelper
        self.db = db
        self.dbFromTx = dbFromTx
        self.modelReadCaches = modelReadCaches
        self.recipientDatabaseTable = recipientDatabaseTable
    }

    private enum Constants {
        /// The desired write transaction duration for each batch.
        static let estimatedBatchDuration: TimeInterval = 0.5
        /// The estimated cost of writing a row vs. reading a row. We should err on
        /// the side of a value that's much too large rather than too small.
        static let writeFactor: Double = 50
    }

    func buildTableIfNeeded() async {
        do {
            try await _buildTableIfNeeded()
        } catch {
            Logger.warn("Couldn't build lookup table: \(error)")
        }
    }

    private func _buildTableIfNeeded() async throws {
        let (currentVersion, nextVersion) = db.read { tx in
            return (authorMergeHelper.currentVersion(tx: tx), authorMergeHelper.nextVersion(tx: tx))
        }
        // If we've already finished, don't do anything.
        if currentVersion == nextVersion {
            return
        }
        // Otherwise, process everything until we're done.
        for table in AuthorDatabaseTable.all {
            while try await processBatch(table: table, nextVersion: nextVersion) {
                try await Task.sleep(nanoseconds: NSEC_PER_SEC)
            }
        }
        // Finally, mark that we've finished.
        try await db.awaitableWrite { tx in
            try self.authorMergeHelper.setCurrentVersion(nextVersion: nextVersion, tx: tx)
        }
    }

    @MainActor
    private func waitForPreconditions() async {
        guard appContext.isAppForegroundAndActive() else {
            await NotificationCenter.default.observe(once: UIApplication.didBecomeActiveNotification).asVoid().awaitable()
            await waitForPreconditions()
            return
        }
    }

    private func processBatch(table: AuthorDatabaseTable, nextVersion: Int) async throws -> Bool {
        await waitForPreconditions()
        let backgroundTask = OWSBackgroundTask(label: #function)
        defer { backgroundTask.end() }
        return try await db.awaitableWrite { tx in
            try self._processBatch(table: table, nextVersion: nextVersion, tx: tx)
        }
    }

    private func _processBatch(table: AuthorDatabaseTable, nextVersion: Int, tx: DBWriteTransaction) throws -> Bool {
        let startTime = CACurrentMediaTime()

        try authorMergeHelper.checkNextVersion(nextVersion, tx: tx)

        var hasMore = false
        var mostRecentRowId: Int64?
        let batch = AuthorMergeHelperBuilderBatch(recipientDatabaseTable: recipientDatabaseTable)
        let cursor = try cursorForBatch(table: table, tx: tx)
        while let row = try cursor.next() {
            let rowId = row[0] as Int64
            mostRecentRowId = rowId
            let aciString = row[1] as String?
            let phoneNumber = row[2] as String?
            batch.processRow(rowId: rowId, aciString: aciString, phoneNumber: phoneNumber, tx: tx)

            let elapsedReadTime = CACurrentMediaTime() - startTime
            let timePerRead = elapsedReadTime / Double(batch.rowCount)
            let estimatedWriteTime = Double(batch.tableUpdates.count) * Constants.writeFactor * timePerRead
            if (elapsedReadTime + estimatedWriteTime) > Constants.estimatedBatchDuration {
                hasMore = true
                break
            }
        }

        // We build a list of updates to perform and then perform them separately
        // to avoid mutating the table while we're executing a SELECT statement.

        for tableUpdate in batch.tableUpdates {
            try performUpdate(table: table, rowId: tableUpdate.rowId, aciString: tableUpdate.aciString, tx: tx)
        }

        for phoneNumber in batch.phoneNumbersMissingAnAciString {
            authorMergeHelper.foundMissingAci(for: phoneNumber, tx: tx)
        }

        if let mostRecentRowId {
            authorMergeHelper.nextRowIdStore.setInt64(mostRecentRowId, key: table.name, transaction: tx)
        }

        let formattedDuration = String(format: "%0.1fms", (CACurrentMediaTime() - startTime) * 1000)
        Logger.info("Updated \(batch.tableUpdates.count) out of \(batch.rowCount) fetched \(table.name)s in \(formattedDuration)")

        modelReadCaches.evacuateAllCaches()

        return hasMore
    }

    private func cursorForBatch(table: AuthorDatabaseTable, tx: DBReadTransaction) throws -> RowCursor {
        let nextRowId = authorMergeHelper.nextRowIdStore.getInt64(table.name, transaction: tx)
        let (sqlQuery, sqlArguments) = sqlQueryForBatch(table: table, nextRowId: nextRowId)
        return try Row.fetchCursor(dbFromTx(tx), sql: sqlQuery, arguments: sqlArguments)
    }

    private func sqlQueryForBatch(table: AuthorDatabaseTable, nextRowId: Int64?) -> (String, StatementArguments) {
        var sqlQuery = """
            SELECT "id", "\(table.aciColumn)", "\(table.phoneNumberColumn)" FROM "\(table.name)"
        """
        var sqlArguments = [DatabaseValueConvertible]()
        if let nextRowId {
            sqlQuery += """
                WHERE "id" > ?
            """
            sqlArguments.append(nextRowId)
        }
        sqlQuery += """
            ORDER BY "id" ASC
        """
        return (sqlQuery, StatementArguments(sqlArguments))
    }

    private func performUpdate(table: AuthorDatabaseTable, rowId: Int64, aciString: String, tx: DBWriteTransaction) throws {
        let sqlQuery = """
            UPDATE "\(table.name)" SET "\(table.aciColumn)" = ?, "\(table.phoneNumberColumn)" = NULL WHERE "id" = ?
        """
        try dbFromTx(tx).execute(sql: sqlQuery, arguments: [aciString, rowId])
    }

}

private class AuthorMergeHelperBuilderBatch {
    private let recipientDatabaseTable: RecipientDatabaseTable

    private var phoneNumberAciStringCache = [String: String?]()

    private(set) var rowCount = 0
    private(set) var tableUpdates = [(rowId: Int64, aciString: String)]()
    private(set) var phoneNumbersMissingAnAciString = Set<String>()

    init(recipientDatabaseTable: RecipientDatabaseTable) {
        self.recipientDatabaseTable = recipientDatabaseTable
    }

    func processRow(rowId: Int64, aciString: String?, phoneNumber: String?, tx: DBReadTransaction) {
        rowCount += 1
        // If there's no phone number, then we don't need to clear the phone
        // number, and we can't possibly find an ACI for the phone number.
        guard let phoneNumber else {
            return
        }
        // If there's already an ACI, then that's what we should keep, and we
        // should clear the phone number.
        if let aciString {
            tableUpdates.append((rowId, aciString))
            return
        }
        // If we can find the ACI, then we fix it right now to avoid a costly
        // blocking migration later.
        if let aciString = findAciString(for: phoneNumber, tx: tx) {
            tableUpdates.append((rowId, aciString))
            return
        }
        phoneNumbersMissingAnAciString.insert(phoneNumber)
    }

    private func findAciString(for phoneNumber: String, tx: DBReadTransaction) -> String? {
        if let aciString = phoneNumberAciStringCache[phoneNumber] {
            return aciString
        }
        let phoneNumberRecipient = recipientDatabaseTable.fetchRecipient(phoneNumber: phoneNumber, transaction: tx)
        let aciString: String? = phoneNumberRecipient?.aciString
        phoneNumberAciStringCache[phoneNumber] = aciString
        return aciString
    }
}

extension AuthorMergeHelperBuilder {
    enum Shims {
        typealias ModelReadCaches = _AuthorMergeHelperBuilder_ModelReadCachesShim
    }

    enum Wrappers {
        typealias ModelReadCaches = _AuthorMergeHelperBuilder_ModelReadCachesWrapper
    }
}

protocol _AuthorMergeHelperBuilder_ModelReadCachesShim {
    func evacuateAllCaches()
}

class _AuthorMergeHelperBuilder_ModelReadCachesWrapper: _AuthorMergeHelperBuilder_ModelReadCachesShim {
    private let modelReadCaches: ModelReadCaches
    init(_ modelReadCaches: ModelReadCaches) {
        self.modelReadCaches = modelReadCaches
    }
    func evacuateAllCaches() {
        modelReadCaches.evacuateAllCaches()
    }
}

// MARK: - Unit Tests

#if TESTABLE_BUILD

class AuthorMergeHelperBuilder_MockModelReadCaches: _AuthorMergeHelperBuilder_ModelReadCachesShim {
    func evacuateAllCaches() {}
}

#endif
