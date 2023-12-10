//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import SignalServiceKit

final class FullTextSearchOptimizer {
    private let db: DB
    private let keyValueStore: KeyValueStore
    private let preconditions: Preconditions

    private enum Constants {
        static let numberOfPagesToMergeAtATime = 64

        static let nanosecondsBetweenMergeBatches = 50 * NSEC_PER_MSEC

        static let versionKey = "version"

        /// Incrementing this value will ensure the optimizer runs again for all users.
        static let currentVersion = 1
    }

    init(appContext: AppContext, db: DB, keyValueStoreFactory: KeyValueStoreFactory) {
        self.db = db
        self.keyValueStore = keyValueStoreFactory.keyValueStore(collection: "FullTextSearchOptimizer")
        self.preconditions = Preconditions([AppActivePrecondition(appContext: appContext)])
    }

    /// Optimizes a SQLite FTS5 table by issuing [merge commands][0] until no
    /// more merges are needed.
    ///
    /// To avoid hogging the database, a short delay is added between merges.
    ///
    /// [0]: https://www.sqlite.org/fts5.html#the_merge_command
    func run() async {
        do {
            let completedVersion = db.read { tx in
                keyValueStore.getInt(Constants.versionKey, defaultValue: 0, transaction: tx)
            }
            guard completedVersion < Constants.currentVersion else {
                return
            }
            try await performAllMerges()
            await db.awaitableWrite { tx in
                self.keyValueStore.setInt(Constants.currentVersion, key: Constants.versionKey, transaction: tx)
            }
        } catch {
            Logger.warn("\(error)")
        }
    }

    private func performAllMerges() async throws {
        var isFirstBatch = true
        while try await performMerge(isFirstBatch: isFirstBatch) {
            isFirstBatch = false
            try await Task.sleep(nanoseconds: Constants.nanosecondsBetweenMergeBatches)
        }
    }

    private func performMerge(isFirstBatch: Bool) async throws -> Bool {
        try await preconditions.waitUntilSatisfied()

        let backgroundTask = OWSBackgroundTask(label: #function)
        defer { backgroundTask.end() }

        let startTime = CACurrentMediaTime()

        let mergeResult = try await db.awaitableWrite { tx -> SqliteUtil.Fts5.MergeResult in
            return try SqliteUtil.Fts5.merge(
                db: SDSDB.shimOnlyBridge(tx).unwrapGrdbWrite.database,
                ftsTableName: GRDBFullTextSearchFinder.ftsTableName,
                numberOfPages: Constants.numberOfPagesToMergeAtATime,
                isFirstBatch: isFirstBatch
            )
        }

        let formattedDuration = String(format: "%.1fms", (CACurrentMediaTime() - startTime)*1000)
        Logger.info("\(mergeResult) in \(formattedDuration)")

        return mergeResult == .workWasPerformed
    }
}
