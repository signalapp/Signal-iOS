//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDB

@objc
public class GRDBSchemaMigrator: NSObject {

    var grdbStorage: GRDBDatabaseStorageAdapter {
        return SDSDatabaseStorage.shared.grdbStorage
    }

    @objc
    public func runMigrationsForNewUser() {
        try! newUserMigrator.migrate(grdbStorage.pool)
    }

    @objc
    public func runOutstandingMigrationsForExistingUser() {
        try! incrementalMigrator.migrate(grdbStorage.pool)
    }

    // MARK: -

    private enum MigrationId: String, CaseIterable {
        case createInitialSchema
    }

    // For new users, we import the latest schema with the first migration
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
            migrator.registerMigration(migrationId.rawValue) { id in
                Logger.info("skipping migration: \(id) for new user.")
                // no-op
            }
        }

        return migrator
    }()

    // Used by existing users to incrementally update from their existing schema
    // to the latest.
    private lazy var incrementalMigrator: DatabaseMigrator = {
        var migrator = DatabaseMigrator()
        migrator.registerMigration(MigrationId.createInitialSchema.rawValue) { _ in
            owsFail("This migration should have already been run by the last YapDB migration.")
            // try createV1Schema(db: db)
        }
        return migrator
    }()

    // Create the v1 schema before running the YDB to GRDB migration.
    public func runCreateV1SchemaMigration() throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration(MigrationId.createInitialSchema.rawValue) { db in
            Logger.info("migrating initial schema")
            try createV1Schema(db: db)
        }
        try migrator.migrate(grdbStorage.pool)
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
        // GRDB TODO remove this column
        table.column("archivalDate", .double)
        table.column("conversationColorName", .text)
            .notNull()
        table.column("creationDate", .double)
        table.column("isArchived", .integer)
            .notNull()
        table.column("isArchivedByLegacyTimestampForSorting", .integer)
            .notNull()
        table.column("lastInteractionRowId", .integer)
            .notNull()
        table.column("lastMessageDate", .double)
        table.column("messageDraft", .text)
        table.column("mutedUntilDate", .double)
        table.column("shouldThreadBeVisible", .integer)
            .notNull()
        table.column("contactPhoneNumber", .text)
        // GRDB TODO remove this column?
        table.column("contactThreadSchemaVersion", .integer)
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
        // GRDB TODO remove this column?
        table.column("beforeInteractionId", .text)
        table.column("body", .text)
        // GRDB TODO remove this column?
        table.column("callSchemaVersion", .integer)
        table.column("callType", .integer)
        // GRDB TODO remove this column - userInfo?
        table.column("configurationDurationSeconds", .integer)
        // GRDB TODO remove this column - userInfo?
        table.column("configurationIsEnabled", .integer)
        // GRDB TODO remove this column - userInfo?
        table.column("contactId", .text)
        table.column("contactShare", .blob)
        // GRDB TODO remove this column - userInfo?
        table.column("createdByRemoteName", .text)
        // GRDB TODO remove this column - userInfo?
        table.column("createdInExistingGroup", .integer)
        // GRDB TODO remove this column - userInfo?
        table.column("customMessage", .text)
        // GRDB TODO remove this column - userInfo?
        table.column("envelopeData", .blob)
        // GRDB TODO remove this column
        table.column("errorMessageSchemaVersion", .integer)
        table.column("errorType", .integer)
        table.column("expireStartedAt", .integer)
        table.column("expiresAt", .integer)
        table.column("expiresInSeconds", .integer)
        table.column("groupMetaMessage", .integer)
        // GRDB TODO remove this column?
        table.column("hasAddToContactsOffer", .integer)
        // GRDB TODO remove this column?
        table.column("hasAddToProfileWhitelistOffer", .integer)
        // GRDB TODO remove this column?
        table.column("hasBlockOffer", .integer)
        // GRDB TODO remove this column?
        table.column("hasLegacyMessageState", .integer)
        // GRDB TODO remove this column?
        table.column("hasSyncedTranscript", .integer)
        // GRDB TODO remove this column?
        table.column("incomingMessageSchemaVersion", .integer)
        // GRDB TODO remove this column?
        table.column("infoMessageSchemaVersion", .integer)
        // GRDB TODO - do we really need to persist this? It only affects scroll behavior
        // when first appearing
        table.column("isFromLinkedDevice", .integer)
        // GRDB TODO remove this column - userInfo?
        table.column("isLocalChange", .integer)
        table.column("isViewOnceComplete", .integer)
        table.column("isViewOnceMessage", .integer)
        table.column("isVoiceMessage", .integer)
        // GRDB TODO remove this column
        table.column("legacyMessageState", .integer)
        // GRDB TODO remove this column
        table.column("legacyWasDelivered", .integer)
        table.column("linkPreview", .blob)
        // GRDB TODO what is messageId?
        table.column("messageId", .text)
        table.column("messageSticker", .blob)
        table.column("messageType", .integer)
        // GRDB TODO remove this column - userInfo?
        table.column("mostRecentFailureText", .text)
        // GRDB TODO remove this column
        table.column("outgoingMessageSchemaVersion", .integer)
        // GRDB TODO remove this column - userInfo?
        table.column("preKeyBundle", .blob)
        // GRDB TODO remove this column - userInfo?
        table.column("protocolVersion", .integer)
        table.column("quotedMessage", .blob)
        table.column("read", .integer)
        table.column("recipientAddress", .blob)
        table.column("recipientAddressStates", .blob)
        // GRDB TODO remove this column
        table.column("schemaVersion", .integer)
        // GRDB TODO remove this column - userInfo?
        table.column("sender", .blob)
        table.column("serverTimestamp", .integer)
        table.column("sourceDeviceId", .integer)
        table.column("storedMessageState", .integer)
        table.column("storedShouldStartExpireTimer", .integer)
        // GRDB TODO remove this column
        table.column("unknownProtocolVersionMessageSchemaVersion", .integer)
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
        // GRDB TODO remove this column
        table.column("attachmentSchemaVersion", .integer)
            .notNull()
        table.column("attachmentType", .integer)
            .notNull()
        table.column("blurHash", .text)
        table.column("byteCount", .integer)
            .notNull()
        table.column("caption", .text)
        table.column("contentType", .text)
            .notNull()
        table.column("encryptionKey", .blob)
        // GRDB TODO remove this column? Redundant with TSAttachmentStream vs. pointer?
        table.column("isDownloaded", .integer)
            .notNull()
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
        // GRDB TODO remove this column? Add back once we have working restore?
        table.column("lazyRestoreFragmentId", .text)
        table.column("localRelativeFilePath", .text)
        table.column("mediaSize", .blob)
        table.column("mostRecentFailureLocalizedText", .text)
        // GRDB TODO remove this column? Does this need to be persisted?
        table.column("pointerType", .integer)
        // GRDB TODO remove this column? Does this need to be persisted?
        table.column("shouldAlwaysPad", .integer)
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
        // GRDB TODO remove this column? redundant with threadId?
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
        // GRDB TODO remove this column?
        table.column("recipientIdentitySchemaVersion", .integer)
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
        table.column("recipientSchemaVersion", .integer)
            .notNull()
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
        // GRDB TODO remove this column
        table.column("accountSchemaVersion", .integer)
            .notNull()
        table.column("contact", .blob)
        table.column("hasMultipleAccountContact", .integer)
            .notNull()
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
        // GRDB TODO remove this column? Does this need to be persisted?
        table.column("userProfileSchemaVersion", .integer)
            .notNull()
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
        // GRDB TODO remove this column? Does this need to be persisted?
        table.column("recipientReadReceiptSchemaVersion", .integer)
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
        // GRDB TODO remove this column? Does this need to be persisted?
        table.column("linkedDeviceReadReceiptSchemaVersion", .integer)
            .notNull()
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

    // Linked Device Read Receipts
    try db.create(
        index: "index_linkedDeviceReadReceipt_on_senderPhoneNumberAndTimestamp",
        on: LinkedDeviceReadReceiptRecord.databaseTableName,
        columns: [LinkedDeviceReadReceiptRecord.columnName(.senderPhoneNumber), LinkedDeviceReadReceiptRecord.columnName(.messageIdTimestamp)]
    )

    try db.create(
        index: "index_linkedDeviceReadReceipt_on_senderUUIDAndTimestamp",
        on: LinkedDeviceReadReceiptRecord.databaseTableName,
        columns: [LinkedDeviceReadReceiptRecord.columnName(.senderUUID), LinkedDeviceReadReceiptRecord.columnName(.messageIdTimestamp)]
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
                  on: ContactQueryRecord.databaseTableName,
                  columns: [
                    ContactQueryRecord.columnName(.lastQueried)
        ])

    // Backup
    try db.create(index: "index_attachments_on_lazyRestoreFragmentId",
                  on: AttachmentRecord.databaseTableName,
                  columns: [
                    AttachmentRecord.columnName(.lazyRestoreFragmentId)
        ])

    try GRDBFullTextSearchFinder.createTables(database: db)
}
