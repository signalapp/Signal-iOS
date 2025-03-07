//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

class LazyDatabaseMigratorRunner: BGProcessingTaskRunner {
    private let databaseStorage: SDSDatabaseStorage
    private let remoteConfigManager: () -> any RemoteConfigManager
    private let tsAccountManager: () -> any TSAccountManager

    init(
        databaseStorage: SDSDatabaseStorage,
        remoteConfigManager: @escaping () -> any RemoteConfigManager,
        tsAccountManager: @escaping () -> any TSAccountManager
    ) {
        self.databaseStorage = databaseStorage
        self.remoteConfigManager = remoteConfigManager
        self.tsAccountManager = tsAccountManager
    }

    static var taskIdentifier: String = "LazyDatabaseMigratorTask"

    static var requiresNetworkConnectivity: Bool = true

    func shouldLaunchBGProcessingTask() -> Bool {
        guard
            tsAccountManager().registrationStateWithMaybeSneakyTransaction.isRegistered,
            remoteConfigManager().currentConfig().isLazyDatabaseMigratorEnabled
        else {
            return false
        }
        do {
            let indexes = try databaseStorage.read { tx in
                let db = tx.asV2Read.databaseConnection
                return Set(try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'index'"))
            }
            let lazilyRemovedIndexes = [
                "index_interactions_on_view_once",
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
                "Interaction_incompleteViewOnce_partial",
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
            Logger.warn("Couldn't check if we need to execute.")
            return false
        }
    }

    /// Run the migrations.
    ///
    /// If you encounter an error in this method, you can update
    /// `simulatePriorCancellation` to return true and run on a simulator.
    func run() async throws {
        // Must be idempotent.

        guard tsAccountManager().registrationStateWithMaybeSneakyTransaction.isRegistered else {
            Logger.warn("Skipping because we're not registered.")
            return
        }

        try await remoteConfigManager().refreshIfNeeded()
        guard remoteConfigManager().currentConfig().isLazyDatabaseMigratorEnabled else {
            Logger.warn("Skipping because kill switch is set.")
            return
        }

        try Task.checkCancellation()
        await databaseStorage.awaitableWrite { tx in
            Logger.info("Rebuilding incomplete view once index.")
            try! GRDBSchemaMigrator.rebuildIncompleteViewOnceIndex(tx: tx.unwrapGrdbWrite)
        }

        try Task.checkCancellation()
        await databaseStorage.awaitableWrite { tx in
            Logger.info("Removing threadUniqueId/uniqueId index.")
            try! GRDBSchemaMigrator.removeInteractionThreadUniqueIdUniqueIdIndex(tx: tx.unwrapGrdbWrite)
        }

        try Task.checkCancellation()
        await databaseStorage.awaitableWrite { tx in
            Logger.info("Rebuilding disappearing messages index.")
            try! GRDBSchemaMigrator.rebuildDisappearingMessagesIndex(tx: tx.unwrapGrdbWrite)
        }

        try Task.checkCancellation()
        await databaseStorage.awaitableWrite { tx in
            Logger.info("Removing attachmentIds index.")
            try! GRDBSchemaMigrator.removeInteractionAttachmentIdsIndex(tx: tx.unwrapGrdbWrite)
        }

        try Task.checkCancellation()
        await databaseStorage.awaitableWrite { tx in
            Logger.info("Rebuilding timestamp index.")
            try! GRDBSchemaMigrator.rebuildInteractionTimestampIndex(tx: tx.unwrapGrdbWrite)
        }

        try Task.checkCancellation()
        await databaseStorage.awaitableWrite { tx in
            Logger.info("Rebuilding unended groupCall index.")
            try! GRDBSchemaMigrator.rebuildInteractionUnendedGroupCallIndex(tx: tx.unwrapGrdbWrite)
        }

        try Task.checkCancellation()
        await databaseStorage.awaitableWrite { tx in
            Logger.info("Rebuilding groupCall/eraId index.")
            try! GRDBSchemaMigrator.rebuildInteractionGroupCallEraIdIndex(tx: tx.unwrapGrdbWrite)
        }

        try Task.checkCancellation()
        await databaseStorage.awaitableWrite { tx in
            Logger.info("Rebuilding story message index.")
            try! GRDBSchemaMigrator.rebuildInteractionStoryReplyIndex(tx: tx.unwrapGrdbWrite)
        }

        try Task.checkCancellation()
        await databaseStorage.awaitableWrite { tx in
            Logger.info("Removing conversation load count index.")
            try! GRDBSchemaMigrator.removeInteractionConversationLoadCountIndex(tx: tx.unwrapGrdbWrite)
        }

        try Task.checkCancellation()
        await databaseStorage.awaitableWrite { tx in
            Logger.info("Removing conversation load distance index.")
            try! GRDBSchemaMigrator.removeInteractionConversationLoadDistanceIndex(tx: tx.unwrapGrdbWrite)
        }

        #if DEBUG
        // If we just ran the migration, we shouldn't need to run it again. If this
        // fails, the list of indexes and migrations we perform don't match.
        owsAssertDebug(!shouldLaunchBGProcessingTask())
        #endif

        Logger.info("Done!")
    }

    #if targetEnvironment(simulator)
    func simulatePriorCancellation() -> Bool {
        // Simulates a prior cancellation that may cause the task to run when it's
        // already finished.
        return Int.random(in: 0..<10) == 0
    }
    #endif
}
