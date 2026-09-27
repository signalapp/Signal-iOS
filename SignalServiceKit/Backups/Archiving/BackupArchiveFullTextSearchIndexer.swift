//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB

public protocol BackupArchiveFullTextSearchIndexer {

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

public class BackupArchiveFullTextSearchIndexerImpl: BackupArchiveFullTextSearchIndexer {

    private let appReadiness: AppReadiness
    private let dateProvider: DateProviderMonotonic
    private let db: any DB
    private let interactionStore: InteractionStore
    private let kvStore: KeyValueStore
    private let logger: PrefixedLogger
    private let searchableNameIndexer: SearchableNameIndexer
    private let taskQueue: SerialTaskQueue

    public init(
        appReadiness: AppReadiness,
        dateProvider: @escaping DateProviderMonotonic,
        db: any DB,
        interactionStore: InteractionStore,
        searchableNameIndexer: SearchableNameIndexer,
    ) {
        self.appReadiness = appReadiness
        self.dateProvider = dateProvider
        self.db = db
        self.interactionStore = interactionStore
        self.kvStore = KeyValueStore(collection: "BackupFullTextSearchIndexerImpl")
        self.logger = PrefixedLogger(prefix: "[Backups]")
        self.searchableNameIndexer = searchableNameIndexer
        self.taskQueue = SerialTaskQueue()

        appReadiness.runNowOrWhenAppDidBecomeReadyAsync { [self] in
            taskQueue.enqueue { [self] in
                try await runMessagesJobIfNeeded()
            }
        }
    }

    public func indexThreads(tx: DBWriteTransaction) {
        searchableNameIndexer.indexThreads(tx: tx)
    }

    public func scheduleMessagesJob(tx: DBWriteTransaction) throws {
        setMinInteractionRowIdExclusive(nil, tx: tx)
        let maxInteractionRowId = try Int64.fetchOne(
            tx.database,
            sql: """
            SELECT max(\(TSInteractionSerializer.idColumn.columnName))
            FROM \(TSInteraction.table.tableName);
            """,
        )
        if let maxInteractionRowId {
            setMaxInteractionRowIdInclusive(maxInteractionRowId, tx: tx)
            tx.addSyncCompletion { [self] in
                self.taskQueue.enqueue { [weak self] in
                    try await self?.runMessagesJobIfNeeded()
                }
            }
        }
    }

    private func runMessagesJobIfNeeded() async throws {
        guard appReadiness.isAppReady else {
            return
        }

        // This value is set once when we schedule the job, and won't change
        // across multiple runs of the job.
        guard
            let maxInteractionRowIdInclusive = db.read(block: { tx in
                maxInteractionRowIdInclusive(tx: tx)
            })
        else {
            // No job to run
            return
        }

        logger.info("Starting job")

        struct TxContext {
            let interactionCursor: AnyCursor<InteractionRecord>
            var maxInteractionRowIdSoFar: Int64?
        }
        await TimeGatedBatch.processAll(
            db: db,
            yieldTxAfter: 0.1,
            delayTwixtTx: 0.2,
            buildTxContext: { tx -> TxContext in
                let minInteractionRowIdExclusive = minInteractionRowIdExclusive(tx: tx)

                let interactionCursor = interactionStore.fetchCursor(
                    minRowIdExclusive: minInteractionRowIdExclusive,
                    maxRowIdInclusive: maxInteractionRowIdInclusive,
                    tx: tx,
                )

                return TxContext(
                    interactionCursor: interactionCursor,
                    maxInteractionRowIdSoFar: nil,
                )
            },
            processBatch: { tx, context -> TimeGatedBatch.ProcessBatchResult<Void> in
                let interactionRecord: InteractionRecord? = failIfThrows {
                    try context.interactionCursor.next()
                }

                guard let interactionRecord else {
                    return .done(())
                }

                context.maxInteractionRowIdSoFar = interactionRecord.id!

                let interaction: TSInteraction
                do {
                    interaction = try TSInteraction.fromRecord(interactionRecord)
                } catch {
                    // Skip this interaction and move on. It's already been
                    // popped from the cursor and we've recorded its row ID, so
                    // we'll skip it going forward.
                    logger.warn("Failed to create interaction from record! \(error)")
                    return .more
                }

                index(interaction, tx: tx)
                return .more
            },
            concludeTx: { tx, context in
                guard let maxInteractionRowIdSoFar = context.maxInteractionRowIdSoFar else {
                    // No interactions processed!
                    return
                }

                if maxInteractionRowIdSoFar >= maxInteractionRowIdInclusive {
                    // We made it to the end of the cursor, which means the end
                    // of the set of interactions at the time the job was
                    // scheduled. We're done!
                    setMaxInteractionRowIdInclusive(nil, tx: tx)
                    setMinInteractionRowIdExclusive(nil, tx: tx)
                    logger.info("Finished!")
                } else {
                    // The batch completed but there's more to do: update our
                    // lower bound, so the next batch starts here.
                    setMinInteractionRowIdExclusive(maxInteractionRowIdSoFar, tx: tx)
                }
            },
        )
    }

    private func index(_ interaction: TSInteraction, tx: DBWriteTransaction) {
        guard let message = interaction as? TSMessage else {
            return
        }

        FullTextSearchIndexer.insert(message, tx: tx)

        if let bodyRanges = message.bodyRanges {
            let uniqueMentionedAcis = Set(bodyRanges.orderedMentions.map(\.value))
            for mentionedAci in uniqueMentionedAcis {
                let mention = TSMention(uniqueMessageId: message.uniqueId, uniqueThreadId: message.uniqueThreadId, aci: mentionedAci)
                failIfThrows {
                    try mention.save(tx.database)
                }
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
    }
}
