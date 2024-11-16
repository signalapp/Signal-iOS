//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// Responsible for deletion of ``TSPrivateStoryThread``s, which represent story
/// distribution lists.
public protocol PrivateStoryThreadDeletionManager {
    /// Fetches the timestamp at which the story distribution list with
    /// the given identifier was deleted.
    ///
    /// - Note
    /// Deleted story distribution lists are marked as deleted and kept for a
    /// period of time to ensure proper syncing across devices (i.e., via
    /// Storage Service) before being purged from disk.
    func deletedAtTimestamp(
        forDistributionListIdentifier identifier: Data,
        tx: any DBReadTransaction
    ) -> UInt64?

    /// Marks the story distribution list with the given identifier as deleted
    /// at the given timestamp.
    ///
    /// - Note
    /// Deleted story distribution lists are marked as deleted and kept for a
    /// period of time to ensure proper syncing across devices (i.e., via
    /// Storage Service) before being purged from disk.
    func recordDeletedAtTimestamp(
        _ timestamp: UInt64,
        forDistributionListIdentifier identifier: Data,
        tx: any DBWriteTransaction
    )

    /// All distribution list identifiers currently marked as deleted.
    func allDeletedIdentifiers(tx: any DBReadTransaction) -> [Data]

    /// Purges any distribution list identifiers marked as deleted sufficiently
    /// long ago.
    func cleanUpDeletedTimestamps(tx: any DBWriteTransaction)
}

// MARK: -

final class PrivateStoryThreadDeletionManagerImpl: PrivateStoryThreadDeletionManager {
    private let logger = PrefixedLogger(prefix: "PvtStoryThreadDelMgr")

    private let dateProvider: DateProvider
    private let deletedAtTimestampStore: KeyValueStore
    private let remoteConfigProvider: any RemoteConfigProvider
    private let storageServiceManager: any StorageServiceManager
    private let threadRemover: any ThreadRemover
    private let threadStore: any ThreadStore

    init(
        dateProvider: @escaping DateProvider,
        remoteConfigProvider: any RemoteConfigProvider,
        storageServiceManager: any StorageServiceManager,
        threadRemover: any ThreadRemover,
        threadStore: any ThreadStore
    ) {
        self.dateProvider = dateProvider
        self.deletedAtTimestampStore = KeyValueStore(collection: "TSPrivateStoryThread+DeletedAtTimestamp")
        self.remoteConfigProvider = remoteConfigProvider
        self.storageServiceManager = storageServiceManager
        self.threadRemover = threadRemover
        self.threadStore = threadStore
    }

    func deletedAtTimestamp(
        forDistributionListIdentifier identifier: Data,
        tx: any DBReadTransaction
    ) -> UInt64? {
        guard let uniqueId = identifier.uuidString else { return nil }
        return deletedAtTimestampStore.getUInt64(uniqueId, transaction: tx)
    }

    func recordDeletedAtTimestamp(
        _ timestamp: UInt64,
        forDistributionListIdentifier identifier: Data,
        tx: any DBWriteTransaction
    ) {
        guard timeInterval(sinceTimestamp: timestamp) < remoteConfigProvider.currentConfig().messageQueueTime else {
            logger.warn("Ignorning stale deleted at timestamp.")
            return
        }

        guard let uniqueId = identifier.uuidString else { return }
        deletedAtTimestampStore.setUInt64(timestamp, key: uniqueId, transaction: tx)
    }

    func allDeletedIdentifiers(tx: any DBReadTransaction) -> [Data] {
        deletedAtTimestampStore.allKeys(transaction: tx).compactMap { UUID(uuidString: $0)?.data }
    }

    func cleanUpDeletedTimestamps(tx: any DBWriteTransaction) {
        var deletedIdentifiers = [Data]()
        for identifier in deletedAtTimestampStore.allKeys(transaction: tx) {
            guard
                let timestamp = deletedAtTimestampStore.getUInt64(
                    identifier,
                    transaction: tx
                ),
                timeInterval(sinceTimestamp: timestamp) > remoteConfigProvider.currentConfig().messageQueueTime
            else { continue }

            deletedAtTimestampStore.removeValue(forKey: identifier, transaction: tx)

            /// If we still have a private story thread for this deleted
            /// timestamp, it's now safe to purge it from the database.
            if let thread = threadStore.fetchThread(uniqueId: identifier, tx: tx) as? TSPrivateStoryThread {
                threadRemover.remove(thread, tx: tx)
            }

            UUID(uuidString: identifier).map { deletedIdentifiers.append($0.data) }
        }

        storageServiceManager.recordPendingUpdates(updatedStoryDistributionListIds: deletedIdentifiers)
    }

    private func timeInterval(sinceTimestamp timestamp: UInt64) -> TimeInterval {
        let timestampDate = Date(millisecondsSince1970: timestamp)
        return dateProvider().timeIntervalSince(timestampDate)
    }
}

// MARK: -

private extension Data {
    var uuidString: String? {
        return UUID(data: self)?.uuidString
    }
}
