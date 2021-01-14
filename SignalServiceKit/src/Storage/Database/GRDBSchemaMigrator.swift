//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDB

@objc
public class GRDBSchemaMigrator: NSObject {

    // MARK: - Dependencies

    private var grdbStorage: GRDBDatabaseStorageAdapter {
        return SDSDatabaseStorage.shared.grdbStorage
    }

    // MARK: -

    @objc
    public func runSchemaMigrations() {
        if hasCreatedInitialSchema {
            Logger.info("Using incrementalMigrator.")
            try! incrementalMigrator.migrate(grdbStorage.pool)
        } else {
            Logger.info("Using newUserMigrator.")
            try! newUserMigrator.migrate(grdbStorage.pool)
        }
        Logger.info("Migrations complete.")

        SSKPreferences.markGRDBSchemaAsLatest()
    }

    private var hasCreatedInitialSchema: Bool {
        // HACK: GRDB doesn't create the grdb_migrations table until running a migration.
        // So we can't cleanly check which migrations have run for new users until creating this
        // table ourselves.
        try! grdbStorage.write { transaction in
            try! self.fixit_setupMigrations(transaction.database)
        }

        let appliedMigrations = try! incrementalMigrator.appliedMigrations(in: grdbStorage.pool)
        Logger.info("appliedMigrations: \(appliedMigrations).")
        return appliedMigrations.contains(MigrationId.createInitialSchema.rawValue)
    }

    private func fixit_setupMigrations(_ db: Database) throws {
        try db.execute(sql: "CREATE TABLE IF NOT EXISTS grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY)")
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
        case dataMigration_disableLinkPreviewForExistingUsers
        case dataMigration_groupIdMapping
    }

    public static let grdbSchemaVersionDefault: UInt = 0
    public static let grdbSchemaVersionLatest: UInt = 16

    // An optimization for new users, we have the first migration import the latest schema
    // and mark any other migrations as "already run".
    private lazy var newUserMigrator: DatabaseMigrator = {
        var migrator = DatabaseMigrator()
        migrator.registerMigration(MigrationId.createInitialSchema.rawValue) { db in
            Logger.info("importing latest schema")
            guard let sqlFile = Bundle(for: GRDBSchemaMigrator.self).url(forResource: "schema", withExtension: "sql") else {
                owsFail("sqlFile was unexpectedly nil")
            }
            let sql = try String(contentsOf: sqlFile)
            try db.execute(sql: sql)
        }

        // After importing the initial schema, we want to skip the remaining incremental migrations
        // so we register each migration id with a no-op implementation.
        for migrationId in (MigrationId.allCases.filter { $0 != .createInitialSchema }) {
            migrator.registerMigration(migrationId.rawValue) { _ in
                Logger.info("skipping migration: \(migrationId) for new user.")
                // no-op
            }
        }

        return migrator
    }()

    class DatabaseMigratorWrapper {
        var migrator = DatabaseMigrator()

        func registerMigration(_ identifier: String, migrate: @escaping (Database) throws -> Void) {
            migrator.registerMigration(identifier) {  (database: Database) throws in
                Logger.info("Running migration: \(identifier)")
                try migrate(database)
            }
        }
    }

    // Used by existing users to incrementally update from their existing schema
    // to the latest.
    private lazy var incrementalMigrator: DatabaseMigrator = {
        var migratorWrapper = DatabaseMigratorWrapper()

        registerSchemaMigrations(migrator: migratorWrapper)

        // Data Migrations must run *after* schema migrations
        registerDataMigrations(migrator: migratorWrapper)

        return migratorWrapper.migrator
    }()

    private func registerSchemaMigrations(migrator: DatabaseMigratorWrapper) {

        // The migration blocks should never throw. If we introduce a crashing
        // migration, we want the crash logs reflect where it occurred.

        migrator.registerMigration(MigrationId.createInitialSchema.rawValue) { _ in
            owsFail("This migration should have already been run by the last YapDB migration.")
            // try createV1Schema(db: db)
        }

        migrator.registerMigration(MigrationId.signalAccount_add_contactAvatars.rawValue) { database in
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

        migrator.registerMigration(MigrationId.signalAccount_add_contactAvatars_indices.rawValue) { db in
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

        migrator.registerMigration(MigrationId.jobRecords_add_attachmentId.rawValue) { db in
            do {
                try db.alter(table: "model_SSKJobRecord") { (table: TableAlteration) -> Void in
                    table.add(column: "attachmentId", .text)
                }
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(MigrationId.createMediaGalleryItems.rawValue) { db in
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

        migrator.registerMigration(MigrationId.createReaction.rawValue) { db in
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

        migrator.registerMigration(MigrationId.dedupeSignalRecipients.rawValue) { db in
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
        // migrator.registerMigration(MigrationId.indexMediaGallery2.rawValue) { db in
        //     // re-index the media gallery for those who failed to create during the initial YDB migration
        //     try createInitialGalleryRecords(transaction: GRDBWriteTransaction(database: db))
        // }

        migrator.registerMigration(MigrationId.unreadThreadInteractions.rawValue) { db in
            do {
                try db.create(index: "index_interactions_on_threadId_read_and_id",
                              on: "model_TSInteraction",
                              columns: ["uniqueThreadId", "read", "id"],
                              unique: true)
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(MigrationId.createFamilyName.rawValue) { db in
            do {
                try db.alter(table: "model_OWSUserProfile", body: { alteration in
                    alteration.add(column: "familyName", .text)
                })
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(MigrationId.createIndexableFTSTable.rawValue) { db in
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

        migrator.registerMigration(MigrationId.dropContactQuery.rawValue) { db in
            do {
                try db.drop(table: "model_OWSContactQuery")
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(MigrationId.indexFailedJob.rawValue) { db in
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

        migrator.registerMigration(MigrationId.groupsV2MessageJobs.rawValue) { db in
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

        migrator.registerMigration(MigrationId.addUserInfoToInteractions.rawValue) { db in
            do {
                try db.alter(table: "model_TSInteraction") { (table: TableAlteration) -> Void in
                    table.add(column: "infoMessageUserInfo", .blob)
                }
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(MigrationId.recreateExperienceUpgradeWithNewColumns.rawValue) { db in
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

        migrator.registerMigration(MigrationId.recreateExperienceUpgradeIndex.rawValue) { db in
            do {
                try db.create(index: "index_model_ExperienceUpgrade_on_uniqueId", on: "model_ExperienceUpgrade", columns: ["uniqueId"])
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(MigrationId.indexInfoMessageOnType_v2.rawValue) { db in
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

        migrator.registerMigration(MigrationId.createPendingReadReceipts.rawValue) { db in
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

        migrator.registerMigration(MigrationId.createInteractionAttachmentIdsIndex.rawValue) { db in
            do {
                try db.create(index: "index_model_TSInteraction_on_threadUniqueId_and_attachmentIds",
                              on: "model_TSInteraction",
                              columns: ["threadUniqueId", "attachmentIds"])
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(MigrationId.addIsUuidCapableToUserProfiles.rawValue) { db in
            do {
                try db.alter(table: "model_OWSUserProfile") { (table: TableAlteration) -> Void in
                    table.add(column: "isUuidCapable", .boolean).notNull().defaults(to: false)
                }
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(MigrationId.uploadTimestamp.rawValue) { db in
            do {
                try db.alter(table: "model_TSAttachment") { (table: TableAlteration) -> Void in
                    table.add(column: "uploadTimestamp", .integer).notNull().defaults(to: 0)
                }
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(MigrationId.addRemoteDeleteToInteractions.rawValue) { db in
            do {
                try db.alter(table: "model_TSInteraction") { (table: TableAlteration) -> Void in
                    table.add(column: "wasRemotelyDeleted", .boolean)
                }
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(MigrationId.cdnKeyAndCdnNumber.rawValue) { db in
            do {
                try db.alter(table: "model_TSAttachment") { (table: TableAlteration) -> Void in
                    table.add(column: "cdnKey", .text).notNull().defaults(to: "")
                    table.add(column: "cdnNumber", .integer).notNull().defaults(to: 0)
                }
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(MigrationId.addGroupIdToGroupsV2IncomingMessageJobs.rawValue) { db in
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

        migrator.registerMigration(MigrationId.removeEarlyReceiptTables.rawValue) { db in
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

        migrator.registerMigration(MigrationId.addReadToReactions.rawValue) { db in
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

        migrator.registerMigration(MigrationId.addIsMarkedUnreadToThreads.rawValue) { db in
            do {
                try db.alter(table: "model_TSThread") { (table: TableAlteration) -> Void in
                    table.add(column: "isMarkedUnread", .boolean).notNull().defaults(to: false)
                }
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(MigrationId.addIsMediaMessageToMessageSenderJobQueue.rawValue) { db in
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

        migrator.registerMigration(MigrationId.readdAttachmentIndex.rawValue) { db in
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

        migrator.registerMigration(MigrationId.addLastVisibleRowIdToThreads.rawValue) { db in
            do {
                try db.alter(table: "model_TSThread") { (table: TableAlteration) -> Void in
                    table.add(column: "lastVisibleSortIdOnScreenPercentage", .double).notNull().defaults(to: 0)
                    table.add(column: "lastVisibleSortId", .integer).notNull().defaults(to: 0)
                }
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(MigrationId.addMarkedUnreadIndexToThread.rawValue) { db in
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

        migrator.registerMigration(MigrationId.fixIncorrectIndexes.rawValue) { db in
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

        migrator.registerMigration(MigrationId.resetThreadVisibility.rawValue) { db in
            do {
                try db.execute(sql: "UPDATE model_TSThread SET lastVisibleSortIdOnScreenPercentage = 0, lastVisibleSortId = 0")
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(MigrationId.trackUserProfileFetches.rawValue) { db in
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

        migrator.registerMigration(MigrationId.addMentions.rawValue) { db in
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

        migrator.registerMigration(MigrationId.addMentionNotificationMode.rawValue) { db in
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

        migrator.registerMigration(MigrationId.addOfferTypeToCalls.rawValue) { db in
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

        migrator.registerMigration(MigrationId.addServerDeliveryTimestamp.rawValue) { db in
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

        migrator.registerMigration(MigrationId.updateAnimatedStickers.rawValue) { db in
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

        migrator.registerMigration(MigrationId.updateMarkedUnreadIndex.rawValue) { db in
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

        migrator.registerMigration(MigrationId.addGroupCallMessage2.rawValue) { db in
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

        migrator.registerMigration(MigrationId.addGroupCallEraIdIndex.rawValue) { db in
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

        // MARK: - Schema Migration Insertion Point
    }

    func registerDataMigrations(migrator: DatabaseMigratorWrapper) {

        // The migration blocks should never throw. If we introduce a crashing
        // migration, we want the crash logs reflect where it occurred.

        migrator.registerMigration(MigrationId.dataMigration_populateGalleryItems.rawValue) { db in
            do {
                let transaction = GRDBWriteTransaction(database: db)
                defer { transaction.finalizeTransaction() }

                try createInitialGalleryRecords(transaction: transaction)
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(MigrationId.dataMigration_markOnboardedUsers_v2.rawValue) { db in
            let transaction = GRDBWriteTransaction(database: db)
            defer { transaction.finalizeTransaction() }

            if TSAccountManager.shared().isRegistered(transaction: transaction.asAnyWrite) {
                Logger.info("marking existing user as onboarded")
                TSAccountManager.shared().setIsOnboarded(true, transaction: transaction.asAnyWrite)
            }
        }

        migrator.registerMigration(MigrationId.dataMigration_clearLaunchScreenCache.rawValue) { _ in
            OWSFileSystem.deleteFileIfExists(NSHomeDirectory() + "/Library/SplashBoard")
        }

        migrator.registerMigration(MigrationId.dataMigration_enableV2RegistrationLockIfNecessary.rawValue) { db in
            let transaction = GRDBWriteTransaction(database: db)
            defer { transaction.finalizeTransaction() }

            guard KeyBackupService.hasMasterKey(transaction: transaction.asAnyWrite) else { return }

            OWS2FAManager.keyValueStore().setBool(true, key: OWS2FAManager.isRegistrationLockV2EnabledKey, transaction: transaction.asAnyWrite)
        }

        migrator.registerMigration(MigrationId.dataMigration_resetStorageServiceData.rawValue) { db in
            let transaction = GRDBWriteTransaction(database: db)
            defer { transaction.finalizeTransaction() }

            SSKEnvironment.shared.storageServiceManager.resetLocalData(transaction: transaction.asAnyWrite)
        }

        migrator.registerMigration(MigrationId.dataMigration_markAllInteractionsAsNotDeleted.rawValue) { db in
            do {
                try db.execute(sql: "UPDATE model_TSInteraction SET wasRemotelyDeleted = 0")
            } catch {
                owsFail("Error: \(error)")
            }
        }

        migrator.registerMigration(MigrationId.dataMigration_recordMessageRequestInteractionIdEpoch.rawValue) { db in
            let transaction = GRDBWriteTransaction(database: db)
            defer { transaction.finalizeTransaction() }

            // Set the epoch only if we haven't already, this lets us track and grandfather
            // conversations that existed before the message request feature was launched.
            guard SSKPreferences.messageRequestInteractionIdEpoch(transaction: transaction) == nil else { return }

            let maxId = GRDBInteractionFinder.maxRowId(transaction: transaction)
            SSKPreferences.setMessageRequestInteractionIdEpoch(maxId, transaction: transaction)
        }

        migrator.registerMigration(MigrationId.dataMigration_indexSignalRecipients.rawValue) { db in
            let transaction = GRDBWriteTransaction(database: db)
            defer { transaction.finalizeTransaction() }

            // This migration was initially created as a schema migration instead of a data migration.
            // If we already ran it there, we need to skip it here since we're doing inserts below that
            // cannot be repeated.
            guard !hasRunMigration("indexSignalRecipients", transaction: transaction) else { return }

            SignalRecipient.anyEnumerate(transaction: transaction.asAnyWrite) { (signalRecipient: SignalRecipient,
                _: UnsafeMutablePointer<ObjCBool>) in
                GRDBFullTextSearchFinder.modelWasInserted(model: signalRecipient, transaction: transaction)
            }
        }

        migrator.registerMigration(MigrationId.dataMigration_kbsStateCleanup.rawValue) { db in
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

        migrator.registerMigration(MigrationId.dataMigration_turnScreenSecurityOnForExistingUsers.rawValue) { db in
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

        migrator.registerMigration(MigrationId.dataMigration_disableLinkPreviewForExistingUsers.rawValue) { db in
            let transaction = GRDBWriteTransaction(database: db)
            defer { transaction.finalizeTransaction() }
            let linkPreviewsWereEnabled = SSKPreferences.areLinkPreviewsEnabled(transaction: transaction.asAnyRead)

            if linkPreviewsWereEnabled {
                // Disable link previews until user interacts with megaphone
                SSKPreferences.setAreLinkPreviewsEnabled(false, transaction: transaction.asAnyWrite)
            } else {
                // We don't want to show the megaphone for users that already had link previews disabled
                ExperienceUpgradeFinder.markAsComplete(experienceUpgradeId: .linkPreviews, transaction: transaction)
            }
        }

        migrator.registerMigration(MigrationId.dataMigration_groupIdMapping.rawValue) { db in
            let transaction = GRDBWriteTransaction(database: db)
            defer { transaction.finalizeTransaction() }

            TSThread.anyEnumerate(transaction: transaction.asAnyWrite) { (thread: TSThread,
                _: UnsafeMutablePointer<ObjCBool>) in
                guard let groupThread = thread as? TSGroupThread else {
                    return
                }
                TSGroupThread.setGroupIdMapping(groupThread.uniqueId,
                                                forGroupId: groupThread.groupModel.groupId,
                                                transaction: transaction.asAnyWrite)
            }
        }
    }
}

private func createV1Schema(db: Database) throws {
    // Key-Value Stores
    try SDSKeyValueStore.createTable(database: db)

    // MARK: Model tables

    try db.create(table: "model_TSThread") { table in
        table.autoIncrementedPrimaryKey("id")
            .notNull()
        table.column("recordType", .integer)
            .notNull()
        table.column("uniqueId", .text)
            .notNull()
            .unique(onConflict: .fail)
        table.column("conversationColorName", .text)
            .notNull()
        table.column("creationDate", .double)
        table.column("isArchived", .integer)
            .notNull()
        table.column("lastInteractionRowId", .integer)
            .notNull()
        table.column("messageDraft", .text)
        table.column("mutedUntilDate", .double)
        table.column("shouldThreadBeVisible", .integer)
            .notNull()
        table.column("contactPhoneNumber", .text)
        table.column("contactUUID", .text)
        table.column("groupModel", .blob)
        table.column("hasDismissedOffers", .integer)
    }
    try db.create(index: "index_model_TSThread_on_uniqueId", on: "model_TSThread", columns: ["uniqueId"])

    try db.create(table: "model_TSInteraction") { table in
        table.autoIncrementedPrimaryKey("id")
            .notNull()
        table.column("recordType", .integer)
            .notNull()
        table.column("uniqueId", .text)
            .notNull()
            .unique(onConflict: .fail)
        table.column("receivedAtTimestamp", .integer)
            .notNull()
        table.column("timestamp", .integer)
            .notNull()
        table.column("uniqueThreadId", .text)
            .notNull()
        table.column("attachmentIds", .blob)
        table.column("authorId", .text)
        table.column("authorPhoneNumber", .text)
        table.column("authorUUID", .text)
        table.column("body", .text)
        table.column("callType", .integer)
        // GRDB TODO remove this column - userInfo?
        table.column("configurationDurationSeconds", .integer)
        // GRDB TODO remove this column - userInfo?
        table.column("configurationIsEnabled", .integer)
        table.column("contactShare", .blob)
        // GRDB TODO remove this column - userInfo?
        table.column("createdByRemoteName", .text)
        // GRDB TODO remove this column - userInfo?
        table.column("createdInExistingGroup", .integer)
        // GRDB TODO remove this column - userInfo?
        table.column("customMessage", .text)
        // GRDB TODO remove this column - userInfo?
        table.column("envelopeData", .blob)
        table.column("errorType", .integer)
        table.column("expireStartedAt", .integer)
        table.column("expiresAt", .integer)
        table.column("expiresInSeconds", .integer)
        table.column("groupMetaMessage", .integer)
        // GRDB TODO remove this column? We'd have to migrate the legacy values.
        table.column("hasLegacyMessageState", .integer)
        table.column("hasSyncedTranscript", .integer)
        table.column("isFromLinkedDevice", .integer)
        // GRDB TODO remove this column - userInfo?
        table.column("isLocalChange", .integer)
        table.column("isViewOnceComplete", .integer)
        table.column("isViewOnceMessage", .integer)
        table.column("isVoiceMessage", .integer)
        table.column("legacyMessageState", .integer)
        table.column("legacyWasDelivered", .integer)
        table.column("linkPreview", .blob)
        // GRDB TODO remove this column - userInfo?
        table.column("messageId", .text)
        table.column("messageSticker", .blob)
        table.column("messageType", .integer)
        // GRDB TODO remove this column - userInfo?
        table.column("mostRecentFailureText", .text)
        // GRDB TODO remove this column - userInfo?
        table.column("preKeyBundle", .blob)
        // GRDB TODO remove this column - userInfo?
        table.column("protocolVersion", .integer)
        table.column("quotedMessage", .blob)
        table.column("read", .integer)
        table.column("recipientAddress", .blob)
        table.column("recipientAddressStates", .blob)
        // GRDB TODO remove this column - userInfo?
        table.column("sender", .blob)
        table.column("serverTimestamp", .integer)
        table.column("sourceDeviceId", .integer)
        table.column("storedMessageState", .integer)
        table.column("storedShouldStartExpireTimer", .integer)
        table.column("unregisteredAddress", .blob)
        // GRDB TODO remove this column - userInfo?
        table.column("verificationState", .integer)
        table.column("wasReceivedByUD", .integer)
    }
    try db.create(index: "index_model_TSInteraction_on_uniqueId", on: "model_TSInteraction", columns: ["uniqueId"])

    try db.create(table: "model_StickerPack") { table in
        table.autoIncrementedPrimaryKey("id")
            .notNull()
        table.column("recordType", .integer)
            .notNull()
        table.column("uniqueId", .text)
            .notNull()
            .unique(onConflict: .fail)
        table.column("author", .text)
        table.column("cover", .blob)
            .notNull()
        table.column("dateCreated", .double)
            .notNull()
        table.column("info", .blob)
            .notNull()
        table.column("isInstalled", .integer)
            .notNull()
        table.column("items", .blob)
            .notNull()
        table.column("title", .text)
    }
    try db.create(index: "index_model_StickerPack_on_uniqueId", on: "model_StickerPack", columns: ["uniqueId"])

    try db.create(table: "model_InstalledSticker") { table in
        table.autoIncrementedPrimaryKey("id")
            .notNull()
        table.column("recordType", .integer)
            .notNull()
        table.column("uniqueId", .text)
            .notNull()
            .unique(onConflict: .fail)
        table.column("emojiString", .text)
        table.column("info", .blob)
            .notNull()
    }
    try db.create(index: "index_model_InstalledSticker_on_uniqueId", on: "model_InstalledSticker", columns: ["uniqueId"])

    try db.create(table: "model_KnownStickerPack") { table in
        table.autoIncrementedPrimaryKey("id")
            .notNull()
        table.column("recordType", .integer)
            .notNull()
        table.column("uniqueId", .text)
            .notNull()
            .unique(onConflict: .fail)
        table.column("dateCreated", .double)
            .notNull()
        table.column("info", .blob)
            .notNull()
        table.column("referenceCount", .integer)
            .notNull()
    }
    try db.create(index: "index_model_KnownStickerPack_on_uniqueId", on: "model_KnownStickerPack", columns: ["uniqueId"])

    try db.create(table: "model_TSAttachment") { table in
        table.autoIncrementedPrimaryKey("id")
            .notNull()
        table.column("recordType", .integer)
            .notNull()
        table.column("uniqueId", .text)
            .notNull()
            .unique(onConflict: .fail)
        table.column("albumMessageId", .text)
        table.column("attachmentType", .integer)
            .notNull()
        table.column("blurHash", .text)
        table.column("byteCount", .integer)
            .notNull()
        table.column("caption", .text)
        table.column("contentType", .text)
            .notNull()
        table.column("encryptionKey", .blob)
        table.column("serverId", .integer)
            .notNull()
        table.column("sourceFilename", .text)
        table.column("cachedAudioDurationSeconds", .double)
        table.column("cachedImageHeight", .double)
        table.column("cachedImageWidth", .double)
        table.column("creationTimestamp", .double)
        table.column("digest", .blob)
        table.column("isUploaded", .integer)
        table.column("isValidImageCached", .integer)
        table.column("isValidVideoCached", .integer)
        // GRDB TODO remove this column? Add back once we have working restore? There are some, ultimately unused,
        // unused finder methods which references this field.
        table.column("lazyRestoreFragmentId", .text)
        table.column("localRelativeFilePath", .text)
        // GRDB TODO why do we have mediaSize *and* cachedImageHeight/cachedImageWidth? Seems redundant.
        table.column("mediaSize", .blob)
        // GRDB TODO remove this column? Add back once we have working restore?
        table.column("pointerType", .integer)
        table.column("state", .integer)
    }
    try db.create(index: "index_model_TSAttachment_on_uniqueId", on: "model_TSAttachment", columns: ["uniqueId"])

    try db.create(table: "model_SSKJobRecord") { table in
        table.autoIncrementedPrimaryKey("id")
            .notNull()
        table.column("recordType", .integer)
            .notNull()
        table.column("uniqueId", .text)
            .notNull()
            .unique(onConflict: .fail)
        table.column("failureCount", .integer)
            .notNull()
        table.column("label", .text)
            .notNull()
        table.column("status", .integer)
            .notNull()
        table.column("attachmentIdMap", .blob)
        // GRDB TODO remove this column? Migrate existing data to share "threadId" column used by other jobs
        table.column("contactThreadId", .text)
        table.column("envelopeData", .blob)
        table.column("invisibleMessage", .blob)
        table.column("messageId", .text)
        table.column("removeMessageAfterSending", .integer)
        table.column("threadId", .text)
    }
    try db.create(index: "index_model_SSKJobRecord_on_uniqueId", on: "model_SSKJobRecord", columns: ["uniqueId"])

    try db.create(table: "model_OWSMessageContentJob") { table in
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
    try db.create(index: "index_model_OWSMessageContentJob_on_uniqueId", on: "model_OWSMessageContentJob", columns: ["uniqueId"])

    try db.create(table: "model_OWSRecipientIdentity") { table in
        table.autoIncrementedPrimaryKey("id")
            .notNull()
        table.column("recordType", .integer)
            .notNull()
        table.column("uniqueId", .text)
            .notNull()
            .unique(onConflict: .fail)
        table.column("accountId", .text)
            .notNull()
        table.column("createdAt", .double)
            .notNull()
        table.column("identityKey", .blob)
            .notNull()
        table.column("isFirstKnownKey", .integer)
            .notNull()
        table.column("verificationState", .integer)
            .notNull()
    }
    try db.create(index: "index_model_OWSRecipientIdentity_on_uniqueId", on: "model_OWSRecipientIdentity", columns: ["uniqueId"])

    try db.create(table: "model_ExperienceUpgrade") { table in
        table.autoIncrementedPrimaryKey("id")
            .notNull()
        table.column("recordType", .integer)
            .notNull()
        table.column("uniqueId", .text)
            .notNull()
            .unique(onConflict: .fail)
    }
    try db.create(index: "index_model_ExperienceUpgrade_on_uniqueId", on: "model_ExperienceUpgrade", columns: ["uniqueId"])

    try db.create(table: "model_OWSDisappearingMessagesConfiguration") { table in
        table.autoIncrementedPrimaryKey("id")
            .notNull()
        table.column("recordType", .integer)
            .notNull()
        table.column("uniqueId", .text)
            .notNull()
            .unique(onConflict: .fail)
        table.column("durationSeconds", .integer)
            .notNull()
        table.column("enabled", .integer)
            .notNull()
    }
    try db.create(index: "index_model_OWSDisappearingMessagesConfiguration_on_uniqueId", on: "model_OWSDisappearingMessagesConfiguration", columns: ["uniqueId"])

    try db.create(table: "model_SignalRecipient") { table in
        table.autoIncrementedPrimaryKey("id")
            .notNull()
        table.column("recordType", .integer)
            .notNull()
        table.column("uniqueId", .text)
            .notNull()
            .unique(onConflict: .fail)
        table.column("devices", .blob)
            .notNull()
        table.column("recipientPhoneNumber", .text)
        table.column("recipientUUID", .text)
    }
    try db.create(index: "index_model_SignalRecipient_on_uniqueId", on: "model_SignalRecipient", columns: ["uniqueId"])

    try db.create(table: "model_SignalAccount") { table in
        table.autoIncrementedPrimaryKey("id")
            .notNull()
        table.column("recordType", .integer)
            .notNull()
        table.column("uniqueId", .text)
            .notNull()
            .unique(onConflict: .fail)
        // GRDB how big are these serialized contacts?
        table.column("contact", .blob)
        table.column("contactAvatarHash", .blob)
        table.column("contactAvatarJpegData", .blob)
        table.column("multipleAccountLabelText", .text)
            .notNull()
        table.column("recipientPhoneNumber", .text)
        table.column("recipientUUID", .text)
    }
    try db.create(index: "index_model_SignalAccount_on_uniqueId", on: "model_SignalAccount", columns: ["uniqueId"])

    try db.create(table: "model_OWSUserProfile") { table in
        table.autoIncrementedPrimaryKey("id")
            .notNull()
        table.column("recordType", .integer)
            .notNull()
        table.column("uniqueId", .text)
            .notNull()
            .unique(onConflict: .fail)
        table.column("avatarFileName", .text)
        table.column("avatarUrlPath", .text)
        table.column("profileKey", .blob)
        table.column("profileName", .text)
        table.column("recipientPhoneNumber", .text)
        table.column("recipientUUID", .text)
        table.column("username", .text)
    }
    try db.create(index: "index_model_OWSUserProfile_on_uniqueId", on: "model_OWSUserProfile", columns: ["uniqueId"])

    try db.create(table: "model_TSRecipientReadReceipt") { table in
        table.autoIncrementedPrimaryKey("id")
            .notNull()
        table.column("recordType", .integer)
            .notNull()
        table.column("uniqueId", .text)
            .notNull()
            .unique(onConflict: .fail)
        table.column("recipientMap", .blob)
            .notNull()
        table.column("sentTimestamp", .integer)
            .notNull()
    }
    try db.create(index: "index_model_TSRecipientReadReceipt_on_uniqueId", on: "model_TSRecipientReadReceipt", columns: ["uniqueId"])

    try db.create(table: "model_OWSLinkedDeviceReadReceipt") { table in
        table.autoIncrementedPrimaryKey("id")
            .notNull()
        table.column("recordType", .integer)
            .notNull()
        table.column("uniqueId", .text)
            .notNull()
            .unique(onConflict: .fail)
        table.column("messageIdTimestamp", .integer)
            .notNull()
        table.column("readTimestamp", .integer)
            .notNull()
        table.column("senderPhoneNumber", .text)
        table.column("senderUUID", .text)
    }
    try db.create(index: "index_model_OWSLinkedDeviceReadReceipt_on_uniqueId", on: "model_OWSLinkedDeviceReadReceipt", columns: ["uniqueId"])

    try db.create(table: "model_OWSDevice") { table in
        table.autoIncrementedPrimaryKey("id")
            .notNull()
        table.column("recordType", .integer)
            .notNull()
        table.column("uniqueId", .text)
            .notNull()
            .unique(onConflict: .fail)
        table.column("createdAt", .double)
            .notNull()
        table.column("deviceId", .integer)
            .notNull()
        table.column("lastSeenAt", .double)
            .notNull()
        table.column("name", .text)
    }
    try db.create(index: "index_model_OWSDevice_on_uniqueId", on: "model_OWSDevice", columns: ["uniqueId"])

    // GRDB TODO remove this table/class?
    try db.create(table: "model_OWSContactQuery") { table in
        table.autoIncrementedPrimaryKey("id")
            .notNull()
        table.column("recordType", .integer)
            .notNull()
        table.column("uniqueId", .text)
            .notNull()
            .unique(onConflict: .fail)
        table.column("lastQueried", .double)
            .notNull()
        table.column("nonce", .blob)
            .notNull()
    }
    try db.create(index: "index_model_OWSContactQuery_on_uniqueId", on: "model_OWSContactQuery", columns: ["uniqueId"])

    // GRDB TODO remove this table for prod?
    try db.create(table: "model_TestModel") { table in
        table.autoIncrementedPrimaryKey("id")
            .notNull()
        table.column("recordType", .integer)
            .notNull()
        table.column("uniqueId", .text)
            .notNull()
            .unique(onConflict: .fail)
        table.column("dateValue", .double)
        table.column("doubleValue", .double)
            .notNull()
        table.column("floatValue", .double)
            .notNull()
        table.column("int64Value", .integer)
            .notNull()
        table.column("nsIntegerValue", .integer)
            .notNull()
        table.column("nsNumberValueUsingInt64", .integer)
        table.column("nsNumberValueUsingUInt64", .integer)
        table.column("nsuIntegerValue", .integer)
            .notNull()
        table.column("uint64Value", .integer)
            .notNull()
    }
    try db.create(index: "index_model_TestModel_on_uniqueId", on: "model_TestModel", columns: ["uniqueId"])

    // MARK: - Indices

    try db.create(index: "index_interactions_on_threadUniqueId_and_id",
                  on: InteractionRecord.databaseTableName,
                  columns: [
                    InteractionRecord.columnName(.threadUniqueId),
                    InteractionRecord.columnName(.id)
    ])

    // Durable Job Queue

    try db.create(index: "index_jobs_on_label_and_id",
                  on: JobRecordRecord.databaseTableName,
                  columns: [JobRecordRecord.columnName(.label),
                            JobRecordRecord.columnName(.id)])

    try db.create(index: "index_jobs_on_status_and_label_and_id",
                  on: JobRecordRecord.databaseTableName,
                  columns: [JobRecordRecord.columnName(.label),
                            JobRecordRecord.columnName(.status),
                            JobRecordRecord.columnName(.id)])

    // View Once
    try db.create(index: "index_interactions_on_view_once",
                  on: InteractionRecord.databaseTableName,
                  columns: [
                    InteractionRecord.columnName(.isViewOnceMessage),
                    InteractionRecord.columnName(.isViewOnceComplete)
    ])
    try db.create(index: "index_key_value_store_on_collection_and_key",
                  on: SDSKeyValueStore.table.tableName,
                  columns: [
                    SDSKeyValueStore.collectionColumn.columnName,
                    SDSKeyValueStore.keyColumn.columnName
    ])
    try db.create(index: "index_interactions_on_recordType_and_threadUniqueId_and_errorType",
                  on: InteractionRecord.databaseTableName,
                  columns: [
                    InteractionRecord.columnName(.recordType),
                    InteractionRecord.columnName(.threadUniqueId),
                    InteractionRecord.columnName(.errorType)
    ])

    // Media Gallery Indices
    try db.create(index: "index_attachments_on_albumMessageId",
                  on: AttachmentRecord.databaseTableName,
                  columns: [AttachmentRecord.columnName(.albumMessageId),
                            AttachmentRecord.columnName(.recordType)])

    try db.create(index: "index_interactions_on_uniqueId_and_threadUniqueId",
                  on: InteractionRecord.databaseTableName,
                  columns: [
                    InteractionRecord.columnName(.threadUniqueId),
                    InteractionRecord.columnName(.uniqueId)
    ])

    // Signal Account Indices
    try db.create(
        index: "index_signal_accounts_on_recipientPhoneNumber",
        on: SignalAccountRecord.databaseTableName,
        columns: [SignalAccountRecord.columnName(.recipientPhoneNumber)]
    )

    try db.create(
        index: "index_signal_accounts_on_recipientUUID",
        on: SignalAccountRecord.databaseTableName,
        columns: [SignalAccountRecord.columnName(.recipientUUID)]
    )

    // Signal Recipient Indices
    try db.create(
        index: "index_signal_recipients_on_recipientPhoneNumber",
        on: SignalRecipientRecord.databaseTableName,
        columns: [SignalRecipientRecord.columnName(.recipientPhoneNumber)]
    )

    try db.create(
        index: "index_signal_recipients_on_recipientUUID",
        on: SignalRecipientRecord.databaseTableName,
        columns: [SignalRecipientRecord.columnName(.recipientUUID)]
    )

    // Thread Indices
    try db.create(
        index: "index_thread_on_contactPhoneNumber",
        on: ThreadRecord.databaseTableName,
        columns: [ThreadRecord.columnName(.contactPhoneNumber)]
    )

    try db.create(
        index: "index_thread_on_contactUUID",
        on: ThreadRecord.databaseTableName,
        columns: [ThreadRecord.columnName(.contactUUID)]
    )

    try db.create(
        index: "index_thread_on_shouldThreadBeVisible",
        on: ThreadRecord.databaseTableName,
        columns: [
            ThreadRecord.columnName(.shouldThreadBeVisible),
            ThreadRecord.columnName(.isArchived),
            ThreadRecord.columnName(.lastInteractionRowId)
        ]
    )

    // User Profile
    try db.create(
        index: "index_user_profiles_on_recipientPhoneNumber",
        on: UserProfileRecord.databaseTableName,
        columns: [UserProfileRecord.columnName(.recipientPhoneNumber)]
    )

    try db.create(
        index: "index_user_profiles_on_recipientUUID",
        on: UserProfileRecord.databaseTableName,
        columns: [UserProfileRecord.columnName(.recipientUUID)]
    )

    try db.create(
        index: "index_user_profiles_on_username",
        on: UserProfileRecord.databaseTableName,
        columns: [UserProfileRecord.columnName(.username)]
    )

    // Interaction Finder
    try db.create(index: "index_interactions_on_timestamp_sourceDeviceId_and_authorUUID",
                  on: InteractionRecord.databaseTableName,
                  columns: [
                    InteractionRecord.columnName(.timestamp),
                    InteractionRecord.columnName(.sourceDeviceId),
                    InteractionRecord.columnName(.authorUUID)
    ])

    try db.create(index: "index_interactions_on_timestamp_sourceDeviceId_and_authorPhoneNumber",
                  on: InteractionRecord.databaseTableName,
                  columns: [
                    InteractionRecord.columnName(.timestamp),
                    InteractionRecord.columnName(.sourceDeviceId),
                    InteractionRecord.columnName(.authorPhoneNumber)
    ])
    try db.create(index: "index_interactions_unread_counts",
                  on: InteractionRecord.databaseTableName,
                  columns: [
                    InteractionRecord.columnName(.read),
                    InteractionRecord.columnName(.threadUniqueId),
                    InteractionRecord.columnName(.recordType)
    ])

    // Disappearing Messages
    try db.create(index: "index_interactions_on_expiresInSeconds_and_expiresAt",
                  on: InteractionRecord.databaseTableName,
                  columns: [
                    InteractionRecord.columnName(.expiresAt),
                    InteractionRecord.columnName(.expiresInSeconds)
    ])
    try db.create(index: "index_interactions_on_threadUniqueId_storedShouldStartExpireTimer_and_expiresAt",
                  on: InteractionRecord.databaseTableName,
                  columns: [
                    InteractionRecord.columnName(.expiresAt),
                    InteractionRecord.columnName(.expireStartedAt),
                    InteractionRecord.columnName(.storedShouldStartExpireTimer),
                    InteractionRecord.columnName(.threadUniqueId)
    ])

    // ContactQuery
    try db.create(index: "index_contact_queries_on_lastQueried",
                  on: "model_OWSContactQuery",
                  columns: ["lastQueried"])

    // Backup
    try db.create(index: "index_attachments_on_lazyRestoreFragmentId",
                  on: AttachmentRecord.databaseTableName,
                  columns: [
                    AttachmentRecord.columnName(.lazyRestoreFragmentId)
    ])

    try db.create(virtualTable: "signal_grdb_fts", using: FTS5()) { table in
        // We could use FTS5TokenizerDescriptor.porter(wrapping: FTS5TokenizerDescriptor.unicode61())
        //
        // Porter does stemming (e.g. "hunting" will match "hunter").
        // unicode61 will remove diacritics (e.g. "senor" will match "señor").
        //
        // GRDB TODO: Should we do stemming?
        let tokenizer = FTS5TokenizerDescriptor.unicode61()
        table.tokenizer = tokenizer

        table.column("collection").notIndexed()
        table.column("uniqueId").notIndexed()
        table.column("ftsIndexableContent")
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

            try GRDBMediaGalleryFinder.insertGalleryRecord(attachmentStream: attachmentStream, transaction: transaction)
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
