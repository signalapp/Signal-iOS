//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

/// Refreshes call links that need to be updated.
actor CallLinkFetchJobRunner: DatabaseChangeDelegate {
    private let callLinkStore: any CallLinkRecordStore
    private let callLinkStateUpdater: CallLinkStateUpdater
    private let db: any DB

    init(
        callLinkStore: any CallLinkRecordStore,
        callLinkStateUpdater: CallLinkStateUpdater,
        db: any DB
    ) {
        self.callLinkStore = callLinkStore
        self.callLinkStateUpdater = callLinkStateUpdater
        self.db = db
    }

    /// If true, we need to issue a query to check for pending fetches.
    private var mightHavePendingFetch = false

    /// If true, we're currently fetching and don't need another Task to fetch.
    private var isFetching = false

    /// Indicates that a fetch may have been scheduled.
    ///
    /// It's harmless to call this when it's not required.
    nonisolated func setMightHavePendingFetchAndFetch() {
        Task { await self._setMightHavePendingFetchAndFetch() }
    }

    private func _setMightHavePendingFetchAndFetch() async {
        self.mightHavePendingFetch = true
        await self.fetchIfNeeded()
    }

    private func fetchIfNeeded() async {
        guard mightHavePendingFetch, !isFetching else {
            return
        }

        isFetching = true
        defer {
            isFetching = false
        }

        var sequentialFailureCount = 0
        while true {
            let callLinkToFetch: CallLinkRecord?
            do {
                callLinkToFetch = try db.read(block: callLinkStore.fetchAnyPendingRecord(tx:))
            } catch {
                owsFailDebug("Can't fetch pending record: \(error)")
                mightHavePendingFetch = false
                return
            }
            guard let callLinkToFetch else {
                // Nothing to fetch.
                mightHavePendingFetch = false
                return
            }
            do {
                Logger.info("Refreshing \(callLinkToFetch.rootKey); pendingFetchCounter = \(callLinkToFetch.pendingFetchCounter)…")
                _ = try await callLinkStateUpdater.readCallLink(rootKey: callLinkToFetch.rootKey)
                sequentialFailureCount = 0
            } catch {
                sequentialFailureCount += 1
                let retryDelayNs = OWSOperation.retryIntervalForExponentialBackoffNs(failureCount: sequentialFailureCount, maxBackoff: 6 * kHourInterval)
                Logger.warn("Retrying persistent call link fetch after ≈\(OWSOperation.formattedNs(retryDelayNs))s; \(error)")
                try? await Task.sleep(nanoseconds: retryDelayNs)
            }
        }
    }

    // MARK: - DatabaseChangeDelegate

    @MainActor
    func observeDatabase(_ databaseChangeObserver: DatabaseChangeObserver) {
        databaseChangeObserver.appendDatabaseChangeDelegate(self)
    }

    @MainActor
    func databaseChangesDidReset() {}

    @MainActor
    func databaseChangesDidUpdateExternally() {
        setMightHavePendingFetchAndFetch()
    }

    @MainActor
    func databaseChangesDidUpdate(databaseChanges: any DatabaseChanges) {
        guard databaseChanges.didUpdate(tableName: CallLinkRecord.databaseTableName) else {
            return
        }
        setMightHavePendingFetchAndFetch()
    }
}
