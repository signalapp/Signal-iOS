//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

@objc
public class GRDBSchemaMigrator: NSObject {

    private static let _areMigrationsComplete = AtomicBool(false)
    @objc
    public static var areMigrationsComplete: Bool { _areMigrationsComplete.get() }
    public static let migrationSideEffectsCollectionName = "MigrationSideEffects"
    public static let avatarRepairAttemptCount = "Avatar Repair Attempt Count"

    /// Migrate a database to the latest version. Throws if migrations fail.
    ///
    /// - Parameter databaseStorage: The database to migrate.
    /// - Parameter isMainDatabase: A boolean indicating whether this is the main database. If so, some global state will be set.
    /// - Parameter runDataMigrations: A boolean indicating whether to include data migrations. Typically, you want to omit this value or set it to `true`, but we want to skip them when recovering a corrupted database.
    /// - Returns: `true` if incremental migrations were performed, and `false` otherwise.
    @discardableResult
    public static func migrateDatabase(
        databaseStorage: SDSDatabaseStorage,
        isMainDatabase: Bool,
        runDataMigrations: Bool = true
    ) throws -> Bool {
        let didPerformIncrementalMigrations: Bool

        let grdbStorageAdapter = databaseStorage.grdbStorage

        let hasCreatedInitialSchema = try grdbStorageAdapter.read {
            try Self.hasCreatedInitialSchema(transaction: $0)
        }

        if hasCreatedInitialSchema {
            do {
                Logger.info("Using incrementalMigrator.")
                didPerformIncrementalMigrations = try runIncrementalMigrations(
                    databaseStorage: databaseStorage,
                    runDataMigrations: runDataMigrations
                )
            } catch {
                owsFailDebug("Incremental migrations failed: \(error.grdbErrorForLogging)")
                throw error
            }
        } else {
            do {
                Logger.info("Using newUserMigrator.")
                try newUserMigrator().migrate(grdbStorageAdapter.pool)
                didPerformIncrementalMigrations = false
            } catch {
                owsFailDebug("New user migrator failed: \(error.grdbErrorForLogging)")
                throw error
            }
        }
        Logger.info("Migrations complete.")

        if isMainDatabase {
            SSKPreferences.markGRDBSchemaAsLatest()
            Self._areMigrationsComplete.set(true)
        }

        return didPerformIncrementalMigrations
    }

    private static func runIncrementalMigrations(
        databaseStorage: SDSDatabaseStorage,
        runDataMigrations: Bool
    ) throws -> Bool {
        let grdbStorageAdapter = databaseStorage.grdbStorage

        let previouslyAppliedMigrations = try grdbStorageAdapter.read { transaction in
            try DatabaseMigrator().appliedIdentifiers(transaction.database)
        }

        // First do the schema migrations. (See the comment within MigrationId for why schema and data
        // migrations are separate.)
        let incrementalMigrator = DatabaseMigratorWrapper()
        registerSchemaMigrations(migrator: incrementalMigrator)
        try incrementalMigrator.migrate(grdbStorageAdapter.pool)

        if runDataMigrations {
            // Hack: Load the account state now, so it can be accessed while performing other migrations.
            // Otherwise one of them might indirectly try to load the account state using a sneaky transaction,
            // which won't work because migrations use a barrier block to prevent observing database state
            // before migration.
            try grdbStorageAdapter.read { transaction in
                _ = self.tsAccountManager.localAddress(with: transaction.asAnyRead)
            }

            // Finally, do data migrations.
            registerDataMigrations(migrator: incrementalMigrator)
            try incrementalMigrator.migrate(grdbStorageAdapter.pool)
        }

        let allAppliedMigrations = try grdbStorageAdapter.read { transaction in
            try DatabaseMigrator().appliedIdentifiers(transaction.database)
        }

        return allAppliedMigrations != previouslyAppliedMigrations
    }

    private static func hasCreatedInitialSchema(transaction: GRDBReadTransaction) throws -> Bool {
        let appliedMigrations = try DatabaseMigrator().appliedIdentifiers(transaction.database)
        Logger.info("appliedMigrations: \(appliedMigrations.sorted()).")
        return appliedMigrations.contains(MigrationId.createInitialSchema.rawValue)
    }

    // MARK: -

    private enum MigrationId: String, CaseIterable {
        case createInitialSchema
        case signalAccount_add_contactAvatars
        case signalAccount_add_contactAvatars_indices
        case jobRecords_add_attachmentId
        case createMediaGalleryItems
        case createReaction
        case dedupeSignalRecipients
        case unreadThreadInteractions
        case createFamilyName
        case createIndexableFTSTable
        case dropContactQuery
        case indexFailedJob
        case groupsV2MessageJobs
        case addUserInfoToInteractions
        case recreateExperienceUpgradeWithNewColumns
        case recreateExperienceUpgradeIndex
        case indexInfoMessageOnType_v2
        case createPendingReadReceipts
        case createInteractionAttachmentIdsIndex
        case addIsUuidCapableToUserProfiles
        case uploadTimestamp
        case addRemoteDeleteToInteractions
        case cdnKeyAndCdnNumber
        case addGroupIdToGroupsV2IncomingMessageJobs
        case removeEarlyReceiptTables
        case addReadToReactions
        case addIsMarkedUnreadToThreads
        case addIsMediaMessageToMessageSenderJobQueue
        case readdAttachmentIndex
        case addLastVisibleRowIdToThreads
        case addMarkedUnreadIndexToThread
        case fixIncorrectIndexes
        case resetThreadVisibility
        case trackUserProfileFetches
        case addMentions
        case addMentionNotificationMode
        case addOfferTypeToCalls
        case addServerDeliveryTimestamp
        case updateAnimatedStickers
        case updateMarkedUnreadIndex
        case addGroupCallMessage2
        case addGroupCallEraIdIndex
        case addProfileBio
        case addWasIdentityVerified
        case storeMutedUntilDateAsMillisecondTimestamp
        case addPaymentModels15
        case addPaymentModels40
        case fixPaymentModels
        case addGroupMember
        case createPendingViewedReceipts
        case addViewedToInteractions
        case createThreadAssociatedData
        case addServerGuidToInteractions
        case addMessageSendLog
        case updatePendingReadReceipts
        case addSendCompletionToMessageSendLog
        case addExclusiveProcessIdentifierAndHighPriorityToJobRecord
        case updateMessageSendLogColumnTypes
        case addRecordTypeIndex
        case tunedConversationLoadIndices
        case messageDecryptDeduplicationV6
        case createProfileBadgeTable
        case createSubscriptionDurableJob
        case addReceiptPresentationToSubscriptionDurableJob
        case createStoryMessageTable
        case addColumnsForStoryContextRedux
        case addIsStoriesCapableToUserProfiles
        case addStoryContextIndexToInteractions
        case updateConversationLoadInteractionCountIndex
        case updateConversationLoadInteractionDistanceIndex
        case updateConversationUnreadCountIndex
        case createDonationReceiptTable
        case addBoostAmountToSubscriptionDurableJob
        case improvedDisappearingMessageIndices
        case addProfileBadgeDuration
        case addGiftBadges
        case addCanReceiveGiftBadgesToUserProfiles
        case addStoryThreadColumns
        case addUnsavedMessagesToSendToJobRecord
        case addColumnsForSendGiftBadgeDurableJob
        case addDonationReceiptTypeColumn
        case addAudioPlaybackRateColumn
        case addSchemaVersionToAttachments
        case makeAudioPlaybackRateColumnNonNull
        case addLastViewedStoryTimestampToTSThread
        case convertStoryIncomingManifestStorageFormat
        case recreateStoryIncomingViewedTimestampIndex
        case addColumnsForLocalUserLeaveGroupDurableJob
        case addStoriesHiddenStateToThreadAssociatedData
        case addUnregisteredAtTimestampToSignalRecipient
        case addLastReceivedStoryTimestampToTSThread
        case addStoryContextAssociatedDataTable
        case populateStoryContextAssociatedDataTableAndRemoveOldColumns
        case addColumnForExperienceUpgradeManifest
        case addStoryContextAssociatedDataReadTimestampColumn
        case addIsCompleteToContactSyncJob
        case addSnoozeCountToExperienceUpgrade
        case addCancelledGroupRingsTable
        case addPaymentProcessorColumnToJobRecords
        case addCdsPreviousE164
        case addCallRecordTable
        case addColumnsForGiftingWithPaypalToJobRecords
        case addSpamReportingTokenRecordTable
        case addVideoDuration

        // NOTE: Every time we add a migration id, consider
        // incrementing grdbSchemaVersionLatest.
        // We only need to do this for breaking changes.

        // MARK: Data Migrations
        //
        // Any migration which leverages SDSModel serialization must occur *after* changes to the
        // database schema complete.
        //
        // Otherwise, for example, consider we have these two pending migrations:
        //  - Migration 1: resaves all instances of Foo (Foo is some SDSModel)
        //  - Migration 2: adds a column "new_column" to the "model_Foo" table
        //
        // Migration 1 will fail, because the generated serialization logic for Foo expects
        // "new_column" to already exist before Migration 2 has even run.
        //
        // The solution is to always split logic that leverages SDSModel serialization into a
        // separate migration, and ensure it runs *after* any schema migrations. That is, new schema
        // migrations must be inserted *before* any of these Data Migrations.
        //
        // Note that account state is loaded *before* running data migrations, because many model objects expect
        // to be able to access that without a transaction.
        case dataMigration_populateGalleryItems
        case dataMigration_markOnboardedUsers_v2
        case dataMigration_clearLaunchScreenCache
        case dataMigration_enableV2RegistrationLockIfNecessary
        case dataMigration_resetStorageServiceData
        case dataMigration_markAllInteractionsAsNotDeleted
        case dataMigration_recordMessageRequestInteractionIdEpoch
        case dataMigration_indexSignalRecipients
        case dataMigration_kbsStateCleanup
        case dataMigration_turnScreenSecurityOnForExistingUsers
        case dataMigration_groupIdMapping
        case dataMigration_disableSharingSuggestionsForExistingUsers
        case dataMigration_removeOversizedGroupAvatars
        case dataMigration_scheduleStorageServiceUpdateForMutedThreads
        case dataMigration_populateGroupMember
        case dataMigration_cullInvalidIdentityKeySendingErrors
        case dataMigration_moveToThreadAssociatedData
        case dataMigration_senderKeyStoreKeyIdMigration
        case dataMigration_reindexGroupMembershipAndMigrateLegacyAvatarDataFixed
        case dataMigration_repairAvatar
        case dataMigration_dropEmojiAvailabilityStore
        case dataMigration_dropSentStories
        case dataMigration_indexMultipleNameComponentsForReceipients
        case dataMigration_syncGroupStories
        case dataMigration_deleteOldGroupCapabilities
        case dataMigration_updateStoriesDisabledInAccountRecord
        case dataMigration_removeGroupStoryRepliesFromSearchIndex
        case dataMigration_populateStoryContextAssociatedDataLastReadTimestamp
        case dataMigration_indexPrivateStoryThreadNames
        case dataMigration_scheduleStorageServiceUpdateForSystemContacts
        case dataMigration_removeLinkedDeviceSystemContacts
    }

    public static let grdbSchemaVersionDefault: UInt = 0
    public static let grdbSchemaVersionLatest: UInt = 54

    // An optimization for new users, we have the first migration import the latest schema
    // and mark any other migrations as "already run".
    private static func newUserMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration(MigrationId.createInitialSchema.rawValue) { db in
            // Within the transaction this migration opens, check that we haven't already run
            // the initial schema migration, in case we are racing with another process that
            // is also running migrations.
            guard try hasCreatedInitialSchema(transaction: GRDBReadTransaction(database: db)).negated else {
                // Already done!
                return
            }

            Logger.info("importing latest schema")
            guard let sqlFile = Bundle(for: GRDBSchemaMigrator.self).url(forResource: "schema", withExtension: "sql") else {
                owsFail("sqlFile was unexpectedly nil")
            }
            let sql = try String(contentsOf: sqlFile)
            try db.execute(sql: sql)

            // After importing the initial schema, we want to skip the remaining
            // incremental migrations, so we manually mark them as complete.
            for migrationId in (MigrationId.allCases.filter { $0 != .createInitialSchema }) {
                if !CurrentAppContext().isRunningTests {
                    Logger.info("skipping migration: \(migrationId) for new user.")
                }
                insertMigration(migrationId.rawValue, db: db)
            }
        }
        return migrator
    }

    private class DatabaseMigratorWrapper {
        var migrator = DatabaseMigrator()

        /**
         * Registers a database migration to be run asynchronously.
         *
         * In short, migrations get registered, GRDB checks which if any haven't been run yet, and runs those.
         * Each migration is provided a transaction and is allowed to throw exceptions on failures.
         * Migrations MUST use the provided transaction to guarantee correctness. The same transaction
         * is used to check migration eligibility and to mark migrations as completed.
         * Migrations that _do not_ throw an exception will be marked at completed. Failed migrations
         * _must_ throw an exception to be marked as incomplete and be re-run on next app launch.
         * Every exception thrown crashes the app.
         */
        func registerMigration(
            _ identifier: MigrationId,
            migrate: @escaping (GRDBWriteTransaction) throws -> Result<Void, Error>
        ) {
            // Hold onto a reference to the migrator, so we can use its `appliedIdentifiers` method
            // which is really a static method since it uses no instance state, but needs a reference
            // to an instance (any instance, doesn't matter) anyway.
            // Don't keep a strong reference to self as that would be a retain cycle, and don't rely
            // on a weak reference to self because self is not guaranteed to be retained when
            // the migration actually runs; this class is used primary for migration setup.
            let migrator = self.migrator
            // Run with immediate foreign key checks so that pre-existing dangling rows
            // don't cause unrelated migrations to fail. We also don't perform schema
            // alterations that would necessitate disabling foreign key checks.
            self.migrator.registerMigration(identifier.rawValue, foreignKeyChecks: .immediate) { (database: Database) in
                let startTime = CACurrentMediaTime()

                // Create a transaction with this database connection.
                // GRDB creates a database connection for each migration applied; this migration
                // is finalized by GRDB internally. The steps look like:
                // 1. Create Database connection (in a write transaction)
                // 2. Run this closure, the migration itself
                // 3. Write to the grdb_migrations table to mark this migration as done (if we don't throw)
                // 4. Commit the transaction.
                //
                // Notably, it does _not_ check that the migration hasn't been run within the same transaction.
                // We do that here and just say we succeeded by early returning and not throwing an error.
                // This catches situations where the migrations are racing across processes.
                //
                // As long as we do this within the same DB connection we get as input to this
                // method, the check happens within the same transaction that writes that
                // the migration is complete, and we can take advantage of DB locks to enforce
                // migrations are only run once across processes.
                guard try migrator
                    .appliedIdentifiers(database)
                    .contains(identifier.rawValue)
                    .negated
                else {
                    // Already run! Just succeed.
                    Logger.info("Attempting to re-run an already-finished migration, exiting: \(identifier)")
                    return
                }

                Logger.info("Running migration: \(identifier)")
                let transaction = GRDBWriteTransaction(database: database)
                let result = try migrate(transaction)
                switch result {
                case .success:
                    let timeElapsed = CACurrentMediaTime() - startTime
                    let formattedTime = String(format: "%0.2fms", timeElapsed * 1000)
                    Logger.info("Migration completed: \(identifier), duration: \(formattedTime)")
                case .failure(let error):
                    throw error
                }
                transaction.finalizeTransaction()
            }
        }

        func migrate(_ database: DatabaseWriter) throws {
            try migrator.migrate(database)
        }
    }

    private static func registerSchemaMigrations(migrator: DatabaseMigratorWrapper) {

        migrator.registerMigration(.createInitialSchema) { _ in
            owsFail("This migration should have already been run by the last YapDB migration.")
            return .success(())
        }

        migrator.registerMigration(.signalAccount_add_contactAvatars) { transaction in
            let sql = """
            DROP TABLE "model_SignalAccount";
            CREATE
                TABLE
                    IF NOT EXISTS "model_SignalAccount" (
                        "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
                        ,"recordType" INTEGER NOT NULL
                        ,"uniqueId" TEXT NOT NULL UNIQUE
                            ON CONFLICT FAIL
                        ,"contact" BLOB
                        ,"contactAvatarHash" BLOB
                        ,"contactAvatarJpegData" BLOB
                        ,"multipleAccountLabelText" TEXT NOT NULL
                        ,"recipientPhoneNumber" TEXT
                        ,"recipientUUID" TEXT
                    );
            """
            try transaction.database.execute(sql: sql)
            return .success(())
        }

        migrator.registerMigration(.signalAccount_add_contactAvatars_indices) { transaction in
            let sql = """
            CREATE
                INDEX IF NOT EXISTS "index_model_SignalAccount_on_uniqueId"
                    ON "model_SignalAccount"("uniqueId"
            )
            ;

            CREATE
                INDEX IF NOT EXISTS "index_signal_accounts_on_recipientPhoneNumber"
                    ON "model_SignalAccount"("recipientPhoneNumber"
            )
            ;

            CREATE
                INDEX IF NOT EXISTS "index_signal_accounts_on_recipientUUID"
                    ON "model_SignalAccount"("recipientUUID"
            )
            ;
            """
            try transaction.database.execute(sql: sql)
            return .success(())
        }

        migrator.registerMigration(.jobRecords_add_attachmentId) { transaction in
            try transaction.database.alter(table: "model_SSKJobRecord") { (table: TableAlteration) -> Void in
                table.add(column: "attachmentId", .text)
            }
            return .success(())
        }

        migrator.registerMigration(.createMediaGalleryItems) { transaction in
            try transaction.database.create(table: "media_gallery_items") { table in
                table.column("attachmentId", .integer)
                    .notNull()
                    .unique()
                table.column("albumMessageId", .integer)
                    .notNull()
                table.column("threadId", .integer)
                    .notNull()
                table.column("originalAlbumOrder", .integer)
                    .notNull()
            }

            try transaction.database.create(index: "index_media_gallery_items_for_gallery",
                          on: "media_gallery_items",
                          columns: ["threadId", "albumMessageId", "originalAlbumOrder"])

            try transaction.database.create(index: "index_media_gallery_items_on_attachmentId",
                          on: "media_gallery_items",
                          columns: ["attachmentId"])

            // Creating gallery records here can crash since it's run in the middle of schema migrations.
            // It instead has been moved to a separate Data Migration.
            // see: "dataMigration_populateGalleryItems"
            // try createInitialGalleryRecords(transaction: GRDBWriteTransaction(database: db))
            return .success(())
        }

        migrator.registerMigration(.createReaction) { transaction in
            try transaction.database.create(table: "model_OWSReaction") { table in
                table.autoIncrementedPrimaryKey("id")
                    .notNull()
                table.column("recordType", .integer)
                    .notNull()
                table.column("uniqueId", .text)
                    .notNull()
                    .unique(onConflict: .fail)
                table.column("emoji", .text)
                    .notNull()
                table.column("reactorE164", .text)
                table.column("reactorUUID", .text)
                table.column("receivedAtTimestamp", .integer)
                    .notNull()
                table.column("sentAtTimestamp", .integer)
                    .notNull()
                table.column("uniqueMessageId", .text)
                    .notNull()
            }
            try transaction.database.create(
                index: "index_model_OWSReaction_on_uniqueId",
                on: "model_OWSReaction",
                columns: ["uniqueId"]
            )
            try transaction.database.create(
                index: "index_model_OWSReaction_on_uniqueMessageId_and_reactorE164",
                on: "model_OWSReaction",
                columns: ["uniqueMessageId", "reactorE164"]
            )
            try transaction.database.create(
                index: "index_model_OWSReaction_on_uniqueMessageId_and_reactorUUID",
                on: "model_OWSReaction",
                columns: ["uniqueMessageId", "reactorUUID"]
            )
            return .success(())
        }

        migrator.registerMigration(.dedupeSignalRecipients) { transaction in
            try autoreleasepool {
                try dedupeSignalRecipients(transaction: transaction.asAnyWrite)
            }

            try transaction.database.drop(index: "index_signal_recipients_on_recipientPhoneNumber")
            try transaction.database.drop(index: "index_signal_recipients_on_recipientUUID")

            try transaction.database.create(
                index: "index_signal_recipients_on_recipientPhoneNumber",
                on: "model_SignalRecipient",
                columns: ["recipientPhoneNumber"],
                unique: true
            )

            try transaction.database.create(
                index: "index_signal_recipients_on_recipientUUID",
                on: "model_SignalRecipient",
                columns: ["recipientUUID"],
                unique: true
            )
            return .success(())
        }

        // Creating gallery records here can crash since it's run in the middle of schema migrations.
        // It instead has been moved to a separate Data Migration.
        // see: "dataMigration_populateGalleryItems"
        // migrator.registerMigration(.indexMediaGallery2) { db in
        //     // re-index the media gallery for those who failed to create during the initial YDB migration
        //     try createInitialGalleryRecords(transaction: GRDBWriteTransaction(database: db))
        // }

        migrator.registerMigration(.unreadThreadInteractions) { transaction in
            try transaction.database.create(
                index: "index_interactions_on_threadId_read_and_id",
                on: "model_TSInteraction",
                columns: ["uniqueThreadId", "read", "id"],
                unique: true
            )
            return .success(())
        }

        migrator.registerMigration(.createFamilyName) { transaction in
            try transaction.database.alter(table: "model_OWSUserProfile", body: { alteration in
                alteration.add(column: "familyName", .text)
            })
            return .success(())
        }

        migrator.registerMigration(.createIndexableFTSTable) { transaction in
            try Bench(title: MigrationId.createIndexableFTSTable.rawValue, logInProduction: true) {
                try transaction.database.create(table: "indexable_text") { table in
                    table.autoIncrementedPrimaryKey("id")
                        .notNull()
                    table.column("collection", .text)
                        .notNull()
                    table.column("uniqueId", .text)
                        .notNull()
                    table.column("ftsIndexableContent", .text)
                        .notNull()
                }

                try transaction.database.create(index: "index_indexable_text_on_collection_and_uniqueId",
                              on: "indexable_text",
                              columns: ["collection", "uniqueId"],
                              unique: true)

                try transaction.database.create(virtualTable: "indexable_text_fts", using: FTS5()) { table in
                    // We could use FTS5TokenizerDescriptor.porter(wrapping: FTS5TokenizerDescriptor.unicode61())
                    //
                    // Porter does stemming (e.g. "hunting" will match "hunter").
                    // unicode61 will remove diacritics (e.g. "senor" will match "señor").
                    //
                    // GRDB TODO: Should we do stemming?
                    let tokenizer = FTS5TokenizerDescriptor.unicode61()
                    table.tokenizer = tokenizer

                    table.synchronize(withTable: "indexable_text")

                    // I thought leveraging the prefix-index feature would speed up as-you-type
                    // searching, but my measurements showed no substantive change.
                    // table.prefixes = [2, 4]

                    table.column("ftsIndexableContent")
                }

                // Copy over existing indexable content so we don't have to regenerate content from every indexed object.
                try transaction.database.execute(sql: "INSERT INTO indexable_text (collection, uniqueId, ftsIndexableContent) SELECT collection, uniqueId, ftsIndexableContent FROM signal_grdb_fts")
                try transaction.database.drop(table: "signal_grdb_fts")
            }
            return .success(())
        }

        migrator.registerMigration(.dropContactQuery) { transaction in
            try transaction.database.drop(table: "model_OWSContactQuery")
            return .success(())
        }

        migrator.registerMigration(.indexFailedJob) { transaction in
            // index this query:
            //      SELECT \(interactionColumn: .uniqueId)
            //      FROM \(InteractionRecord.databaseTableName)
            //      WHERE \(interactionColumn: .storedMessageState) = ?
            try transaction.database.create(index: "index_interaction_on_storedMessageState",
                          on: "model_TSInteraction",
                          columns: ["storedMessageState"])

            // index this query:
            //      SELECT \(interactionColumn: .uniqueId)
            //      FROM \(InteractionRecord.databaseTableName)
            //      WHERE \(interactionColumn: .recordType) = ?
            //      AND (
            //          \(interactionColumn: .callType) = ?
            //          OR \(interactionColumn: .callType) = ?
            //      )
            try transaction.database.create(index: "index_interaction_on_recordType_and_callType",
                          on: "model_TSInteraction",
                          columns: ["recordType", "callType"])
            return .success(())
        }

        migrator.registerMigration(.groupsV2MessageJobs) { transaction in
            try transaction.database.create(table: "model_IncomingGroupsV2MessageJob") { table in
                table.autoIncrementedPrimaryKey("id")
                    .notNull()
                table.column("recordType", .integer)
                    .notNull()
                table.column("uniqueId", .text)
                    .notNull()
                    .unique(onConflict: .fail)
                table.column("createdAt", .double)
                    .notNull()
                table.column("envelopeData", .blob)
                    .notNull()
                table.column("plaintextData", .blob)
                table.column("wasReceivedByUD", .integer)
                    .notNull()
            }
            try transaction.database.create(index: "index_model_IncomingGroupsV2MessageJob_on_uniqueId", on: "model_IncomingGroupsV2MessageJob", columns: ["uniqueId"])
            return .success(())
        }

        migrator.registerMigration(.addUserInfoToInteractions) { transaction in
            try transaction.database.alter(table: "model_TSInteraction") { (table: TableAlteration) -> Void in
                table.add(column: "infoMessageUserInfo", .blob)
            }
            return .success(())
        }

        migrator.registerMigration(.recreateExperienceUpgradeWithNewColumns) { transaction in
            // It's safe to just throw away old experience upgrade data since
            // there are no campaigns actively running that we need to preserve
            try transaction.database.drop(table: "model_ExperienceUpgrade")
            try transaction.database.create(table: "model_ExperienceUpgrade", body: { table in
                table.autoIncrementedPrimaryKey("id")
                    .notNull()
                table.column("recordType", .integer)
                    .notNull()
                table.column("uniqueId", .text)
                    .notNull()
                    .unique(onConflict: .fail)
                table.column("firstViewedTimestamp", .double)
                    .notNull()
                table.column("lastSnoozedTimestamp", .double)
                    .notNull()
                table.column("isComplete", .boolean)
                    .notNull()
            })
            return .success(())
        }

        migrator.registerMigration(.recreateExperienceUpgradeIndex) { transaction in
            try transaction.database.create(index: "index_model_ExperienceUpgrade_on_uniqueId", on: "model_ExperienceUpgrade", columns: ["uniqueId"])
            return .success(())
        }

        migrator.registerMigration(.indexInfoMessageOnType_v2) { transaction in
            // cleanup typo in index name that was released to a small number of internal testflight users
            try transaction.database.execute(sql: "DROP INDEX IF EXISTS index_model_TSInteraction_on_threadUniqueId_recordType_messagType")

            try transaction.database.create(
                index: "index_model_TSInteraction_on_threadUniqueId_recordType_messageType",
                on: "model_TSInteraction",
                columns: ["threadUniqueId", "recordType", "messageType"]
            )
            return .success(())
        }

        migrator.registerMigration(.createPendingReadReceipts) { transaction in
            try transaction.database.create(table: "pending_read_receipts") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("threadId", .integer).notNull()
                table.column("messageTimestamp", .integer).notNull()
                table.column("authorPhoneNumber", .text)
                table.column("authorUuid", .text)
            }
            try transaction.database.create(
                index: "index_pending_read_receipts_on_threadId",
                on: "pending_read_receipts",
                columns: ["threadId"]
            )
            return .success(())
        }

        migrator.registerMigration(.createInteractionAttachmentIdsIndex) { transaction in
            try transaction.database.create(
                index: "index_model_TSInteraction_on_threadUniqueId_and_attachmentIds",
                on: "model_TSInteraction",
                columns: ["threadUniqueId", "attachmentIds"]
            )
            return .success(())
        }

        migrator.registerMigration(.addIsUuidCapableToUserProfiles) { transaction in
            try transaction.database.alter(table: "model_OWSUserProfile") { (table: TableAlteration) -> Void in
                table.add(column: "isUuidCapable", .boolean).notNull().defaults(to: false)
            }
            return .success(())
        }

        migrator.registerMigration(.uploadTimestamp) { transaction in
            try transaction.database.alter(table: "model_TSAttachment") { (table: TableAlteration) -> Void in
                table.add(column: "uploadTimestamp", .integer).notNull().defaults(to: 0)
            }
            return .success(())
        }

        migrator.registerMigration(.addRemoteDeleteToInteractions) { transaction in
            try transaction.database.alter(table: "model_TSInteraction") { (table: TableAlteration) -> Void in
                table.add(column: "wasRemotelyDeleted", .boolean)
            }
            return .success(())
        }

        migrator.registerMigration(.cdnKeyAndCdnNumber) { transaction in
            try transaction.database.alter(table: "model_TSAttachment") { (table: TableAlteration) -> Void in
                table.add(column: "cdnKey", .text).notNull().defaults(to: "")
                table.add(column: "cdnNumber", .integer).notNull().defaults(to: 0)
            }
            return .success(())
        }

        migrator.registerMigration(.addGroupIdToGroupsV2IncomingMessageJobs) { transaction in
            try transaction.database.alter(table: "model_IncomingGroupsV2MessageJob") { (table: TableAlteration) -> Void in
                table.add(column: "groupId", .blob)
            }
            try transaction.database.create(
                index: "index_model_IncomingGroupsV2MessageJob_on_groupId_and_id",
                on: "model_IncomingGroupsV2MessageJob",
                columns: ["groupId", "id"]
            )
            return .success(())
        }

        migrator.registerMigration(.removeEarlyReceiptTables) { transaction in
            try transaction.database.drop(table: "model_TSRecipientReadReceipt")
            try transaction.database.drop(table: "model_OWSLinkedDeviceReadReceipt")

            let viewOnceStore = SDSKeyValueStore(collection: "viewOnceMessages")
            viewOnceStore.removeAll(transaction: transaction.asAnyWrite)
            return .success(())
        }

        migrator.registerMigration(.addReadToReactions) { transaction in
            try transaction.database.alter(table: "model_OWSReaction") { (table: TableAlteration) -> Void in
                table.add(column: "read", .boolean).notNull().defaults(to: false)
            }

            try transaction.database.create(
                index: "index_model_OWSReaction_on_uniqueMessageId_and_read",
                on: "model_OWSReaction",
                columns: ["uniqueMessageId", "read"]
            )

            // Mark existing reactions as read
            try transaction.database.execute(sql: "UPDATE model_OWSReaction SET read = 1")
            return .success(())
        }

        migrator.registerMigration(.addIsMarkedUnreadToThreads) { transaction in
            try transaction.database.alter(table: "model_TSThread") { (table: TableAlteration) -> Void in
                table.add(column: "isMarkedUnread", .boolean).notNull().defaults(to: false)
            }
            return .success(())
        }

        migrator.registerMigration(.addIsMediaMessageToMessageSenderJobQueue) { transaction in
            try transaction.database.alter(table: "model_SSKJobRecord") { (table: TableAlteration) -> Void in
                table.add(column: "isMediaMessage", .boolean)
            }

            try transaction.database.drop(index: "index_model_TSAttachment_on_uniqueId")

            try transaction.database.create(
                index: "index_model_TSAttachment_on_uniqueId_and_contentType",
                on: "model_TSAttachment",
                columns: ["uniqueId", "contentType"]
            )
            return .success(())
        }

        migrator.registerMigration(.readdAttachmentIndex) { transaction in
            try transaction.database.create(
                index: "index_model_TSAttachment_on_uniqueId",
                on: "model_TSAttachment",
                columns: ["uniqueId"]
            )

            try transaction.database.execute(sql: "UPDATE model_SSKJobRecord SET isMediaMessage = 0")
            return .success(())
        }

        migrator.registerMigration(.addLastVisibleRowIdToThreads) { transaction in
            try transaction.database.alter(table: "model_TSThread") { (table: TableAlteration) -> Void in
                table.add(column: "lastVisibleSortIdOnScreenPercentage", .double).notNull().defaults(to: 0)
                table.add(column: "lastVisibleSortId", .integer).notNull().defaults(to: 0)
            }
            return .success(())
        }

        migrator.registerMigration(.addMarkedUnreadIndexToThread) { transaction in
            try transaction.database.create(
                index: "index_model_TSThread_on_isMarkedUnread",
                on: "model_TSThread",
                columns: ["isMarkedUnread"]
            )
            return .success(())
        }

        migrator.registerMigration(.fixIncorrectIndexes) { transaction in
            try transaction.database.drop(index: "index_model_TSInteraction_on_threadUniqueId_recordType_messageType")
            try transaction.database.create(
                index: "index_model_TSInteraction_on_uniqueThreadId_recordType_messageType",
                on: "model_TSInteraction",
                columns: ["uniqueThreadId", "recordType", "messageType"]
            )

            try transaction.database.drop(index: "index_model_TSInteraction_on_threadUniqueId_and_attachmentIds")
            try transaction.database.create(
                index: "index_model_TSInteraction_on_uniqueThreadId_and_attachmentIds",
                on: "model_TSInteraction",
                columns: ["uniqueThreadId", "attachmentIds"]
            )
            return .success(())
        }

        migrator.registerMigration(.resetThreadVisibility) { transaction in
            try transaction.database.execute(sql: "UPDATE model_TSThread SET lastVisibleSortIdOnScreenPercentage = 0, lastVisibleSortId = 0")
            return .success(())
        }

        migrator.registerMigration(.trackUserProfileFetches) { transaction in
            try transaction.database.alter(table: "model_OWSUserProfile") { (table: TableAlteration) -> Void in
                table.add(column: "lastFetchDate", .double)
                table.add(column: "lastMessagingDate", .double)
            }
            try transaction.database.create(
                index: "index_model_OWSUserProfile_on_lastFetchDate_and_lastMessagingDate",
                on: "model_OWSUserProfile",
                columns: ["lastFetchDate", "lastMessagingDate"]
            )
            return .success(())
        }

        migrator.registerMigration(.addMentions) { transaction in
            try transaction.database.create(table: "model_TSMention") { table in
                table.autoIncrementedPrimaryKey("id")
                    .notNull()
                table.column("recordType", .integer)
                    .notNull()
                table.column("uniqueId", .text)
                    .notNull()
                    .unique(onConflict: .fail)
                table.column("uniqueMessageId", .text)
                    .notNull()
                table.column("uniqueThreadId", .text)
                    .notNull()
                table.column("uuidString", .text)
                    .notNull()
                table.column("creationTimestamp", .double)
                    .notNull()
            }
            try transaction.database.create(
                index: "index_model_TSMention_on_uniqueId",
                on: "model_TSMention",
                columns: ["uniqueId"]
            )
            try transaction.database.create(
                index: "index_model_TSMention_on_uuidString_and_uniqueThreadId",
                on: "model_TSMention",
                columns: ["uuidString", "uniqueThreadId"]
            )
            try transaction.database.create(
                index: "index_model_TSMention_on_uniqueMessageId_and_uuidString",
                on: "model_TSMention",
                columns: ["uniqueMessageId", "uuidString"],
                unique: true
            )

            try transaction.database.alter(table: "model_TSThread") { (table: TableAlteration) -> Void in
                table.add(column: "messageDraftBodyRanges", .blob)
            }

            try transaction.database.alter(table: "model_TSInteraction") { (table: TableAlteration) -> Void in
                table.add(column: "bodyRanges", .blob)
            }
            return .success(())
        }

        migrator.registerMigration(.addMentionNotificationMode) { transaction in
            try transaction.database.alter(table: "model_TSThread") { (table: TableAlteration) -> Void in
                table.add(column: "mentionNotificationMode", .integer)
                    .notNull()
                    .defaults(to: 0)
            }
            return .success(())
        }

        migrator.registerMigration(.addOfferTypeToCalls) { transaction in
            try transaction.database.alter(table: "model_TSInteraction") { (table: TableAlteration) -> Void in
                table.add(column: "offerType", .integer)
            }

            // Backfill all existing calls as "audio" calls.
            try transaction.database.execute(sql: "UPDATE model_TSInteraction SET offerType = 0 WHERE recordType IS \(SDSRecordType.call.rawValue)")
            return .success(())
        }

        migrator.registerMigration(.addServerDeliveryTimestamp) { transaction in
            try transaction.database.alter(table: "model_IncomingGroupsV2MessageJob") { (table: TableAlteration) -> Void in
                table.add(column: "serverDeliveryTimestamp", .integer).notNull().defaults(to: 0)
            }

            try transaction.database.alter(table: "model_OWSMessageContentJob") { (table: TableAlteration) -> Void in
                table.add(column: "serverDeliveryTimestamp", .integer).notNull().defaults(to: 0)
            }

            try transaction.database.alter(table: "model_SSKJobRecord") { (table: TableAlteration) -> Void in
                table.add(column: "serverDeliveryTimestamp", .integer)
            }

            try transaction.database.alter(table: "model_TSInteraction") { (table: TableAlteration) -> Void in
                table.add(column: "serverDeliveryTimestamp", .integer)
            }

            // Backfill all incoming messages with "0" as their timestamp
            try transaction.database.execute(sql: "UPDATE model_TSInteraction SET serverDeliveryTimestamp = 0 WHERE recordType IS \(SDSRecordType.incomingMessage.rawValue)")

            // Backfill all jobs with "0" as their timestamp
            try transaction.database.execute(sql: "UPDATE model_SSKJobRecord SET serverDeliveryTimestamp = 0 WHERE recordType IS \(SDSRecordType.messageDecryptJobRecord.rawValue)")
            return .success(())
        }

        migrator.registerMigration(.updateAnimatedStickers) { transaction in
            try transaction.database.alter(table: "model_TSAttachment") { (table: TableAlteration) -> Void in
                table.add(column: "isAnimatedCached", .integer)
            }
            try transaction.database.alter(table: "model_InstalledSticker") { (table: TableAlteration) -> Void in
                table.add(column: "contentType", .text)
            }
            return .success(())
        }

        migrator.registerMigration(.updateMarkedUnreadIndex) { transaction in
            try transaction.database.drop(index: "index_model_TSThread_on_isMarkedUnread")
            try transaction.database.create(
                index: "index_model_TSThread_on_isMarkedUnread_and_shouldThreadBeVisible",
                on: "model_TSThread",
                columns: ["isMarkedUnread", "shouldThreadBeVisible"]
            )
            return .success(())
        }

        migrator.registerMigration(.addGroupCallMessage2) { transaction in
            try transaction.database.alter(table: "model_TSInteraction") { table in
                table.add(column: "eraId", .text)
                table.add(column: "hasEnded", .boolean)
                table.add(column: "creatorUuid", .text)
                table.add(column: "joinedMemberUuids", .blob)
            }

            try transaction.database.create(
                index: "index_model_TSInteraction_on_uniqueThreadId_and_hasEnded_and_recordType",
                on: "model_TSInteraction",
                columns: ["uniqueThreadId", "hasEnded", "recordType"]
            )
            return .success(())
        }

        migrator.registerMigration(.addGroupCallEraIdIndex) { transaction in
            try transaction.database.create(
                index: "index_model_TSInteraction_on_uniqueThreadId_and_eraId_and_recordType",
                on: "model_TSInteraction",
                columns: ["uniqueThreadId", "eraId", "recordType"]
            )
            return .success(())
        }

        migrator.registerMigration(.addProfileBio) { transaction in
            try transaction.database.alter(table: "model_OWSUserProfile") { table in
                table.add(column: "bio", .text)
                table.add(column: "bioEmoji", .text)
            }
            return .success(())
        }

        migrator.registerMigration(.addWasIdentityVerified) { transaction in
            try transaction.database.alter(table: "model_TSInteraction") { table in
                table.add(column: "wasIdentityVerified", .boolean)
            }

            try transaction.database.execute(sql: "UPDATE model_TSInteraction SET wasIdentityVerified = 0")
            return .success(())
        }

        migrator.registerMigration(.storeMutedUntilDateAsMillisecondTimestamp) { transaction in
            try transaction.database.alter(table: "model_TSThread") { table in
                table.add(column: "mutedUntilTimestamp", .integer).notNull().defaults(to: 0)
            }

            // Convert any existing mutedUntilDate (seconds) into mutedUntilTimestamp (milliseconds)
            try transaction.database.execute(sql: "UPDATE model_TSThread SET mutedUntilTimestamp = CAST(mutedUntilDate * 1000 AS INT) WHERE mutedUntilDate IS NOT NULL")
            try transaction.database.execute(sql: "UPDATE model_TSThread SET mutedUntilDate = NULL")
            return .success(())
        }

        migrator.registerMigration(.addPaymentModels15) { transaction in
            try transaction.database.alter(table: "model_TSInteraction") { (table: TableAlteration) -> Void in
                table.add(column: "paymentCancellation", .blob)
                table.add(column: "paymentNotification", .blob)
                table.add(column: "paymentRequest", .blob)
            }
            return .success(())
        }

        migrator.registerMigration(.addPaymentModels40) { transaction in
            // PAYMENTS TODO: Remove.
            try transaction.database.execute(sql: "DROP TABLE IF EXISTS model_TSPaymentModel")
            try transaction.database.execute(sql: "DROP TABLE IF EXISTS model_TSPaymentRequestModel")

            try transaction.database.create(table: "model_TSPaymentModel") { table in
                table.autoIncrementedPrimaryKey("id")
                    .notNull()
                table.column("recordType", .integer)
                    .notNull()
                table.column("uniqueId", .text)
                    .notNull()
                    .unique(onConflict: .fail)
                table.column("addressUuidString", .text)
                table.column("createdTimestamp", .integer)
                    .notNull()
                table.column("isUnread", .boolean)
                    .notNull()
                table.column("mcLedgerBlockIndex", .integer)
                    .notNull()
                table.column("mcReceiptData", .blob)
                table.column("mcTransactionData", .blob)
                table.column("memoMessage", .text)
                table.column("mobileCoin", .blob)
                table.column("paymentAmount", .blob)
                table.column("paymentFailure", .integer)
                    .notNull()
                table.column("paymentState", .integer)
                    .notNull()
                table.column("paymentType", .integer)
                    .notNull()
                table.column("requestUuidString", .text)
            }

            try transaction.database.create(index: "index_model_TSPaymentModel_on_uniqueId", on: "model_TSPaymentModel", columns: ["uniqueId"])
            try transaction.database.create(index: "index_model_TSPaymentModel_on_paymentState", on: "model_TSPaymentModel", columns: ["paymentState"])
            try transaction.database.create(index: "index_model_TSPaymentModel_on_mcLedgerBlockIndex", on: "model_TSPaymentModel", columns: ["mcLedgerBlockIndex"])
            try transaction.database.create(index: "index_model_TSPaymentModel_on_mcReceiptData", on: "model_TSPaymentModel", columns: ["mcReceiptData"])
            try transaction.database.create(index: "index_model_TSPaymentModel_on_mcTransactionData", on: "model_TSPaymentModel", columns: ["mcTransactionData"])
            try transaction.database.create(index: "index_model_TSPaymentModel_on_isUnread", on: "model_TSPaymentModel", columns: ["isUnread"])
            return .success(())
        }

        migrator.registerMigration(.fixPaymentModels) { transaction in
            // We released a build with an out-of-date schema that didn't reflect
            // `addPaymentModels15`. To fix this, we need to run the column adds
            // again to get all users in a consistent state. We can safely skip
            // this migration if it fails.
            do {
                try transaction.database.alter(table: "model_TSInteraction") { (table: TableAlteration) -> Void in
                    table.add(column: "paymentCancellation", .blob)
                    table.add(column: "paymentNotification", .blob)
                    table.add(column: "paymentRequest", .blob)
                }
            } catch {
                // We can safely skip this if it fails.
                Logger.info("Skipping re-add of interaction payment columns.")
            }
            return .success(())
        }

        migrator.registerMigration(.addGroupMember) { transaction in
            try transaction.database.create(table: "model_TSGroupMember") { table in
                table.autoIncrementedPrimaryKey("id")
                    .notNull()
                table.column("recordType", .integer)
                    .notNull()
                table.column("uniqueId", .text)
                    .notNull()
                    .unique(onConflict: .fail)
                table.column("groupThreadId", .text)
                    .notNull()
                table.column("phoneNumber", .text)
                table.column("uuidString", .text)
                table.column("lastInteractionTimestamp", .integer)
                    .notNull().defaults(to: 0)
            }

            try transaction.database.create(
                index: "index_model_TSGroupMember_on_uniqueId",
                on: "model_TSGroupMember",
                columns: ["uniqueId"]
            )
            try transaction.database.create(
                index: "index_model_TSGroupMember_on_groupThreadId",
                on: "model_TSGroupMember",
                columns: ["groupThreadId"]
            )
            try transaction.database.create(
                index: "index_model_TSGroupMember_on_uuidString_and_groupThreadId",
                on: "model_TSGroupMember",
                columns: ["uuidString", "groupThreadId"],
                unique: true
            )
            try transaction.database.create(
                index: "index_model_TSGroupMember_on_phoneNumber_and_groupThreadId",
                on: "model_TSGroupMember",
                columns: ["phoneNumber", "groupThreadId"],
                unique: true
            )
            return .success(())
        }

        migrator.registerMigration(.createPendingViewedReceipts) { transaction in
            try transaction.database.create(table: "pending_viewed_receipts") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("threadId", .integer).notNull()
                table.column("messageTimestamp", .integer).notNull()
                table.column("authorPhoneNumber", .text)
                table.column("authorUuid", .text)
            }
            try transaction.database.create(
                index: "index_pending_viewed_receipts_on_threadId",
                on: "pending_viewed_receipts",
                columns: ["threadId"]
            )
            return .success(())
        }

        migrator.registerMigration(.addViewedToInteractions) { transaction in
            try transaction.database.alter(table: "model_TSInteraction") { (table: TableAlteration) -> Void in
                table.add(column: "viewed", .boolean)
            }

            try transaction.database.execute(sql: "UPDATE model_TSInteraction SET viewed = 0")
            return .success(())
        }

        migrator.registerMigration(.createThreadAssociatedData) { transaction in
            try transaction.database.create(table: "thread_associated_data") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("threadUniqueId", .text)
                    .notNull()
                    .unique(onConflict: .fail)
                table.column("isArchived", .boolean)
                    .notNull()
                    .defaults(to: false)
                table.column("isMarkedUnread", .boolean)
                    .notNull()
                    .defaults(to: false)
                table.column("mutedUntilTimestamp", .integer)
                    .notNull()
                    .defaults(to: 0)
            }

            try transaction.database.create(
                index: "index_thread_associated_data_on_threadUniqueId",
                on: "thread_associated_data",
                columns: ["threadUniqueId"],
                unique: true
            )
            try transaction.database.create(
                index: "index_thread_associated_data_on_threadUniqueId_and_isMarkedUnread",
                on: "thread_associated_data",
                columns: ["threadUniqueId", "isMarkedUnread"]
            )
            try transaction.database.create(
                index: "index_thread_associated_data_on_threadUniqueId_and_isArchived",
                on: "thread_associated_data",
                columns: ["threadUniqueId", "isArchived"]
            )
            return .success(())
        }

        migrator.registerMigration(.addServerGuidToInteractions) { transaction in
            try transaction.database.alter(table: "model_TSInteraction") { (table: TableAlteration) -> Void in
                table.add(column: "serverGuid", .text)
            }
            return .success(())
        }

        migrator.registerMigration(.addMessageSendLog) { transaction in
            // Records all sent payloads
            // The sentTimestamp is the timestamp of the outgoing payload
            try transaction.database.create(table: "MessageSendLog_Payload") { table in
                table.autoIncrementedPrimaryKey("payloadId")
                    .notNull()
                table.column("plaintextContent", .blob)
                    .notNull()
                table.column("contentHint", .integer)
                    .notNull()
                table.column("sentTimestamp", .date)
                    .notNull()
                table.column("uniqueThreadId", .text)
                    .notNull()
            }

            // This table tracks a many-to-many relationship mapping
            // TSInteractions to related payloads. This is tracked so
            // when a given interaction is deleted, all related payloads
            // can be queried and deleted.
            //
            // An interaction can have multiple payloads (e.g. the message,
            // reactions, read receipts).
            // A payload can have multiple associated interactions (e.g.
            // a single receipt message marking multiple messages as read).
            try transaction.database.create(table: "MessageSendLog_Message") { table in
                table.column("payloadId", .integer)
                    .notNull()
                table.column("uniqueId", .text)
                    .notNull()

                table.primaryKey(["payloadId", "uniqueId"])
                table.foreignKey(
                    ["payloadId"],
                    references: "MessageSendLog_Payload",
                    columns: ["payloadId"],
                    onDelete: .cascade,
                    onUpdate: .cascade)
            }

            // Records all intended recipients for an intended payload
            // A trigger will ensure that once all recipients have acked,
            // the corresponding payload is deleted.
            try transaction.database.create(table: "MessageSendLog_Recipient") { table in
                table.column("payloadId", .integer)
                    .notNull()
                table.column("recipientUUID", .text)
                    .notNull()
                table.column("recipientDeviceId", .integer)
                    .notNull()

                table.primaryKey(["payloadId", "recipientUUID", "recipientDeviceId"])
                table.foreignKey(
                    ["payloadId"],
                    references: "MessageSendLog_Payload",
                    columns: ["payloadId"],
                    onDelete: .cascade,
                    onUpdate: .cascade)
            }

            // This trigger ensures that once every intended recipient of
            // a payload has responded with a delivery receipt that the
            // payload is deleted.
            try transaction.database.execute(sql: """
                CREATE TRIGGER MSLRecipient_deliveryReceiptCleanup
                AFTER DELETE ON MessageSendLog_Recipient
                WHEN 0 = (
                    SELECT COUNT(*) FROM MessageSendLog_Recipient
                    WHERE payloadId = old.payloadId
                )
                BEGIN
                    DELETE FROM MessageSendLog_Payload
                    WHERE payloadId = old.payloadId;
                END;
            """)

            // This trigger ensures that if a given interaction is deleted,
            // all associated payloads are also deleted.
            try transaction.database.execute(sql: """
                CREATE TRIGGER MSLMessage_payloadCleanup
                AFTER DELETE ON MessageSendLog_Message
                BEGIN
                    DELETE FROM MessageSendLog_Payload WHERE payloadId = old.payloadId;
                END;
            """)

            // When we receive a decryption failure message, we need to look up
            // the content proto based on the date sent
            try transaction.database.create(
                index: "MSLPayload_sentTimestampIndex",
                on: "MessageSendLog_Payload",
                columns: ["sentTimestamp"]
            )

            // When deleting an interaction, we'll need to be able to lookup all
            // payloads associated with that interaction.
            try transaction.database.create(
                index: "MSLMessage_relatedMessageId",
                on: "MessageSendLog_Message",
                columns: ["uniqueId"]
            )
            return .success(())
        }

        migrator.registerMigration(.updatePendingReadReceipts) { transaction in
            try transaction.database.alter(table: "pending_read_receipts") { (table: TableAlteration) -> Void in
                table.add(column: "messageUniqueId", .text)
            }
            try transaction.database.alter(table: "pending_viewed_receipts") { (table: TableAlteration) -> Void in
                table.add(column: "messageUniqueId", .text)
            }
            return .success(())
        }

        migrator.registerMigration(.addSendCompletionToMessageSendLog) { transaction in
            try transaction.database.alter(table: "MessageSendLog_Payload") { (table: TableAlteration) -> Void in
                table.add(column: "sendComplete", .boolean).notNull().defaults(to: false)
            }

            // All existing entries are assumed to have completed.
            try transaction.database.execute(sql: "UPDATE MessageSendLog_Payload SET sendComplete = 1")

            // Update the trigger to include the new column: "AND sendComplete = true"
            try transaction.database.execute(sql: """
                DROP TRIGGER MSLRecipient_deliveryReceiptCleanup;

                CREATE TRIGGER MSLRecipient_deliveryReceiptCleanup
                AFTER DELETE ON MessageSendLog_Recipient
                WHEN 0 = (
                    SELECT COUNT(*) FROM MessageSendLog_Recipient
                    WHERE payloadId = old.payloadId
                )
                BEGIN
                    DELETE FROM MessageSendLog_Payload
                    WHERE payloadId = old.payloadId AND sendComplete = true;
                END;
            """)
            return .success(())
        }

        migrator.registerMigration(.addExclusiveProcessIdentifierAndHighPriorityToJobRecord) { transaction in
            try transaction.database.alter(table: "model_SSKJobRecord") { (table: TableAlteration) -> Void in
                table.add(column: "exclusiveProcessIdentifier", .text)
                table.add(column: "isHighPriority", .boolean)
            }
            try transaction.database.execute(sql: "UPDATE model_SSKJobRecord SET isHighPriority = 0")
            return .success(())
        }

        migrator.registerMigration(.updateMessageSendLogColumnTypes) { transaction in
            // Since the MessageSendLog hasn't shipped yet, we can get away with just dropping and rebuilding
            // the tables instead of performing a more expensive migration.
            try transaction.database.drop(table: "MessageSendLog_Payload")
            try transaction.database.drop(table: "MessageSendLog_Message")
            try transaction.database.drop(table: "MessageSendLog_Recipient")

            try transaction.database.create(table: "MessageSendLog_Payload") { table in
                table.autoIncrementedPrimaryKey("payloadId")
                    .notNull()
                table.column("plaintextContent", .blob)
                    .notNull()
                table.column("contentHint", .integer)
                    .notNull()
                table.column("sentTimestamp", .integer)
                    .notNull()
                table.column("uniqueThreadId", .text)
                    .notNull()
                table.column("sendComplete", .boolean)
                    .notNull().defaults(to: false)
            }

            try transaction.database.create(table: "MessageSendLog_Message") { table in
                table.column("payloadId", .integer)
                    .notNull()
                table.column("uniqueId", .text)
                    .notNull()

                table.primaryKey(["payloadId", "uniqueId"])
                table.foreignKey(
                    ["payloadId"],
                    references: "MessageSendLog_Payload",
                    columns: ["payloadId"],
                    onDelete: .cascade,
                    onUpdate: .cascade)
            }

            try transaction.database.create(table: "MessageSendLog_Recipient") { table in
                table.column("payloadId", .integer)
                    .notNull()
                table.column("recipientUUID", .text)
                    .notNull()
                table.column("recipientDeviceId", .integer)
                    .notNull()

                table.primaryKey(["payloadId", "recipientUUID", "recipientDeviceId"])
                table.foreignKey(
                    ["payloadId"],
                    references: "MessageSendLog_Payload",
                    columns: ["payloadId"],
                    onDelete: .cascade,
                    onUpdate: .cascade)
            }

            try transaction.database.execute(sql: """
                CREATE TRIGGER MSLRecipient_deliveryReceiptCleanup
                AFTER DELETE ON MessageSendLog_Recipient
                WHEN 0 = (
                    SELECT COUNT(*) FROM MessageSendLog_Recipient
                    WHERE payloadId = old.payloadId
                )
                BEGIN
                    DELETE FROM MessageSendLog_Payload
                    WHERE payloadId = old.payloadId AND sendComplete = true;
                END;

                CREATE TRIGGER MSLMessage_payloadCleanup
                AFTER DELETE ON MessageSendLog_Message
                BEGIN
                    DELETE FROM MessageSendLog_Payload WHERE payloadId = old.payloadId;
                END;
            """)

            try transaction.database.create(
                index: "MSLPayload_sentTimestampIndex",
                on: "MessageSendLog_Payload",
                columns: ["sentTimestamp"]
            )
            try transaction.database.create(
                index: "MSLMessage_relatedMessageId",
                on: "MessageSendLog_Message",
                columns: ["uniqueId"]
            )
            return .success(())
        }

        migrator.registerMigration(.addRecordTypeIndex) { transaction in
            try transaction.database.create(
                index: "index_model_TSInteraction_on_nonPlaceholders_uniqueThreadId_id",
                on: "model_TSInteraction",
                columns: ["uniqueThreadId", "id"],
                condition: "\(interactionColumn: .recordType) IS NOT \(SDSRecordType.recoverableDecryptionPlaceholder.rawValue)"
            )
            return .success(())
        }

        migrator.registerMigration(.tunedConversationLoadIndices) { transaction in
            // These two indices are hyper-tuned for queries used to fetch the conversation load window. Specifically:
            // - GRDBInteractionFinder.count(excludingPlaceholders:transaction:)
            // - GRDBInteractionFinder.distanceFromLatest(interactionUniqueId:excludingPlaceholders:transaction:)
            // - GRDBInteractionFinder.enumerateInteractions(range:excludingPlaceholders:transaction:block:)
            //
            // These indices are partial, covering and as small as possible. The columns selected appear
            // redundant, but this is to avoid the SQLite query planner from selecting a less-optimal,
            // non-covering index that it thinks may be more optimal since it's less bytes/row.
            // More detailed info is included in the commit message.
            //
            // Note: These are not generated using the GRDB index creation syntax. In my testing it seems that
            // placing quotes around the column name in the WHERE clause will trick the SQLite query planner
            // into thinking these indices can't be applied to the queries we're optimizing for.
            try transaction.database.execute(sql: """
                DROP INDEX IF EXISTS index_model_TSInteraction_on_nonPlaceholders_uniqueThreadId_id;

                CREATE INDEX index_model_TSInteraction_ConversationLoadInteractionCount
                ON model_TSInteraction(uniqueThreadId, recordType)
                WHERE recordType IS NOT \(SDSRecordType.recoverableDecryptionPlaceholder.rawValue);

                CREATE INDEX index_model_TSInteraction_ConversationLoadInteractionDistance
                ON model_TSInteraction(uniqueThreadId, id, recordType, uniqueId)
                WHERE recordType IS NOT \(SDSRecordType.recoverableDecryptionPlaceholder.rawValue);
            """)
            return .success(())
        }

        migrator.registerMigration(.messageDecryptDeduplicationV6) { transaction in
            if try transaction.database.tableExists("MessageDecryptDeduplication") {
                try transaction.database.drop(table: "MessageDecryptDeduplication")
            }
            return .success(())
        }

        migrator.registerMigration(.createProfileBadgeTable) { transaction in
            try transaction.database.alter(table: "model_OWSUserProfile", body: { alteration in
                alteration.add(column: "profileBadgeInfo", .blob)
            })

            try transaction.database.create(table: "model_ProfileBadgeTable") { table in
                table.column("id", .text).primaryKey()
                table.column("rawCategory", .text).notNull()
                table.column("localizedName", .text).notNull()
                table.column("localizedDescriptionFormatString", .text).notNull()
                table.column("resourcePath", .text).notNull()

                table.column("badgeVariant", .text).notNull()
                table.column("localization", .text).notNull()
            }
            return .success(())
        }

        migrator.registerMigration(.createSubscriptionDurableJob) { transaction in
            try transaction.database.alter(table: "model_SSKJobRecord") { (table: TableAlteration) -> Void in
                table.add(column: "receiptCredentailRequest", .blob)
                table.add(column: "receiptCredentailRequestContext", .blob)
                table.add(column: "priorSubscriptionLevel", .integer)
                table.add(column: "subscriberID", .blob)
                table.add(column: "targetSubscriptionLevel", .integer)
                table.add(column: "boostPaymentIntentID", .text)
                table.add(column: "isBoost", .boolean)
            }
            return .success(())
        }

        migrator.registerMigration(.addReceiptPresentationToSubscriptionDurableJob) { transaction in
            try transaction.database.alter(table: "model_SSKJobRecord") { (table: TableAlteration) -> Void in
                table.add(column: "receiptCredentialPresentation", .blob)
            }
            return .success(())
        }

        migrator.registerMigration(.createStoryMessageTable) { transaction in
            try transaction.database.create(table: "model_StoryMessage") { table in
                table.autoIncrementedPrimaryKey("id")
                    .notNull()
                table.column("recordType", .integer)
                    .notNull()
                table.column("uniqueId", .text)
                    .notNull()
                    .unique(onConflict: .fail)
                table.column("timestamp", .integer)
                    .notNull()
                table.column("authorUuid", .text)
                    .notNull()
                table.column("groupId", .blob)
                table.column("direction", .integer)
                    .notNull()
                table.column("manifest", .blob)
                    .notNull()
                table.column("attachment", .blob)
                    .notNull()
            }

            try transaction.database.create(index: "index_model_StoryMessage_on_uniqueId", on: "model_StoryMessage", columns: ["uniqueId"])

            try transaction.database.create(
                index: "index_model_StoryMessage_on_timestamp_and_authorUuid",
                on: "model_StoryMessage",
                columns: ["timestamp", "authorUuid"]
            )
            try transaction.database.create(
                index: "index_model_StoryMessage_on_direction",
                on: "model_StoryMessage",
                columns: ["direction"]
            )
            try transaction.database.execute(sql: """
                CREATE
                    INDEX index_model_StoryMessage_on_incoming_viewedTimestamp
                        ON model_StoryMessage (
                        json_extract (
                            manifest
                            ,'$.incoming.viewedTimestamp'
                        )
                    )
                ;
            """)
            return .success(())
        }

        migrator.registerMigration(.addColumnsForStoryContextRedux) { transaction in
            guard !hasRunMigration("addColumnsForStoryContext", transaction: transaction) else {
                return .success(())
            }

            try transaction.database.alter(table: "model_TSInteraction") { (table: TableAlteration) -> Void in
                table.add(column: "storyAuthorUuidString", .text)
                table.add(column: "storyTimestamp", .integer)
                table.add(column: "isGroupStoryReply", .boolean).defaults(to: false)
                table.add(column: "storyReactionEmoji", .text)
            }
            return .success(())
        }

        migrator.registerMigration(.addIsStoriesCapableToUserProfiles) { transaction in
            try transaction.database.alter(table: "model_OWSUserProfile") { (table: TableAlteration) -> Void in
                table.add(column: "isStoriesCapable", .boolean).notNull().defaults(to: false)
            }

            try transaction.database.execute(sql: "ALTER TABLE model_OWSUserProfile DROP COLUMN isUuidCapable")
            return .success(())
        }

        migrator.registerMigration(.createDonationReceiptTable) { transaction in
            try transaction.database.create(table: "model_DonationReceipt") { table in
                table.autoIncrementedPrimaryKey("id")
                    .notNull()
                table.column("uniqueId", .text)
                    .notNull()
                    .unique(onConflict: .fail)
                table.column("timestamp", .integer)
                    .notNull()
                table.column("subscriptionLevel", .integer)
                table.column("amount", .numeric)
                    .notNull()
                table.column("currencyCode", .text)
                    .notNull()
            }
            return .success(())
        }

        migrator.registerMigration(.addBoostAmountToSubscriptionDurableJob) { transaction in
            try transaction.database.alter(table: "model_SSKJobRecord") { (table: TableAlteration) -> Void in
                table.add(column: "amount", .numeric)
                table.add(column: "currencyCode", .text)
            }
            return .success(())
        }

        // These index migrations are *expensive* for users with large interaction tables. For external
        // users who don't yet have access to stories and don't have need for the indices, we will perform
        // one migration per release to keep the blocking time low (ideally one 5-7s migration per release).
        migrator.registerMigration(.updateConversationLoadInteractionCountIndex) { transaction in
            guard !hasRunMigration("addColumnsForStoryContext", transaction: transaction) else {
                return .success(())
            }

            try transaction.database.execute(sql: """
                DROP INDEX index_model_TSInteraction_ConversationLoadInteractionCount;

                CREATE INDEX index_model_TSInteraction_ConversationLoadInteractionCount
                ON model_TSInteraction(uniqueThreadId, isGroupStoryReply, recordType)
                WHERE recordType IS NOT \(SDSRecordType.recoverableDecryptionPlaceholder.rawValue);
            """)
            return .success(())
        }

        migrator.registerMigration(.updateConversationLoadInteractionDistanceIndex) { transaction in
            guard !hasRunMigration("addColumnsForStoryContext", transaction: transaction) else {
                return .success(())
            }

            try transaction.database.execute(sql: """
                DROP INDEX index_model_TSInteraction_ConversationLoadInteractionDistance;

                CREATE INDEX index_model_TSInteraction_ConversationLoadInteractionDistance
                ON model_TSInteraction(uniqueThreadId, id, isGroupStoryReply, recordType, uniqueId)
                WHERE recordType IS NOT \(SDSRecordType.recoverableDecryptionPlaceholder.rawValue);
            """)
            return .success(())
        }

        migrator.registerMigration(.updateConversationUnreadCountIndex) { transaction in
            guard !hasRunMigration("addColumnsForStoryContext", transaction: transaction) else {
                return .success(())
            }

            try transaction.database.execute(sql: """
                DROP INDEX IF EXISTS index_interactions_unread_counts;
                DROP INDEX IF EXISTS index_model_TSInteraction_UnreadCount;

                CREATE INDEX index_model_TSInteraction_UnreadCount
                ON model_TSInteraction(read, isGroupStoryReply, uniqueThreadId, recordType);
            """)
            return .success(())
        }

        migrator.registerMigration(.addStoryContextIndexToInteractions) { transaction in
            try transaction.database.create(
                index: "index_model_TSInteraction_on_StoryContext",
                on: "model_TSInteraction",
                columns: ["storyTimestamp", "storyAuthorUuidString", "isGroupStoryReply"]
            )
            return .success(())
        }

        migrator.registerMigration(.improvedDisappearingMessageIndices) { transaction in
            // The old index was created in an order that made it practically useless for the query
            // we needed it for. This rebuilds it as a partial index.
            try transaction.database.execute(sql: """
                DROP INDEX index_interactions_on_threadUniqueId_storedShouldStartExpireTimer_and_expiresAt;

                CREATE INDEX index_interactions_on_threadUniqueId_storedShouldStartExpireTimer_and_expiresAt
                ON model_TSInteraction(uniqueThreadId, uniqueId)
                WHERE
                    storedShouldStartExpireTimer IS TRUE
                AND
                    (expiresAt IS 0 OR expireStartedAt IS 0)
                ;
            """)
            return .success(())
        }

        migrator.registerMigration(.addProfileBadgeDuration) { transaction in
            try transaction.database.alter(table: "model_ProfileBadgeTable") { (table: TableAlteration) -> Void in
                table.add(column: "duration", .numeric)
            }
            return .success(())
        }

        migrator.registerMigration(.addGiftBadges) { transaction in
            try transaction.database.alter(table: "model_TSInteraction") { (table: TableAlteration) -> Void in
                table.add(column: "giftBadge", .blob)
            }
            return .success(())
        }

        migrator.registerMigration(.addCanReceiveGiftBadgesToUserProfiles) { transaction in
            try transaction.database.alter(table: "model_OWSUserProfile") { (table: TableAlteration) -> Void in
                table.add(column: "canReceiveGiftBadges", .boolean).notNull().defaults(to: false)
            }
            return .success(())
        }

        migrator.registerMigration(.addStoryThreadColumns) { transaction in
            try transaction.database.alter(table: "model_TSThread") { (table: TableAlteration) -> Void in
                table.add(column: "allowsReplies", .boolean).defaults(to: false)
                table.add(column: "lastSentStoryTimestamp", .integer)
                table.add(column: "name", .text)
                table.add(column: "addresses", .blob)
                table.add(column: "storyViewMode", .integer).defaults(to: 0)
            }

            try transaction.database.create(index: "index_model_TSThread_on_storyViewMode", on: "model_TSThread", columns: ["storyViewMode", "lastSentStoryTimestamp", "allowsReplies"])
            return .success(())
        }

        migrator.registerMigration(.addUnsavedMessagesToSendToJobRecord) { transaction in
            try transaction.database.alter(table: "model_SSKJobRecord") { (table: TableAlteration) -> Void in
                table.add(column: "unsavedMessagesToSend", .blob)
            }
            return .success(())
        }

        migrator.registerMigration(.addColumnsForSendGiftBadgeDurableJob) { transaction in
            try transaction.database.alter(table: "model_SSKJobRecord") { (table: TableAlteration) -> Void in
                table.add(column: "messageText", .text)
                table.add(column: "paymentIntentClientSecret", .text)
                table.add(column: "paymentMethodId", .text)
            }
            return .success(())
        }

        migrator.registerMigration(.addDonationReceiptTypeColumn) { transaction in
            try transaction.database.alter(table: "model_DonationReceipt") { (table: TableAlteration) -> Void in
                table.add(column: "receiptType", .numeric)
            }
            return .success(())
        }

        migrator.registerMigration(.addAudioPlaybackRateColumn) { transaction in
            try transaction.database.alter(table: "thread_associated_data") { table in
                table.add(column: "audioPlaybackRate", .double)
            }
            return .success(())
        }

        migrator.registerMigration(.addSchemaVersionToAttachments) { transaction in
            try transaction.database.alter(table: "model_TSAttachment") { table in
                table.add(column: "attachmentSchemaVersion", .integer).defaults(to: 0)
            }
            return .success(())
        }

        migrator.registerMigration(.makeAudioPlaybackRateColumnNonNull) { transaction in
            // Up until when this is merged, there has been no way for users
            // to actually set an audio playback rate, so its okay to drop the column
            // just to reset the schema constraints to non-null.
            try transaction.database.alter(table: "thread_associated_data") { table in
                table.drop(column: "audioPlaybackRate")
                table.add(column: "audioPlaybackRate", .double).notNull().defaults(to: 1)
            }
            return .success(())
        }

        migrator.registerMigration(.addLastViewedStoryTimestampToTSThread) { transaction in
            try transaction.database.alter(table: "model_TSThread") { table in
                table.add(column: "lastViewedStoryTimestamp", .integer)
            }
            return .success(())
        }

        migrator.registerMigration(.convertStoryIncomingManifestStorageFormat) { transaction in
            // Nest the "incoming" state under the "receivedState" key to make
            // future migrations more future proof.
            try transaction.database.execute(sql: """
                UPDATE model_StoryMessage
                SET manifest = json_replace(
                    manifest,
                    '$.incoming',
                    json_object(
                        'receivedState',
                        json_extract(
                            manifest,
                            '$.incoming'
                        )
                    )
                )
                WHERE json_extract(manifest, '$.incoming') IS NOT NULL;
            """)
            return .success(())
        }

        migrator.registerMigration(.recreateStoryIncomingViewedTimestampIndex) { transaction in
            try transaction.database.drop(index: "index_model_StoryMessage_on_incoming_viewedTimestamp")
            try transaction.database.execute(sql: """
                CREATE
                    INDEX index_model_StoryMessage_on_incoming_receivedState_viewedTimestamp
                        ON model_StoryMessage (
                        json_extract (
                            manifest
                            ,'$.incoming.receivedState.viewedTimestamp'
                        )
                    )
                ;
            """)
            return .success(())
        }

        migrator.registerMigration(.addColumnsForLocalUserLeaveGroupDurableJob) { transaction in
            try transaction.database.alter(table: "model_SSKJobRecord") { table in
                table.add(column: "replacementAdminUuid", .text)
                table.add(column: "waitForMessageProcessing", .boolean)
            }
            return .success(())
        }

        migrator.registerMigration(.addStoriesHiddenStateToThreadAssociatedData) { transaction in
            try transaction.database.alter(table: "thread_associated_data") { table in
                table.add(column: "hideStory", .boolean).notNull().defaults(to: false)
            }
            return .success(())
        }

        migrator.registerMigration(.addUnregisteredAtTimestampToSignalRecipient) { transaction in
            try transaction.database.alter(table: "model_SignalRecipient") { table in
                table.add(column: "unregisteredAtTimestamp", .integer)
            }
            return .success(())
        }

        migrator.registerMigration(.addLastReceivedStoryTimestampToTSThread) { transaction in
            try transaction.database.alter(table: "model_TSThread") { table in
                table.add(column: "lastReceivedStoryTimestamp", .integer)
            }
            return .success(())
        }

        migrator.registerMigration(.addStoryContextAssociatedDataTable) { transaction in
            try transaction.database.create(table: StoryContextAssociatedData.databaseTableName) { table in
                table.autoIncrementedPrimaryKey(StoryContextAssociatedData.columnName(.id))
                    .notNull()
                table.column(StoryContextAssociatedData.columnName(.recordType), .integer)
                    .notNull()
                table.column(StoryContextAssociatedData.columnName(.uniqueId))
                    .notNull()
                    .unique(onConflict: .fail)
                table.column(StoryContextAssociatedData.columnName(.contactUuid), .text)
                table.column(StoryContextAssociatedData.columnName(.groupId), .blob)
                table.column(StoryContextAssociatedData.columnName(.isHidden), .boolean)
                    .notNull()
                    .defaults(to: false)
                table.column(StoryContextAssociatedData.columnName(.latestUnexpiredTimestamp), .integer)
                table.column(StoryContextAssociatedData.columnName(.lastReceivedTimestamp), .integer)
                table.column(StoryContextAssociatedData.columnName(.lastViewedTimestamp), .integer)
            }
            try transaction.database.create(
                index: "index_story_context_associated_data_contact_on_contact_uuid",
                on: StoryContextAssociatedData.databaseTableName,
                columns: [StoryContextAssociatedData.columnName(.contactUuid)]
            )
            try transaction.database.create(
                index: "index_story_context_associated_data_contact_on_group_id",
                on: StoryContextAssociatedData.databaseTableName,
                columns: [StoryContextAssociatedData.columnName(.groupId)]
            )
            return .success(())
        }

        migrator.registerMigration(.populateStoryContextAssociatedDataTableAndRemoveOldColumns) { transaction in
            // All we need to do is iterate over ThreadAssociatedData; one exists for every
            // thread, so we can pull hidden state from the associated data and received/viewed
            // timestamps from their threads and have a copy of everything we need.
            try Row.fetchCursor(transaction.database, sql: """
                SELECT * FROM thread_associated_data
            """).forEach { threadAssociatedDataRow in
                guard
                    let hideStory = (threadAssociatedDataRow["hideStory"] as? NSNumber)?.boolValue,
                    let threadUniqueId = threadAssociatedDataRow["threadUniqueId"] as? String
                else {
                    owsFailDebug("Did not find hideStory or threadUniqueId columnds on ThreadAssociatedData table")
                    return
                }
                let insertSQL = """
                INSERT INTO model_StoryContextAssociatedData (
                    recordType,
                    uniqueId,
                    contactUuid,
                    groupId,
                    isHidden,
                    latestUnexpiredTimestamp,
                    lastReceivedTimestamp,
                    lastViewedTimestamp
                )
                VALUES ('0', ?, ?, ?, ?, ?, ?, ?)
                """

                if
                    let threadRow = try? Row.fetchOne(
                        transaction.database,
                        sql: """
                            SELECT * FROM model_TSThread
                            WHERE uniqueId = ?
                        """,
                        arguments: [threadUniqueId]
                    )
                {
                    let lastReceivedStoryTimestamp = (threadRow["lastReceivedStoryTimestamp"] as? NSNumber)?.uint64Value
                    let latestUnexpiredTimestamp = (lastReceivedStoryTimestamp ?? 0) > Date().ows_millisecondsSince1970 - kDayInMs
                        ? lastReceivedStoryTimestamp : nil
                    let lastViewedStoryTimestamp = (threadRow["lastViewedStoryTimestamp"] as? NSNumber)?.uint64Value
                    if
                        let groupModelData = threadRow["groupModel"] as? Data,
                        let unarchivedObject = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(groupModelData),
                        let groupId = (unarchivedObject as? TSGroupModel)?.groupId
                    {
                        try transaction.database.execute(
                            sql: insertSQL,
                            arguments: [
                                UUID().uuidString,
                                nil,
                                groupId,
                                hideStory,
                                latestUnexpiredTimestamp,
                                lastReceivedStoryTimestamp,
                                lastViewedStoryTimestamp
                            ]
                        )
                    } else if
                        let contactUuidString = threadRow["contactUUID"] as? String
                    {
                        // Okay to ignore e164 addresses because we can't have updated story metadata
                        // for those contact threads anyway.
                        try transaction.database.execute(
                            sql: insertSQL,
                            arguments: [
                                UUID().uuidString,
                                contactUuidString,
                                nil,
                                hideStory,
                                latestUnexpiredTimestamp,
                                lastReceivedStoryTimestamp,
                                lastViewedStoryTimestamp
                            ]
                        )
                    }
                } else {
                    // If we couldn't find a thread, that means this associated data was
                    // created for a group we don't know about yet.
                    // Stories is in beta at the time of this migration, so we will just drop it.
                    Logger.info("Dropping StoryContextAssociatedData migration for ThreadAssociatedData without a TSThread")
                }

            }

            // Drop the old columns since they are no longer needed.
            try transaction.database.alter(table: "model_TSThread") { alteration in
                alteration.drop(column: "lastViewedStoryTimestamp")
                alteration.drop(column: "lastReceivedStoryTimestamp")
            }
            try transaction.database.alter(table: "thread_associated_data") { alteration in
                alteration.drop(column: "hideStory")
            }
            return .success(())
        }

        migrator.registerMigration(.addColumnForExperienceUpgradeManifest) { transaction in
            try transaction.database.alter(table: "model_ExperienceUpgrade") { table in
                table.add(column: "manifest", .blob)
            }
            return .success(())
        }

        migrator.registerMigration(.addStoryContextAssociatedDataReadTimestampColumn) { transaction in
            try transaction.database.alter(table: "model_StoryContextAssociatedData") { table in
                table.add(column: "lastReadTimestamp", .integer)
            }
            return .success(())
        }

        migrator.registerMigration(.addIsCompleteToContactSyncJob) { transaction in
            try transaction.database.alter(table: "model_SSKJobRecord") { (table: TableAlteration) -> Void in
                table.add(column: "isCompleteContactSync", .boolean).defaults(to: false)
            }
            return .success(())
        } // end: .addIsCompleteToContactSyncJob

        migrator.registerMigration(.addSnoozeCountToExperienceUpgrade) { transaction in
            try transaction.database.alter(table: "model_ExperienceUpgrade") { (table: TableAlteration) in
                table.add(column: "snoozeCount", .integer)
                    .notNull()
                    .defaults(to: 0)
            }

            let populateSql = """
                UPDATE model_ExperienceUpgrade
                SET snoozeCount = 1
                WHERE lastSnoozedTimestamp > 0
            """
            try transaction.database.execute(sql: populateSql)
            return .success(())
        }

        migrator.registerMigration(.addCancelledGroupRingsTable) { transaction in
            try transaction.database.create(table: CancelledGroupRing.databaseTableName) { table in
                table.column("id", .integer).primaryKey().notNull()
                table.column("timestamp", .integer).notNull()
            }
            return .success(())
        }

        migrator.registerMigration(.addPaymentProcessorColumnToJobRecords) { transaction in
            // Add a column to job records for "payment processor", which is
            // used by gift badge and receipt credential redemption jobs.
            //
            // Any old jobs should specify Stripe as their processor.

            try transaction.database.alter(table: "model_SSKJobRecord") { (table: TableAlteration) in
                table.add(column: "paymentProcessor", .text)
            }

            let populateSql = """
                UPDATE model_SSKJobRecord
                SET \(jobRecordColumn: .paymentProcessor) = 'STRIPE'
                WHERE \(jobRecordColumn: .recordType) = \(SDSRecordType.sendGiftBadgeJobRecord.rawValue)
                OR \(jobRecordColumn: .recordType) = \(SDSRecordType.receiptCredentialRedemptionJobRecord.rawValue)
            """
            try transaction.database.execute(sql: populateSql)

            return .success(())
        }

        migrator.registerMigration(.addCdsPreviousE164) { transaction in
            try transaction.database.create(table: "CdsPreviousE164") { table in
                table.column("id", .integer).notNull().primaryKey()
                table.column("e164", .text).notNull()
            }
            return .success(())
        } // end: .addCdsPreviousE164

        migrator.registerMigration(.addCallRecordTable) { transaction in
            /// Add the CallRecord table which from here on out is used to track when calls
            /// are accepted/declined, missed, etc, across linked devices.
            /// See `CallRecord`.
            try transaction.database.create(table: "model_CallRecord") { (table: TableDefinition) in
                table.column("id", .integer).primaryKey().notNull()
                table.column("uniqueId", .text).unique(onConflict: .fail).notNull()
                table.column("callId", .text).unique(onConflict: .ignore).notNull()
                table.column("interactionUniqueId", .text)
                    .notNull()
                    .references("model_TSInteraction", column: "uniqueId", onDelete: .cascade)
                table.column("peerUuid", .text).notNull()
                table.column("type", .integer).notNull()
                table.column("direction", .integer).notNull()
                table.column("status", .integer).notNull()
            }
            try transaction.database.create(
                index: "index_call_record_on_interaction_unique_id",
                on: "model_CallRecord",
                columns: ["interactionUniqueId"]
            )
            return .success(())
        }

        migrator.registerMigration(.addColumnsForGiftingWithPaypalToJobRecords) { transaction in
            try transaction.database.alter(table: "model_SSKJobRecord") { (table: TableAlteration) in
                table.add(column: "paypalPayerId", .text)
                table.add(column: "paypalPaymentId", .text)
                table.add(column: "paypalPaymentToken", .text)
            }
            return .success(())
        }

        migrator.registerMigration(.addSpamReportingTokenRecordTable) { transaction in
            try transaction.database.create(table: SpamReportingTokenRecord.databaseTableName) { table in
                table.column("sourceUuid").primaryKey().notNull()
                table.column("spamReportingToken", .blob).notNull()
            }
            return .success(())
        }

        migrator.registerMigration(.addVideoDuration) { transaction in
            try transaction.database.alter(table: "model_TSAttachment") { (table: TableAlteration) in
                table.add(column: "videoDuration", .double)
            }
            return .success(())
        }

        // MARK: - Schema Migration Insertion Point
    }

    private static func registerDataMigrations(migrator: DatabaseMigratorWrapper) {

        // The migration blocks should never throw. If we introduce a crashing
        // migration, we want the crash logs reflect where it occurred.

        migrator.registerMigration(.dataMigration_populateGalleryItems) { transaction in
            try createInitialGalleryRecords(transaction: transaction)
            return .success(())
        }

        migrator.registerMigration(.dataMigration_markOnboardedUsers_v2) { transaction in
            if TSAccountManager.shared.isRegistered(transaction: transaction.asAnyWrite) {
                Logger.info("marking existing user as onboarded")
                TSAccountManager.shared.setIsOnboarded(true, transaction: transaction.asAnyWrite)
            }
            return .success(())
        }

        migrator.registerMigration(.dataMigration_clearLaunchScreenCache) { _ in
            OWSFileSystem.deleteFileIfExists(NSHomeDirectory() + "/Library/SplashBoard")
            return .success(())
        }

        migrator.registerMigration(.dataMigration_enableV2RegistrationLockIfNecessary) { transaction in
            guard DependenciesBridge.shared.keyBackupService.hasMasterKey(transaction: transaction.asAnyWrite.asV2Write) else {
                return .success(())
            }

            OWS2FAManager.keyValueStore().setBool(true, key: OWS2FAManager.isRegistrationLockV2EnabledKey, transaction: transaction.asAnyWrite)
            return .success(())
        }

        migrator.registerMigration(.dataMigration_resetStorageServiceData) { transaction in
            Self.storageServiceManager.resetLocalData(transaction: transaction.asAnyWrite)
            return .success(())
        }

        migrator.registerMigration(.dataMigration_markAllInteractionsAsNotDeleted) { transaction in
            try transaction.database.execute(sql: "UPDATE model_TSInteraction SET wasRemotelyDeleted = 0")
            return .success(())
        }

        migrator.registerMigration(.dataMigration_recordMessageRequestInteractionIdEpoch) { transaction in
            // Set the epoch only if we haven't already, this lets us track and grandfather
            // conversations that existed before the message request feature was launched.
            guard SSKPreferences.messageRequestInteractionIdEpoch(transaction: transaction) == nil else {
                return .success(())
            }

            let maxId = GRDBInteractionFinder.maxRowId(transaction: transaction)
            SSKPreferences.setMessageRequestInteractionIdEpoch(maxId, transaction: transaction)
            return .success(())
        }

        migrator.registerMigration(.dataMigration_indexSignalRecipients) { transaction in
            // This migration was initially created as a schema migration instead of a data migration.
            // If we already ran it there, we need to skip it here since we're doing inserts below that
            // cannot be repeated.
            guard !hasRunMigration("indexSignalRecipients", transaction: transaction) else {
                return .success(())
            }

            SignalRecipient.anyEnumerate(transaction: transaction.asAnyWrite) { (signalRecipient: SignalRecipient, _: UnsafeMutablePointer<ObjCBool>) in
                GRDBFullTextSearchFinder.modelWasInserted(model: signalRecipient, transaction: transaction)
            }
            return .success(())
        }

        migrator.registerMigration(.dataMigration_kbsStateCleanup) { transaction in
            if DependenciesBridge.shared.keyBackupService.hasMasterKey(transaction: transaction.asAnyRead.asV2Read) {
                DependenciesBridge.shared.keyBackupService.setMasterKeyBackedUp(true, transaction: transaction.asAnyWrite.asV2Write)
            }

            guard let isUsingRandomPinKey = OWS2FAManager.keyValueStore().getBool(
                "isUsingRandomPinKey",
                transaction: transaction.asAnyRead
            ), isUsingRandomPinKey else {
                return .success(())
            }

            OWS2FAManager.keyValueStore().removeValue(forKey: "isUsingRandomPinKey", transaction: transaction.asAnyWrite)
            DependenciesBridge.shared.keyBackupService.useDeviceLocalMasterKey(transaction: transaction.asAnyWrite.asV2Write)
            return .success(())
        }

        migrator.registerMigration(.dataMigration_turnScreenSecurityOnForExistingUsers) { transaction in
            // Declare the key value store here, since it's normally only
            // available in SignalMessaging (OWSPreferences).
            let preferencesKeyValueStore = SDSKeyValueStore(collection: "SignalPreferences")
            let screenSecurityKey = "Screen Security Key"
            guard !preferencesKeyValueStore.hasValue(
                forKey: screenSecurityKey,
                transaction: transaction.asAnyRead
            ) else {
                return .success(())
            }

            preferencesKeyValueStore.setBool(true, key: screenSecurityKey, transaction: transaction.asAnyWrite)
            return .success(())
        }

        migrator.registerMigration(.dataMigration_groupIdMapping) { transaction in
            TSThread.anyEnumerate(transaction: transaction.asAnyWrite) { (thread: TSThread, _: UnsafeMutablePointer<ObjCBool>) in
                guard let groupThread = thread as? TSGroupThread else {
                    return
                }
                TSGroupThread.setGroupIdMapping(groupThread.uniqueId,
                                                forGroupId: groupThread.groupModel.groupId,
                                                transaction: transaction.asAnyWrite)
            }
            return .success(())
        }

        migrator.registerMigration(.dataMigration_disableSharingSuggestionsForExistingUsers) { transaction in
            SSKPreferences.setAreIntentDonationsEnabled(false, transaction: transaction.asAnyWrite)
            return .success(())
        }

        migrator.registerMigration(.dataMigration_removeOversizedGroupAvatars) { transaction in
            var thrownError: Error?
            TSGroupThread.anyEnumerate(transaction: transaction.asAnyWrite) { (thread: TSThread, stop: UnsafeMutablePointer<ObjCBool>) in
                guard let groupThread = thread as? TSGroupThread else { return }
                guard let avatarData = groupThread.groupModel.legacyAvatarData else { return }
                guard !TSGroupModel.isValidGroupAvatarData(avatarData) else { return }

                var builder = groupThread.groupModel.asBuilder
                builder.avatarData = nil
                builder.avatarUrlPath = nil

                do {
                    let newGroupModel = try builder.build()
                    groupThread.update(with: newGroupModel, transaction: transaction.asAnyWrite)
                } catch {
                    thrownError = error
                    stop.pointee = true
                }
            }
            return thrownError.map { .failure($0) } ?? .success(())
        }

        migrator.registerMigration(.dataMigration_scheduleStorageServiceUpdateForMutedThreads) { transaction in
            let cursor = TSThread.grdbFetchCursor(
                sql: "SELECT * FROM \(ThreadRecord.databaseTableName) WHERE \(threadColumn: .mutedUntilTimestamp) > 0",
                transaction: transaction
            )

            while let thread = try cursor.next() {
                if let thread = thread as? TSContactThread {
                    Self.storageServiceManager.recordPendingUpdates(updatedAddresses: [thread.contactAddress])
                } else if let thread = thread as? TSGroupThread {
                    Self.storageServiceManager.recordPendingUpdates(groupModel: thread.groupModel)
                } else {
                    owsFail("Unexpected thread type \(thread)")
                }
            }
            return .success(())
        }

        migrator.registerMigration(.dataMigration_populateGroupMember) { transaction in
            let cursor = TSThread.grdbFetchCursor(
                sql: "SELECT * FROM \(ThreadRecord.databaseTableName) WHERE \(threadColumn: .recordType) = \(SDSRecordType.groupThread.rawValue)",
                transaction: transaction
            )

            while let thread = try cursor.next() {
                guard let groupThread = thread as? TSGroupThread else {
                    owsFail("Unexpected thread type \(thread)")
                }
                let interactionFinder = InteractionFinder(threadUniqueId: groupThread.uniqueId)
                groupThread.groupMembership.fullMembers.forEach { address in
                    // Group member addresses are low-trust, and the address cache has
                    // not been populated yet at this point in time. We want to record
                    // as close to a fully qualified address as we can in the database,
                    // so defer to the address from the signal recipient (if one exists)
                    let recipient = GRDBSignalRecipientFinder().signalRecipient(for: address, transaction: transaction)
                    let memberAddress = recipient?.address ?? address

                    let latestInteraction = interactionFinder.latestInteraction(from: memberAddress, transaction: transaction.asAnyWrite)
                    let memberRecord = TSGroupMember(
                        address: memberAddress,
                        groupThreadId: groupThread.uniqueId,
                        lastInteractionTimestamp: latestInteraction?.timestamp ?? 0
                    )
                    memberRecord.anyInsert(transaction: transaction.asAnyWrite)
                }
            }
            return .success(())
        }

        migrator.registerMigration(.dataMigration_cullInvalidIdentityKeySendingErrors) { transaction in
            let sql = """
                DELETE FROM \(InteractionRecord.databaseTableName)
                WHERE \(interactionColumn: .recordType) = ?
            """
            transaction.execute(
                sql: sql,
                arguments: [SDSRecordType.invalidIdentityKeySendingErrorMessage.rawValue]
            )
            return .success(())
        }

        migrator.registerMigration(.dataMigration_moveToThreadAssociatedData) { transaction in
            var thrownError: Error?
            TSThread.anyEnumerate(transaction: transaction.asAnyWrite) { (thread, stop: UnsafeMutablePointer<ObjCBool>) in
                do {
                    try ThreadAssociatedData(
                        threadUniqueId: thread.uniqueId,
                        isArchived: thread.isArchivedObsolete,
                        isMarkedUnread: thread.isMarkedUnreadObsolete,
                        mutedUntilTimestamp: thread.mutedUntilTimestampObsolete,
                        // this didn't exist pre-migration, just write the default
                        audioPlaybackRate: 1
                    ).insert(transaction.database)
                } catch {
                    thrownError = error
                    stop.pointee = true
                }
            }
            return thrownError.map { .failure($0) } ?? .success(())
        }

        migrator.registerMigration(.dataMigration_senderKeyStoreKeyIdMigration) { transaction in
            SenderKeyStore.performKeyIdMigration(transaction: transaction.asAnyWrite)
            return .success(())
        }

        migrator.registerMigration(.dataMigration_reindexGroupMembershipAndMigrateLegacyAvatarDataFixed) { transaction in
            let threadCursor = TSThread.grdbFetchCursor(
                sql: "SELECT * FROM \(ThreadRecord.databaseTableName) WHERE \(threadColumn: .recordType) = \(SDSRecordType.groupThread.rawValue)",
                transaction: transaction
            )

            while let thread = try threadCursor.next() as? TSGroupThread {
                try autoreleasepool {
                    try thread.groupModel.attemptToMigrateLegacyAvatarDataToDisk()
                    thread.anyUpsert(transaction: transaction.asAnyWrite)
                    GRDBFullTextSearchFinder.modelWasUpdated(model: thread, transaction: transaction)
                }
            }

            // There was a broken version of this migration that did not persist the avatar migration. It's now fixed, but for
            // users who ran it we need to skip the re-index of the group members because we can't perform a second "insert"
            // query. This is superfluous anyways, so it's safe to skip.
            guard !hasRunMigration("dataMigration_reindexGroupMembershipAndMigrateLegacyAvatarData", transaction: transaction) else {
                return .success(())
            }

            let memberCursor = try TSGroupMember.fetchCursor(transaction.database)

            while let member = try memberCursor.next() {
                autoreleasepool {
                    GRDBFullTextSearchFinder.modelWasInsertedOrUpdated(model: member, transaction: transaction)
                }
            }
            return .success(())
        }

        migrator.registerMigration(.dataMigration_repairAvatar) { transaction in
            // Declare the key value store here, since it's normally only
            // available in SignalMessaging (OWSPreferences).
            let preferencesKeyValueStore = SDSKeyValueStore(collection: Self.migrationSideEffectsCollectionName)
            let key = Self.avatarRepairAttemptCount
            preferencesKeyValueStore.setInt(0, key: key, transaction: transaction.asAnyWrite)
            return .success(())
        }

        migrator.registerMigration(.dataMigration_dropEmojiAvailabilityStore) { transaction in
            // This is a bit of a layering violation, since these tables were previously managed in the app layer.
            // In the long run we'll have a general "unused SDSKeyValueStore cleaner" migration,
            // but for now this should drop 2000 or so rows for free.
            SDSKeyValueStore(collection: "Emoji+availableStore").removeAll(transaction: transaction.asAnyWrite)
            SDSKeyValueStore(collection: "Emoji+metadataStore").removeAll(transaction: transaction.asAnyWrite)
            return .success(())
        }

        migrator.registerMigration(.dataMigration_dropSentStories) { transaction in
            let sql = """
                DELETE FROM \(StoryMessage.databaseTableName)
                WHERE \(StoryMessage.columnName(.direction)) = \(StoryMessage.Direction.outgoing.rawValue)
            """
            try transaction.database.execute(sql: sql)
            return .success(())
        }

        migrator.registerMigration(.dataMigration_indexMultipleNameComponentsForReceipients) { transaction in
            // We updated how we generate text for the search index for a
            // recipient, and consequently should touch all recipients so that
            // we regenerate the index text.

            SignalRecipient.anyEnumerate(transaction: transaction.asAnyWrite) { (signalRecipient: SignalRecipient, _: UnsafeMutablePointer<ObjCBool>) in
                GRDBFullTextSearchFinder.modelWasUpdated(model: signalRecipient, transaction: transaction)
            }
            return .success(())
        }

        migrator.registerMigration(.dataMigration_syncGroupStories) { transaction in
            for thread in AnyThreadFinder().storyThreads(includeImplicitGroupThreads: false, transaction: transaction.asAnyRead) {
                guard let thread = thread as? TSGroupThread else { continue }
                self.storageServiceManager.recordPendingUpdates(groupModel: thread.groupModel)
            }
            return .success(())
        }

        migrator.registerMigration(.dataMigration_deleteOldGroupCapabilities) { transaction in
            let sql = """
                DELETE FROM \(SDSKeyValueStore.tableName)
                WHERE \(SDSKeyValueStore.collectionColumn.columnName)
                IN ("GroupManager.senderKeyCapability", "GroupManager.announcementOnlyGroupsCapability", "GroupManager.groupsV2MigrationCapability")
            """
            try transaction.database.execute(sql: sql)
            return .success(())
        }

        migrator.registerMigration(.dataMigration_updateStoriesDisabledInAccountRecord) { transaction in
            storageServiceManager.recordPendingLocalAccountUpdates()
            return .success(())
        }

        migrator.registerMigration(.dataMigration_removeGroupStoryRepliesFromSearchIndex) { transaction in
            let uniqueIdSql = """
                SELECT \(interactionColumn: .uniqueId)
                FROM \(InteractionRecord.databaseTableName)
                WHERE \(interactionColumn: .isGroupStoryReply) = 1
            """
            let uniqueIds = try String.fetchAll(transaction.database, sql: uniqueIdSql)

            guard !uniqueIds.isEmpty else {
                return .success(())
            }

            let indexUpdateSql = """
                DELETE FROM \(GRDBFullTextSearchFinder.contentTableName)
                WHERE \(GRDBFullTextSearchFinder.uniqueIdColumn) IN (\(uniqueIds.map { "\"\($0)\"" }.joined(separator: ", ")))
                AND \(GRDBFullTextSearchFinder.collectionColumn) = "\(TSInteraction.collection())"
            """
            try transaction.database.execute(sql: indexUpdateSql)
            return .success(())
        }

        migrator.registerMigration(.dataMigration_populateStoryContextAssociatedDataLastReadTimestamp) { transaction in
            let sql = """
                UPDATE model_StoryContextAssociatedData
                SET lastReadTimestamp = lastViewedTimestamp
            """
            try transaction.database.execute(sql: sql)
            return .success(())
        }

        migrator.registerMigration(.dataMigration_indexPrivateStoryThreadNames) { transaction in
            let sql = "SELECT * FROM model_TSThread WHERE recordType IS \(SDSRecordType.privateStoryThread.rawValue)"
            let cursor = TSThread.grdbFetchCursor(sql: sql, transaction: transaction)
            while let thread = try cursor.next() {
                guard let storyThread = thread as? TSPrivateStoryThread else {
                    continue
                }
                let uniqueId = thread.uniqueId
                let collection = TSPrivateStoryThread.collection()
                let ftsContent = FullTextSearchFinder.normalize(text: storyThread.name)

                let sql = """
                INSERT OR REPLACE INTO indexable_text
                (collection, uniqueId, ftsIndexableContent)
                VALUES
                (?, ?, ?)
                """

                try transaction.database.execute(
                    sql: sql,
                    arguments: [collection, uniqueId, ftsContent]
                )
            }
            return .success(())
        }

        migrator.registerMigration(.dataMigration_scheduleStorageServiceUpdateForSystemContacts) { transaction in
            // We've added fields on the StorageService ContactRecord proto for
            // their "system name", or the name of their associated system
            // contact, if present. Consequently, for all Signal contacts with
            // a system contact, we should schedule a StorageService update.
            //
            // We only want to do this if we are the primary device, since only
            // the primary device's system contacts are synced.

            guard tsAccountManager.isPrimaryDevice else {
                return .success(())
            }

            var accountsToRemove: Set<SignalAccount> = []

            SignalAccount.anyEnumerate(transaction: transaction.asAnyRead) { account, _ in
                guard
                    let contact = account.contact,
                    contact.isFromLocalAddressBook
                else {
                    // Skip any accounts that do not have a system contact
                    return
                }

                accountsToRemove.insert(account)
            }

            storageServiceManager.recordPendingUpdates(updatedAddresses: accountsToRemove.map { $0.recipientAddress })
            return .success(())
        }

        if FeatureFlags.contactDiscoveryV2 {
            migrator.registerMigration(.dataMigration_removeLinkedDeviceSystemContacts) { transaction in
                guard !tsAccountManager.isPrimaryDevice else {
                    return .success(())
                }

                let keyValueCollections = [
                    "ContactsManagerCache.uniqueIdStore",
                    "ContactsManagerCache.phoneNumberStore",
                    "ContactsManagerCache.allContacts"
                ]

                for collection in keyValueCollections {
                    SDSKeyValueStore(collection: collection).removeAll(transaction: transaction.asAnyWrite)
                }

                return .success(())
            }
        }

        // MARK: - Data Migration Insertion Point
    }
}

public func createInitialGalleryRecords(transaction: GRDBWriteTransaction) throws {
    try Bench(title: "createInitialGalleryRecords", logInProduction: true) {
        try MediaGalleryRecord.deleteAll(transaction.database)
        let scope = AttachmentRecord.filter(sql: "\(attachmentColumn: .recordType) = \(SDSRecordType.attachmentStream.rawValue)")

        let totalCount = try scope.fetchCount(transaction.database)
        let cursor = try scope.fetchCursor(transaction.database)
        var i = 0
        try Batching.loop(batchSize: 500) { stopPtr in
            guard let record = try cursor.next() else {
                stopPtr.pointee = true
                return
            }

            i+=1
            if (i % 100) == 0 {
                Logger.info("migrated \(i) / \(totalCount)")
            }

            guard let attachmentStream = try TSAttachment.fromRecord(record) as? TSAttachmentStream else {
                owsFailDebug("unexpected record: \(record.recordType)")
                return
            }

            try MediaGalleryManager.insertGalleryRecord(attachmentStream: attachmentStream, transaction: transaction)
        }
    }
}

public func dedupeSignalRecipients(transaction: SDSAnyWriteTransaction) throws {
    BenchEventStart(title: "Deduping Signal Recipients", eventId: "dedupeSignalRecipients")
    defer { BenchEventComplete(eventId: "dedupeSignalRecipients") }

    var recipients: [SignalServiceAddress: [String]] = [:]

    SignalRecipient.anyEnumerate(transaction: transaction) { (recipient, _) in
        if let existing = recipients[recipient.address] {
            recipients[recipient.address] = existing + [recipient.uniqueId]
        } else {
            recipients[recipient.address] = [recipient.uniqueId]
        }
    }

    var duplicatedRecipients: [SignalServiceAddress: [String]] = [:]
    for (address, recipients) in recipients {
        if recipients.count > 1 {
            duplicatedRecipients[address] = recipients
        }
    }

    guard duplicatedRecipients.count > 0 else {
        Logger.info("No duplicated recipients")
        return
    }

    for (address, recipientIds) in duplicatedRecipients {
        // Since we have duplicate recipients for an address, we want to keep the one returned by the
        // finder, since that is the one whose uniqueId is used as the `accountId` for the
        // accountId finder.
        guard let primaryRecipient = SignalRecipient.get(
            address: address,
            mustHaveDevices: false,
            transaction: transaction
        ) else {
            owsFailDebug("primaryRecipient was unexpectedly nil")
            continue
        }

        let redundantRecipientIds = recipientIds.filter { $0 != primaryRecipient.uniqueId }
        for redundantId in redundantRecipientIds {
            guard let redundantRecipient = SignalRecipient.anyFetch(uniqueId: redundantId, transaction: transaction) else {
                owsFailDebug("redundantRecipient was unexpectedly nil")
                continue
            }
            Logger.info("removing redundant recipient: \(redundantRecipient)")
            redundantRecipient.anyRemove(transaction: transaction)
        }
    }
}

private func hasRunMigration(_ identifier: String, transaction: GRDBReadTransaction) -> Bool {
    do {
        return try String.fetchOne(transaction.database, sql: "SELECT identifier FROM grdb_migrations WHERE identifier = ?", arguments: [identifier]) != nil
    } catch {
        owsFail("Error: \(error)")
    }
}

private func insertMigration(_ identifier: String, db: Database) {
    do {
        try db.execute(sql: "INSERT INTO grdb_migrations (identifier) VALUES (?)", arguments: [identifier])
    } catch {
        owsFail("Error: \(error)")
    }
}
