//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import SignalServiceKit

class LazyDatabaseMigratorRunner: BGProcessingTaskRunner {
    private let indexMigrator: LazyIndexMigrator
    private let infoMessageMigrator: InfoMessageGroupUpdateMigrator

    init(
        databaseStorage: SDSDatabaseStorage,
        modelReadCaches: @escaping () -> ModelReadCaches,
        tsAccountManager: @escaping () -> TSAccountManager,
    ) {
        self.indexMigrator = LazyIndexMigrator(databaseStorage: databaseStorage)
        self.infoMessageMigrator = InfoMessageGroupUpdateMigrator(
            db: databaseStorage,
            modelReadCaches: modelReadCaches,
            tsAccountManager: tsAccountManager,
        )
    }

    static var taskIdentifier: String = "LazyDatabaseMigratorTask"
    static let logPrefix: String? = nil
    static var requiresNetworkConnectivity: Bool = false
    static let requiresExternalPower = false

    func startCondition() -> BGProcessingTaskStartCondition {
        if indexMigrator.needsToRun() {
            return .asSoonAsPossible
        }

        if infoMessageMigrator.needsToRun() {
            return .asSoonAsPossible
        }

        return .never
    }

    /// Run the migrations.
    ///
    /// If you encounter an error in this method, you can update
    /// `simulatePriorCancellation` to return true and run on a simulator.
    func run() async throws {
        try await indexMigrator.run()
        try await infoMessageMigrator.run()
    }

#if targetEnvironment(simulator)
    func simulatePriorCancellation() -> Bool {
        // Simulates a prior cancellation that may cause the task to run when it's
        // already finished.
        return Int.random(in: 0..<10) == 0
    }
#endif
}

private struct LazyIndexMigrator {
    let databaseStorage: SDSDatabaseStorage
    private let logger = PrefixedLogger(prefix: "LazyIndexMigrator")

    func needsToRun() -> Bool {
        do {
            let indexes = try databaseStorage.read { tx in
                let db = tx.database
                return Set(try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'index'"))
            }
            let lazilyRemovedIndexes = [
                "index_interactions_on_uniqueId_and_threadUniqueId",
                "index_interactions_on_expiresInSeconds_and_expiresAt",
                "index_model_TSInteraction_on_uniqueThreadId_and_attachmentIds",
                "index_interactions_on_timestamp_sourceDeviceId_and_authorUUID",
                "index_interactions_on_timestamp_sourceDeviceId_and_authorPhoneNumber",
                "index_model_TSInteraction_on_uniqueThreadId_and_hasEnded_and_recordType",
                "index_model_TSInteraction_on_uniqueThreadId_and_eraId_and_recordType",
                "index_model_TSInteraction_on_StoryContext",
                "index_model_TSInteraction_ConversationLoadInteractionCount",
                "index_model_TSInteraction_ConversationLoadInteractionDistance",
            ]
            if !indexes.isDisjoint(with: lazilyRemovedIndexes) {
                return true
            }

            let lazilyInsertedIndexes = [
                "Interaction_disappearingMessages_partial",
                "Interaction_timestamp",
                "Interaction_unendedGroupCall_partial",
                "Interaction_groupCallEraId_partial",
                "Interaction_storyReply_partial",
            ]
            if !indexes.isSuperset(of: lazilyInsertedIndexes) {
                return true
            }

            return false
        } catch {
            logger.warn("Couldn't check if we need to execute.")
            return false
        }
    }

    func run() async throws {
        // Must be idempotent.

        try Task.checkCancellation()
        await databaseStorage.awaitableWrite { tx in
            logger.info("Removing threadUniqueId/uniqueId index.")
            try! GRDBSchemaMigrator.removeInteractionThreadUniqueIdUniqueIdIndex(tx: tx)
        }

        try Task.checkCancellation()
        await databaseStorage.awaitableWrite { tx in
            logger.info("Rebuilding disappearing messages index.")
            try! GRDBSchemaMigrator.rebuildDisappearingMessagesIndex(tx: tx)
        }

        try Task.checkCancellation()
        await databaseStorage.awaitableWrite { tx in
            logger.info("Removing attachmentIds index.")
            try! GRDBSchemaMigrator.removeInteractionAttachmentIdsIndex(tx: tx)
        }

        try Task.checkCancellation()
        await databaseStorage.awaitableWrite { tx in
            logger.info("Rebuilding timestamp index.")
            try! GRDBSchemaMigrator.rebuildInteractionTimestampIndex(tx: tx)
        }

        try Task.checkCancellation()
        await databaseStorage.awaitableWrite { tx in
            logger.info("Rebuilding unended groupCall index.")
            try! GRDBSchemaMigrator.rebuildInteractionUnendedGroupCallIndex(tx: tx)
        }

        try Task.checkCancellation()
        await databaseStorage.awaitableWrite { tx in
            logger.info("Rebuilding groupCall/eraId index.")
            try! GRDBSchemaMigrator.rebuildInteractionGroupCallEraIdIndex(tx: tx)
        }

        try Task.checkCancellation()
        await databaseStorage.awaitableWrite { tx in
            logger.info("Rebuilding story message index.")
            try! GRDBSchemaMigrator.rebuildInteractionStoryReplyIndex(tx: tx)
        }

        try Task.checkCancellation()
        await databaseStorage.awaitableWrite { tx in
            logger.info("Removing conversation load count index.")
            try! GRDBSchemaMigrator.removeInteractionConversationLoadCountIndex(tx: tx)
        }

        try Task.checkCancellation()
        await databaseStorage.awaitableWrite { tx in
            logger.info("Removing conversation load distance index.")
            try! GRDBSchemaMigrator.removeInteractionConversationLoadDistanceIndex(tx: tx)
        }

#if DEBUG
        // If we just ran the migration, we shouldn't need to run it again. If this
        // fails, the list of indexes and migrations we perform don't match.
        owsAssertDebug(
            !needsToRun(),
            "Needs to run, but just ran!",
        )
#endif

        logger.info("Done!")
    }
}
