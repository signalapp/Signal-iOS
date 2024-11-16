//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public protocol MessageBackupFullTextSearchIndexer {

    /// Index all searchable threads.
    /// Does not cover message contents (or mentions in messages)
    ///
    /// Done synchronously with the actual backup (in the same transaction) because
    /// its cheap compared to messages (p99 thread count is relatively small).
    func indexThreads(tx: DBWriteTransaction)

    /// Schedule work to index message contents for all messages that have been inserted
    /// until this point. Future messages can index themselves upon insertion while this
    /// job runs.
    func scheduleMessagesJob(tx: DBWriteTransaction) throws
}

public class MessageBackupFullTextSearchIndexerImpl: MessageBackupFullTextSearchIndexer {

    private let appReadiness: AppReadiness
    private let dateProvider: DateProvider
    private let db: any DB
    private let fullTextSearchIndexer: Shims.FullTextSearchIndexer
    private let interactionStore: InteractionStore
    private let kvStore: KeyValueStore
    private let searchableNameIndexer: SearchableNameIndexer
    private let taskQueue: SerialTaskQueue

    public init(
        appReadiness: AppReadiness,
        dateProvider: @escaping DateProvider,
        db: any DB,
        fullTextSearchIndexer: Shims.FullTextSearchIndexer,
        interactionStore: InteractionStore,
        searchableNameIndexer: SearchableNameIndexer
    ) {
        self.appReadiness = appReadiness
        self.dateProvider = dateProvider
        self.db = db
        self.fullTextSearchIndexer = fullTextSearchIndexer
        self.interactionStore = interactionStore
        self.kvStore = KeyValueStore(collection: "BackupFullTextSearchIndexerImpl")
        self.searchableNameIndexer = searchableNameIndexer
        self.taskQueue = SerialTaskQueue()

        appReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            Task {
                try await self.taskQueue.enqueue(operation: { [weak self] in
                    try await self?.runMessagesJobIfNeeded()
                }).value
            }
        }
    }

    public func indexThreads(tx: DBWriteTransaction) {
        searchableNameIndexer.indexThreads(tx: tx)
    }

    public func scheduleMessagesJob(tx: DBWriteTransaction) throws {
        setMinInteractionRowIdExclusive(nil, tx: tx)
        let maxInteractionRowId = try Int64.fetchOne(
            tx.databaseConnection,
            sql: """
                SELECT max(\(TSInteractionSerializer.idColumn.columnName))
                FROM \(TSInteraction.table.tableName);
                """
        )
        if let maxInteractionRowId {
            setMaxInteractionRowIdInclusive(maxInteractionRowId, tx: tx)
            tx.addAsyncCompletion(on: DispatchQueue.global()) {
                Task {
                    try await self.taskQueue.enqueue(operation: { [weak self] in
                        try await self?.runMessagesJobIfNeeded()
                    }).value
                }
            }
        }
    }

    private func runMessagesJobIfNeeded() async throws {
        guard appReadiness.isAppReady else {
            return
        }
        var (
            minInteractionRowIdExclusive,
            maxInteractionRowIdInclusive
        ) = db.read { tx in
            return (
                self.minInteractionRowIdExclusive(tx: tx),
                self.maxInteractionRowIdInclusive(tx: tx)
            )
        }

        guard let maxInteractionRowIdInclusive else {
            // No job to run
            return
        }

        var maxInteractionRowIdSoFar: Int64?
        func finalizeBatch(tx: DBWriteTransaction) {
            if let maxInteractionRowIdSoFar {
                if maxInteractionRowIdSoFar >= maxInteractionRowIdInclusive {
                    self.setMaxInteractionRowIdInclusive(nil, tx: tx)
                    self.setMinInteractionRowIdExclusive(nil, tx: tx)
                    Logger.info("Finished")
                } else {
                    minInteractionRowIdExclusive = maxInteractionRowIdSoFar
                    self.setMinInteractionRowIdExclusive(maxInteractionRowIdSoFar, tx: tx)
                }
            }
        }

        Logger.info("Starting job")

        var hasMoreMessages = true
        while hasMoreMessages {
            Logger.info("Starting next batch")
            hasMoreMessages = try await db.awaitableWrite { tx in
                let startTimeMs = self.dateProvider().ows_millisecondsSince1970

                let cursor = try self.interactionStore.fetchCursor(
                    minRowIdExclusive: minInteractionRowIdExclusive,
                    maxRowIdInclusive: maxInteractionRowIdInclusive,
                    tx: tx
                )
                var processedCount = 0

                do {
                    while let interaction = try cursor.next() {
                        let nowMs = self.dateProvider().ows_millisecondsSince1970
                        if nowMs - startTimeMs > Constants.batchDurationMs {
                            Logger.info("Bailing on batch after \(processedCount) interactions")
                            finalizeBatch(tx: tx)
                            return true
                        }
                        try self.index(interaction, tx: tx)
                        maxInteractionRowIdSoFar = interaction.sqliteRowId
                        processedCount += 1
                    }
                    finalizeBatch(tx: tx)
                    return false
                } catch let error {
                    Logger.info("Failed batch after \(processedCount) interactions \(error.grdbErrorForLogging)")
                    finalizeBatch(tx: tx)
                    return true
                }
            }
        }
    }

    private func index(_ interaction: TSInteraction, tx: DBWriteTransaction) throws {
        guard let message = interaction as? TSMessage else {
            return
        }
        do {
            try self.fullTextSearchIndexer.insert(message, tx: tx)
        } catch let insertError {
            do {
                try self.fullTextSearchIndexer.update(message, tx: tx)
            } catch {
                throw insertError
            }
        }

        if let bodyRanges = message.bodyRanges {
            let uniqueMentionedAcis = Set(bodyRanges.mentions.values)
            for mentionedAci in uniqueMentionedAcis {
                let mention = TSMention(uniqueMessageId: message.uniqueId, uniqueThreadId: message.uniqueThreadId, aci: mentionedAci)
                try mention.save(tx.databaseConnection)
            }
        }
    }

    // MARK: - State

    private func setMinInteractionRowIdExclusive(_ newValue: Int64?, tx: DBWriteTransaction) {
        if let newValue {
            kvStore.setInt64(newValue, key: Constants.minInteractionRowIdKey, transaction: tx)
        } else {
            kvStore.removeValue(forKey: Constants.minInteractionRowIdKey, transaction: tx)
        }
    }

    private func minInteractionRowIdExclusive(tx: DBReadTransaction) -> Int64? {
        kvStore.getInt64(Constants.minInteractionRowIdKey, transaction: tx)
    }

    private func setMaxInteractionRowIdInclusive(_ newValue: Int64?, tx: DBWriteTransaction) {
        if let newValue {
            kvStore.setInt64(newValue, key: Constants.maxInteractionRowIdKey, transaction: tx)
        } else {
            kvStore.removeValue(forKey: Constants.maxInteractionRowIdKey, transaction: tx)
        }
    }

    private func maxInteractionRowIdInclusive(tx: DBReadTransaction) -> Int64? {
        kvStore.getInt64(Constants.maxInteractionRowIdKey, transaction: tx)
    }

    private enum Constants {
        /// Exclusive; this marke the last interaction row id we already indexed.
        static let minInteractionRowIdKey = "minInteractionRowIdKey"
        /// Inclusive; this marks the highest unindexed row id.
        static let maxInteractionRowIdKey = "maxInteractionRowIdKey"

        static let batchDurationMs: UInt64 = 90
    }
}

// MARK: - Shims

extension MessageBackupFullTextSearchIndexerImpl {
    public enum Shims {
        public typealias FullTextSearchIndexer = _MessageBackupFullTextSearchIndexerImpl_FullTextSearchIndexerShim
    }
    public enum Wrappers {
        public typealias FullTextSearchIndexer = _MessageBackupFullTextSearchIndexerImpl_FullTextSearchIndexerWrapper
    }
}

public protocol _MessageBackupFullTextSearchIndexerImpl_FullTextSearchIndexerShim {
    func insert(_ message: TSMessage, tx: DBWriteTransaction) throws
    func update(_ message: TSMessage, tx: DBWriteTransaction) throws
}

public class _MessageBackupFullTextSearchIndexerImpl_FullTextSearchIndexerWrapper: MessageBackupFullTextSearchIndexerImpl.Shims.FullTextSearchIndexer {

    public init() {}

    public func insert(_ message: TSMessage, tx: DBWriteTransaction) throws {
        try FullTextSearchIndexer.insert(message, tx: SDSDB.shimOnlyBridge(tx))
    }

    public func update(_ message: TSMessage, tx: DBWriteTransaction) throws {
        try FullTextSearchIndexer.update(message, tx: SDSDB.shimOnlyBridge(tx))
    }
}
