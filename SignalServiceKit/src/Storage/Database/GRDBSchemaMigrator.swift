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

        if hasCreatedInitialSchema(grdbStorageAdapter: grdbStorageAdapter) {
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

    private static func hasCreatedInitialSchema(grdbStorageAdapter: GRDBDatabaseStorageAdapter) -> Bool {
        let appliedMigrations = try! grdbStorageAdapter.read { transaction in
            try! DatabaseMigrator().appliedIdentifiers(transaction.database)
        }
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
    }

    public static let grdbSchemaVersionDefault: UInt = 0
    public static let grdbSchemaVersionLatest: UInt = 51

    // An optimization for new users, we have the first migration import the latest schema
    // and mark any other migrations as "already run".
    private static func newUserMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration(MigrationId.createInitialSchema.rawValue) { db in
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

        func registerMigration(_ identifier: MigrationId, migrate: @escaping (Database) -> Void) {
            // Run with immediate foreign key checks so that pre-existing dangling rows
            // don't cause unrelated migrations to fail. We also don't perform schema
            // alterations that would necessitate disabling foreign key checks.
            migrator.registerMigration(identifier.rawValue, foreignKeyChecks: .immediate) { (database: Database) in
                let startTime = CACurrentMediaTime()
                Logger.info("Running migration: \(identifier)")
                migrate(database)
                let timeElapsed = CACurrentMediaTime() - startTime
                let formattedTime = String(format: "%0.2fms", timeElapsed * 1000)
                Logger.info("Migration completed: \(identifier), duration: \(formattedTime)")
            }
        }

        func migrate(_ database: DatabaseWriter) throws {
            try migrator.migrate(database)
        }
    }

    private static func registerSchemaMigrations(migrator: DatabaseMigratorWrapper) {

        // The migration blocks should never throw. If we introduce a crashing
        // migration, we want the crash logs reflect where it occurred.

        migrator.registerMigration(.createInitialSchema) { _ in
            owsFail("This migration should have already been run by the last YapDB migration.")
        }

        migrator.registerMigration(.signalAccount_add_contactAvatars) { database in
            do {
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
                try database.execute(sql: sql)
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.signalAccount_add_contactAvatars_indices) { db in
            do {
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
                try db.execute(sql: sql)
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.jobRecords_add_attachmentId) { db in
            do {
                try db.alter(table: "model_SSKJobRecord") { (table: TableAlteration) -> Void in
                    table.add(column: "attachmentId", .text)
                }
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.createMediaGalleryItems) { db in
            do {
                try db.create(table: "media_gallery_items") { table in
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

                try db.create(index: "index_media_gallery_items_for_gallery",
                              on: "media_gallery_items",
                              columns: ["threadId", "albumMessageId", "originalAlbumOrder"])

                try db.create(index: "index_media_gallery_items_on_attachmentId",
                              on: "media_gallery_items",
                              columns: ["attachmentId"])

                // Creating gallery records here can crash since it's run in the middle of schema migrations.
                // It instead has been moved to a separate Data Migration.
                // see: "dataMigration_populateGalleryItems"
                // try createInitialGalleryRecords(transaction: GRDBWriteTransaction(database: db))
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.createReaction) { db in
            do {
                try db.create(table: "model_OWSReaction") { table in
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
                try db.create(index: "index_model_OWSReaction_on_uniqueId",
                              on: "model_OWSReaction",
                              columns: ["uniqueId"])
                try db.create(index: "index_model_OWSReaction_on_uniqueMessageId_and_reactorE164",
                              on: "model_OWSReaction",
                              columns: ["uniqueMessageId", "reactorE164"])
                try db.create(index: "index_model_OWSReaction_on_uniqueMessageId_and_reactorUUID",
                              on: "model_OWSReaction",
                              columns: ["uniqueMessageId", "reactorUUID"])
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.dedupeSignalRecipients) { db in
            do {
                try autoreleasepool {
                    let transaction = GRDBWriteTransaction(database: db)
                    defer { transaction.finalizeTransaction() }

                    try dedupeSignalRecipients(transaction: transaction.asAnyWrite)
                }

                try db.drop(index: "index_signal_recipients_on_recipientPhoneNumber")
                try db.drop(index: "index_signal_recipients_on_recipientUUID")

                try db.create(index: "index_signal_recipients_on_recipientPhoneNumber",
                              on: "model_SignalRecipient",
                              columns: ["recipientPhoneNumber"],
                              unique: true)

                try db.create(index: "index_signal_recipients_on_recipientUUID",
                              on: "model_SignalRecipient",
                              columns: ["recipientUUID"],
                              unique: true)
            } catch {
                owsFail("Error: \(error)")
            }
        }

        // Creating gallery records here can crash since it's run in the middle of schema migrations.
        // It instead has been moved to a separate Data Migration.
        // see: "dataMigration_populateGalleryItems"
        // migrator.registerMigration(.indexMediaGallery2) { db in
        //     // re-index the media gallery for those who failed to create during the initial YDB migration
        //     try createInitialGalleryRecords(transaction: GRDBWriteTransaction(database: db))
        // }

        migrator.registerMigration(.unreadThreadInteractions) { db in
            do {
                try db.create(index: "index_interactions_on_threadId_read_and_id",
                              on: "model_TSInteraction",
                              columns: ["uniqueThreadId", "read", "id"],
                              unique: true)
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.createFamilyName) { db in
            do {
                try db.alter(table: "model_OWSUserProfile", body: { alteration in
                    alteration.add(column: "familyName", .text)
                })
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.createIndexableFTSTable) { db in
            do {
                try Bench(title: MigrationId.createIndexableFTSTable.rawValue, logInProduction: true) {
                    try db.create(table: "indexable_text") { table in
                        table.autoIncrementedPrimaryKey("id")
                            .notNull()
                        table.column("collection", .text)
                            .notNull()
                        table.column("uniqueId", .text)
                            .notNull()
                        table.column("ftsIndexableContent", .text)
                            .notNull()
                    }

                    try db.create(index: "index_indexable_text_on_collection_and_uniqueId",
                                  on: "indexable_text",
                                  columns: ["collection", "uniqueId"],
                                  unique: true)

                    try db.create(virtualTable: "indexable_text_fts", using: FTS5()) { table in
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
                    try db.execute(sql: "INSERT INTO indexable_text (collection, uniqueId, ftsIndexableContent) SELECT collection, uniqueId, ftsIndexableContent FROM signal_grdb_fts")
                    try db.drop(table: "signal_grdb_fts")
                }
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.dropContactQuery) { db in
            do {
                try db.drop(table: "model_OWSContactQuery")
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.indexFailedJob) { db in
            do {
                // index this query:
                //      SELECT \(interactionColumn: .uniqueId)
                //      FROM \(InteractionRecord.databaseTableName)
                //      WHERE \(interactionColumn: .storedMessageState) = ?
                try db.create(index: "index_interaction_on_storedMessageState",
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
                try db.create(index: "index_interaction_on_recordType_and_callType",
                              on: "model_TSInteraction",
                              columns: ["recordType", "callType"])
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.groupsV2MessageJobs) { db in
            do {
                try db.create(table: "model_IncomingGroupsV2MessageJob") { table in
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
                try db.create(index: "index_model_IncomingGroupsV2MessageJob_on_uniqueId", on: "model_IncomingGroupsV2MessageJob", columns: ["uniqueId"])
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.addUserInfoToInteractions) { db in
            do {
                try db.alter(table: "model_TSInteraction") { (table: TableAlteration) -> Void in
                    table.add(column: "infoMessageUserInfo", .blob)
                }
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.recreateExperienceUpgradeWithNewColumns) { db in
            do {
                // It's safe to just throw away old experience upgrade data since
                // there are no campaigns actively running that we need to preserve
                try db.drop(table: "model_ExperienceUpgrade")
                try db.create(table: "model_ExperienceUpgrade", body: { table in
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
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.recreateExperienceUpgradeIndex) { db in
            do {
                try db.create(index: "index_model_ExperienceUpgrade_on_uniqueId", on: "model_ExperienceUpgrade", columns: ["uniqueId"])
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.indexInfoMessageOnType_v2) { db in
            do {
                // cleanup typo in index name that was released to a small number of internal testflight users
                try db.execute(sql: "DROP INDEX IF EXISTS index_model_TSInteraction_on_threadUniqueId_recordType_messagType")

                try db.create(index: "index_model_TSInteraction_on_threadUniqueId_recordType_messageType",
                              on: "model_TSInteraction",
                              columns: ["threadUniqueId", "recordType", "messageType"])
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.createPendingReadReceipts) { db in
            do {
                try db.create(table: "pending_read_receipts") { table in
                    table.autoIncrementedPrimaryKey("id")
                    table.column("threadId", .integer).notNull()
                    table.column("messageTimestamp", .integer).notNull()
                    table.column("authorPhoneNumber", .text)
                    table.column("authorUuid", .text)
                }
                try db.create(index: "index_pending_read_receipts_on_threadId",
                              on: "pending_read_receipts",
                              columns: ["threadId"])
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.createInteractionAttachmentIdsIndex) { db in
            do {
                try db.create(index: "index_model_TSInteraction_on_threadUniqueId_and_attachmentIds",
                              on: "model_TSInteraction",
                              columns: ["threadUniqueId", "attachmentIds"])
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.addIsUuidCapableToUserProfiles) { db in
            do {
                try db.alter(table: "model_OWSUserProfile") { (table: TableAlteration) -> Void in
                    table.add(column: "isUuidCapable", .boolean).notNull().defaults(to: false)
                }
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.uploadTimestamp) { db in
            do {
                try db.alter(table: "model_TSAttachment") { (table: TableAlteration) -> Void in
                    table.add(column: "uploadTimestamp", .integer).notNull().defaults(to: 0)
                }
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.addRemoteDeleteToInteractions) { db in
            do {
                try db.alter(table: "model_TSInteraction") { (table: TableAlteration) -> Void in
                    table.add(column: "wasRemotelyDeleted", .boolean)
                }
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.cdnKeyAndCdnNumber) { db in
            do {
                try db.alter(table: "model_TSAttachment") { (table: TableAlteration) -> Void in
                    table.add(column: "cdnKey", .text).notNull().defaults(to: "")
                    table.add(column: "cdnNumber", .integer).notNull().defaults(to: 0)
                }
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.addGroupIdToGroupsV2IncomingMessageJobs) { db in
            do {
                try db.alter(table: "model_IncomingGroupsV2MessageJob") { (table: TableAlteration) -> Void in
                    table.add(column: "groupId", .blob)
                }
                try db.create(index: "index_model_IncomingGroupsV2MessageJob_on_groupId_and_id",
                              on: "model_IncomingGroupsV2MessageJob",
                              columns: ["groupId", "id"])
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.removeEarlyReceiptTables) { db in
            do {
                try db.drop(table: "model_TSRecipientReadReceipt")
                try db.drop(table: "model_OWSLinkedDeviceReadReceipt")

                let transaction = GRDBWriteTransaction(database: db)
                defer { transaction.finalizeTransaction() }

                let viewOnceStore = SDSKeyValueStore(collection: "viewOnceMessages")
                viewOnceStore.removeAll(transaction: transaction.asAnyWrite)
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.addReadToReactions) { db in
            do {
                try db.alter(table: "model_OWSReaction") { (table: TableAlteration) -> Void in
                    table.add(column: "read", .boolean).notNull().defaults(to: false)
                }

                try db.create(index: "index_model_OWSReaction_on_uniqueMessageId_and_read",
                              on: "model_OWSReaction",
                              columns: ["uniqueMessageId", "read"])

                // Mark existing reactions as read
                try db.execute(sql: "UPDATE model_OWSReaction SET read = 1")
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.addIsMarkedUnreadToThreads) { db in
            do {
                try db.alter(table: "model_TSThread") { (table: TableAlteration) -> Void in
                    table.add(column: "isMarkedUnread", .boolean).notNull().defaults(to: false)
                }
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.addIsMediaMessageToMessageSenderJobQueue) { db in
            do {
                try db.alter(table: "model_SSKJobRecord") { (table: TableAlteration) -> Void in
                    table.add(column: "isMediaMessage", .boolean)
                }

                try db.drop(index: "index_model_TSAttachment_on_uniqueId")

                try db.create(
                    index: "index_model_TSAttachment_on_uniqueId_and_contentType",
                    on: "model_TSAttachment",
                    columns: ["uniqueId", "contentType"]
                )
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.readdAttachmentIndex) { db in
            do {
                try db.create(
                    index: "index_model_TSAttachment_on_uniqueId",
                    on: "model_TSAttachment",
                    columns: ["uniqueId"]
                )

                try db.execute(sql: "UPDATE model_SSKJobRecord SET isMediaMessage = 0")
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.addLastVisibleRowIdToThreads) { db in
            do {
                try db.alter(table: "model_TSThread") { (table: TableAlteration) -> Void in
                    table.add(column: "lastVisibleSortIdOnScreenPercentage", .double).notNull().defaults(to: 0)
                    table.add(column: "lastVisibleSortId", .integer).notNull().defaults(to: 0)
                }
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.addMarkedUnreadIndexToThread) { db in
            do {
                try db.create(
                    index: "index_model_TSThread_on_isMarkedUnread",
                    on: "model_TSThread",
                    columns: ["isMarkedUnread"]
                )
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.fixIncorrectIndexes) { db in
            do {
                try db.drop(index: "index_model_TSInteraction_on_threadUniqueId_recordType_messageType")
                try db.create(index: "index_model_TSInteraction_on_uniqueThreadId_recordType_messageType",
                              on: "model_TSInteraction",
                              columns: ["uniqueThreadId", "recordType", "messageType"])

                try db.drop(index: "index_model_TSInteraction_on_threadUniqueId_and_attachmentIds")
                try db.create(index: "index_model_TSInteraction_on_uniqueThreadId_and_attachmentIds",
                              on: "model_TSInteraction",
                              columns: ["uniqueThreadId", "attachmentIds"])

            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.resetThreadVisibility) { db in
            do {
                try db.execute(sql: "UPDATE model_TSThread SET lastVisibleSortIdOnScreenPercentage = 0, lastVisibleSortId = 0")
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.trackUserProfileFetches) { db in
            do {
                try db.alter(table: "model_OWSUserProfile") { (table: TableAlteration) -> Void in
                    table.add(column: "lastFetchDate", .double)
                    table.add(column: "lastMessagingDate", .double)
                }
                try db.create(index: "index_model_OWSUserProfile_on_lastFetchDate_and_lastMessagingDate",
                              on: "model_OWSUserProfile",
                              columns: ["lastFetchDate", "lastMessagingDate"])
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.addMentions) { db in
            do {
                try db.create(table: "model_TSMention") { table in
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
                try db.create(index: "index_model_TSMention_on_uniqueId",
                              on: "model_TSMention",
                              columns: ["uniqueId"])
                try db.create(index: "index_model_TSMention_on_uuidString_and_uniqueThreadId",
                              on: "model_TSMention",
                              columns: ["uuidString", "uniqueThreadId"])
                try db.create(index: "index_model_TSMention_on_uniqueMessageId_and_uuidString",
                              on: "model_TSMention",
                              columns: ["uniqueMessageId", "uuidString"],
                              unique: true)

                try db.alter(table: "model_TSThread") { (table: TableAlteration) -> Void in
                    table.add(column: "messageDraftBodyRanges", .blob)
                }

                try db.alter(table: "model_TSInteraction") { (table: TableAlteration) -> Void in
                    table.add(column: "bodyRanges", .blob)
                }
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.addMentionNotificationMode) { db in
            do {
                try db.alter(table: "model_TSThread") { (table: TableAlteration) -> Void in
                    table.add(column: "mentionNotificationMode", .integer)
                        .notNull()
                        .defaults(to: 0)
                }
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.addOfferTypeToCalls) { db in
            do {
                try db.alter(table: "model_TSInteraction") { (table: TableAlteration) -> Void in
                    table.add(column: "offerType", .integer)
                }

                // Backfill all existing calls as "audio" calls.
                try db.execute(sql: "UPDATE model_TSInteraction SET offerType = 0 WHERE recordType IS \(SDSRecordType.call.rawValue)")
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.addServerDeliveryTimestamp) { db in
            do {
                try db.alter(table: "model_IncomingGroupsV2MessageJob") { (table: TableAlteration) -> Void in
                    table.add(column: "serverDeliveryTimestamp", .integer).notNull().defaults(to: 0)
                }

                try db.alter(table: "model_OWSMessageContentJob") { (table: TableAlteration) -> Void in
                    table.add(column: "serverDeliveryTimestamp", .integer).notNull().defaults(to: 0)
                }

                try db.alter(table: "model_SSKJobRecord") { (table: TableAlteration) -> Void in
                    table.add(column: "serverDeliveryTimestamp", .integer)
                }

                try db.alter(table: "model_TSInteraction") { (table: TableAlteration) -> Void in
                    table.add(column: "serverDeliveryTimestamp", .integer)
                }

                // Backfill all incoming messages with "0" as their timestamp
                try db.execute(sql: "UPDATE model_TSInteraction SET serverDeliveryTimestamp = 0 WHERE recordType IS \(SDSRecordType.incomingMessage.rawValue)")

                // Backfill all jobs with "0" as their timestamp
                try db.execute(sql: "UPDATE model_SSKJobRecord SET serverDeliveryTimestamp = 0 WHERE recordType IS \(SDSRecordType.messageDecryptJobRecord.rawValue)")
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.updateAnimatedStickers) { db in
            do {
                try db.alter(table: "model_TSAttachment") { (table: TableAlteration) -> Void in
                    table.add(column: "isAnimatedCached", .integer)
                }
                try db.alter(table: "model_InstalledSticker") { (table: TableAlteration) -> Void in
                    table.add(column: "contentType", .text)
                }
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.updateMarkedUnreadIndex) { db in
            do {
                try db.drop(index: "index_model_TSThread_on_isMarkedUnread")
                try db.create(
                    index: "index_model_TSThread_on_isMarkedUnread_and_shouldThreadBeVisible",
                    on: "model_TSThread",
                    columns: ["isMarkedUnread", "shouldThreadBeVisible"]
                )
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.addGroupCallMessage2) { db in
            do {
                try db.alter(table: "model_TSInteraction") { table in
                    table.add(column: "eraId", .text)
                    table.add(column: "hasEnded", .boolean)
                    table.add(column: "creatorUuid", .text)
                    table.add(column: "joinedMemberUuids", .blob)
                }

                try db.create(
                    index: "index_model_TSInteraction_on_uniqueThreadId_and_hasEnded_and_recordType",
                    on: "model_TSInteraction",
                    columns: ["uniqueThreadId", "hasEnded", "recordType"]
                )
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.addGroupCallEraIdIndex) { db in
            do {
                try db.create(
                    index: "index_model_TSInteraction_on_uniqueThreadId_and_eraId_and_recordType",
                    on: "model_TSInteraction",
                    columns: ["uniqueThreadId", "eraId", "recordType"]
                )
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.addProfileBio) { db in
            do {
                try db.alter(table: "model_OWSUserProfile") { table in
                    table.add(column: "bio", .text)
                    table.add(column: "bioEmoji", .text)
                }
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.addWasIdentityVerified) { db in
            do {
                try db.alter(table: "model_TSInteraction") { table in
                    table.add(column: "wasIdentityVerified", .boolean)
                }

                try db.execute(sql: "UPDATE model_TSInteraction SET wasIdentityVerified = 0")
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.storeMutedUntilDateAsMillisecondTimestamp) { db in
            do {
                try db.alter(table: "model_TSThread") { table in
                    table.add(column: "mutedUntilTimestamp", .integer).notNull().defaults(to: 0)
                }

                // Convert any existing mutedUntilDate (seconds) into mutedUntilTimestamp (milliseconds)
                try db.execute(sql: "UPDATE model_TSThread SET mutedUntilTimestamp = CAST(mutedUntilDate * 1000 AS INT) WHERE mutedUntilDate IS NOT NULL")
                try db.execute(sql: "UPDATE model_TSThread SET mutedUntilDate = NULL")
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.addPaymentModels15) { db in
            do {
                try db.alter(table: "model_TSInteraction") { (table: TableAlteration) -> Void in
                    table.add(column: "paymentCancellation", .blob)
                    table.add(column: "paymentNotification", .blob)
                    table.add(column: "paymentRequest", .blob)
                }
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.addPaymentModels40) { db in
            do {
                // PAYMENTS TODO: Remove.
                try db.execute(sql: "DROP TABLE IF EXISTS model_TSPaymentModel")
                try db.execute(sql: "DROP TABLE IF EXISTS model_TSPaymentRequestModel")

                try db.create(table: "model_TSPaymentModel") { table in
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

                try db.create(index: "index_model_TSPaymentModel_on_uniqueId", on: "model_TSPaymentModel", columns: ["uniqueId"])
                try db.create(index: "index_model_TSPaymentModel_on_paymentState", on: "model_TSPaymentModel", columns: ["paymentState"])
                try db.create(index: "index_model_TSPaymentModel_on_mcLedgerBlockIndex", on: "model_TSPaymentModel", columns: ["mcLedgerBlockIndex"])
                try db.create(index: "index_model_TSPaymentModel_on_mcReceiptData", on: "model_TSPaymentModel", columns: ["mcReceiptData"])
                try db.create(index: "index_model_TSPaymentModel_on_mcTransactionData", on: "model_TSPaymentModel", columns: ["mcTransactionData"])
                try db.create(index: "index_model_TSPaymentModel_on_isUnread", on: "model_TSPaymentModel", columns: ["isUnread"])
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.fixPaymentModels) { db in
            // We released a build with an out-of-date schema that didn't reflect
            // `addPaymentModels15`. To fix this, we need to run the column adds
            // again to get all users in a consistent state. We can safely skip
            // this migration if it fails.
            do {
                try db.alter(table: "model_TSInteraction") { (table: TableAlteration) -> Void in
                    table.add(column: "paymentCancellation", .blob)
                    table.add(column: "paymentNotification", .blob)
                    table.add(column: "paymentRequest", .blob)
                }
            } catch {
                // We can safely skip this if it fails.
                Logger.info("Skipping re-add of interaction payment columns.")
            }
        }

        migrator.registerMigration(.addGroupMember) { db in
            do {
                try db.create(table: "model_TSGroupMember") { table in
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

                try db.create(index: "index_model_TSGroupMember_on_uniqueId",
                              on: "model_TSGroupMember",
                              columns: ["uniqueId"])
                try db.create(index: "index_model_TSGroupMember_on_groupThreadId",
                              on: "model_TSGroupMember",
                              columns: ["groupThreadId"])
                try db.create(index: "index_model_TSGroupMember_on_uuidString_and_groupThreadId",
                              on: "model_TSGroupMember",
                              columns: ["uuidString", "groupThreadId"],
                              unique: true)
                try db.create(index: "index_model_TSGroupMember_on_phoneNumber_and_groupThreadId",
                              on: "model_TSGroupMember",
                              columns: ["phoneNumber", "groupThreadId"],
                              unique: true)
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.createPendingViewedReceipts) { db in
            do {
                try db.create(table: "pending_viewed_receipts") { table in
                    table.autoIncrementedPrimaryKey("id")
                    table.column("threadId", .integer).notNull()
                    table.column("messageTimestamp", .integer).notNull()
                    table.column("authorPhoneNumber", .text)
                    table.column("authorUuid", .text)
                }
                try db.create(index: "index_pending_viewed_receipts_on_threadId",
                              on: "pending_viewed_receipts",
                              columns: ["threadId"])
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.addViewedToInteractions) { db in
            do {
                try db.alter(table: "model_TSInteraction") { (table: TableAlteration) -> Void in
                    table.add(column: "viewed", .boolean)
                }

                try db.execute(sql: "UPDATE model_TSInteraction SET viewed = 0")
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.createThreadAssociatedData) { db in
            do {
                try db.create(table: "thread_associated_data") { table in
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

                try db.create(index: "index_thread_associated_data_on_threadUniqueId",
                              on: "thread_associated_data",
                              columns: ["threadUniqueId"],
                              unique: true)
                try db.create(index: "index_thread_associated_data_on_threadUniqueId_and_isMarkedUnread",
                              on: "thread_associated_data",
                              columns: ["threadUniqueId", "isMarkedUnread"])
                try db.create(index: "index_thread_associated_data_on_threadUniqueId_and_isArchived",
                              on: "thread_associated_data",
                              columns: ["threadUniqueId", "isArchived"])
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.addServerGuidToInteractions) { db in
            do {
                try db.alter(table: "model_TSInteraction") { (table: TableAlteration) -> Void in
                    table.add(column: "serverGuid", .text)
                }
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.addMessageSendLog) { db in
            do {
                // Records all sent payloads
                // The sentTimestamp is the timestamp of the outgoing payload
                try db.create(table: "MessageSendLog_Payload") { table in
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
                try db.create(table: "MessageSendLog_Message") { table in
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
                try db.create(table: "MessageSendLog_Recipient") { table in
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
                try db.execute(sql: """
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
                try db.execute(sql: """
                    CREATE TRIGGER MSLMessage_payloadCleanup
                    AFTER DELETE ON MessageSendLog_Message
                    BEGIN
                        DELETE FROM MessageSendLog_Payload WHERE payloadId = old.payloadId;
                    END;
                """)

                // When we receive a decryption failure message, we need to look up
                // the content proto based on the date sent
                try db.create(
                    index: "MSLPayload_sentTimestampIndex",
                    on: "MessageSendLog_Payload",
                    columns: ["sentTimestamp"]
                )

                // When deleting an interaction, we'll need to be able to lookup all
                // payloads associated with that interaction.
                try db.create(
                    index: "MSLMessage_relatedMessageId",
                    on: "MessageSendLog_Message",
                    columns: ["uniqueId"]
                )
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.updatePendingReadReceipts) { db in
            do {
                try db.alter(table: "pending_read_receipts") { (table: TableAlteration) -> Void in
                    table.add(column: "messageUniqueId", .text)
                }
                try db.alter(table: "pending_viewed_receipts") { (table: TableAlteration) -> Void in
                    table.add(column: "messageUniqueId", .text)
                }
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.addSendCompletionToMessageSendLog) { db in
            do {
                try db.alter(table: "MessageSendLog_Payload") { (table: TableAlteration) -> Void in
                    table.add(column: "sendComplete", .boolean).notNull().defaults(to: false)
                }

                // All existing entries are assumed to have completed.
                try db.execute(sql: "UPDATE MessageSendLog_Payload SET sendComplete = 1")

                // Update the trigger to include the new column: "AND sendComplete = true"
                try db.execute(sql: """
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
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.addExclusiveProcessIdentifierAndHighPriorityToJobRecord) { db in
            do {
                try db.alter(table: "model_SSKJobRecord") { (table: TableAlteration) -> Void in
                    table.add(column: "exclusiveProcessIdentifier", .text)
                    table.add(column: "isHighPriority", .boolean)
                }
                try db.execute(sql: "UPDATE model_SSKJobRecord SET isHighPriority = 0")
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.updateMessageSendLogColumnTypes) { db in
            do {
                // Since the MessageSendLog hasn't shipped yet, we can get away with just dropping and rebuilding
                // the tables instead of performing a more expensive migration.
                try db.drop(table: "MessageSendLog_Payload")
                try db.drop(table: "MessageSendLog_Message")
                try db.drop(table: "MessageSendLog_Recipient")

                try db.create(table: "MessageSendLog_Payload") { table in
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

                try db.create(table: "MessageSendLog_Message") { table in
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

                try db.create(table: "MessageSendLog_Recipient") { table in
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

                try db.execute(sql: """
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

                try db.create(
                    index: "MSLPayload_sentTimestampIndex",
                    on: "MessageSendLog_Payload",
                    columns: ["sentTimestamp"]
                )
                try db.create(
                    index: "MSLMessage_relatedMessageId",
                    on: "MessageSendLog_Message",
                    columns: ["uniqueId"]
                )
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.addRecordTypeIndex) { db in
            do {
                try db.create(
                    index: "index_model_TSInteraction_on_nonPlaceholders_uniqueThreadId_id",
                    on: "model_TSInteraction",
                    columns: ["uniqueThreadId", "id"],
                    condition: "\(interactionColumn: .recordType) IS NOT \(SDSRecordType.recoverableDecryptionPlaceholder.rawValue)"
                )
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.tunedConversationLoadIndices) { db in
            do {
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
                try db.execute(sql: """
                    DROP INDEX IF EXISTS index_model_TSInteraction_on_nonPlaceholders_uniqueThreadId_id;

                    CREATE INDEX index_model_TSInteraction_ConversationLoadInteractionCount
                    ON model_TSInteraction(uniqueThreadId, recordType)
                    WHERE recordType IS NOT \(SDSRecordType.recoverableDecryptionPlaceholder.rawValue);

                    CREATE INDEX index_model_TSInteraction_ConversationLoadInteractionDistance
                    ON model_TSInteraction(uniqueThreadId, id, recordType, uniqueId)
                    WHERE recordType IS NOT \(SDSRecordType.recoverableDecryptionPlaceholder.rawValue);
                """)
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.messageDecryptDeduplicationV6) { db in
            do {
                if try db.tableExists("MessageDecryptDeduplication") {
                    try db.drop(table: "MessageDecryptDeduplication")
                }
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.createProfileBadgeTable) { db in
            do {
                try db.alter(table: "model_OWSUserProfile", body: { alteration in
                    alteration.add(column: "profileBadgeInfo", .blob)
                })

                try db.create(table: "model_ProfileBadgeTable") { table in
                    table.column("id", .text).primaryKey()
                    table.column("rawCategory", .text).notNull()
                    table.column("localizedName", .text).notNull()
                    table.column("localizedDescriptionFormatString", .text).notNull()
                    table.column("resourcePath", .text).notNull()

                    table.column("badgeVariant", .text).notNull()
                    table.column("localization", .text).notNull()
                }
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.createSubscriptionDurableJob) { db in
            do {
                try db.alter(table: "model_SSKJobRecord") { (table: TableAlteration) -> Void in
                    table.add(column: "receiptCredentailRequest", .blob)
                    table.add(column: "receiptCredentailRequestContext", .blob)
                    table.add(column: "priorSubscriptionLevel", .integer)
                    table.add(column: "subscriberID", .blob)
                    table.add(column: "targetSubscriptionLevel", .integer)
                    table.add(column: "boostPaymentIntentID", .text)
                    table.add(column: "isBoost", .boolean)
                }
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.addReceiptPresentationToSubscriptionDurableJob) { db in
            do {
                try db.alter(table: "model_SSKJobRecord") { (table: TableAlteration) -> Void in
                    table.add(column: "receiptCredentialPresentation", .blob)
                }
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.createStoryMessageTable) { db in
            do {
                try db.create(table: "model_StoryMessage") { table in
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

                try db.create(index: "index_model_StoryMessage_on_uniqueId", on: "model_StoryMessage", columns: ["uniqueId"])

                try db.create(
                    index: "index_model_StoryMessage_on_timestamp_and_authorUuid",
                    on: "model_StoryMessage",
                    columns: ["timestamp", "authorUuid"]
                )
                try db.create(
                    index: "index_model_StoryMessage_on_direction",
                    on: "model_StoryMessage",
                    columns: ["direction"]
                )
                try db.execute(sql: """
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
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.addColumnsForStoryContextRedux) { db in
            let transaction = GRDBWriteTransaction(database: db)
            defer { transaction.finalizeTransaction() }
            guard !hasRunMigration("addColumnsForStoryContext", transaction: transaction) else { return }

            do {
                try db.alter(table: "model_TSInteraction") { (table: TableAlteration) -> Void in
                    table.add(column: "storyAuthorUuidString", .text)
                    table.add(column: "storyTimestamp", .integer)
                    table.add(column: "isGroupStoryReply", .boolean).defaults(to: false)
                    table.add(column: "storyReactionEmoji", .text)
                }
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.addIsStoriesCapableToUserProfiles) { db in
            do {
                try db.alter(table: "model_OWSUserProfile") { (table: TableAlteration) -> Void in
                    table.add(column: "isStoriesCapable", .boolean).notNull().defaults(to: false)
                }

                try db.execute(sql: "ALTER TABLE model_OWSUserProfile DROP COLUMN isUuidCapable")
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.createDonationReceiptTable) { db in
            do {
                try db.create(table: "model_DonationReceipt") { table in
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
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.addBoostAmountToSubscriptionDurableJob) { db in
            do {
                try db.alter(table: "model_SSKJobRecord") { (table: TableAlteration) -> Void in
                    table.add(column: "amount", .numeric)
                    table.add(column: "currencyCode", .text)
                }
            } catch {
                owsFail("Error: \(error)")
            }
        }

        // These index migrations are *expensive* for users with large interaction tables. For external
        // users who don't yet have access to stories and don't have need for the indices, we will perform
        // one migration per release to keep the blocking time low (ideally one 5-7s migration per release).
        migrator.registerMigration(.updateConversationLoadInteractionCountIndex) { db in
            let transaction = GRDBWriteTransaction(database: db)
            defer { transaction.finalizeTransaction() }
            guard !hasRunMigration("addColumnsForStoryContext", transaction: transaction) else { return }

            do {
                try db.execute(sql: """
                    DROP INDEX index_model_TSInteraction_ConversationLoadInteractionCount;

                    CREATE INDEX index_model_TSInteraction_ConversationLoadInteractionCount
                    ON model_TSInteraction(uniqueThreadId, isGroupStoryReply, recordType)
                    WHERE recordType IS NOT \(SDSRecordType.recoverableDecryptionPlaceholder.rawValue);
                """)
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.updateConversationLoadInteractionDistanceIndex) { db in
            let transaction = GRDBWriteTransaction(database: db)
            defer { transaction.finalizeTransaction() }
            guard !hasRunMigration("addColumnsForStoryContext", transaction: transaction) else { return }

            do {
                try db.execute(sql: """
                    DROP INDEX index_model_TSInteraction_ConversationLoadInteractionDistance;

                    CREATE INDEX index_model_TSInteraction_ConversationLoadInteractionDistance
                    ON model_TSInteraction(uniqueThreadId, id, isGroupStoryReply, recordType, uniqueId)
                    WHERE recordType IS NOT \(SDSRecordType.recoverableDecryptionPlaceholder.rawValue);
                """)
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.updateConversationUnreadCountIndex) { db in
            let transaction = GRDBWriteTransaction(database: db)
            defer { transaction.finalizeTransaction() }
            guard !hasRunMigration("addColumnsForStoryContext", transaction: transaction) else { return }

            do {
                try db.execute(sql: """
                    DROP INDEX IF EXISTS index_interactions_unread_counts;
                    DROP INDEX IF EXISTS index_model_TSInteraction_UnreadCount;

                    CREATE INDEX index_model_TSInteraction_UnreadCount
                    ON model_TSInteraction(read, isGroupStoryReply, uniqueThreadId, recordType);
                """)
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.addStoryContextIndexToInteractions) { db in
            do {
                try db.create(
                    index: "index_model_TSInteraction_on_StoryContext",
                    on: "model_TSInteraction",
                    columns: ["storyTimestamp", "storyAuthorUuidString", "isGroupStoryReply"]
                )
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.improvedDisappearingMessageIndices) { db in
            do {
                // The old index was created in an order that made it practically useless for the query
                // we needed it for. This rebuilds it as a partial index.
                try db.execute(sql: """
                    DROP INDEX index_interactions_on_threadUniqueId_storedShouldStartExpireTimer_and_expiresAt;

                    CREATE INDEX index_interactions_on_threadUniqueId_storedShouldStartExpireTimer_and_expiresAt
                    ON model_TSInteraction(uniqueThreadId, uniqueId)
                    WHERE
                        storedShouldStartExpireTimer IS TRUE
                    AND
                        (expiresAt IS 0 OR expireStartedAt IS 0)
                    ;
                """)
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.addProfileBadgeDuration) { db in
            do {
                try db.alter(table: "model_ProfileBadgeTable") { (table: TableAlteration) -> Void in
                    table.add(column: "duration", .numeric)
                }
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.addGiftBadges) { db in
            do {
                try db.alter(table: "model_TSInteraction") { (table: TableAlteration) -> Void in
                    table.add(column: "giftBadge", .blob)
                }
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.addCanReceiveGiftBadgesToUserProfiles) { db in
            do {
                try db.alter(table: "model_OWSUserProfile") { (table: TableAlteration) -> Void in
                    table.add(column: "canReceiveGiftBadges", .boolean).notNull().defaults(to: false)
                }
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.addStoryThreadColumns) { db in
            do {
                try db.alter(table: "model_TSThread") { (table: TableAlteration) -> Void in
                    table.add(column: "allowsReplies", .boolean).defaults(to: false)
                    table.add(column: "lastSentStoryTimestamp", .integer)
                    table.add(column: "name", .text)
                    table.add(column: "addresses", .blob)
                    table.add(column: "storyViewMode", .integer).defaults(to: 0)
                }

                try db.create(index: "index_model_TSThread_on_storyViewMode", on: "model_TSThread", columns: ["storyViewMode", "lastSentStoryTimestamp", "allowsReplies"])
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.addUnsavedMessagesToSendToJobRecord) { db in
            do {
                try db.alter(table: "model_SSKJobRecord") { (table: TableAlteration) -> Void in
                    table.add(column: "unsavedMessagesToSend", .blob)
                }
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.addColumnsForSendGiftBadgeDurableJob) { db in
            do {
                try db.alter(table: "model_SSKJobRecord") { (table: TableAlteration) -> Void in
                    table.add(column: "messageText", .text)
                    table.add(column: "paymentIntentClientSecret", .text)
                    table.add(column: "paymentMethodId", .text)
                }
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.addDonationReceiptTypeColumn) { db in
            do {
                try db.alter(table: "model_DonationReceipt") { (table: TableAlteration) -> Void in
                    table.add(column: "receiptType", .numeric)
                }
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.addAudioPlaybackRateColumn) { db in
            do {
                try db.alter(table: "thread_associated_data") { table in
                    table.add(column: "audioPlaybackRate", .double)
                }
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.addSchemaVersionToAttachments) { db in
            do {
                try db.alter(table: "model_TSAttachment") { table in
                    table.add(column: "attachmentSchemaVersion", .integer).defaults(to: 0)
                }
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.makeAudioPlaybackRateColumnNonNull) { db in
            do {
                // Up until when this is merged, there has been no way for users
                // to actually set an audio playback rate, so its okay to drop the column
                // just to reset the schema constraints to non-null.
                try db.alter(table: "thread_associated_data") { table in
                    table.drop(column: "audioPlaybackRate")
                    table.add(column: "audioPlaybackRate", .double).notNull().defaults(to: 1)
                }
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.addLastViewedStoryTimestampToTSThread) { db in
            do {
                try db.alter(table: "model_TSThread") { table in
                    table.add(column: "lastViewedStoryTimestamp", .integer)
                }
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.convertStoryIncomingManifestStorageFormat) { db in
            do {
                // Nest the "incoming" state under the "receivedState" key to make
                // future migrations more future proof.
                try db.execute(sql: """
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
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.recreateStoryIncomingViewedTimestampIndex) { db in
            do {
                try db.drop(index: "index_model_StoryMessage_on_incoming_viewedTimestamp")
                try db.execute(sql: """
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
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.addColumnsForLocalUserLeaveGroupDurableJob) { db in
            do {
                try db.alter(table: "model_SSKJobRecord") { table in
                    table.add(column: "replacementAdminUuid", .text)
                    table.add(column: "waitForMessageProcessing", .boolean)
                }
            } catch let error {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.addStoriesHiddenStateToThreadAssociatedData) { db in
            do {
                try db.alter(table: "thread_associated_data") { table in
                    table.add(column: "hideStory", .boolean).notNull().defaults(to: false)
                }
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.addUnregisteredAtTimestampToSignalRecipient) { db in
            do {
                try db.alter(table: "model_SignalRecipient") { table in
                    table.add(column: "unregisteredAtTimestamp", .integer)
                }
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.addLastReceivedStoryTimestampToTSThread) { db in
            do {
                try db.alter(table: "model_TSThread") { table in
                    table.add(column: "lastReceivedStoryTimestamp", .integer)
                }
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.addStoryContextAssociatedDataTable) { db in
            do {
                try db.create(table: StoryContextAssociatedData.databaseTableName) { table in
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
                try db.create(
                    index: "index_story_context_associated_data_contact_on_contact_uuid",
                    on: StoryContextAssociatedData.databaseTableName,
                    columns: [StoryContextAssociatedData.columnName(.contactUuid)]
                )
                try db.create(
                    index: "index_story_context_associated_data_contact_on_group_id",
                    on: StoryContextAssociatedData.databaseTableName,
                    columns: [StoryContextAssociatedData.columnName(.groupId)]
                )
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.populateStoryContextAssociatedDataTableAndRemoveOldColumns) { db in
            let transaction = GRDBWriteTransaction(database: db)
            defer { transaction.finalizeTransaction() }

            do {
                // All we need to do is iterate over ThreadAssociatedData; one exists for every
                // thread, so we can pull hidden state from the associated data and received/viewed
                // timestamps from their threads and have a copy of everything we need.
                try Row.fetchCursor(db, sql: """
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
                            db,
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
                            try db.execute(
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
                            try db.execute(
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
                try db.alter(table: "model_TSThread") { alteration in
                    alteration.drop(column: "lastViewedStoryTimestamp")
                    alteration.drop(column: "lastReceivedStoryTimestamp")
                }
                try db.alter(table: "thread_associated_data") { alteration in
                    alteration.drop(column: "hideStory")
                }

            } catch {
                owsFail("Error \(error)")
            }
        }

        migrator.registerMigration(.addColumnForExperienceUpgradeManifest) { db in
            do {
                try db.alter(table: "model_ExperienceUpgrade") { table in
                    table.add(column: "manifest", .blob)
                }
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.addStoryContextAssociatedDataReadTimestampColumn) { db in
            do {
                try db.alter(table: "model_StoryContextAssociatedData") { table in
                    table.add(column: "lastReadTimestamp", .integer)
                }
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.addIsCompleteToContactSyncJob) { db in
            do {
                try db.alter(table: "model_SSKJobRecord") { (table: TableAlteration) -> Void in
                    table.add(column: "isCompleteContactSync", .boolean).defaults(to: false)
                }
            } catch let error {
                owsFail("Error: \(error)")
            }
        } // end: .addIsCompleteToContactSyncJob

        // MARK: - Schema Migration Insertion Point
    }

    private static func registerDataMigrations(migrator: DatabaseMigratorWrapper) {

        // The migration blocks should never throw. If we introduce a crashing
        // migration, we want the crash logs reflect where it occurred.

        migrator.registerMigration(.dataMigration_populateGalleryItems) { db in
            do {
                let transaction = GRDBWriteTransaction(database: db)
                defer { transaction.finalizeTransaction() }

                try createInitialGalleryRecords(transaction: transaction)
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.dataMigration_markOnboardedUsers_v2) { db in
            let transaction = GRDBWriteTransaction(database: db)
            defer { transaction.finalizeTransaction() }

            if TSAccountManager.shared.isRegistered(transaction: transaction.asAnyWrite) {
                Logger.info("marking existing user as onboarded")
                TSAccountManager.shared.setIsOnboarded(true, transaction: transaction.asAnyWrite)
            }
        }

        migrator.registerMigration(.dataMigration_clearLaunchScreenCache) { _ in
            OWSFileSystem.deleteFileIfExists(NSHomeDirectory() + "/Library/SplashBoard")
        }

        migrator.registerMigration(.dataMigration_enableV2RegistrationLockIfNecessary) { db in
            let transaction = GRDBWriteTransaction(database: db)
            defer { transaction.finalizeTransaction() }

            guard KeyBackupService.hasMasterKey(transaction: transaction.asAnyWrite) else { return }

            OWS2FAManager.keyValueStore().setBool(true, key: OWS2FAManager.isRegistrationLockV2EnabledKey, transaction: transaction.asAnyWrite)
        }

        migrator.registerMigration(.dataMigration_resetStorageServiceData) { db in
            let transaction = GRDBWriteTransaction(database: db)
            defer { transaction.finalizeTransaction() }

            Self.storageServiceManager.resetLocalData(transaction: transaction.asAnyWrite)
        }

        migrator.registerMigration(.dataMigration_markAllInteractionsAsNotDeleted) { db in
            do {
                try db.execute(sql: "UPDATE model_TSInteraction SET wasRemotelyDeleted = 0")
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.dataMigration_recordMessageRequestInteractionIdEpoch) { db in
            let transaction = GRDBWriteTransaction(database: db)
            defer { transaction.finalizeTransaction() }

            // Set the epoch only if we haven't already, this lets us track and grandfather
            // conversations that existed before the message request feature was launched.
            guard SSKPreferences.messageRequestInteractionIdEpoch(transaction: transaction) == nil else { return }

            let maxId = GRDBInteractionFinder.maxRowId(transaction: transaction)
            SSKPreferences.setMessageRequestInteractionIdEpoch(maxId, transaction: transaction)
        }

        migrator.registerMigration(.dataMigration_indexSignalRecipients) { db in
            let transaction = GRDBWriteTransaction(database: db)
            defer { transaction.finalizeTransaction() }

            // This migration was initially created as a schema migration instead of a data migration.
            // If we already ran it there, we need to skip it here since we're doing inserts below that
            // cannot be repeated.
            guard !hasRunMigration("indexSignalRecipients", transaction: transaction) else { return }

            SignalRecipient.anyEnumerate(transaction: transaction.asAnyWrite) { (signalRecipient: SignalRecipient, _: UnsafeMutablePointer<ObjCBool>) in
                GRDBFullTextSearchFinder.modelWasInserted(model: signalRecipient, transaction: transaction)
            }
        }

        migrator.registerMigration(.dataMigration_kbsStateCleanup) { db in
            let transaction = GRDBWriteTransaction(database: db)
            defer { transaction.finalizeTransaction() }

            if KeyBackupService.hasMasterKey(transaction: transaction.asAnyRead) {
                KeyBackupService.setMasterKeyBackedUp(true, transaction: transaction.asAnyWrite)
            }

            guard let isUsingRandomPinKey = OWS2FAManager.keyValueStore().getBool(
                "isUsingRandomPinKey",
                transaction: transaction.asAnyRead
            ), isUsingRandomPinKey else { return }

            OWS2FAManager.keyValueStore().removeValue(forKey: "isUsingRandomPinKey", transaction: transaction.asAnyWrite)
            KeyBackupService.useDeviceLocalMasterKey(transaction: transaction.asAnyWrite)
        }

        migrator.registerMigration(.dataMigration_turnScreenSecurityOnForExistingUsers) { db in
            let transaction = GRDBWriteTransaction(database: db)
            defer { transaction.finalizeTransaction() }

            // Declare the key value store here, since it's normally only
            // available in SignalMessaging (OWSPreferences).
            let preferencesKeyValueStore = SDSKeyValueStore(collection: "SignalPreferences")
            let screenSecurityKey = "Screen Security Key"
            guard !preferencesKeyValueStore.hasValue(
                forKey: screenSecurityKey,
                transaction: transaction.asAnyRead
            ) else { return }

            preferencesKeyValueStore.setBool(true, key: screenSecurityKey, transaction: transaction.asAnyWrite)
        }

        migrator.registerMigration(.dataMigration_groupIdMapping) { db in
            let transaction = GRDBWriteTransaction(database: db)
            defer { transaction.finalizeTransaction() }

            TSThread.anyEnumerate(transaction: transaction.asAnyWrite) { (thread: TSThread, _: UnsafeMutablePointer<ObjCBool>) in
                guard let groupThread = thread as? TSGroupThread else {
                    return
                }
                TSGroupThread.setGroupIdMapping(groupThread.uniqueId,
                                                forGroupId: groupThread.groupModel.groupId,
                                                transaction: transaction.asAnyWrite)
            }
        }

        migrator.registerMigration(.dataMigration_disableSharingSuggestionsForExistingUsers) { db in
            let transaction = GRDBWriteTransaction(database: db)
            defer { transaction.finalizeTransaction() }
            SSKPreferences.setAreIntentDonationsEnabled(false, transaction: transaction.asAnyWrite)
        }

        migrator.registerMigration(.dataMigration_removeOversizedGroupAvatars) { db in
            let transaction = GRDBWriteTransaction(database: db)
            defer { transaction.finalizeTransaction() }

            TSGroupThread.anyEnumerate(transaction: transaction.asAnyWrite) { (thread: TSThread, _) in
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
                    owsFail("Failed to remove invalid group avatar during migration: \(error)")
                }
            }
        }

        migrator.registerMigration(.dataMigration_scheduleStorageServiceUpdateForMutedThreads) { db in
            let transaction = GRDBWriteTransaction(database: db)
            defer { transaction.finalizeTransaction() }

            do {
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
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.dataMigration_populateGroupMember) { db in
            let transaction = GRDBWriteTransaction(database: db)
            defer { transaction.finalizeTransaction() }

            do {
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
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.dataMigration_cullInvalidIdentityKeySendingErrors) { db in
            let transaction = GRDBWriteTransaction(database: db)
            defer { transaction.finalizeTransaction() }

            let sql = """
                DELETE FROM \(InteractionRecord.databaseTableName)
                WHERE \(interactionColumn: .recordType) = ?
            """
            transaction.executeUpdate(sql: sql, arguments: [SDSRecordType.invalidIdentityKeySendingErrorMessage.rawValue])
        }

        migrator.registerMigration(.dataMigration_moveToThreadAssociatedData) { db in
            let transaction = GRDBWriteTransaction(database: db)
            defer { transaction.finalizeTransaction() }

            TSThread.anyEnumerate(transaction: transaction.asAnyWrite) { thread, _ in
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
                    owsFail("Error \(error)")
                }
            }
        }

        migrator.registerMigration(.dataMigration_senderKeyStoreKeyIdMigration) { db in
            let transaction = GRDBWriteTransaction(database: db)
            defer { transaction.finalizeTransaction() }

            SenderKeyStore.performKeyIdMigration(transaction: transaction.asAnyWrite)
        }

        migrator.registerMigration(.dataMigration_reindexGroupMembershipAndMigrateLegacyAvatarDataFixed) { db in
            let transaction = GRDBWriteTransaction(database: db)
            defer { transaction.finalizeTransaction() }

            do {
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
                guard !hasRunMigration("dataMigration_reindexGroupMembershipAndMigrateLegacyAvatarData", transaction: transaction) else { return }

                let memberCursor = try TSGroupMember.fetchCursor(db)

                while let member = try memberCursor.next() {
                    autoreleasepool {
                        GRDBFullTextSearchFinder.modelWasInsertedOrUpdated(model: member, transaction: transaction)
                    }
                }
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.dataMigration_repairAvatar) { db in
            let transaction = GRDBWriteTransaction(database: db)
            defer { transaction.finalizeTransaction() }

            // Declare the key value store here, since it's normally only
            // available in SignalMessaging (OWSPreferences).
            let preferencesKeyValueStore = SDSKeyValueStore(collection: Self.migrationSideEffectsCollectionName)
            let key = Self.avatarRepairAttemptCount
            preferencesKeyValueStore.setInt(0, key: key, transaction: transaction.asAnyWrite)
        }

        migrator.registerMigration(.dataMigration_dropEmojiAvailabilityStore) { db in
            let transaction = GRDBWriteTransaction(database: db)
            defer { transaction.finalizeTransaction() }

            // This is a bit of a layering violation, since these tables were previously managed in the app layer.
            // In the long run we'll have a general "unused SDSKeyValueStore cleaner" migration,
            // but for now this should drop 2000 or so rows for free.
            SDSKeyValueStore(collection: "Emoji+availableStore").removeAll(transaction: transaction.asAnyWrite)
            SDSKeyValueStore(collection: "Emoji+metadataStore").removeAll(transaction: transaction.asAnyWrite)
        }

        migrator.registerMigration(.dataMigration_dropSentStories) { db in
            let sql = """
                DELETE FROM \(StoryMessage.databaseTableName)
                WHERE \(StoryMessage.columnName(.direction)) = \(StoryMessage.Direction.outgoing.rawValue)
            """
            do {
                try db.execute(sql: sql)
            } catch {
                owsFail("Error \(error)")
            }
        }

        migrator.registerMigration(.dataMigration_indexMultipleNameComponentsForReceipients) { db in
            let transaction = GRDBWriteTransaction(database: db)
            defer { transaction.finalizeTransaction() }

            // We updated how we generate text for the search index for a
            // recipient, and consequently should touch all recipients so that
            // we regenerate the index text.

            SignalRecipient.anyEnumerate(transaction: transaction.asAnyWrite) { (signalRecipient: SignalRecipient, _: UnsafeMutablePointer<ObjCBool>) in
                GRDBFullTextSearchFinder.modelWasUpdated(model: signalRecipient, transaction: transaction)
            }
        }

        migrator.registerMigration(.dataMigration_syncGroupStories) { db in
            let transaction = GRDBWriteTransaction(database: db)
            defer { transaction.finalizeTransaction() }

            for thread in AnyThreadFinder().storyThreads(includeImplicitGroupThreads: false, transaction: transaction.asAnyRead) {
                guard let thread = thread as? TSGroupThread else { continue }
                self.storageServiceManager.recordPendingUpdates(groupModel: thread.groupModel)
            }
        }

        migrator.registerMigration(.dataMigration_deleteOldGroupCapabilities) { db in
            let sql = """
                DELETE FROM \(SDSKeyValueStore.tableName)
                WHERE \(SDSKeyValueStore.collectionColumn.columnName)
                IN ("GroupManager.senderKeyCapability", "GroupManager.announcementOnlyGroupsCapability", "GroupManager.groupsV2MigrationCapability")
            """
            do {
                try db.execute(sql: sql)
            } catch {
                owsFail("Error \(error)")
            }
        }

        migrator.registerMigration(.dataMigration_updateStoriesDisabledInAccountRecord) { db in
            storageServiceManager.recordPendingLocalAccountUpdates()
        }

        migrator.registerMigration(.dataMigration_removeGroupStoryRepliesFromSearchIndex) { db in
            do {
                let uniqueIdSql = """
                    SELECT \(interactionColumn: .uniqueId)
                    FROM \(InteractionRecord.databaseTableName)
                    WHERE \(interactionColumn: .isGroupStoryReply) = 1
                """
                let uniqueIds = try String.fetchAll(db, sql: uniqueIdSql)

                guard !uniqueIds.isEmpty else { return }

                let indexUpdateSql = """
                    DELETE FROM \(GRDBFullTextSearchFinder.contentTableName)
                    WHERE \(GRDBFullTextSearchFinder.uniqueIdColumn) IN (\(uniqueIds.map { "\"\($0)\"" }.joined(separator: ", ")))
                    AND \(GRDBFullTextSearchFinder.collectionColumn) = "\(TSInteraction.collection())"
                """
                try db.execute(sql: indexUpdateSql)
            } catch {
                owsFail("Error \(error)")
            }
        }

        migrator.registerMigration(.dataMigration_populateStoryContextAssociatedDataLastReadTimestamp) { db in
            do {
                let sql = """
                    UPDATE model_StoryContextAssociatedData
                    SET lastReadTimestamp = lastViewedTimestamp
                """
                try db.execute(sql: sql)
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(.dataMigration_indexPrivateStoryThreadNames) { db in
            do {
                let transaction = GRDBWriteTransaction(database: db)
                defer { transaction.finalizeTransaction() }

                let sql = "SELECT * FROM model_TSThread WHERE recordType IS \(SDSRecordType.privateStoryThread.rawValue)"
                let cursor = TSThread.grdbFetchCursor(sql: sql, transaction: transaction)
                while let thread = try cursor.next() {
                    guard let storyThread = thread as? TSPrivateStoryThread else {
                        continue
                    }
                    GRDBFullTextSearchFinder.modelWasInserted(model: storyThread, transaction: transaction)
                }
            } catch {
                owsFail("Error: \(error)")
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
