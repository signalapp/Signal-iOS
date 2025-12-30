//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import SignalServiceKit

/// Responsible for migrating "group update info message" to store group updates
/// in the most "modern" format, contrasted with a variety of legacy formats.
struct InfoMessageGroupUpdateMigrator {
    private enum StoreKeys {
        static let hasFinishedMigrating = "hasFinishedMigrating"
        static let lastMigratedInfoMessageRowID = "lastMigratedInfoMessageRowID"
    }

    private let db: DB
    private let kvStore: NewKeyValueStore
    private let logger: PrefixedLogger
    private let modelReadCaches: () -> ModelReadCaches
    private let tsAccountManager: () -> TSAccountManager

    init(
        db: DB,
        modelReadCaches: @escaping () -> ModelReadCaches,
        tsAccountManager: @escaping () -> TSAccountManager,
    ) {
        self.db = db
        self.kvStore = NewKeyValueStore(collection: "GroupUpdateInfoMessageMigrator")
        self.logger = PrefixedLogger(prefix: "GroupUpdateInfoMessageMigrator")
        self.modelReadCaches = modelReadCaches
        self.tsAccountManager = tsAccountManager
    }

    func needsToRun() -> Bool {
        let hasFinishedMigrating = db.read { tx in
            kvStore.fetchValue(Bool.self, forKey: StoreKeys.hasFinishedMigrating, tx: tx) ?? false
        }

        return !hasFinishedMigrating
    }

    func run() async throws(CancellationError) {
        struct InfoMessage: GRDB.FetchableRecord {
            static let databaseTableName = InteractionRecord.databaseTableName
            static let idColumn = "\(interactionColumn: .id)"
            static let infoMessageUserInfoColumn = "\(interactionColumn: .infoMessageUserInfo)"

            let rowID: Int64
            let infoMessageUserInfoBlob: Data?

            init(row: Row) {
                self.rowID = row[Self.idColumn]
                self.infoMessageUserInfoBlob = row[Self.infoMessageUserInfoColumn]
            }
        }

        struct TxContext {
            var hasFinishedMigrating: Bool
            var lastMigratedInfoMessageRowID: Int64?
            let localIdentifiers: LocalIdentifiers?
        }

        logger.info("Starting...")

        try await TimeGatedBatch.processAll(
            db: db,
            buildTxContext: { tx throws(CancellationError) -> TxContext in
                let lastMigratedInfoMessageRowID = kvStore.fetchValue(
                    Int64.self,
                    forKey: StoreKeys.lastMigratedInfoMessageRowID,
                    tx: tx,
                )

                return TxContext(
                    hasFinishedMigrating: false,
                    lastMigratedInfoMessageRowID: lastMigratedInfoMessageRowID,
                    localIdentifiers: tsAccountManager().localIdentifiers(tx: tx),
                )
            },
            processBatch: { tx, context throws(CancellationError) in
                guard
                    !Task.isCancelled,
                    let localIdentifiers = context.localIdentifiers
                else {
                    // Stop the iteration, but don't record that we're done.
                    throw CancellationError()
                }

                let infoMessage: InfoMessage
                do {
                    var infoMessageQuery = """
                        SELECT \(InfoMessage.idColumn), \(InfoMessage.infoMessageUserInfoColumn) FROM \(InfoMessage.databaseTableName)
                    """
                    if let lastMigratedInfoMessageRowID = context.lastMigratedInfoMessageRowID {
                        infoMessageQuery += " WHERE \(InfoMessage.idColumn) < \(lastMigratedInfoMessageRowID)"
                    }
                    infoMessageQuery += " ORDER BY \(InfoMessage.idColumn) DESC"

                    guard let _infoMessage = try InfoMessage.fetchOne(tx.database, sql: infoMessageQuery) else {
                        // No more info messages: we're done!
                        context.hasFinishedMigrating = true
                        return .done(())
                    }

                    infoMessage = _infoMessage
                } catch {
                    logger.error("Failed to read InfoMessage from cursor: aborting migration.")
                    context.hasFinishedMigrating = true
                    return .done(())
                }

                guard
                    let infoMessageUserInfoBlob = infoMessage.infoMessageUserInfoBlob,
                    let infoMessageUserInfo = try? NSKeyedUnarchiver.unarchivedObject(
                        ofClass: NSDictionary.self,
                        from: infoMessageUserInfoBlob,
                        requiringSecureCoding: false,
                    ) as? [InfoMessageUserInfoKey: Any]
                else {
                    // Missing or failed-to-unarchive infoMessageUserInfo: skip
                    // this interaction.
                    context.lastMigratedInfoMessageRowID = infoMessage.rowID
                    return .more
                }

                guard
                    let precomputedGroupUpdateItems = TSInfoMessage.computedGroupUpdateItems(
                        infoMessageUserInfo: infoMessageUserInfo,
                        customMessage: nil,
                        localIdentifiers: localIdentifiers,
                        tx: tx,
                    )
                else {
                    // No precomputed group update items. This may not be a
                    // group update, or a malformed one: skip it.
                    context.lastMigratedInfoMessageRowID = infoMessage.rowID
                    return .more
                }

                // This is the only key in infoMessageUserInfo that we're now
                // interested in – everything else can be discarded. There are
                // no info messages with group-update keys *and* keys for some
                // other update type, and once we have these precomputed update
                // items we don't need any of the other keys that might have
                // been present before.
                let newInfoMessageUserInfo: [InfoMessageUserInfoKey: Any] = [
                    .groupUpdateItems: TSInfoMessage.PersistableGroupUpdateItemsWrapper(precomputedGroupUpdateItems),
                ]
                let newInfoMessageUserInfoBlob = try! NSKeyedArchiver.archivedData(
                    withRootObject: newInfoMessageUserInfo,
                    requiringSecureCoding: false,
                )

                try? tx.database.execute(
                    sql: """
                        UPDATE \(InfoMessage.databaseTableName)
                        SET \(InfoMessage.infoMessageUserInfoColumn) = ?
                        WHERE \(InfoMessage.idColumn) = ?
                    """,
                    arguments: [newInfoMessageUserInfoBlob, infoMessage.rowID],
                )

                context.lastMigratedInfoMessageRowID = infoMessage.rowID
                return .more
            },
            concludeTx: { tx, context throws(CancellationError) in
                // We've directly modified TSInteractions that may be cached, so
                // clear said caches.
                modelReadCaches().evacuateAllCaches()

                if let lastMigratedInfoMessageRowID = context.lastMigratedInfoMessageRowID {
                    kvStore.writeValue(
                        lastMigratedInfoMessageRowID,
                        forKey: StoreKeys.lastMigratedInfoMessageRowID,
                        tx: tx,
                    )
                }

                if context.hasFinishedMigrating {
                    kvStore.writeValue(true, forKey: StoreKeys.hasFinishedMigrating, tx: tx)
                }
            },
        )

        logger.info("Done!")
    }
}
