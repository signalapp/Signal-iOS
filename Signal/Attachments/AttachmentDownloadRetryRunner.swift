//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
public import SignalServiceKit

public class AttachmentDownloadRetryRunner {

    private let db: SDSDatabaseStorage
    private let runner: Runner
    private let dbObserver: DownloadTableObserver

    public init(
        attachmentDownloadManager: AttachmentDownloadManager,
        attachmentDownloadStore: AttachmentDownloadStore,
        db: SDSDatabaseStorage
    ) {
        self.db = db
        self.runner = Runner(
            attachmentDownloadManager: attachmentDownloadManager,
            attachmentDownloadStore: attachmentDownloadStore,
            db: db
        )
        self.dbObserver = DownloadTableObserver(runner: runner)
    }

    public static let shared = AttachmentDownloadRetryRunner(
        attachmentDownloadManager: DependenciesBridge.shared.attachmentDownloadManager,
        attachmentDownloadStore: DependenciesBridge.shared.attachmentDownloadStore,
        db: SSKEnvironment.shared.databaseStorageRef
    )

    public func beginObserving() {
        db.grdbStorage.pool.add(transactionObserver: dbObserver)
        Task {
            await runner.runIfNotRunning()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didEnterForeground),
            name: .OWSApplicationWillEnterForeground,
            object: nil
        )
    }

    @objc
    private func didEnterForeground() {
        Task {
            // Trigger any ready-to-go downloads; this method exits early and cheaply
            // if there is nothing to download.
            self.runner.attachmentDownloadManager.beginDownloadingIfNecessary()
            // Check for downloads with retry timers and wait for those timers.
            await runner.runIfNotRunning()
        }
    }

    private actor Runner {
        nonisolated let attachmentDownloadManager: AttachmentDownloadManager
        nonisolated let attachmentDownloadStore: AttachmentDownloadStore
        nonisolated let db: SDSDatabaseStorage

        init(
            attachmentDownloadManager: AttachmentDownloadManager,
            attachmentDownloadStore: AttachmentDownloadStore,
            db: SDSDatabaseStorage
        ) {
            self.attachmentDownloadManager = attachmentDownloadManager
            self.attachmentDownloadStore = attachmentDownloadStore
            self.db = db
        }

        private var isRunning = false

        fileprivate func runIfNotRunning() async {
            if self.isRunning { return }
            await self.run()
        }

        private func run() async {
            do {
                self.isRunning = true
                defer { self.isRunning = false }

                let nextTimestamp = db.read { tx in
                    return try? self.attachmentDownloadStore.nextRetryTimestamp(tx: tx.asV2Read)
                }
                guard let nextTimestamp else {
                    return
                }
                let nowMs = Date().ows_millisecondsSince1970
                if nowMs < nextTimestamp {
                    try? await Task.sleep(nanoseconds: (nextTimestamp - nowMs) * NSEC_PER_MSEC)
                }

                await db.awaitableWrite { tx in
                    try? self.attachmentDownloadStore.updateRetryableDownloads(tx: tx.asV2Write)
                }
                // Kick the tires to start any downloads.
                attachmentDownloadManager.beginDownloadingIfNecessary()
            }

            // Run again to wait for the next timestamp.
            await self.run()
        }
    }

    // MARK: - Observation

    private class DownloadTableObserver: TransactionObserver {

        private let runner: Runner

        init(runner: Runner) {
            self.runner = runner
        }

        func observes(eventsOfKind eventKind: DatabaseEventKind) -> Bool {
            switch eventKind {
            case let .update(tableName, columnNames):
                return
                    tableName == QueuedAttachmentDownloadRecord.databaseTableName
                    && columnNames.contains(QueuedAttachmentDownloadRecord.CodingKeys.minRetryTimestamp.rawValue)
            case .insert, .delete:
                // We _never_ insert a download in the retry state to begin with,
                // so we really only care about observing updates.
                return false
            }
        }

        /// `observes(eventsOfKind:)` filtering _only_ applies to `databaseDidChange`,  _not_ `databaseDidCommit`.
        /// We want to filter, but only want to _do_ anything after the changes commit.
        /// Use this bool to track when the filter is passed (didChange) so we know whether to do anything on didCommit .
        private var shouldRunOnNextCommit = false

        func databaseDidChange(with event: DatabaseEvent) {
            shouldRunOnNextCommit = true
        }

        func databaseDidCommit(_ db: GRDB.Database) {
            guard shouldRunOnNextCommit else {
                return
            }
            shouldRunOnNextCommit = false

            // When we get a matching event, run the next job _after_ committing.
            // The job should pick up whatever new row(s) got updated in the table.
            Task { [runner] in
                await runner.runIfNotRunning()
            }
        }

        func databaseDidRollback(_ db: GRDB.Database) {}
    }
}
