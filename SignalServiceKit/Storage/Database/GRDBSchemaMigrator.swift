//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import LibSignalClient

public class GRDBSchemaMigrator {

    public static let migrationSideEffectsCollectionName = "MigrationSideEffects"
    public static let avatarRepairAttemptCount = "Avatar Repair Attempt Count"

    /// Migrate a database to the latest version. Throws if migrations fail.
    ///
    /// - Parameter databaseStorage: The database to migrate.
    /// - Parameter runDataMigrations: A boolean indicating whether to include data migrations. Typically, you want to omit this value or set it to `true`, but we want to skip them when recovering a corrupted database.
    /// - Returns: `true` if incremental migrations were performed, and `false` otherwise.
    @discardableResult
    static func migrateDatabase(
        databaseStorage: SDSDatabaseStorage,
        runDataMigrations: Bool = true,
    ) throws -> Bool {
        return try runIncrementalMigrations(databaseStorage: databaseStorage, runDataMigrations: runDataMigrations)
    }

    private static func runIncrementalMigrations(
        databaseStorage: SDSDatabaseStorage,
        runDataMigrations: Bool,
    ) throws -> Bool {
        return try _runIncrementalMigrations(
            databaseWriter: databaseStorage.grdbStorage.pool,
            runDataMigrations: runDataMigrations,
        )
    }

#if TESTABLE_BUILD
    static func runIncrementalMigrations(databaseWriter: some DatabaseWriter) throws {
        _ = try _runIncrementalMigrations(databaseWriter: databaseWriter, runDataMigrations: false)
    }
#endif

    private static func _runIncrementalMigrations(
        databaseWriter: some DatabaseWriter,
        runDataMigrations: Bool,
    ) throws -> Bool {
        let previouslyAppliedMigrations = try databaseWriter.read { database in
            try DatabaseMigrator().appliedIdentifiers(database)
        }

        // First do the schema migrations. (See the comment within MigrationId for why schema and data
        // migrations are separate.)
        let incrementalMigrator = DatabaseMigratorWrapper()
        registerSchemaMigrations(migrator: incrementalMigrator)
        try incrementalMigrator.migrate(databaseWriter)

        if runDataMigrations {
            // Finally, do data migrations.
            registerDataMigrations(migrator: incrementalMigrator)
            try incrementalMigrator.migrate(databaseWriter)
        }

        let allAppliedMigrations = try databaseWriter.read { database in
            try DatabaseMigrator().appliedIdentifiers(database)
        }

        return allAppliedMigrations != previouslyAppliedMigrations
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
        case createDonationReceiptTable
        case addBoostAmountToSubscriptionDurableJob
        case updateConversationLoadInteractionCountIndex
        case updateConversationLoadInteractionDistanceIndex
        case updateConversationUnreadCountIndex
        case addStoryContextIndexToInteractions
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
        case addUsernameLookupRecordsTable
        case dropUsernameColumnFromOWSUserProfile
        case migrateVoiceMessageDrafts
        case addIsPniCapableColumnToOWSUserProfile
        case addStoryMessageReplyCount
        case populateStoryMessageReplyCount
        case addIndexToFindFailedAttachments
        case addEditMessageChanges
        case dropMessageSendLogTriggers
        case threadReplyInfoServiceIds
        case updateEditMessageUnreadIndex
        case updateEditRecordTable
        case threadReplyEditTarget
        case addHiddenRecipientsTable
        case editRecordReadState
        case addPaymentModelInteractionUniqueId
        case addPaymentsActivationRequestModel
        case addRecipientPniColumn
        case deletePhoneNumberAccessStore
        case dropOldAndCreateNewCallRecordTable
        case fixUniqueConstraintOnCallRecord
        case addTimestampToCallRecord
        case addPaymentMethodToJobRecords
        case addIsNewSubscriptionToJobRecords
        case enableFts5SecureDelete
        case addShouldSuppressPaymentAlreadyRedeemedToJobRecords
        case addGroupCallRingerAciToCallRecords
        case renameIsFromLinkedDevice
        case renameAndDeprecateSourceDeviceId
        case addCallRecordQueryIndices
        case addDeletedCallRecordTable
        case addFirstDeletedIndexToDeletedCallRecord
        case addCallRecordDeleteAllColumnsToJobRecord
        case addPhoneNumberSharingAndDiscoverability
        case removeRedundantPhoneNumbers2
        case scheduleFullIntersection
        case addUnreadToCallRecord
        case addSearchableName
        case addCallRecordRowIdColumnToCallRecordDeleteAllJobRecord
        case markAllGroupCallMessagesAsRead
        case addIndexForUnreadByThreadRowIdToCallRecord
        case addNicknamesTable
        case expandSignalAccountContactFields
        case addNicknamesToSearchableName
        case addAttachmentMetadataColumnsToIncomingContactSyncJobRecord
        case removeRedundantPhoneNumbers3
        case addV2AttachmentTable
        case addBulkDeleteInteractionJobRecord
        case cleanUpThreadIndexes
        case addOrphanAttachmentPendingColumn
        case cleanUpUniqueIndexes
        case dropTableTestModel
        case addOriginalAttachmentIdForQuotedReplyColumn
        case addClientUuidToTSAttachment
        case recreateMessageAttachmentReferenceMediaGalleryIndexes
        case addAttachmentDownloadQueue
        case attachmentAddCdnUnencryptedByteCounts
        case addArchivedPaymentInfoColumn
        case createArchivedPaymentTable
        case removeDeadEndGroupThreadIdMappings
        case addTSAttachmentMigrationTable
        case indexMessageAttachmentReferenceByReceivedAtTimestamp
        case addBackupAttachmentDownloadQueue
        case createAttachmentUploadRecordTable
        case addBlockedRecipient
        case addDmTimerVersionColumn
        case addVersionedDMTimer
        case addDMTimerVersionToInteractionTable
        case initializeDMTimerVersion
        case attachmentAddMediaTierDigest
        case removeVoIPToken
        case reorderMediaTierDigestColumn
        case addIncrementalMacParamsToAttachment
        case splitIncrementalMacAttachmentColumns
        case addCallEndedTimestampToCallRecord
        case addIsViewOnceColumnToMessageAttachmentReference
        case backfillIsViewOnceMessageAttachmentReference
        case addAttachmentValidationBackfillTable
        case addIsSmsColumnToTSAttachment
        case addInKnownMessageRequestStateToHiddenRecipient
        case addBackupAttachmentUploadQueue
        case addBackupStickerPackDownloadQueue
        case createOrphanedBackupAttachmentTable
        case addCallLinkTable
        case deleteIncomingGroupSyncJobRecords
        case deleteKnownStickerPackTable
        case addReceiptCredentialColumnToJobRecord
        case dropOrphanedGroupStoryReplies
        case addMessageBackupAvatarFetchQueue
        case addMessageBackupAvatarFetchQueueRetries
        case addEditStateToMessageAttachmentReference
        case removeVersionedDMTimerCapabilities
        case removeJobRecordTSAttachmentColumns
        case deprecateAttachmentIdsColumn
        case dropMediaGalleryItemTable
        case addBackupsReceiptCredentialStateToJobRecord
        case recreateTSAttachment
        case recreateTSAttachmentMigration
        case addBlockedGroup
        case addGroupSendEndorsement
        case deleteLegacyMessageDecryptJobRecords
        case dropMessageContentJobTable
        case deleteMessageRequestInteractionEpoch
        case addAvatarDefaultColorTable
        case populateAvatarDefaultColorTable
        case addStoryRecipient
        case addAttachmentLastFullscreenViewTimestamp
        case addByteCountAndIsFullsizeToBackupAttachmentUpload
        case refactorBackupAttachmentDownload
        case removeAttachmentMediaTierDigestColumn
        case addListMediaTable
        case recomputeAttachmentMediaNames
        case lastDraftInteractionRowID
        case addBackupOversizeText
        case addBackupOversizeTextRedux
        case addRetriesToBackupAttachmentUploadQueue
        case replaceOWSDeviceTable
        case reindexBackupAttachmentUploadQueue
        case dropAllIncrementalMacs
        case addOriginalTransitTierInfoAttachmentColumns
        case rebuildIncompleteViewOnceIndex
        case addIsPollToTSInteraction
        case addBackupAttachmentUploadQueueStateColumn
        case addBackupAttachmentUploadQueueTrigger
        case migrateRecipientDeviceIds
        case fixUniqueConstraintOnPollVotes
        case migrateTSAccountManagerKeyValueStore
        case populateBackupAttachmentUploadProgressKVStore
        case addPollVoteState
        case addPreKey
        case addKyberPreKeyUse
        case uniquifyUsernameLookupRecord
        case fixUpcomingCallLinks
        case uniquifyUsernameLookupRecord2
        case fixRevokedForRestoredCallLinks
        case fixNameForRestoredCallLinks
        case addPinnedMessagesTable
        case addPinnedAtTimestampToPinnedMessageTable
        case dropTSAttachment
        case deprecateStoredShouldStartExpireTimer
        case addSession
        case addRecipientStatus

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
        case dataMigration_enableV2RegistrationLockIfNecessary
        case dataMigration_resetStorageServiceData
        case dataMigration_markAllInteractionsAsNotDeleted
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
        case dataMigration_syncGroupStories
        case dataMigration_deleteOldGroupCapabilities
        case dataMigration_updateStoriesDisabledInAccountRecord
        case dataMigration_removeGroupStoryRepliesFromSearchIndex
        case dataMigration_populateStoryContextAssociatedDataLastReadTimestamp
        case dataMigration_scheduleStorageServiceUpdateForSystemContacts
        case dataMigration_ensureLocalDeviceId
        case dataMigration_indexSearchableNames
        case dataMigration_removeSystemContacts
        case dataMigration_clearLaunchScreenCache2
        case dataMigration_resetLinkedDeviceAuthorMergeBuilder

// We must ensure that we never re-use a MigrationId. It's unlikely that
// we'll happen to pick the same name twice, but it's possible. We keep old
// MigrationIds here (in DEBUG builds) so that the compiler will complain
// if we ever re-use an existing identifier.
#if DEBUG
        case addColumnsForStoryContext
        case addExclusiveProcessIdentifierToJobRecord
        case addGroupCallMessage
        case addHiddenInteractionColumn
        case addOrphanedBackupAttachmentTable
        case addPaymentModels36
        case addPaymentModels37
        case addPaymentModels39
        case dataMigration_clearLaunchScreenCache
        case dataMigration_disableLinkPreviewForExistingUsers
        case dataMigration_fixThreeSixteenDowngraders
        case dataMigration_kbsStateCleanup
        case dataMigration_markAvatarBuilderMegaphoneCompleteIfNecessary
        case dataMigration_markOnboardedUsers
        case dataMigration_markOnboardedUsers_v2
        case dataMigration_migrateGroupAvatarsToDisk
        case dataMigration_populateLastReceivedStoryTimestamp
        case dataMigration_recordMessageRequestInteractionIdEpoch
        case dataMigration_reindexGroupMembershipAndMigrateLegacyAvatarData
        case dataMigration_rotateStorageServiceKeyAndResetLocalData
        case dataMigration_rotateStorageServiceKeyAndResetLocalDataV2
        case dataMigration_rotateStorageServiceKeyAndResetLocalDataV3
        case experienceUpgradeSnooze
        case indexInfoMessageOnType
        case indexMediaGallery2
        case indexSignalRecipients
        case messageDecryptDeduplication
        case messageDecryptDeduplication2
        case messageDecryptDeduplication3
        case messageDecryptDeduplicationV4
        case messageDecryptDeduplicationV5
        case removeRedundantPhoneNumbers
        case signalAccount_add_contactAvatar
        case signalAccount_add_contactAvatarData
        case signalAccount_add_contactAvatarPngData

        // This used to insert `media_gallery_record` rows for every message
        // attachment. This table is now obsolete.
        case dataMigration_populateGalleryItems

        // These were rolled back in a complex dance of rewriting migration
        // history. See `recreateTSAttachment`.
        case tsMessageAttachmentMigration1
        case tsMessageAttachmentMigration2
        case tsMessageAttachmentMigration3
        case dropTSAttachmentTable

        // Obsoleted by dataMigration_indexSearchableNames.
        case dataMigration_indexSignalRecipients
        case dataMigration_indexMultipleNameComponentsForReceipients
        case dataMigration_indexPrivateStoryThreadNames
        case dataMigration_reindexSignalAccounts

        // Obsoleted by dataMigration_removeSystemContacts.
        case dataMigration_removeLinkedDeviceSystemContacts

        // Obsoleted when we removed the TSAttachment migration.
        case threadWallpaperTSAttachmentMigration1
        case threadWallpaperTSAttachmentMigration2
        case threadWallpaperTSAttachmentMigration3
        case migrateStoryMessageTSAttachments1
        case migrateStoryMessageTSAttachments2
#endif
    }

    public static let grdbSchemaVersionDefault: UInt = 0
    public static let grdbSchemaVersionLatest: UInt = 139

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
            migrate: @escaping (DBWriteTransaction) throws -> Result<Void, Error>,
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
                guard
                    try migrator
                        .appliedIdentifiers(database)
                        .contains(identifier.rawValue)
                        .negated
                else {
                    // Already run! Just succeed.
                    Logger.info("Attempting to re-run an already-finished migration, exiting: \(identifier)")
                    return
                }

                Logger.info("Running migration: \(identifier)")
                let transaction = DBWriteTransaction(database: database)
                defer { transaction.finalizeTransaction() }
                let result = try migrate(transaction)
                switch result {
                case .success:
                    let timeElapsed = CACurrentMediaTime() - startTime
                    let formattedTime = String(format: "%0.2fms", timeElapsed * 1000)
                    Logger.info("Migration completed: \(identifier), duration: \(formattedTime)")
                case .failure(let error):
                    throw error
                }
            }
        }

        func migrate(_ database: DatabaseWriter) throws {
            try migrator.migrate(database)
        }
    }

    private static func registerSchemaMigrations(migrator: DatabaseMigratorWrapper) {

        migrator.registerMigration(.createInitialSchema) { tx in
            let sql = """
            CREATE
                TABLE
                    keyvalue (
                        KEY TEXT NOT NULL
                        ,collection TEXT NOT NULL
                        ,VALUE BLOB NOT NULL
                        ,PRIMARY KEY (
                            KEY
                            ,collection
                        )
                    )
            ;

            CREATE
                TABLE
                    IF NOT EXISTS "model_TSThread" (
                        "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
                        ,"recordType" INTEGER NOT NULL
                        ,"uniqueId" TEXT NOT NULL UNIQUE
                            ON CONFLICT FAIL
                        ,"conversationColorName" TEXT NOT NULL
                        ,"creationDate" DOUBLE
                        ,"isArchived" INTEGER NOT NULL
                        ,"lastInteractionRowId" INTEGER NOT NULL
                        ,"messageDraft" TEXT
                        ,"mutedUntilDate" DOUBLE
                        ,"shouldThreadBeVisible" INTEGER NOT NULL
                        ,"contactPhoneNumber" TEXT
                        ,"contactUUID" TEXT
                        ,"groupModel" BLOB
                        ,"hasDismissedOffers" INTEGER
                    )
            ;

            CREATE
                INDEX "index_model_TSThread_on_uniqueId"
                    ON "model_TSThread"("uniqueId"
            )
            ;

            CREATE
                TABLE
                    IF NOT EXISTS "model_TSInteraction" (
                        "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
                        ,"recordType" INTEGER NOT NULL
                        ,"uniqueId" TEXT NOT NULL UNIQUE
                            ON CONFLICT FAIL
                        ,"receivedAtTimestamp" INTEGER NOT NULL
                        ,"timestamp" INTEGER NOT NULL
                        ,"uniqueThreadId" TEXT NOT NULL
                        ,"attachmentIds" BLOB
                        ,"authorId" TEXT
                        ,"authorPhoneNumber" TEXT
                        ,"authorUUID" TEXT
                        ,"body" TEXT
                        ,"callType" INTEGER
                        ,"configurationDurationSeconds" INTEGER
                        ,"configurationIsEnabled" INTEGER
                        ,"contactShare" BLOB
                        ,"createdByRemoteName" TEXT
                        ,"createdInExistingGroup" INTEGER
                        ,"customMessage" TEXT
                        ,"envelopeData" BLOB
                        ,"errorType" INTEGER
                        ,"expireStartedAt" INTEGER
                        ,"expiresAt" INTEGER
                        ,"expiresInSeconds" INTEGER
                        ,"groupMetaMessage" INTEGER
                        ,"hasLegacyMessageState" INTEGER
                        ,"hasSyncedTranscript" INTEGER
                        ,"isFromLinkedDevice" INTEGER
                        ,"isLocalChange" INTEGER
                        ,"isViewOnceComplete" INTEGER
                        ,"isViewOnceMessage" INTEGER
                        ,"isVoiceMessage" INTEGER
                        ,"legacyMessageState" INTEGER
                        ,"legacyWasDelivered" INTEGER
                        ,"linkPreview" BLOB
                        ,"messageId" TEXT
                        ,"messageSticker" BLOB
                        ,"messageType" INTEGER
                        ,"mostRecentFailureText" TEXT
                        ,"preKeyBundle" BLOB
                        ,"protocolVersion" INTEGER
                        ,"quotedMessage" BLOB
                        ,"read" INTEGER
                        ,"recipientAddress" BLOB
                        ,"recipientAddressStates" BLOB
                        ,"sender" BLOB
                        ,"serverTimestamp" INTEGER
                        ,"sourceDeviceId" INTEGER
                        ,"storedMessageState" INTEGER
                        ,"storedShouldStartExpireTimer" INTEGER
                        ,"unregisteredAddress" BLOB
                        ,"verificationState" INTEGER
                        ,"wasReceivedByUD" INTEGER
                    )
            ;

            CREATE
                INDEX "index_model_TSInteraction_on_uniqueId"
                    ON "model_TSInteraction"("uniqueId"
            )
            ;

            CREATE
                TABLE
                    IF NOT EXISTS "model_StickerPack" (
                        "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
                        ,"recordType" INTEGER NOT NULL
                        ,"uniqueId" TEXT NOT NULL UNIQUE
                            ON CONFLICT FAIL
                        ,"author" TEXT
                        ,"cover" BLOB NOT NULL
                        ,"dateCreated" DOUBLE NOT NULL
                        ,"info" BLOB NOT NULL
                        ,"isInstalled" INTEGER NOT NULL
                        ,"items" BLOB NOT NULL
                        ,"title" TEXT
                    )
            ;

            CREATE
                INDEX "index_model_StickerPack_on_uniqueId"
                    ON "model_StickerPack"("uniqueId"
            )
            ;

            CREATE
                TABLE
                    IF NOT EXISTS "model_InstalledSticker" (
                        "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
                        ,"recordType" INTEGER NOT NULL
                        ,"uniqueId" TEXT NOT NULL UNIQUE
                            ON CONFLICT FAIL
                        ,"emojiString" TEXT
                        ,"info" BLOB NOT NULL
                    )
            ;

            CREATE
                INDEX "index_model_InstalledSticker_on_uniqueId"
                    ON "model_InstalledSticker"("uniqueId"
            )
            ;

            CREATE
                TABLE
                    IF NOT EXISTS "model_KnownStickerPack" (
                        "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
                        ,"recordType" INTEGER NOT NULL
                        ,"uniqueId" TEXT NOT NULL UNIQUE
                            ON CONFLICT FAIL
                        ,"dateCreated" DOUBLE NOT NULL
                        ,"info" BLOB NOT NULL
                        ,"referenceCount" INTEGER NOT NULL
                    )
            ;

            CREATE
                INDEX "index_model_KnownStickerPack_on_uniqueId"
                    ON "model_KnownStickerPack"("uniqueId"
            )
            ;

            CREATE
                TABLE
                    IF NOT EXISTS "model_TSAttachment" (
                        "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
                        ,"recordType" INTEGER NOT NULL
                        ,"uniqueId" TEXT NOT NULL UNIQUE
                            ON CONFLICT FAIL
                        ,"albumMessageId" TEXT
                        ,"attachmentType" INTEGER NOT NULL
                        ,"blurHash" TEXT
                        ,"byteCount" INTEGER NOT NULL
                        ,"caption" TEXT
                        ,"contentType" TEXT NOT NULL
                        ,"encryptionKey" BLOB
                        ,"serverId" INTEGER NOT NULL
                        ,"sourceFilename" TEXT
                        ,"cachedAudioDurationSeconds" DOUBLE
                        ,"cachedImageHeight" DOUBLE
                        ,"cachedImageWidth" DOUBLE
                        ,"creationTimestamp" DOUBLE
                        ,"digest" BLOB
                        ,"isUploaded" INTEGER
                        ,"isValidImageCached" INTEGER
                        ,"isValidVideoCached" INTEGER
                        ,"lazyRestoreFragmentId" TEXT
                        ,"localRelativeFilePath" TEXT
                        ,"mediaSize" BLOB
                        ,"pointerType" INTEGER
                        ,"state" INTEGER
                    )
            ;

            CREATE
                INDEX "index_model_TSAttachment_on_uniqueId"
                    ON "model_TSAttachment"("uniqueId"
            )
            ;

            CREATE
                TABLE
                    IF NOT EXISTS "model_SSKJobRecord" (
                        "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
                        ,"recordType" INTEGER NOT NULL
                        ,"uniqueId" TEXT NOT NULL UNIQUE
                            ON CONFLICT FAIL
                        ,"failureCount" INTEGER NOT NULL
                        ,"label" TEXT NOT NULL
                        ,"status" INTEGER NOT NULL
                        ,"attachmentIdMap" BLOB
                        ,"contactThreadId" TEXT
                        ,"envelopeData" BLOB
                        ,"invisibleMessage" BLOB
                        ,"messageId" TEXT
                        ,"removeMessageAfterSending" INTEGER
                        ,"threadId" TEXT
                    )
            ;

            CREATE
                INDEX "index_model_SSKJobRecord_on_uniqueId"
                    ON "model_SSKJobRecord"("uniqueId"
            )
            ;

            CREATE
                TABLE
                    IF NOT EXISTS "model_OWSMessageContentJob" (
                        "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
                        ,"recordType" INTEGER NOT NULL
                        ,"uniqueId" TEXT NOT NULL UNIQUE
                            ON CONFLICT FAIL
                        ,"createdAt" DOUBLE NOT NULL
                        ,"envelopeData" BLOB NOT NULL
                        ,"plaintextData" BLOB
                        ,"wasReceivedByUD" INTEGER NOT NULL
                    )
            ;

            CREATE
                INDEX "index_model_OWSMessageContentJob_on_uniqueId"
                    ON "model_OWSMessageContentJob"("uniqueId"
            )
            ;

            CREATE
                TABLE
                    IF NOT EXISTS "model_OWSRecipientIdentity" (
                        "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
                        ,"recordType" INTEGER NOT NULL
                        ,"uniqueId" TEXT NOT NULL UNIQUE
                            ON CONFLICT FAIL
                        ,"accountId" TEXT NOT NULL
                        ,"createdAt" DOUBLE NOT NULL
                        ,"identityKey" BLOB NOT NULL
                        ,"isFirstKnownKey" INTEGER NOT NULL
                        ,"verificationState" INTEGER NOT NULL
                    )
            ;

            CREATE
                INDEX "index_model_OWSRecipientIdentity_on_uniqueId"
                    ON "model_OWSRecipientIdentity"("uniqueId"
            )
            ;

            CREATE
                TABLE
                    IF NOT EXISTS "model_ExperienceUpgrade" (
                        "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
                        ,"recordType" INTEGER NOT NULL
                        ,"uniqueId" TEXT NOT NULL UNIQUE
                            ON CONFLICT FAIL
                    )
            ;

            CREATE
                INDEX "index_model_ExperienceUpgrade_on_uniqueId"
                    ON "model_ExperienceUpgrade"("uniqueId"
            )
            ;

            CREATE
                TABLE
                    IF NOT EXISTS "model_OWSDisappearingMessagesConfiguration" (
                        "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
                        ,"recordType" INTEGER NOT NULL
                        ,"uniqueId" TEXT NOT NULL UNIQUE
                            ON CONFLICT FAIL
                        ,"durationSeconds" INTEGER NOT NULL
                        ,"enabled" INTEGER NOT NULL
                    )
            ;

            CREATE
                INDEX "index_model_OWSDisappearingMessagesConfiguration_on_uniqueId"
                    ON "model_OWSDisappearingMessagesConfiguration"("uniqueId"
            )
            ;

            CREATE
                TABLE
                    IF NOT EXISTS "model_SignalRecipient" (
                        "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
                        ,"recordType" INTEGER NOT NULL
                        ,"uniqueId" TEXT NOT NULL UNIQUE
                            ON CONFLICT FAIL
                        ,"devices" BLOB NOT NULL
                        ,"recipientPhoneNumber" TEXT
                        ,"recipientUUID" TEXT
                    )
            ;

            CREATE
                INDEX "index_model_SignalRecipient_on_uniqueId"
                    ON "model_SignalRecipient"("uniqueId"
            )
            ;

            CREATE
                TABLE
                    IF NOT EXISTS "model_SignalAccount" (
                        "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
                        ,"recordType" INTEGER NOT NULL
                        ,"uniqueId" TEXT NOT NULL UNIQUE
                            ON CONFLICT FAIL
                        ,"contact" BLOB
                        ,"multipleAccountLabelText" TEXT NOT NULL
                        ,"recipientPhoneNumber" TEXT
                        ,"recipientUUID" TEXT
                    )
            ;

            CREATE
                INDEX "index_model_SignalAccount_on_uniqueId"
                    ON "model_SignalAccount"("uniqueId"
            )
            ;

            CREATE
                TABLE
                    IF NOT EXISTS "model_OWSUserProfile" (
                        "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
                        ,"recordType" INTEGER NOT NULL
                        ,"uniqueId" TEXT NOT NULL UNIQUE
                            ON CONFLICT FAIL
                        ,"avatarFileName" TEXT
                        ,"avatarUrlPath" TEXT
                        ,"profileKey" BLOB
                        ,"profileName" TEXT
                        ,"recipientPhoneNumber" TEXT
                        ,"recipientUUID" TEXT
                        ,"username" TEXT
                    )
            ;

            CREATE
                INDEX "index_model_OWSUserProfile_on_uniqueId"
                    ON "model_OWSUserProfile"("uniqueId"
            )
            ;

            CREATE
                TABLE
                    IF NOT EXISTS "model_TSRecipientReadReceipt" (
                        "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
                        ,"recordType" INTEGER NOT NULL
                        ,"uniqueId" TEXT NOT NULL UNIQUE
                            ON CONFLICT FAIL
                        ,"recipientMap" BLOB NOT NULL
                        ,"sentTimestamp" INTEGER NOT NULL
                    )
            ;

            CREATE
                INDEX "index_model_TSRecipientReadReceipt_on_uniqueId"
                    ON "model_TSRecipientReadReceipt"("uniqueId"
            )
            ;

            CREATE
                TABLE
                    IF NOT EXISTS "model_OWSLinkedDeviceReadReceipt" (
                        "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
                        ,"recordType" INTEGER NOT NULL
                        ,"uniqueId" TEXT NOT NULL UNIQUE
                            ON CONFLICT FAIL
                        ,"messageIdTimestamp" INTEGER NOT NULL
                        ,"readTimestamp" INTEGER NOT NULL
                        ,"senderPhoneNumber" TEXT
                        ,"senderUUID" TEXT
                    )
            ;

            CREATE
                INDEX "index_model_OWSLinkedDeviceReadReceipt_on_uniqueId"
                    ON "model_OWSLinkedDeviceReadReceipt"("uniqueId"
            )
            ;

            CREATE
                TABLE
                    IF NOT EXISTS "model_OWSDevice" (
                        "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
                        ,"recordType" INTEGER NOT NULL
                        ,"uniqueId" TEXT NOT NULL UNIQUE
                            ON CONFLICT FAIL
                        ,"createdAt" DOUBLE NOT NULL
                        ,"deviceId" INTEGER NOT NULL
                        ,"lastSeenAt" DOUBLE NOT NULL
                        ,"name" TEXT
                    )
            ;

            CREATE
                INDEX "index_model_OWSDevice_on_uniqueId"
                    ON "model_OWSDevice"("uniqueId"
            )
            ;

            CREATE
                TABLE
                    IF NOT EXISTS "model_OWSContactQuery" (
                        "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
                        ,"recordType" INTEGER NOT NULL
                        ,"uniqueId" TEXT NOT NULL UNIQUE
                            ON CONFLICT FAIL
                        ,"lastQueried" DOUBLE NOT NULL
                        ,"nonce" BLOB NOT NULL
                    )
            ;

            CREATE
                INDEX "index_model_OWSContactQuery_on_uniqueId"
                    ON "model_OWSContactQuery"("uniqueId"
            )
            ;

            CREATE
                TABLE
                    IF NOT EXISTS "model_TestModel" (
                        "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
                        ,"recordType" INTEGER NOT NULL
                        ,"uniqueId" TEXT NOT NULL UNIQUE
                            ON CONFLICT FAIL
                        ,"dateValue" DOUBLE
                        ,"doubleValue" DOUBLE NOT NULL
                        ,"floatValue" DOUBLE NOT NULL
                        ,"int64Value" INTEGER NOT NULL
                        ,"nsIntegerValue" INTEGER NOT NULL
                        ,"nsNumberValueUsingInt64" INTEGER
                        ,"nsNumberValueUsingUInt64" INTEGER
                        ,"nsuIntegerValue" INTEGER NOT NULL
                        ,"uint64Value" INTEGER NOT NULL
                    )
            ;

            CREATE
                INDEX "index_model_TestModel_on_uniqueId"
                    ON "model_TestModel"("uniqueId"
            )
            ;

            CREATE
                INDEX "index_interactions_on_threadUniqueId_and_id"
                    ON "model_TSInteraction"("uniqueThreadId"
                ,"id"
            )
            ;

            CREATE
                INDEX "index_jobs_on_label_and_id"
                    ON "model_SSKJobRecord"("label"
                ,"id"
            )
            ;

            CREATE
                INDEX "index_jobs_on_status_and_label_and_id"
                    ON "model_SSKJobRecord"("label"
                ,"status"
                ,"id"
            )
            ;

            CREATE
                INDEX "index_interactions_on_view_once"
                    ON "model_TSInteraction"("isViewOnceMessage"
                ,"isViewOnceComplete"
            )
            ;

            CREATE
                INDEX "index_key_value_store_on_collection_and_key"
                    ON "keyvalue"("collection"
                ,"key"
            )
            ;

            CREATE
                INDEX "index_interactions_on_recordType_and_threadUniqueId_and_errorType"
                    ON "model_TSInteraction"("recordType"
                ,"uniqueThreadId"
                ,"errorType"
            )
            ;

            CREATE
                INDEX "index_attachments_on_albumMessageId"
                    ON "model_TSAttachment"("albumMessageId"
                ,"recordType"
            )
            ;

            CREATE
                INDEX "index_interactions_on_uniqueId_and_threadUniqueId"
                    ON "model_TSInteraction"("uniqueThreadId"
                ,"uniqueId"
            )
            ;

            CREATE
                INDEX "index_signal_accounts_on_recipientPhoneNumber"
                    ON "model_SignalAccount"("recipientPhoneNumber"
            )
            ;

            CREATE
                INDEX "index_signal_accounts_on_recipientUUID"
                    ON "model_SignalAccount"("recipientUUID"
            )
            ;

            CREATE
                INDEX "index_signal_recipients_on_recipientPhoneNumber"
                    ON "model_SignalRecipient"("recipientPhoneNumber"
            )
            ;

            CREATE
                INDEX "index_signal_recipients_on_recipientUUID"
                    ON "model_SignalRecipient"("recipientUUID"
            )
            ;

            CREATE
                INDEX "index_thread_on_contactPhoneNumber"
                    ON "model_TSThread"("contactPhoneNumber"
            )
            ;

            CREATE
                INDEX "index_thread_on_contactUUID"
                    ON "model_TSThread"("contactUUID"
            )
            ;

            CREATE
                INDEX "index_thread_on_shouldThreadBeVisible"
                    ON "model_TSThread"("shouldThreadBeVisible"
                ,"isArchived"
                ,"lastInteractionRowId"
            )
            ;

            CREATE
                INDEX "index_user_profiles_on_recipientPhoneNumber"
                    ON "model_OWSUserProfile"("recipientPhoneNumber"
            )
            ;

            CREATE
                INDEX "index_user_profiles_on_recipientUUID"
                    ON "model_OWSUserProfile"("recipientUUID"
            )
            ;

            CREATE
                INDEX "index_user_profiles_on_username"
                    ON "model_OWSUserProfile"("username"
            )
            ;

            CREATE
                INDEX "index_linkedDeviceReadReceipt_on_senderPhoneNumberAndTimestamp"
                    ON "model_OWSLinkedDeviceReadReceipt"("senderPhoneNumber"
                ,"messageIdTimestamp"
            )
            ;

            CREATE
                INDEX "index_linkedDeviceReadReceipt_on_senderUUIDAndTimestamp"
                    ON "model_OWSLinkedDeviceReadReceipt"("senderUUID"
                ,"messageIdTimestamp"
            )
            ;

            CREATE
                INDEX "index_interactions_on_timestamp_sourceDeviceId_and_authorUUID"
                    ON "model_TSInteraction"("timestamp"
                ,"sourceDeviceId"
                ,"authorUUID"
            )
            ;

            CREATE
                INDEX "index_interactions_on_timestamp_sourceDeviceId_and_authorPhoneNumber"
                    ON "model_TSInteraction"("timestamp"
                ,"sourceDeviceId"
                ,"authorPhoneNumber"
            )
            ;

            CREATE
                INDEX "index_interactions_unread_counts"
                    ON "model_TSInteraction"("read"
                ,"uniqueThreadId"
                ,"recordType"
            )
            ;

            CREATE
                INDEX "index_interactions_on_expiresInSeconds_and_expiresAt"
                    ON "model_TSInteraction"("expiresAt"
                ,"expiresInSeconds"
            )
            ;

            CREATE
                INDEX "index_interactions_on_threadUniqueId_storedShouldStartExpireTimer_and_expiresAt"
                    ON "model_TSInteraction"("expiresAt"
                ,"expireStartedAt"
                ,"storedShouldStartExpireTimer"
                ,"uniqueThreadId"
            )
            ;

            CREATE
                INDEX "index_contact_queries_on_lastQueried"
                    ON "model_OWSContactQuery"("lastQueried"
            )
            ;

            CREATE
                INDEX "index_attachments_on_lazyRestoreFragmentId"
                    ON "model_TSAttachment"("lazyRestoreFragmentId"
            )
            ;

            CREATE
                VIRTUAL TABLE
                    "signal_grdb_fts"
                        USING fts5 (
                        collection UNINDEXED
                        ,uniqueId UNINDEXED
                        ,ftsIndexableContent
                        ,tokenize = 'unicode61'
                    ) /* signal_grdb_fts(collection,uniqueId,ftsIndexableContent) */
            ;
            """
            try tx.database.execute(sql: sql)
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

            try transaction.database.create(
                index: "index_media_gallery_items_for_gallery",
                on: "media_gallery_items",
                columns: ["threadId", "albumMessageId", "originalAlbumOrder"],
            )

            try transaction.database.create(
                index: "index_media_gallery_items_on_attachmentId",
                on: "media_gallery_items",
                columns: ["attachmentId"],
            )

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
                columns: ["uniqueId"],
            )
            try transaction.database.create(
                index: "index_model_OWSReaction_on_uniqueMessageId_and_reactorE164",
                on: "model_OWSReaction",
                columns: ["uniqueMessageId", "reactorE164"],
            )
            try transaction.database.create(
                index: "index_model_OWSReaction_on_uniqueMessageId_and_reactorUUID",
                on: "model_OWSReaction",
                columns: ["uniqueMessageId", "reactorUUID"],
            )
            return .success(())
        }

        migrator.registerMigration(.dedupeSignalRecipients) { transaction in
            try dedupeSignalRecipients(tx: transaction)

            try transaction.database.drop(index: "index_signal_recipients_on_recipientPhoneNumber")
            try transaction.database.drop(index: "index_signal_recipients_on_recipientUUID")

            try transaction.database.create(
                index: "index_signal_recipients_on_recipientPhoneNumber",
                on: "model_SignalRecipient",
                columns: ["recipientPhoneNumber"],
                unique: true,
            )

            try transaction.database.create(
                index: "index_signal_recipients_on_recipientUUID",
                on: "model_SignalRecipient",
                columns: ["recipientUUID"],
                unique: true,
            )
            return .success(())
        }

        migrator.registerMigration(.unreadThreadInteractions) { transaction in
            try transaction.database.create(
                index: "index_interactions_on_threadId_read_and_id",
                on: "model_TSInteraction",
                columns: ["uniqueThreadId", "read", "id"],
                unique: true,
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

                try transaction.database.create(
                    index: "index_indexable_text_on_collection_and_uniqueId",
                    on: "indexable_text",
                    columns: ["collection", "uniqueId"],
                    unique: true,
                )

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
            try transaction.database.create(
                index: "index_interaction_on_storedMessageState",
                on: "model_TSInteraction",
                columns: ["storedMessageState"],
            )
            try transaction.database.create(
                index: "index_interaction_on_recordType_and_callType",
                on: "model_TSInteraction",
                columns: ["recordType", "callType"],
            )
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
                columns: ["threadUniqueId", "recordType", "messageType"],
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
                columns: ["threadId"],
            )
            return .success(())
        }

        migrator.registerMigration(.createInteractionAttachmentIdsIndex) { transaction in
            try transaction.database.create(
                index: "index_model_TSInteraction_on_threadUniqueId_and_attachmentIds",
                on: "model_TSInteraction",
                columns: ["threadUniqueId", "attachmentIds"],
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
                columns: ["groupId", "id"],
            )
            return .success(())
        }

        migrator.registerMigration(.removeEarlyReceiptTables) { transaction in
            try transaction.database.drop(table: "model_TSRecipientReadReceipt")
            try transaction.database.drop(table: "model_OWSLinkedDeviceReadReceipt")
            try transaction.database.execute(sql: "DELETE FROM keyvalue WHERE collection = ?", arguments: ["viewOnceMessages"])
            return .success(())
        }

        migrator.registerMigration(.addReadToReactions) { transaction in
            try transaction.database.alter(table: "model_OWSReaction") { (table: TableAlteration) -> Void in
                table.add(column: "read", .boolean).notNull().defaults(to: false)
            }

            try transaction.database.create(
                index: "index_model_OWSReaction_on_uniqueMessageId_and_read",
                on: "model_OWSReaction",
                columns: ["uniqueMessageId", "read"],
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
                columns: ["uniqueId", "contentType"],
            )
            return .success(())
        }

        migrator.registerMigration(.readdAttachmentIndex) { transaction in
            try transaction.database.create(
                index: "index_model_TSAttachment_on_uniqueId",
                on: "model_TSAttachment",
                columns: ["uniqueId"],
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
                columns: ["isMarkedUnread"],
            )
            return .success(())
        }

        migrator.registerMigration(.fixIncorrectIndexes) { transaction in
            try transaction.database.drop(index: "index_model_TSInteraction_on_threadUniqueId_recordType_messageType")
            try transaction.database.create(
                index: "index_model_TSInteraction_on_uniqueThreadId_recordType_messageType",
                on: "model_TSInteraction",
                columns: ["uniqueThreadId", "recordType", "messageType"],
            )

            try transaction.database.drop(index: "index_model_TSInteraction_on_threadUniqueId_and_attachmentIds")
            try transaction.database.create(
                index: "index_model_TSInteraction_on_uniqueThreadId_and_attachmentIds",
                on: "model_TSInteraction",
                columns: ["uniqueThreadId", "attachmentIds"],
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
                columns: ["lastFetchDate", "lastMessagingDate"],
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
                columns: ["uniqueId"],
            )
            try transaction.database.create(
                index: "index_model_TSMention_on_uuidString_and_uniqueThreadId",
                on: "model_TSMention",
                columns: ["uuidString", "uniqueThreadId"],
            )
            try transaction.database.create(
                index: "index_model_TSMention_on_uniqueMessageId_and_uuidString",
                on: "model_TSMention",
                columns: ["uniqueMessageId", "uuidString"],
                unique: true,
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
                columns: ["isMarkedUnread", "shouldThreadBeVisible"],
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
                columns: ["uniqueThreadId", "hasEnded", "recordType"],
            )
            return .success(())
        }

        migrator.registerMigration(.addGroupCallEraIdIndex) { transaction in
            try transaction.database.create(
                index: "index_model_TSInteraction_on_uniqueThreadId_and_eraId_and_recordType",
                on: "model_TSInteraction",
                columns: ["uniqueThreadId", "eraId", "recordType"],
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
                columns: ["uniqueId"],
            )
            try transaction.database.create(
                index: "index_model_TSGroupMember_on_groupThreadId",
                on: "model_TSGroupMember",
                columns: ["groupThreadId"],
            )
            try transaction.database.create(
                index: "index_model_TSGroupMember_on_uuidString_and_groupThreadId",
                on: "model_TSGroupMember",
                columns: ["uuidString", "groupThreadId"],
                unique: true,
            )
            try transaction.database.create(
                index: "index_model_TSGroupMember_on_phoneNumber_and_groupThreadId",
                on: "model_TSGroupMember",
                columns: ["phoneNumber", "groupThreadId"],
                unique: true,
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
                columns: ["threadId"],
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
                unique: true,
            )
            try transaction.database.create(
                index: "index_thread_associated_data_on_threadUniqueId_and_isMarkedUnread",
                on: "thread_associated_data",
                columns: ["threadUniqueId", "isMarkedUnread"],
            )
            try transaction.database.create(
                index: "index_thread_associated_data_on_threadUniqueId_and_isArchived",
                on: "thread_associated_data",
                columns: ["threadUniqueId", "isArchived"],
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
                    onUpdate: .cascade,
                )
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
                    onUpdate: .cascade,
                )
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
                columns: ["sentTimestamp"],
            )

            // When deleting an interaction, we'll need to be able to lookup all
            // payloads associated with that interaction.
            try transaction.database.create(
                index: "MSLMessage_relatedMessageId",
                on: "MessageSendLog_Message",
                columns: ["uniqueId"],
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
                    onUpdate: .cascade,
                )
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
                    onUpdate: .cascade,
                )
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
                columns: ["sentTimestamp"],
            )
            try transaction.database.create(
                index: "MSLMessage_relatedMessageId",
                on: "MessageSendLog_Message",
                columns: ["uniqueId"],
            )
            return .success(())
        }

        migrator.registerMigration(.addRecordTypeIndex) { transaction in
            try transaction.database.create(
                index: "index_model_TSInteraction_on_nonPlaceholders_uniqueThreadId_id",
                on: "model_TSInteraction",
                columns: ["uniqueThreadId", "id"],
                condition: "\(interactionColumn: .recordType) IS NOT \(SDSRecordType.recoverableDecryptionPlaceholder.rawValue)",
            )
            return .success(())
        }

        migrator.registerMigration(.tunedConversationLoadIndices) { transaction in
            // These two indices are hyper-tuned for queries used to fetch the conversation load window. Specifically:
            // - InteractionFinder.count(excludingPlaceholders:transaction:)
            // - InteractionFinder.distanceFromLatest(interactionUniqueId:excludingPlaceholders:transaction:)
            // - InteractionFinder.enumerateInteractions(range:excludingPlaceholders:transaction:block:)
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
                columns: ["timestamp", "authorUuid"],
            )
            try transaction.database.create(
                index: "index_model_StoryMessage_on_direction",
                on: "model_StoryMessage",
                columns: ["direction"],
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
                columns: ["storyTimestamp", "storyAuthorUuidString", "isGroupStoryReply"],
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
            try createStoryContextAssociatedData(tx: transaction)
            return .success(())
        }

        migrator.registerMigration(.populateStoryContextAssociatedDataTableAndRemoveOldColumns) { transaction in
            try populateStoryContextAssociatedData(tx: transaction)
            try dropColumnsMigratedToStoryContextAssociatedData(tx: transaction)
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
                SET \(JobRecord.columnName(.paymentProcessor)) = 'STRIPE'
                WHERE \(JobRecord.columnName(.recordType)) = \(SendGiftBadgeJobRecord.recordType)
                OR \(JobRecord.columnName(.recordType)) = \(DonationReceiptCredentialRedemptionJobRecord.recordType)
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
                columns: ["interactionUniqueId"],
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
                // This is a BLOB column [by default][0]. We should've been explicit but don't want
                // to go back and change existing migrations, even if the change should be a no-op.
                // [0]: https://www.sqlite.org/datatype3.html#determination_of_column_affinity
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

        migrator.registerMigration(.addUsernameLookupRecordsTable) { transaction in
            try transaction.database.create(table: UsernameLookupRecord.databaseTableName) { table in
                table.column("aci", .blob).primaryKey().notNull()
                table.column("username", .text).notNull()
            }

            return .success(())
        }

        migrator.registerMigration(.dropUsernameColumnFromOWSUserProfile) { transaction in
            try transaction.database.drop(index: "index_user_profiles_on_username")
            try transaction.database.alter(table: "model_OWSUserProfile") { table in
                table.drop(column: "username")
            }

            return .success(())
        }

        migrator.registerMigration(.migrateVoiceMessageDrafts) { transaction in
            try migrateVoiceMessageDrafts(
                transaction: transaction,
                appSharedDataUrl: URL(fileURLWithPath: CurrentAppContext().appSharedDataDirectoryPath()),
                copyItem: FileManager.default.copyItem(at:to:),
            )
            return .success(())
        }

        migrator.registerMigration(.addIsPniCapableColumnToOWSUserProfile) { transaction in
            try transaction.database.alter(table: "model_OWSUserProfile") { table in
                table.add(column: "isPniCapable", .boolean).notNull().defaults(to: false)
            }

            return .success(())
        }

        migrator.registerMigration(.addStoryMessageReplyCount) { transaction in
            try transaction.database.alter(table: "model_StoryMessage") { table in
                table.add(column: "replyCount", .integer).notNull().defaults(to: 0)
            }
            return .success(())
        }

        migrator.registerMigration(.populateStoryMessageReplyCount) { transaction in
            try populateStoryMessageReplyCount(tx: transaction)
            return .success(())
        }

        migrator.registerMigration(.addIndexToFindFailedAttachments) { tx in
            let sql = """
                CREATE INDEX "index_attachments_toMarkAsFailed" ON "model_TSAttachment"(
                    "recordType", "state"
                ) WHERE "recordType" = 3 AND "state" IN (0, 1)
            """
            try tx.database.execute(sql: sql)

            return .success(())
        }

        migrator.registerMigration(.addEditMessageChanges) { transaction in
            try transaction.database.alter(table: "model_TSInteraction") { table in
                table.add(column: "editState", .integer).defaults(to: 0)
            }

            try Self.createEditRecordTable(tx: transaction)

            return .success(())
        }

        migrator.registerMigration(.dropMessageSendLogTriggers) { tx in
            try tx.database.execute(sql: """
                DROP TRIGGER IF EXISTS MSLRecipient_deliveryReceiptCleanup;
                DROP TRIGGER IF EXISTS MSLMessage_payloadCleanup;
            """)
            return .success(())
        }

        migrator.registerMigration(.threadReplyInfoServiceIds) { tx in
            try Self.migrateThreadReplyInfos(transaction: tx)
            return .success(())
        }

        migrator.registerMigration(.updateEditMessageUnreadIndex) { tx in
            try tx.database.execute(sql: "DROP INDEX IF EXISTS index_interactions_on_threadId_read_and_id")
            try tx.database.execute(sql: "DROP INDEX IF EXISTS index_model_TSInteraction_UnreadCount")

            try tx.database.create(
                index: "index_model_TSInteraction_UnreadMessages",
                on: "\(InteractionRecord.databaseTableName)",
                columns: [
                    "read",
                    "uniqueThreadId",
                    "id",
                    "isGroupStoryReply",
                    "editState",
                    "recordType",
                ],
            )
            return .success(())
        }

        migrator.registerMigration(.updateEditRecordTable) { tx in
            try Self.migrateEditRecordTable(tx: tx)
            return .success(())
        }

        migrator.registerMigration(.threadReplyEditTarget) { tx in
            try tx.database.alter(table: "model_TSThread") { table in
                table.add(column: "editTargetTimestamp", .integer)
            }
            return .success(())
        }

        migrator.registerMigration(.addHiddenRecipientsTable) { transaction in
            try transaction.database.create(table: HiddenRecipient.databaseTableName) { table in
                table.column("recipientId", .integer)
                    .primaryKey()
                    .notNull()
                table.foreignKey(
                    ["recipientId"],
                    references: "model_SignalRecipient",
                    columns: ["id"],
                    onDelete: .cascade,
                )
            }
            return .success(())
        }

        migrator.registerMigration(.editRecordReadState) { tx in
            try tx.database.alter(table: "EditRecord") { table in
                table.add(column: "read", .boolean).notNull().defaults(to: false)
            }
            return .success(())
        }

        migrator.registerMigration(.addPaymentModelInteractionUniqueId) { tx in
            try tx.database.alter(table: "model_TSPaymentModel") { table in
                table.add(column: "interactionUniqueId", .text)
            }
            return .success(())
        }

        migrator.registerMigration(.addPaymentsActivationRequestModel) { tx in
            try tx.database.create(table: "TSPaymentsActivationRequestModel") { table in
                table.autoIncrementedPrimaryKey("id")
                    .notNull()
                table.column("threadUniqueId", .text)
                    .notNull()
                table.column("senderAci", .blob)
                    .notNull()
            }
            try tx.database.create(
                index: "index_TSPaymentsActivationRequestModel_on_threadUniqueId",
                on: "TSPaymentsActivationRequestModel",
                columns: ["threadUniqueId"],
            )
            return .success(())
        }

        migrator.registerMigration(.addRecipientPniColumn) { transaction in
            try transaction.database.alter(table: "model_SignalRecipient") { table in
                table.add(column: "pni", .text)
            }
            try transaction.database.create(
                index: "index_signal_recipients_on_pni",
                on: "model_SignalRecipient",
                columns: ["pni"],
                options: [.unique],
            )
            return .success(())
        }

        migrator.registerMigration(.deletePhoneNumberAccessStore) { tx in
            try tx.database.execute(sql: """
                DELETE FROM "keyvalue" WHERE "collection" = 'kUnidentifiedAccessCollection'
            """)
            return .success(())
        }

        /// Create the "Call Record" table.
        ///
        /// We had a table for this previously, which we dropped in favor of
        /// this newer version.
        migrator.registerMigration(.dropOldAndCreateNewCallRecordTable) { tx in
            try tx.database.drop(index: "index_call_record_on_interaction_unique_id")
            try tx.database.drop(table: "model_CallRecord")

            try tx.database.create(table: "CallRecord") { (table: TableDefinition) in
                table.column("id", .integer).primaryKey().notNull()
                table.column("callId", .text).notNull().unique()
                table.column("interactionRowId", .integer).notNull().unique()
                    .references("model_TSInteraction", column: "id", onDelete: .cascade)
                table.column("threadRowId", .integer).notNull()
                    .references("model_TSThread", column: "id", onDelete: .restrict)
                table.column("type", .integer).notNull()
                table.column("direction", .integer).notNull()
                table.column("status", .integer).notNull()
            }

            // Note that because `callId` and `interactionRowId` are UNIQUE
            // SQLite will automatically create an index on each of them.

            return .success(())
        }

        /// Fix a UNIQUE constraint on the "Call Record" table.
        ///
        /// We previously had a UNIQUE constraint on the `callId` column, which
        /// wasn't quite right. Instead, we want a UNIQUE constraint on
        /// `(callId, threadRowId)`, to mitigate against call ID collision.
        ///
        /// Since the call record table was just added recently, we can drop it
        /// and recreate it with the new UNIQUE constraint, via an explicit
        /// index.
        migrator.registerMigration(.fixUniqueConstraintOnCallRecord) { tx in
            try tx.database.drop(table: "CallRecord")

            try tx.database.create(table: "CallRecord") { (table: TableDefinition) in
                table.column("id", .integer).primaryKey().notNull()
                table.column("callId", .text).notNull()
                table.column("interactionRowId", .integer).notNull().unique()
                    .references("model_TSInteraction", column: "id", onDelete: .cascade)
                table.column("threadRowId", .integer).notNull()
                    .references("model_TSThread", column: "id", onDelete: .restrict)
                table.column("type", .integer).notNull()
                table.column("direction", .integer).notNull()
                table.column("status", .integer).notNull()
            }

            try tx.database.create(
                index: "index_call_record_on_callId_and_threadId",
                on: "CallRecord",
                columns: ["callId", "threadRowId"],
                options: [.unique],
            )

            // Note that because `interactionRowId` is UNIQUE, SQLite will
            // automatically create an index on it.

            return .success(())
        }

        /// Add a timestamp column to call records. Delete any records created
        /// prior, since we don't need them at the time of migration and we
        /// really want timestamps to be populated in the future.
        migrator.registerMigration(.addTimestampToCallRecord) { tx in
            try tx.database.execute(sql: """
                DELETE FROM CallRecord
            """)

            try tx.database.alter(table: "CallRecord") { table in
                table.add(column: "timestamp", .integer).notNull()
            }

            return .success(())
        }

        /// During subscription receipt credential redemption, we now need to
        /// know the payment method used, if possible.
        migrator.registerMigration(.addPaymentMethodToJobRecords) { tx in
            try tx.database.alter(table: "model_SSKJobRecord") { table in
                table.add(column: "paymentMethod", .text)
            }

            return .success(())
        }

        migrator.registerMigration(.addIsNewSubscriptionToJobRecords) { tx in
            try tx.database.alter(table: "model_SSKJobRecord") { table in
                table.add(column: "isNewSubscription", .boolean)
            }

            return .success(())
        }

        migrator.registerMigration(.enableFts5SecureDelete) { tx in
            try enableFts5SecureDelete(for: "indexable_text_fts", db: tx.database)
            return .success(())
        }

        migrator.registerMigration(.addShouldSuppressPaymentAlreadyRedeemedToJobRecords) { tx in
            try tx.database.alter(table: "model_SSKJobRecord") { table in
                table.add(column: "shouldSuppressPaymentAlreadyRedeemed", .boolean)
            }

            return .success(())
        }

        migrator.registerMigration(.addGroupCallRingerAciToCallRecords) { tx in
            try tx.database.alter(table: "CallRecord") { table in
                table.add(column: "groupCallRingerAci", .blob)
            }

            return .success(())
        }

        migrator.registerMigration(.renameIsFromLinkedDevice) { tx in
            try tx.database.alter(table: "model_TSInteraction") { table in
                table.rename(column: "isFromLinkedDevice", to: "wasNotCreatedLocally")
            }
            return .success(())
        }

        migrator.registerMigration(.renameAndDeprecateSourceDeviceId) { tx in
            try tx.database.alter(table: "model_TSInteraction") { table in
                table.rename(column: "sourceDeviceId", to: "deprecated_sourceDeviceId")
            }
            return .success(())
        }

        migrator.registerMigration(.addCallRecordQueryIndices) { tx in
            /// This powers ``CallRecordQuerier/fetchCursor(tx:)``.
            try tx.database.create(
                index: "index_call_record_on_timestamp",
                on: "CallRecord",
                columns: [
                    "timestamp",
                ],
            )

            /// This powers ``CallRecordQuerier/fetchCursor(callStatus:tx:)``.
            try tx.database.create(
                index: "index_call_record_on_status_and_timestamp",
                on: "CallRecord",
                columns: [
                    "status",
                    "timestamp",
                ],
            )

            /// This powers ``CallRecordQuerier/fetchCursor(threadRowId:tx:)``.
            try tx.database.create(
                index: "index_call_record_on_threadRowId_and_timestamp",
                on: "CallRecord",
                columns: [
                    "threadRowId",
                    "timestamp",
                ],
            )

            /// This powers ``CallRecordQuerier/fetchCursor(threadRowId:callStatus:tx:)``.
            try tx.database.create(
                index: "index_call_record_on_threadRowId_and_status_and_timestamp",
                on: "CallRecord",
                columns: [
                    "threadRowId",
                    "status",
                    "timestamp",
                ],
            )

            return .success(())
        }

        migrator.registerMigration(.addDeletedCallRecordTable) { tx in
            try tx.database.create(table: "DeletedCallRecord") { table in
                table.column("id", .integer).primaryKey().notNull()
                table.column("callId", .text).notNull()
                table.column("threadRowId", .integer).notNull()
                    .references("model_TSThread", column: "id", onDelete: .restrict)
                table.column("deletedAtTimestamp", .integer).notNull()
            }

            try tx.database.create(
                index: "index_deleted_call_record_on_threadRowId_and_callId",
                on: "DeletedCallRecord",
                columns: ["threadRowId", "callId"],
                options: [.unique],
            )

            return .success(())
        }

        migrator.registerMigration(.addFirstDeletedIndexToDeletedCallRecord) { tx in
            try tx.database.create(
                index: "index_deleted_call_record_on_deletedAtTimestamp",
                on: "DeletedCallRecord",
                columns: ["deletedAtTimestamp"],
            )

            return .success(())
        }

        migrator.registerMigration(.addCallRecordDeleteAllColumnsToJobRecord) { tx in
            try tx.database.alter(table: "model_SSKJobRecord") { table in
                table.add(column: "CRDAJR_sendDeleteAllSyncMessage", .boolean)
                table.add(column: "CRDAJR_deleteAllBeforeTimestamp", .integer)
            }

            return .success(())
        }

        migrator.registerMigration(.addPhoneNumberSharingAndDiscoverability) { tx in
            try tx.database.alter(table: "model_SignalRecipient") { table in
                table.add(column: "isPhoneNumberDiscoverable", .boolean)
            }
            try tx.database.alter(table: "model_OWSUserProfile") { table in
                table.add(column: "isPhoneNumberShared", .boolean)
            }
            return .success(())
        }

        migrator.registerMigration(.removeRedundantPhoneNumbers2) { tx in
            removeMigration("removeRedundantPhoneNumbers", db: tx.database)
            try removeLocalProfileSignalRecipient(in: tx.database)
            // The OWSUserProfile migration was obsoleted by removeRedundantPhoneNumbers3.
            try removeRedundantPhoneNumbers(
                in: tx.database,
                tableName: "model_TSThread",
                serviceIdColumn: "contactUUID",
                phoneNumberColumn: "contactPhoneNumber",
            )
            try removeRedundantPhoneNumbers(
                in: tx.database,
                tableName: "model_TSGroupMember",
                serviceIdColumn: "uuidString",
                phoneNumberColumn: "phoneNumber",
            )
            return .success(())
        }

        // Perform a full sync to ensure isDiscoverable values are correct.
        migrator.registerMigration(.scheduleFullIntersection) { tx in
            try tx.database.execute(sql: """
            DELETE FROM "keyvalue" WHERE (
                "collection" = 'OWSContactsManagerCollection'
                AND "key" = 'OWSContactsManagerKeyNextFullIntersectionDate2'
            )
            """)
            return .success(())
        }

        migrator.registerMigration(.addUnreadToCallRecord) { tx in
            /// Annoyingly, we need to provide a DEFAULT value in this migration
            /// to cover all existing rows. I'd prefer that we make the column
            /// not have a default value that applies going forward, since all
            /// records inserted after this migration runs will provide a value
            /// for this column.
            ///
            /// However, SQLite doesn't know that, and consequently won't allow
            /// us to create a NOT NULL column without a default – even if we
            /// were to run a separate SQL statement after creating the column
            /// to populate it for existing rows.
            try tx.database.alter(table: "CallRecord") { table in
                table.add(column: "unreadStatus", .integer)
                    .notNull()
                    .defaults(to: CallRecord.CallUnreadStatus.read.rawValue)
            }

            try tx.database.create(
                index: "index_call_record_on_callStatus_and_unreadStatus_and_timestamp",
                on: "CallRecord",
                columns: [
                    "status",
                    "unreadStatus",
                    "timestamp",
                ],
            )

            return .success(())
        }

        migrator.registerMigration(.addSearchableName) { tx in
            try tx.database.execute(
                sql: """
                DELETE FROM "indexable_text" WHERE "collection" IN (
                    'SignalAccount',
                    'SignalRecipient',
                    'TSGroupMember',
                    'TSThread'
                )
                """,
            )

            // If you change the constant, you need to add a new migration. Simply
            // changing this one won't work for existing users.
            assert(SearchableNameIndexerImpl.Constants.databaseTableName == "SearchableName")

            try tx.database.create(table: "SearchableName") { table in
                table.autoIncrementedPrimaryKey("id").notNull()
                table.column("threadId", .integer).unique()
                table.column("signalAccountId", .integer).unique()
                table.column("userProfileId", .integer).unique()
                table.column("signalRecipientId", .integer).unique()
                table.column("usernameLookupRecordId", .blob).unique()
                table.column("value", .text).notNull()

                // Create foreign keys.
                table.foreignKey(["threadId"], references: "model_TSThread", columns: ["id"], onDelete: .cascade, onUpdate: .cascade)
                table.foreignKey(["signalAccountId"], references: "model_SignalAccount", columns: ["id"], onDelete: .cascade, onUpdate: .cascade)
                table.foreignKey(["userProfileId"], references: "model_OWSUserProfile", columns: ["id"], onDelete: .cascade, onUpdate: .cascade)
                table.foreignKey(["signalRecipientId"], references: "model_SignalRecipient", columns: ["id"], onDelete: .cascade, onUpdate: .cascade)
                table.foreignKey(["usernameLookupRecordId"], references: "UsernameLookupRecord", columns: ["aci"], onDelete: .cascade, onUpdate: .cascade)
            }

            try tx.database.create(virtualTable: "SearchableNameFTS", using: FTS5()) { table in
                table.tokenizer = FTS5TokenizerDescriptor.unicode61()
                table.synchronize(withTable: "SearchableName")
                table.column("value")
            }

            try enableFts5SecureDelete(for: "SearchableNameFTS", db: tx.database)

            return .success(())
        }

        migrator.registerMigration(.addCallRecordRowIdColumnToCallRecordDeleteAllJobRecord) { tx in
            try tx.database.alter(table: "model_SSKJobRecord") { table in
                table.add(column: "CRDAJR_deleteAllBeforeCallId", .text)
                table.add(column: "CRDAJR_deleteAllBeforeConversationId", .blob)
            }

            return .success(())
        }

        migrator.registerMigration(.markAllGroupCallMessagesAsRead) { tx in
            try tx.database.execute(sql: """
                UPDATE model_TSInteraction
                SET read = 1
                WHERE recordType = \(SDSRecordType.groupCallMessage.rawValue)
            """)

            return .success(())
        }

        migrator.registerMigration(.addIndexForUnreadByThreadRowIdToCallRecord) { tx in
            try tx.database.create(
                index: "index_call_record_on_threadRowId_and_callStatus_and_unreadStatus_and_timestamp",
                on: "CallRecord",
                columns: [
                    "threadRowId",
                    "status",
                    "unreadStatus",
                    "timestamp",
                ],
            )

            return .success(())
        }

        migrator.registerMigration(.addNicknamesTable) { tx in
            try tx.database.create(table: "NicknameRecord") { table in
                table.column("recipientRowID", .integer).primaryKey().notNull()
                    .references("model_SignalRecipient", column: "id", onDelete: .cascade)
                table.column("givenName", .text)
                table.column("familyName", .text)
                table.column("note", .text)
            }

            return .success(())
        }

        migrator.registerMigration(.expandSignalAccountContactFields) { tx in
            // To match iOS system behavior, these fields are NONNULL, so `contact !=
            // NULL` should be used to differentiate modern/legacy encodings.
            try tx.database.alter(table: "model_SignalAccount") { table in
                table.add(column: "cnContactId", .text)
                table.add(column: "givenName", .text).notNull().defaults(to: "")
                table.add(column: "familyName", .text).notNull().defaults(to: "")
                table.add(column: "nickname", .text).notNull().defaults(to: "")
                table.add(column: "fullName", .text).notNull().defaults(to: "")
            }

            return .success(())
        }

        migrator.registerMigration(.addNicknamesToSearchableName) { tx in
            try tx.database.alter(table: "SearchableName") { table in
                table.add(column: "nicknameRecordRecipientId", .integer)
                    .references("NicknameRecord", column: "recipientRowID", onDelete: .cascade)
            }

            return .success(())
        }

        migrator.registerMigration(.addAttachmentMetadataColumnsToIncomingContactSyncJobRecord) { tx in
            try tx.database.alter(table: "model_SSKJobRecord") { table in
                table.add(column: "ICSJR_cdnNumber", .integer)
                table.add(column: "ICSJR_cdnKey", .text)
                table.add(column: "ICSJR_encryptionKey", .blob)
                table.add(column: "ICSJR_digest", .blob)
                table.add(column: "ICSJR_plaintextLength", .integer)
            }

            return .success(())
        }

        migrator.registerMigration(.removeRedundantPhoneNumbers3) { tx in
            try removeLocalProfileSignalRecipient(in: tx.database)
            try removeRedundantPhoneNumbers(
                in: tx.database,
                tableName: "model_OWSUserProfile",
                serviceIdColumn: "recipientUUID",
                phoneNumberColumn: "recipientPhoneNumber",
            )
            return .success(())
        }

        migrator.registerMigration(.addV2AttachmentTable) { tx in
            return try Self.createV2AttachmentTables(tx)
        }

        migrator.registerMigration(.addBulkDeleteInteractionJobRecord) { tx in
            try tx.database.alter(table: "model_SSKJobRecord") { table in
                table.add(column: "BDIJR_anchorMessageRowId", .integer)
                table.add(column: "BDIJR_fullThreadDeletionAnchorMessageRowId", .integer)
                table.add(column: "BDIJR_threadUniqueId", .text)
            }

            return .success(())
        }

        migrator.registerMigration(.cleanUpThreadIndexes) { tx in
            try tx.database.execute(sql: """
            DROP INDEX IF EXISTS "index_model_TSThread_on_isMarkedUnread_and_shouldThreadBeVisible";
            DROP INDEX IF EXISTS "index_thread_on_shouldThreadBeVisible";
            CREATE INDEX "index_thread_on_shouldThreadBeVisible" ON "model_TSThread" ("shouldThreadBeVisible", "lastInteractionRowId" DESC);
            """)
            return .success(())
        }

        migrator.registerMigration(.addOrphanAttachmentPendingColumn) { tx in
            try tx.database.alter(table: "OrphanedAttachment") { table in
                // When we create an attachment, we first insert the new files
                // into the orphan table, so they get cleaned up if we fail.
                // We don't want to clean them up immediately, so track when
                // we do this so for these cases (and not others) we wait a bit
                // before deleting.
                table.add(column: "isPendingAttachment", .boolean)
                    .notNull()
                    .defaults(to: false)
            }
            return .success(())
        }

        migrator.registerMigration(.cleanUpUniqueIndexes) { tx in
            try tx.database.execute(sql: """
            DROP INDEX IF EXISTS "index_model_ExperienceUpgrade_on_uniqueId";
            DROP INDEX IF EXISTS "index_model_IncomingGroupsV2MessageJob_on_uniqueId";
            DROP INDEX IF EXISTS "index_model_InstalledSticker_on_uniqueId";
            DROP INDEX IF EXISTS "index_model_KnownStickerPack_on_uniqueId";
            DROP INDEX IF EXISTS "index_model_OWSDevice_on_uniqueId";
            DROP INDEX IF EXISTS "index_model_OWSDisappearingMessagesConfiguration_on_uniqueId";
            DROP INDEX IF EXISTS "index_model_OWSMessageContentJob_on_uniqueId";
            DROP INDEX IF EXISTS "index_model_OWSReaction_on_uniqueId";
            DROP INDEX IF EXISTS "index_model_OWSRecipientIdentity_on_uniqueId";
            DROP INDEX IF EXISTS "index_model_OWSUserProfile_on_uniqueId";
            DROP INDEX IF EXISTS "index_model_SSKJobRecord_on_uniqueId";
            DROP INDEX IF EXISTS "index_model_SignalAccount_on_uniqueId";
            DROP INDEX IF EXISTS "index_model_SignalRecipient_on_uniqueId";
            DROP INDEX IF EXISTS "index_model_StickerPack_on_uniqueId";
            DROP INDEX IF EXISTS "index_model_StoryMessage_on_uniqueId";
            DROP INDEX IF EXISTS "index_model_TSAttachment_on_uniqueId";
            DROP INDEX IF EXISTS "index_model_TSGroupMember_on_uniqueId";
            DROP INDEX IF EXISTS "index_model_TSInteraction_on_uniqueId";
            DROP INDEX IF EXISTS "index_model_TSMention_on_uniqueId";
            DROP INDEX IF EXISTS "index_model_TSPaymentModel_on_uniqueId";
            DROP INDEX IF EXISTS "index_model_TSThread_on_uniqueId";
            DROP INDEX IF EXISTS "index_model_TestModel_on_uniqueId";
            DROP INDEX IF EXISTS "index_media_gallery_items_on_attachmentId";
            DROP INDEX IF EXISTS "index_thread_associated_data_on_threadUniqueId";
            """)
            return .success(())
        }

        migrator.registerMigration(.dropTableTestModel) { tx in
            try tx.database.execute(sql: """
            DROP TABLE IF EXISTS "model_TestModel"
            """)
            return .success(())
        }

        migrator.registerMigration(.addOriginalAttachmentIdForQuotedReplyColumn) { tx in
            return try Self.addOriginalAttachmentIdForQuotedReplyColumn(tx)
        }

        migrator.registerMigration(.addClientUuidToTSAttachment) { tx in
            try tx.database.alter(table: "model_TSAttachment") { table in
                table.add(column: "clientUuid", .text)
            }
            return .success(())
        }

        migrator.registerMigration(.recreateMessageAttachmentReferenceMediaGalleryIndexes) { tx in
            // Drop the original index; by putting renderingFlag before the three ordering columns
            // we force all queries to filter to one rendering flag value, which most do not.
            try tx.database.drop(
                index:
                "index_message_attachment_reference_on"
                    + "_threadRowId"
                    + "_and_ownerType"
                    + "_and_contentType"
                    + "_and_renderingFlag"
                    + "_and_receivedAtTimestamp"
                    + "_and_ownerRowId"
                    + "_and_orderInMessage",
            )
            try tx.database.alter(table: "MessageAttachmentReference") { table in
                // We want to be able to filter by
                // (contentType = image OR contentType = video OR contentType = animatedImage)
                // To do this efficiently with the index while applying an ORDER BY, we need
                // that OR to collapse into a single constraint.
                // Do this by creating a generated column. It can be virtual, no need to store it.
                table.addColumn(
                    literal: "isVisualMediaContentType AS (contentType = 2 OR contentType = 3 OR contentType = 4) VIRTUAL",
                )
                // Ditto for
                // (contentType = file OR contentType = invalid)
                // Not used to today, but will be in the future.
                table.addColumn(
                    literal: "isInvalidOrFileContentType AS (contentType = 0 OR contentType = 1) VIRTUAL",
                )
            }

            /// Create three indexes which vary only by contentType/isVisualMediaContentType/isInvalidOrFileContentType
            /// Each media gallery query will either filter to a single content type or one of these pre-defined composit ones.
            try tx.database.create(
                index:
                "message_attachment_reference_media_gallery_single_content_type_index",
                on: "MessageAttachmentReference",
                columns: [
                    "threadRowId",
                    "ownerType",
                    "contentType",
                    "receivedAtTimestamp",
                    "ownerRowId",
                    "orderInMessage",
                ],
            )
            try tx.database.create(
                index:
                "message_attachment_reference_media_gallery_visualMedia_content_type_index",
                on: "MessageAttachmentReference",
                columns: [
                    "threadRowId",
                    "ownerType",
                    "isVisualMediaContentType",
                    "receivedAtTimestamp",
                    "ownerRowId",
                    "orderInMessage",
                ],
            )
            try tx.database.create(
                index:
                "message_attachment_reference_media_gallery_fileOrInvalid_content_type_index",
                on: "MessageAttachmentReference",
                columns: [
                    "threadRowId",
                    "ownerType",
                    "isInvalidOrFileContentType",
                    "receivedAtTimestamp",
                    "ownerRowId",
                    "orderInMessage",
                ],
            )
            return .success(())
        }

        migrator.registerMigration(.addAttachmentDownloadQueue) { tx in
            try tx.database.create(table: "AttachmentDownloadQueue") { table in
                table.autoIncrementedPrimaryKey("id").notNull()
                table.column("sourceType", .integer).notNull()
                table.column("attachmentId", .integer)
                    .references("Attachment", column: "id", onDelete: .cascade)
                    .notNull()
                table.column("priority", .integer).notNull()
                table.column("minRetryTimestamp", .integer)
                table.column("retryAttempts", .integer).notNull()
                table.column("localRelativeFilePath", .text).notNull()
            }

            // When we enqueue a download (from an attachment in a particular source)
            // we want to see if there's an existing download enqueued.
            try tx.database.create(
                index: "index_AttachmentDownloadQueue_on_attachmentId_and_sourceType",
                on: "AttachmentDownloadQueue",
                columns: [
                    "attachmentId",
                    "sourceType",
                ],
            )

            // We only allow N downloads of priority "default", so if we exceed this
            // limit we need to drop the oldest one. This helps us count them.
            try tx.database.create(
                index: "index_AttachmentDownloadQueue_on_priority",
                on: "AttachmentDownloadQueue",
                columns: [
                    "priority",
                ],
            )

            // The index we use to pop the next download off the queue.
            // Only index where minRetryTimestamp == nil; we eliminate non-retryable rows.
            // Then we sort by priority (DESC).
            // Last, we break ties by row id (ASC, FIFO order).
            // GRDB utilities don't let you specify a sort order for columns
            // so just do raw SQL.
            try tx.database.execute(sql: """
                CREATE INDEX
                    "partial_index_AttachmentDownloadQueue_on_priority_DESC_and_id_where_minRetryTimestamp_isNull"
                ON
                    "AttachmentDownloadQueue"
                (
                    "priority" DESC
                    ,"id"
                )
                WHERE minRetryTimestamp IS NULL
            """)

            // We want to get the lowest minRetryTimestamp so we can nil out the column
            // and mark that row as ready to retry when we reach that time.
            try tx.database.execute(sql: """
                CREATE INDEX
                    "partial_index_AttachmentDownloadQueue_on_minRetryTimestamp_where_isNotNull"
                ON
                    "AttachmentDownloadQueue"
                (
                    "minRetryTimestamp"
                )
                WHERE minRetryTimestamp IS NOT NULL
            """)

            /// When we delete an attachment download row in the database, insert the partial download
            /// into the orphan table so we can clean up the file on disk.
            try tx.database.execute(sql: """
                CREATE TRIGGER
                    "__AttachmentDownloadQueue_ad"
                AFTER DELETE ON
                    "AttachmentDownloadQueue"
                BEGIN
                    INSERT INTO OrphanedAttachment (
                        localRelativeFilePath
                    ) VALUES (
                        OLD.localRelativeFilePath
                    );
                END;
            """)

            return .success(())
        }

        migrator.registerMigration(.attachmentAddCdnUnencryptedByteCounts) { tx in

            try tx.database.alter(table: "Attachment") { table in
                table.drop(column: "transitEncryptedByteCount")
                table.add(column: "transitUnencryptedByteCount", .integer)
                table.add(column: "mediaTierUnencryptedByteCount", .integer)
            }
            return .success(())
        }

        migrator.registerMigration(.addArchivedPaymentInfoColumn) { tx in
            try tx.database.alter(table: "model_TSInteraction") { (table: TableAlteration) -> Void in
                table.add(column: "archivedPaymentInfo", .blob)
            }
            return .success(())
        }

        migrator.registerMigration(.createArchivedPaymentTable) { tx in
            try tx.database.execute(sql: "DROP TABLE IF EXISTS ArchivedPayment")
            try tx.database.create(table: "ArchivedPayment") { table in
                table.autoIncrementedPrimaryKey("id")
                    .notNull()
                table.column("amount", .text)
                table.column("fee", .text)
                table.column("note", .text)
                table.column("mobileCoinIdentification", .blob)
                table.column("status", .integer)
                table.column("failureReason", .integer)
                table.column("timestamp", .integer)
                table.column("blockIndex", .integer)
                table.column("blockTimestamp", .integer)
                table.column("transaction", .blob)
                table.column("receipt", .blob)
                table.column("direction", .integer)
                table.column("senderOrRecipientAci", .blob)
                table.column("interactionUniqueId", .text)
            }

            try tx.database.create(
                index: "index_archived_payment_on_interaction_unique_id",
                on: "ArchivedPayment",
                columns: ["interactionUniqueId"],
            )

            return .success(())
        }

        migrator.registerMigration(.removeDeadEndGroupThreadIdMappings) { tx in
            try removeDeadEndGroupThreadIdMappings(tx: tx)
            return .success(())
        }

        migrator.registerMigration(.addTSAttachmentMigrationTable) { tx in
            try tx.database.create(table: "TSAttachmentMigration") { table in
                table.column("tsAttachmentUniqueId", .text).notNull()
                // No benefit from making these foreign keys; we don't want cascade
                // delete behavior and don't need existence guarantees.
                table.column("interactionRowId", .integer)
                table.column("storyMessageRowId", .integer)
                table.column("reservedV2AttachmentPrimaryFileId", .blob).notNull()
                table.column("reservedV2AttachmentAudioWaveformFileId", .blob).notNull()
                table.column("reservedV2AttachmentVideoStillFrameFileId", .blob).notNull()
            }

            try tx.database.execute(sql: """
            CREATE INDEX "index_TSAttachmentMigration_on_interactionRowId"
            ON "TSAttachmentMigration"
            ("interactionRowId")
            WHERE "interactionRowId" IS NOT NULL;
            """)
            try tx.database.execute(sql: """
            CREATE INDEX "index_TSAttachmentMigration_on_storyMessageRowId"
            ON "TSAttachmentMigration"
            ("storyMessageRowId")
            WHERE "storyMessageRowId" IS NOT NULL;
            """)

            return .success(())
        }

        migrator.registerMigration(.indexMessageAttachmentReferenceByReceivedAtTimestamp) { tx in
            try tx.database.create(
                index: "index_message_attachment_reference_on_receivedAtTimestamp",
                on: "MessageAttachmentReference",
                columns: ["receivedAtTimestamp"],
            )
            return .success(())
        }

        migrator.registerMigration(.addBackupAttachmentDownloadQueue) { tx in
            try tx.database.create(table: "BackupAttachmentDownloadQueue") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("attachmentRowId", .integer)
                    .references("Attachment", column: "id", onDelete: .cascade)
                    .notNull()
                    .unique()
                table.column("timestamp", .integer)
            }

            return .success(())
        }

        migrator.registerMigration(.createAttachmentUploadRecordTable) { tx in
            try tx.database.execute(sql: "DROP TABLE IF EXISTS AttachmentUploadRecord")
            try tx.database.create(table: "AttachmentUploadRecord") { table in
                table.autoIncrementedPrimaryKey("id")
                    .notNull()
                table.column("sourceType", .integer)
                    .notNull()
                table.column("attachmentId", .integer)
                    .notNull()
                table.column("uploadForm", .blob)
                table.column("uploadFormTimestamp", .integer)
                table.column("localMetadata", .blob)
                table.column("uploadSessionUrl", .blob)
                table.column("attempt", .integer)
            }

            try tx.database.create(
                index: "index_attachment_upload_record_on_attachment_id",
                on: "AttachmentUploadRecord",
                columns: ["attachmentId"],
            )

            return .success(())
        }

        migrator.registerMigration(.addBlockedRecipient) { tx in
            try migrateBlockedRecipients(tx: tx)

            return .success(())
        }

        migrator.registerMigration(.addDmTimerVersionColumn) { tx in
            try tx.database.alter(table: "model_OWSDisappearingMessagesConfiguration") { table in
                table.add(column: "timerVersion", .integer)
                    .defaults(to: 1)
                    .notNull()
            }
            return .success(())
        }

        migrator.registerMigration(.addVersionedDMTimer) { tx in
            // This table can be deleted 90 days after all clients ship capability
            // support; the capability can be assumed true then.
            try tx.database.create(table: "VersionedDMTimerCapabilities") { table in
                table.column("serviceId", .blob).unique().notNull()
                table.column("isEnabled", .boolean).notNull()
            }
            return .success(())
        }

        migrator.registerMigration(.addDMTimerVersionToInteractionTable) { tx in
            try tx.database.alter(table: "model_TSInteraction") { (table: TableAlteration) -> Void in
                table.add(column: "expireTimerVersion", .integer)
            }
            return .success(())
        }

        migrator.registerMigration(.initializeDMTimerVersion) { tx in
            // One time, we update all timers to an initial value of 2.
            // This prevents the following edge case:
            //
            // 1. Alice and Bob have a chat with DM timer set to some value.
            // 2. Both Alice and Bob update their primaries. If not for this migration,
            //    their clock value would be 1 (the default).
            // 3. Alice links a new iPad/Desktop; it doesn't get a contact sync yet
            //    It sets the chat's clock to 1 (the default).
            // 4. Alice's iPad sends a message with expireTimer=nil clock=1
            // 5. Bob (and Alice's primary) accept and set the timer to nil
            //
            // So we initialize all _existing_ timers to 2, so the default 1 value
            // will be rejected in step 5.
            // (Chats that have never set a timer have no configuration row and are
            // fine to leave as-is. Also this will update the universal and group
            // thread timer versions, but those are never used so it doesn't matter.)
            try tx.database.execute(sql: """
            UPDATE model_OWSDisappearingMessagesConfiguration SET timerVersion = 2;
            """)
            return .success(())
        }

        migrator.registerMigration(.attachmentAddMediaTierDigest) { tx in
            try tx.database.alter(table: "Attachment") { table in
                table.add(column: "mediaTierDigestSHA256Ciphertext", .blob)
            }
            return .success(())
        }

        migrator.registerMigration(.removeVoIPToken) { tx in
            try tx.database.execute(sql: """
            DELETE FROM "keyvalue" WHERE "collection" = 'SignalPreferences' AND "key" = 'LastRecordedVoipToken'
            """)
            return .success(())
        }

        /// The migration that adds `Attachment.mediaTierDigestSHA256Ciphertext`
        /// will add that column to the end of the `Attachment` table's columns.
        /// However, in `schema.sql` that column was added in the middle of the
        /// existing columns. That means that users who did a fresh install with
        /// that `schema.sql` will have a different column order than those who
        /// migrated an existing install.
        ///
        /// This migration drops the column, which is not yet used (it will
        /// eventually be used for Backups-related attachment business), and
        /// re-adds it so that all users will have the column in the same
        /// location. To avoid rewriting data for users whose column is already
        /// at the end of the column list, we check first that the user has the
        /// column in the middle of the list.
        migrator.registerMigration(.reorderMediaTierDigestColumn) { tx in
            let digestColumn = "mediaTierDigestSHA256Ciphertext"

            let existingColumns = try tx.database.columns(in: "Attachment")
            guard let lastColumn = existingColumns.last else {
                throw OWSAssertionError("Missing columns for Attachment table!")
            }

            if lastColumn.name == digestColumn {
                // No need to drop and re-add! The column is at the end, so this
                // must be a migrated (not fresh-installed) database.
                return .success(())
            }

            try tx.database.alter(table: "Attachment") { table in
                table.drop(column: digestColumn)
                table.add(column: digestColumn, .blob)
            }

            return .success(())
        }

        migrator.registerMigration(.addIncrementalMacParamsToAttachment) { tx in
            try tx.database.alter(table: "Attachment") { table in
                table.add(column: "incrementalMac", .blob)
                table.add(column: "incrementalMacChunkSize", .integer)
            }

            return .success(())
        }

        migrator.registerMigration(.splitIncrementalMacAttachmentColumns) { tx in

            try tx.database.alter(table: "Attachment") { table in
                table.rename(column: "incrementalMac", to: "mediaTierIncrementalMac")
                table.rename(column: "incrementalMacChunkSize", to: "mediaTierIncrementalMacChunkSize")
                table.add(column: "transitTierIncrementalMac", .blob)
                table.add(column: "transitTierIncrementalMacChunkSize", .integer)
            }

            return .success(())
        }

        migrator.registerMigration(.addCallEndedTimestampToCallRecord) { tx in
            try tx.database.alter(table: "CallRecord") { table in
                table.add(column: "callEndedTimestamp", .integer)
                    .notNull()
                    .defaults(to: 0)
            }

            return .success(())
        }

        migrator.registerMigration(.addIsViewOnceColumnToMessageAttachmentReference) { tx in
            try tx.database.alter(table: "MessageAttachmentReference") { table in
                table.add(column: "isViewOnce", .boolean)
                    .notNull()
                    .defaults(to: false)
            }
            return .success(())
        }

        migrator.registerMigration(.backfillIsViewOnceMessageAttachmentReference) { tx in
            let cursor = try UInt64.fetchCursor(
                tx.database,
                sql: "SELECT id from model_TSInteraction where isViewOnceMessage = 1;",
            )
            while let nextInteractionId = try cursor.next() {
                try tx.database.execute(
                    sql: """
                    UPDATE MessageAttachmentReference
                    SET isViewOnce = 1
                    WHERE ownerRowId = ?
                    """,
                    arguments: [nextInteractionId],
                )
            }

            return .success(())
        }

        migrator.registerMigration(.addAttachmentValidationBackfillTable) { tx in
            try tx.database.create(table: "AttachmentValidationBackfillQueue") { table in
                table.column("attachmentId", .integer)
                    .notNull()
                    .references("Attachment", column: "id", onDelete: .cascade)
                    .primaryKey(onConflict: .ignore)
            }
            return .success(())
        }

        migrator.registerMigration(.addIsSmsColumnToTSAttachment) { tx in
            try tx.database.alter(table: "model_TSInteraction") { table in
                table.add(column: "isSmsMessageRestoredFromBackup", .boolean)
                    .defaults(to: false)
            }

            return .success(())
        }

        migrator.registerMigration(.addInKnownMessageRequestStateToHiddenRecipient) { tx in
            try tx.database.alter(table: "HiddenRecipient") { table in
                table.add(column: "inKnownMessageRequestState", .boolean)
                    .notNull()
                    .defaults(to: false)
            }

            return .success(())
        }

        migrator.registerMigration(.addBackupAttachmentUploadQueue) { tx in
            try tx.database.create(table: "BackupAttachmentUploadQueue") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("attachmentRowId", .integer)
                    .references("Attachment", column: "id", onDelete: .cascade)
                    .notNull()
                    .unique()
                table.column("sourceType", .integer)
                    .notNull()
                table.column("timestamp", .integer)
            }

            try tx.database.create(
                index: "index_BackupAttachmentUploadQueue_on_sourceType_timestamp",
                on: "BackupAttachmentUploadQueue",
                columns: ["sourceType", "timestamp"],
            )

            return .success(())
        }

        migrator.registerMigration(.addBackupStickerPackDownloadQueue) { tx in
            try tx.database.create(table: "BackupStickerPackDownloadQueue") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("packId", .blob)
                    .notNull()
                table.column("packKey", .blob)
                    .notNull()
            }

            return .success(())
        }

        migrator.registerMigration(.createOrphanedBackupAttachmentTable) { tx in
            // A prior version of this migration is being reverted.
            try tx.database.execute(sql: "DROP TABLE IF EXISTS OrphanedBackupAttachment")
            try tx.database.execute(sql: "DROP TRIGGER IF EXISTS __Attachment_ad_backup_fullsize")
            try tx.database.execute(sql: "DROP TRIGGER IF EXISTS __Attachment_ad_backup_thumbnail")

            /// Rows are written into here to enqueue attachments for deletion from the media tier cdn.
            try tx.database.create(table: "OrphanedBackupAttachment") { table in
                table.autoIncrementedPrimaryKey("id").notNull()
                table.column("cdnNumber", .integer).notNull()
                table.column("mediaName", .text)
                table.column("mediaId", .blob)
                table.column("type", .integer)
            }

            try tx.database.create(
                index: "index_OrphanedBackupAttachment_on_mediaName",
                on: "OrphanedBackupAttachment",
                columns: ["mediaName"],
            )
            try tx.database.create(
                index: "index_OrphanedBackupAttachment_on_mediaId",
                on: "OrphanedBackupAttachment",
                columns: ["mediaId"],
            )

            /// When we delete an attachment row in the database, insert into the orphan backup table
            /// so we can clean up the cdn upload later.
            /// Note this doesn't cover if we start an upload/cdn copy and are interrupted. The attachment
            /// could exist on the cdn but we don't know about it locally, and it later gets deleted locally.
            /// We will pick up on this the next time we query the server list endpoint; this trigger doesn't handle it.
            try tx.database.execute(sql: """
                CREATE TRIGGER "__Attachment_ad_backup_fullsize" AFTER DELETE ON "Attachment"
                    WHEN (
                        OLD.mediaTierCdnNumber IS NOT NULL
                        AND OLD.mediaName IS NOT NULL
                    )
                    BEGIN
                    INSERT INTO OrphanedBackupAttachment (
                      cdnNumber
                      ,mediaName
                      ,mediaId
                      ,type
                    ) VALUES (
                      OLD.mediaTierCdnNumber
                      ,OLD.mediaName
                      ,NULL
                      ,0
                    );
                  END;
            """)
            try tx.database.execute(sql: """
                CREATE TRIGGER "__Attachment_ad_backup_thumbnail" AFTER DELETE ON "Attachment"
                    WHEN (
                        OLD.thumbnailCdnNumber IS NOT NULL
                        AND OLD.mediaName IS NOT NULL
                    )
                    BEGIN
                    INSERT INTO OrphanedBackupAttachment (
                      cdnNumber
                      ,mediaName
                      ,mediaId
                      ,type
                    ) VALUES (
                      OLD.thumbnailCdnNumber
                      ,OLD.mediaName
                      ,NULL
                      ,1
                    );
                  END;
            """)

            return .success(())
        }

        migrator.registerMigration(.addCallLinkTable) { tx in
            try addCallLinkTable(tx: tx)
            return .success(())
        }

        migrator.registerMigration(.deleteIncomingGroupSyncJobRecords) { tx in
            try tx.database.execute(sql: "DELETE FROM model_SSKJobRecord WHERE label = ?", arguments: ["IncomingGroupSync"])
            return .success(())
        }

        migrator.registerMigration(.deleteKnownStickerPackTable) { tx in
            try tx.database.execute(sql: "DROP TABLE IF EXISTS model_KnownStickerPack")
            return .success(())
        }

        migrator.registerMigration(.addReceiptCredentialColumnToJobRecord) { tx in
            try tx.database.alter(table: "model_SSKJobRecord") { table in
                table.add(column: "receiptCredential", .blob)
            }
            return .success(())
        }

        migrator.registerMigration(.dropOrphanedGroupStoryReplies) { tx in
            let groupThreadUniqueIdCursor = try String.fetchCursor(
                tx.database,
                sql: """
                SELECT uniqueId
                FROM model_TSThread
                WHERE groupModel IS NOT NULL;
                """,
            )

            while let threadUniqueId = try groupThreadUniqueIdCursor.next() {
                try tx.database.execute(
                    sql: """
                    DELETE FROM model_TSInteraction
                    WHERE (
                        uniqueThreadId = ?
                        AND isGroupStoryReply = 1
                        AND recordType IS NOT 70
                        AND (storyTimestamp, storyAuthorUuidString) NOT IN (
                            SELECT timestamp, authorUuid
                            FROM model_StoryMessage
                        )
                    );
                    """,
                    arguments: [threadUniqueId],
                )
            }
            return .success(())
        }

        migrator.registerMigration(.addMessageBackupAvatarFetchQueue) { tx in
            try tx.database.create(table: "MessageBackupAvatarFetchQueue") { table in
                table.column("id", .integer).primaryKey().notNull()
                table.column("groupThreadRowId", .integer)
                    .references("model_TSThread", column: "id", onDelete: .cascade)
                table.column("groupAvatarUrl", .text)
                table.column("serviceId", .blob)
            }
            return .success(())
        }

        migrator.registerMigration(.addMessageBackupAvatarFetchQueueRetries) { tx in
            try tx.database.alter(table: "MessageBackupAvatarFetchQueue") { table in
                table.add(column: "numRetries", .integer).notNull().defaults(to: 0)
                table.add(column: "nextRetryTimestamp", .integer).notNull().defaults(to: 0)
            }
            try tx.database.create(
                index: "index_MessageBackupAvatarFetchQueue_on_nextRetryTimestamp",
                on: "MessageBackupAvatarFetchQueue",
                columns: ["nextRetryTimestamp"],
            )
            return .success(())
        }

        migrator.registerMigration(.addEditStateToMessageAttachmentReference) { tx in
            try tx.database.alter(table: "MessageAttachmentReference") { table in
                table.add(column: "ownerIsPastEditRevision", .boolean)
                    .defaults(to: false)
            }
            // TSEditState.pastRevision rawValue is 2
            try tx.database.execute(sql: """
            UPDATE MessageAttachmentReference
            SET ownerIsPastEditRevision = (
              SELECT model_TSInteraction.editState = 2
              FROM model_TSInteraction
              WHERE MessageAttachmentReference.ownerRowId = model_TSInteraction.id
            );
            """)
            return .success(())
        }

        migrator.registerMigration(.removeVersionedDMTimerCapabilities) { tx in
            try tx.database.drop(table: "VersionedDMTimerCapabilities")
            return .success(())
        }

        migrator.registerMigration(.removeJobRecordTSAttachmentColumns) { tx in
            // Remove TSAttachmentMultisend records.
            try tx.database.execute(sql: """
            DELETE FROM model_SSKJobRecord WHERE recordType = 58;
            """)
            try tx.database.alter(table: "model_SSKJobRecord") { table in
                table.drop(column: "attachmentId")
                table.drop(column: "attachmentIdMap")
                table.drop(column: "unsavedMessagesToSend")
            }
            return .success(())
        }

        migrator.registerMigration(.deprecateAttachmentIdsColumn) { tx in
            try tx.database.alter(table: "model_TSInteraction") { table in
                table.rename(column: "attachmentIds", to: "deprecated_attachmentIds")
            }
            return .success(())
        }

        migrator.registerMigration(.dropMediaGalleryItemTable) { tx in
            try tx.database.drop(table: "media_gallery_items")
            return .success(())
        }

        migrator.registerMigration(.addBackupsReceiptCredentialStateToJobRecord) { tx in
            try tx.database.alter(table: "model_SSKJobRecord") { table in
                table.add(column: "BRCRJR_state", .blob)
            }

            return .success(())
        }

        migrator.registerMigration(.recreateTSAttachment) { tx in
            try tx.database.execute(sql: """
            CREATE
                 TABLE
                     IF NOT EXISTS "model_TSAttachment" (
                         "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
                         ,"recordType" INTEGER NOT NULL
                         ,"uniqueId" TEXT NOT NULL UNIQUE
                             ON CONFLICT FAIL
                         ,"albumMessageId" TEXT
                         ,"attachmentType" INTEGER NOT NULL
                         ,"blurHash" TEXT
                         ,"byteCount" INTEGER NOT NULL
                         ,"caption" TEXT
                         ,"contentType" TEXT NOT NULL
                         ,"encryptionKey" BLOB
                         ,"serverId" INTEGER NOT NULL
                         ,"sourceFilename" TEXT
                         ,"cachedAudioDurationSeconds" DOUBLE
                         ,"cachedImageHeight" DOUBLE
                         ,"cachedImageWidth" DOUBLE
                         ,"creationTimestamp" DOUBLE
                         ,"digest" BLOB
                         ,"isUploaded" INTEGER
                         ,"isValidImageCached" INTEGER
                         ,"isValidVideoCached" INTEGER
                         ,"lazyRestoreFragmentId" TEXT
                         ,"localRelativeFilePath" TEXT
                         ,"mediaSize" BLOB
                         ,"pointerType" INTEGER
                         ,"state" INTEGER
                         ,"uploadTimestamp" INTEGER NOT NULL DEFAULT 0
                         ,"cdnKey" TEXT NOT NULL DEFAULT ''
                         ,"cdnNumber" INTEGER NOT NULL DEFAULT 0
                         ,"isAnimatedCached" INTEGER
                         ,"attachmentSchemaVersion" INTEGER DEFAULT 0
                         ,"videoDuration" DOUBLE
                         ,"clientUuid" TEXT
                     )
            ;
            """)

            try tx.database.execute(sql: """
            CREATE
                 INDEX IF NOT EXISTS "index_model_TSAttachment_on_uniqueId_and_contentType"
                     ON "model_TSAttachment"("uniqueId"
                 ,"contentType"
             )
             ;
            """)
            return .success(())
        }

        migrator.registerMigration(.recreateTSAttachmentMigration) { tx in
            try tx.database.execute(sql: """
            CREATE
                 TABLE
                     IF NOT EXISTS "TSAttachmentMigration" (
                         "tsAttachmentUniqueId" TEXT NOT NULL
                         ,"interactionRowId" INTEGER
                         ,"storyMessageRowId" INTEGER
                         ,"reservedV2AttachmentPrimaryFileId" BLOB NOT NULL
                         ,"reservedV2AttachmentAudioWaveformFileId" BLOB NOT NULL
                         ,"reservedV2AttachmentVideoStillFrameFileId" BLOB NOT NULL
                     )
            ;
            """)
            try tx.database.execute(sql: """
            CREATE
                 INDEX IF NOT EXISTS "index_TSAttachmentMigration_on_interactionRowId"
                     ON "TSAttachmentMigration" ("interactionRowId")
             WHERE
                 "interactionRowId" IS NOT NULL
             ;
            """)
            try tx.database.execute(sql: """
            CREATE
                 INDEX IF NOT EXISTS "index_TSAttachmentMigration_on_storyMessageRowId"
                     ON "TSAttachmentMigration" ("storyMessageRowId")
             WHERE
                 "storyMessageRowId" IS NOT NULL
             ;
            """)
            return .success(())
        }

        migrator.registerMigration(.addBlockedGroup) { tx in
            try tx.database.create(table: "BlockedGroup", options: [.withoutRowID]) { table in
                table.column("groupId", .blob).notNull().primaryKey()
            }

            let groupIds = try fetchAndClearBlockedGroupIds(tx: tx)

            for groupId in groupIds {
                try tx.database.execute(sql: "INSERT INTO BlockedGroup VALUES (?)", arguments: [groupId])
            }

            return .success(())
        }

        migrator.registerMigration(.addGroupSendEndorsement) { tx in
            try tx.database.create(table: "CombinedGroupSendEndorsement") { table in
                table.column("threadId", .integer).primaryKey()
                    .references("model_TSThread", column: "id", onDelete: .cascade, onUpdate: .cascade)
                table.column("endorsement", .blob).notNull()
                table.column("expiration", .integer).notNull()
            }
            try tx.database.create(table: "IndividualGroupSendEndorsement") { table in
                table.primaryKey(["threadId", "recipientId"])
                table.column("threadId", .integer).notNull()
                    .references("CombinedGroupSendEndorsement", column: "threadId", onDelete: .cascade, onUpdate: .cascade)
                table.column("recipientId", .integer).notNull()
                    .references("model_SignalRecipient", column: "id", onDelete: .cascade, onUpdate: .cascade)
                table.column("endorsement", .blob).notNull()
            }
            try tx.database.create(
                index: "IndividualGroupSendEndorsement_recipientId",
                on: "IndividualGroupSendEndorsement",
                columns: ["recipientId"],
            )
            return .success(())
        }

        migrator.registerMigration(.deleteLegacyMessageDecryptJobRecords) { tx in
            try tx.database.execute(sql: "DELETE FROM model_SSKJobRecord WHERE label = ?", arguments: ["SSKMessageDecrypt"])
            return .success(())
        }

        migrator.registerMigration(.dropMessageContentJobTable) { tx in
            try tx.database.execute(sql: "DROP TABLE IF EXISTS model_OWSMessageContentJob")
            return .success(())
        }

        migrator.registerMigration(.deleteMessageRequestInteractionEpoch) { tx in
            try tx.database.execute(
                sql: """
                DELETE FROM "keyvalue" WHERE "collection" = ? AND "key" = ?
                """,
                arguments: ["SSKPreferences", "messageRequestInteractionIdEpoch"],
            )
            return .success(())
        }

        migrator.registerMigration(.addAvatarDefaultColorTable) { tx in
            try Self.createDefaultAvatarColorTable(tx: tx)
            return .success(())
        }

        migrator.registerMigration(.populateAvatarDefaultColorTable) { tx in
            try Self.populateDefaultAvatarColorTable(tx: tx)
            return .success(())
        }

        migrator.registerMigration(.addStoryRecipient) { tx in
            try createStoryRecipients(tx: tx)
            return .success(())
        }

        migrator.registerMigration(.addAttachmentLastFullscreenViewTimestamp) { tx in
            try tx.database.alter(table: "Attachment") { table in
                table.add(column: "lastFullscreenViewTimestamp", .integer)
            }
            return .success(())
        }

        migrator.registerMigration(.addByteCountAndIsFullsizeToBackupAttachmentUpload) { tx in
            // At the time of this migration, no user could have backups
            // and therefore its fine to just drop the table and recreate.
            try tx.database.drop(table: "BackupAttachmentUploadQueue")

            try tx.database.create(table: "BackupAttachmentUploadQueue") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("attachmentRowId", .integer)
                    .references("Attachment", column: "id", onDelete: .cascade)
                    .notNull()
                table.column("maxOwnerTimestamp", .integer)
                table.column("estimatedByteCount", .integer)
                    .notNull()
                table.column("isFullsize", .boolean)
                    .notNull()
            }

            // For efficient cascade deletes and lookups
            try tx.database.create(
                index: "index_BackupAttachmentUploadQueue_on_attachmentRowId",
                on: "BackupAttachmentUploadQueue",
                columns: ["attachmentRowId"],
            )
            // For efficient sorting by timestamp
            try tx.database.create(
                index: "index_BackupAttachmentUploadQueue_on_maxOwnerTimestamp_isFullsize",
                on: "BackupAttachmentUploadQueue",
                columns: ["maxOwnerTimestamp", "isFullsize"],
            )

            return .success(())
        }

        migrator.registerMigration(.refactorBackupAttachmentDownload) { tx in
            // We want to migrate existing rows but the alterations we want to make aren't
            // allowed (removing UNIQUE constraint) so keep both tables then copy.
            try tx.database.rename(table: "BackupAttachmentDownloadQueue", to: "tmp_BackupAttachmentDownloadQueue")

            try tx.database.create(table: "BackupAttachmentDownloadQueue") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("attachmentRowId", .integer)
                    .notNull()
                    .references("Attachment", column: "id", onDelete: .cascade)
                table.column("isThumbnail", .boolean).notNull()
                table.column("maxOwnerTimestamp", .integer)
                table.column("canDownloadFromMediaTier", .boolean).notNull()
                table.column("minRetryTimestamp", .integer).notNull()
                table.column("numRetries", .integer).notNull().defaults(to: 0)
                table.column("state", .integer)
                table.column("estimatedByteCount", .integer).notNull()
            }
            // For efficient cascade deletes and lookups
            try tx.database.create(
                index: "index_BackupAttachmentDownloadQueue_on_attachmentRowId",
                on: "BackupAttachmentDownloadQueue",
                columns: ["attachmentRowId"],
            )
            // For efficient sorting when downloading and popping off the queue,
            // which only applies to those in the Ready state.
            // We download recent thumbnails first, then recent fullsize, then
            // old thumbnails, then old fullsize.
            try tx.database.create(
                index: "index_BackupAttachmentDownloadQueue_on_state_isThumbnail_minRetryTimestamp",
                on: "BackupAttachmentDownloadQueue",
                columns: ["state", "isThumbnail", "minRetryTimestamp"],
            )
            // When we enable storage optimization with paid backups, we want to mark
            // ineligible any fullsize rows which are on the media tier and are old
            // enough that they'd be offloaded if we did download them; we mark these
            // ineligible up front in an UPDATE so they're evicted from the byte count.
            try tx.database.create(
                index: "index_BackupAttachmentDownloadQueue_on_isThumbnail_canDownloadFromMediaTier_state_maxOwnerTimestamp",
                on: "BackupAttachmentDownloadQueue",
                columns: ["isThumbnail", "canDownloadFromMediaTier", "state", "maxOwnerTimestamp"],
            )
            // This lets us quickly sum total estimated byte count per-state, so we can count
            // remaining bytes vs already-downloaded bytes.
            try tx.database.create(
                index: "index_BackupAttachmentDownloadQueue_on_state_estimatedByteCount",
                on: "BackupAttachmentDownloadQueue",
                columns: ["state", "estimatedByteCount"],
            )

            let nowMs = Date().ows_millisecondsSince1970

            // Now copy over from the old table to the new table.
            // At time of writing backups is not launched so the only
            // rows in this table are fullsize transit tier downloads enqueued
            // from a link'n'sync, which were removed when done so they're all
            // in the ready state.
            try tx.database.execute(
                sql: """
                INSERT INTO BackupAttachmentDownloadQueue (
                    attachmentRowId,
                    isThumbnail,
                    maxOwnerTimestamp,
                    canDownloadFromMediaTier,
                    minRetryTimestamp,
                    state,
                    estimatedByteCount
                )
                SELECT
                    attachmentRowId,
                    0, -- no thumbnails; see comment above
                    timestamp,
                    0, -- no media tier downloads; see comment above
                    CASE WHEN timestamp IS NULL
                        THEN 0             -- NULL timestamps first
                        ELSE ? - timestamp -- then newest first
                    END,
                    1, -- ready; see comment above
                    0  -- just set estimated byte count to 0; existing link'n'syncs won't get progress.
                FROM tmp_BackupAttachmentDownloadQueue;
                """,
                arguments: [nowMs],
            )

            try tx.database.drop(table: "tmp_BackupAttachmentDownloadQueue")

            return .success(())
        }

        migrator.registerMigration(.removeAttachmentMediaTierDigestColumn) { tx in
            try tx.database.alter(table: "Attachment") { table in
                table.drop(column: "mediaTierDigestSHA256Ciphertext")
            }
            return .success(())
        }

        migrator.registerMigration(.addListMediaTable) { tx in
            try tx.database.create(table: "ListedBackupMediaObject") { table in
                table.column("id", .integer).primaryKey(autoincrement: true)
                table.column("mediaId", .blob).notNull()
                table.column("cdnNumber", .integer).notNull()
                table.column("objectLength", .integer).notNull()
            }

            try tx.database.create(
                index: "index_ListedBackupMediaObject_on_mediaId",
                on: "ListedBackupMediaObject",
                columns: ["mediaId"],
            )

            return .success(())
        }

        migrator.registerMigration(.recomputeAttachmentMediaNames) { tx in
            try tx.database.execute(
                sql: """
                UPDATE Attachment
                SET mediaName = CASE
                    WHEN sha256ContentHash IS NOT NULL AND encryptionKey IS NOT NULL
                        THEN lower(hex(sha256ContentHash || encryptionKey))
                    ELSE NULL
                END;
                """,
            )

            return .success(())
        }

        migrator.registerMigration(.lastDraftInteractionRowID) { tx in
            try tx.database.alter(table: "model_TSThread") { table in
                table.add(column: "lastDraftInteractionRowId", .integer).defaults(to: 0)
            }

            try tx.database.alter(table: "model_TSThread") { table in
                table.add(column: "lastDraftUpdateTimestamp", .integer).defaults(to: 0)
            }

            return .success(())
        }

        migrator.registerMigration(.addBackupOversizeText) { tx in
            try tx.database.create(table: "BackupOversizeTextCache") { table in
                table.autoIncrementedPrimaryKey("id")
                // Row id of the associated Attachment.
                table.column("attachmentRowId", .integer)
                    .unique()
                    .references("Attachment", column: "id", onDelete: .cascade)
                    .notNull()
                table.column("text", .text)
                    .notNull()
                    // Text length is limited to 128 kibibytes.
                    // enforce at SQL level to prevent ambiguity.
                    .check({ length($0) < (128 * 1024) })
            }

            // NOTE: recreated below because of < vs <=

            return .success(())
        }

        /// Ensure the migration value and the live app value are identical; if we change the live app
        /// value we need a new migration to update the CHECK clause below.
        owsAssertDebug(BackupOversizeTextCache.maxTextLengthBytes == 128 * 1024)

        migrator.registerMigration(.addBackupOversizeTextRedux) { tx in
            // NOTE: recreated because of < vs <=; okay to drop existing table
            try tx.database.drop(table: "BackupOversizeTextCache")

            try tx.database.create(table: "BackupOversizeTextCache") { table in
                table.autoIncrementedPrimaryKey("id")
                // Row id of the associated Attachment.
                table.column("attachmentRowId", .integer)
                    .unique()
                    .references("Attachment", column: "id", onDelete: .cascade)
                    .notNull()
                table.column("text", .text)
                    .notNull()
                    // Text length is limited to 128 kibibytes.
                    // enforce at SQL level to prevent ambiguity.
                    .check({ length($0) <= (128 * 1024) })
            }

            return .success(())
        }

        migrator.registerMigration(.addRetriesToBackupAttachmentUploadQueue) { tx in
            try tx.database.alter(table: "BackupAttachmentUploadQueue") { table in
                table.add(column: "numRetries", .integer).notNull().defaults(to: 0)
                table.add(column: "minRetryTimestamp", .integer).notNull().defaults(to: 0)
            }

            return .success(())
        }

        migrator.registerMigration(.replaceOWSDeviceTable) { tx in
            try tx.database.drop(table: "model_OWSDevice")

            try tx.database.create(table: "OWSDevice") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("deviceId", .integer).notNull()
                table.column("createdAt", .double).notNull()
                table.column("lastSeenAt", .double).notNull()
                table.column("name", .text)
            }

            return .success(())
        }

        migrator.registerMigration(.reindexBackupAttachmentUploadQueue) { tx in
            try tx.database.drop(index: "index_BackupAttachmentUploadQueue_on_maxOwnerTimestamp_isFullsize")
            // For efficient sorting by timestamp
            try tx.database.create(
                index: "index_BackupAttachmentUploadQueue_on_isFullsize_maxOwnerTimestamp",
                on: "BackupAttachmentUploadQueue",
                columns: ["isFullsize", "maxOwnerTimestamp"],
            )
            return .success(())
        }

        migrator.registerMigration(.dropAllIncrementalMacs) { tx in
            try tx.database.execute(sql: """
                UPDATE Attachment
                SET
                    mediaTierIncrementalMac = NULL,
                    mediaTierIncrementalMacChunkSize = NULL,
                    transitTierIncrementalMac = NULL,
                    transitTierIncrementalMacChunkSize = NULL;
            """)
            return .success(())
        }

        migrator.registerMigration(.addOriginalTransitTierInfoAttachmentColumns) { tx in
            try tx.database.alter(table: "Attachment") { table in
                table.add(column: "originalTransitCdnNumber", .integer)
                table.add(column: "originalTransitCdnKey", .text)
                table.add(column: "originalTransitUploadTimestamp", .integer)
                table.add(column: "originalTransitUnencryptedByteCount", .integer)
                table.add(column: "originalTransitDigestSHA256Ciphertext", .blob)
                table.add(column: "originalTransitTierIncrementalMac", .blob)
                table.add(column: "originalTransitTierIncrementalMacChunkSize", .integer)
            }
            return .success(())
        }

        migrator.registerMigration(.rebuildIncompleteViewOnceIndex) { tx in
            try self.rebuildIncompleteViewOnceIndex(tx: tx)
            return .success(())
        }

        migrator.registerMigration(.addIsPollToTSInteraction) { tx in
            try tx.database.alter(table: "model_TSInteraction") { table in
                table.add(column: "isPoll", .boolean)
                    .defaults(to: false)
            }

            try tx.database.create(
                table: "Poll",
            ) { table in
                table.column("id", .integer).primaryKey().notNull()
                table.column("interactionId", .integer)
                    .notNull()
                    .references(
                        "model_TSInteraction",
                        column: "id",
                        onDelete: .cascade,
                        onUpdate: .cascade,
                    )
                table.column("isEnded", .boolean)
                table.column("allowsMultiSelect", .boolean)
            }

            try tx.database.create(
                table: "PollOption",
            ) { table in
                table.column("id", .integer).primaryKey().notNull()
                table.column("pollId", .integer)
                    .notNull()
                    .references(
                        "Poll",
                        column: "id",
                        onDelete: .cascade,
                        onUpdate: .cascade,
                    )
                table.column("option", .text)
                table.column("optionIndex", .integer)
            }

            try tx.database.create(
                table: "PollVote",
            ) { table in
                table.column("id", .integer).primaryKey().notNull()
                table.column("optionId", .integer)
                    .notNull()
                    .references(
                        "PollOption",
                        column: "id",
                        onDelete: .cascade,
                        onUpdate: .cascade,
                    )
                table.column("voteAuthorId", .integer)
                    .unique()
                    .references(
                        "model_SignalRecipient",
                        column: "id",
                        onDelete: .cascade,
                        onUpdate: .cascade,
                    )
                table.column("voteCount", .integer)
            }

            try tx.database.create(
                index: "index_poll_on_interactionId",
                on: "Poll",
                columns: ["interactionId"],
            )

            try tx.database.create(
                index: "index_polloption_on_pollId",
                on: "PollOption",
                columns: ["pollId"],
            )

            try tx.database.create(
                index: "index_pollvote_on_optionId",
                on: "PollVote",
                columns: ["optionId"],
            )

            return .success(())
        }

        migrator.registerMigration(.addBackupAttachmentUploadQueueStateColumn) { tx in

            try tx.database.alter(table: "BackupAttachmentUploadQueue") { table in
                table.add(column: "state", .integer)
                    .defaults(to: 0)
            }

            try tx.database.drop(index: "index_BackupAttachmentUploadQueue_on_isFullsize_maxOwnerTimestamp")

            try tx.database.create(
                index: "index_BackupAttachmentUploadQueue_on_state_isFullsize_maxOwnerTimestamp",
                on: "BackupAttachmentUploadQueue",
                columns: ["state", "isFullsize", "maxOwnerTimestamp"],
            )

            return .success(())
        }

        migrator.registerMigration(.addBackupAttachmentUploadQueueTrigger) { tx in
            try tx.database.execute(sql: """
                CREATE TRIGGER __BackupAttachmentUploadQueue_au
                AFTER UPDATE OF state ON BackupAttachmentUploadQueue
                BEGIN
                    DELETE FROM BackupAttachmentUploadQueue
                        WHERE state = 1
                        AND NOT EXISTS (
                            SELECT id FROM BackupAttachmentUploadQueue WHERE state = 0
                        );
                END;
            """)
            return .success(())
        }

        migrator.registerMigration(.migrateRecipientDeviceIds) { tx in
            try migrateRecipientDeviceIds(tx: tx)
            return .success(())
        }

        migrator.registerMigration(.fixUniqueConstraintOnPollVotes) { tx in
            try tx.database.drop(table: "PollVote")

            try tx.database.create(
                table: "PollVote",
            ) { table in
                table.column("id", .integer).primaryKey().notNull()
                table.column("optionId", .integer)
                    .notNull()
                    .references(
                        "PollOption",
                        column: "id",
                        onDelete: .cascade,
                        onUpdate: .cascade,
                    )
                table.column("voteAuthorId", .integer)
                    .references(
                        "model_SignalRecipient",
                        column: "id",
                        onDelete: .cascade,
                        onUpdate: .cascade,
                    )
                table.column("voteCount", .integer)
            }

            try tx.database.create(
                index: "index_pollVote_on_voteAuthorId_and_optionId",
                on: "PollVote",
                columns: ["voteAuthorId", "optionId"],
                options: [.unique],
            )
            return .success(())
        }

        migrator.registerMigration(.migrateTSAccountManagerKeyValueStore) { tx in
            let migrator = KeyValueStoreMigrator(collection: "TSStorageUserAccountCollection")
            try migrator.migrateUInt32("TSStorageLocalRegistrationId", tx: tx)
            try migrator.migrateUInt32("TSStorageLocalPniRegistrationId", tx: tx)
            try migrator.migrateBool("TSAccountManager_ManualMessageFetchKey", tx: tx)
            try migrator.migrateBool("TSAccountManager_IsDiscoverableByPhoneNumber", tx: tx)
            try migrator.migrateDate("TSAccountManager_LastSetIsDiscoverableByPhoneNumberKey", tx: tx)
            try migrator.migrateString("TSStorageRegisteredNumberKey", tx: tx)
            try migrator.migrateString("TSStorageRegisteredUUIDKey", tx: tx)
            try migrator.migrateString("TSAccountManager_RegisteredPNIKey", tx: tx)
            try migrator.migrateUInt32("TSAccountManager_DeviceId", tx: tx)
            try migrator.migrateString("TSStorageServerAuthToken", tx: tx)
            try migrator.migrateDate("TSAccountManager_RegistrationDateKey", tx: tx)
            try migrator.migrateBool("TSAccountManager_IsDeregisteredKey", tx: tx)
            try migrator.migrateString("TSAccountManager_ReregisteringPhoneNumberKey", tx: tx)
            try migrator.migrateString("TSAccountManager_ReregisteringUUIDKey", tx: tx)
            try migrator.migrateBool("TSAccountManager_ReregisteringWasPrimaryDeviceKey", tx: tx)
            try migrator.migrateBool("TSAccountManager_IsTransferInProgressKey", tx: tx)
            try migrator.migrateBool("TSAccountManager_WasTransferredKey", tx: tx)
            return .success(())
        }

        migrator.registerMigration(.populateBackupAttachmentUploadProgressKVStore) { tx in
            let maxAttachmentRowId = try Int64.fetchOne(
                tx.database,
                sql: "SELECT MAX(id) FROM Attachment",
            ) ?? 0

            try tx.database.execute(
                sql: """
                    INSERT INTO keyvalue (collection, key, value)
                    VALUES (?, ?, ?)
                """,
                arguments: ["BackupAttachmentUploadProgress", "maxAttachmentRowId", maxAttachmentRowId],
            )

            return .success(())
        }

        // This hasn't launched yet, so its OK to drop and re-create the index.
        // The constraints need to be updated in order to support
        // a history of vote states.
        migrator.registerMigration(.addPollVoteState) { tx in
            try tx.database.alter(table: "PollVote") { table in
                table.add(column: "voteState", .integer)
                    .defaults(to: 0)
            }

            try tx.database.drop(index: "index_pollVote_on_voteAuthorId_and_optionId")
            try tx.database.create(
                index: "index_pollVote_on_voteAuthorId_and_optionId_voteCount",
                on: "PollVote",
                columns: ["voteAuthorId", "optionId", "voteCount"],
                options: [.unique],
            )
            return .success(())
        }

        migrator.registerMigration(.addPreKey) { tx in
            try createPreKey(tx: tx)
            if BuildFlags.decodeDeprecatedPreKeys {
                try migratePreKeys(tx: tx)
            }
            try dropOldPreKeys(tx: tx)
            return .success(())
        }

        migrator.registerMigration(.addKyberPreKeyUse) { tx in
            try tx.database.create(table: "KyberPreKeyUse", options: [.withoutRowID]) {
                $0.column("kyberRowId", .integer).notNull()
                    .references("PreKey", column: "rowId", onDelete: .cascade, onUpdate: .cascade)
                $0.column("signedPreKeyIdentity", .integer).notNull()
                $0.column("signedPreKeyId", .integer).notNull()
                $0.column("baseKey", .blob).notNull()
                $0.primaryKey(["kyberRowId", "signedPreKeyIdentity", "signedPreKeyId", "baseKey"])
            }
            return .success(())
        }

        migrator.registerMigration(.uniquifyUsernameLookupRecord) { tx in
            try uniquifyUsernameLookupRecord(caseInsensitive: false, tx: tx)
            return .success(())
        }

        migrator.registerMigration(.fixUpcomingCallLinks) { tx in
            try fixUpcomingCallLinks(tx: tx)
            return .success(())
        }

        migrator.registerMigration(.uniquifyUsernameLookupRecord2) { tx in
            // UsernameLookupRecord_UniqueUsernames enforces UNIQUE-ness for the
            // "username" column of UsernameLookupRecord...but when added was
            // case-sensitive, whereas usernames should be case-insensitive.
            //
            // To that end, replay the uniquification, case-insensitive.
            try tx.database.drop(index: "UsernameLookupRecord_UniqueUsernames")
            try uniquifyUsernameLookupRecord(caseInsensitive: true, tx: tx)
            return .success(())
        }

        migrator.registerMigration(.fixRevokedForRestoredCallLinks) { tx in
            try fixRevokedForRestoredCallLinks(tx: tx)
            return .success(())
        }

        migrator.registerMigration(.fixNameForRestoredCallLinks) { tx in
            try fixNameForRestoredCallLinks(tx: tx)
            return .success(())
        }

        migrator.registerMigration(.addPinnedMessagesTable) { tx in
            try tx.database.create(
                table: "PinnedMessage",
            ) { table in
                table.column("id", .integer).primaryKey().notNull()
                table.column("interactionId", .integer)
                    .notNull()
                    .unique()
                    .references(
                        "model_TSInteraction",
                        column: "id",
                        onDelete: .cascade,
                        onUpdate: .cascade,
                    )
                table.column("threadId", .integer)
                    .notNull()
                    .references(
                        "model_TSThread",
                        column: "id",
                        onDelete: .cascade,
                        onUpdate: .cascade,
                    )
                table.column("expiresAt", .integer)
            }

            try tx.database.create(
                index: "index_PinnedMessage_on_threadId",
                on: "PinnedMessage",
                columns: ["threadId"],
            )

            try tx.database.create(
                index: "partial_index_PinnedMessage_on_expiresAt",
                on: "PinnedMessage",
                columns: ["expiresAt"],
                condition: Column("expiresAt") != nil,
            )

            return .success(())
        }

        migrator.registerMigration(.addPinnedAtTimestampToPinnedMessageTable) { tx in
            try tx.database.alter(table: "PinnedMessage") { table in
                table.add(column: "sentTimestamp", .integer).notNull().defaults(to: 0)
                table.add(column: "receivedTimestamp", .integer).notNull().defaults(to: 0)
            }
            return .success(())
        }

        migrator.registerMigration(.dropTSAttachment) { tx in
            // Delete the legacy attachments folder, which is hopefully already
            // deleted.
            if
                let containerURL = FileManager.default.containerURL(
                    forSecurityApplicationGroupIdentifier: TSConstants.applicationGroup,
                )
            {
                let tsAttachmentsDir = containerURL.path.appendingPathComponent("Attachments")
                try? FileManager.default.removeItem(atPath: tsAttachmentsDir)
            }

            try tx.database.drop(table: "TSAttachmentMigration")
            try tx.database.drop(table: "model_TSAttachment")

            return .success(())
        }

        migrator.registerMigration(.deprecateStoredShouldStartExpireTimer) { tx in
            // In the distant past, there may have been messages with
            // storedShouldStartExpireTimer set that failed to set their
            // expiresAt, which is what drives message expiration. If any still
            // somehow exist, make them expire immediately.
            try tx.database.execute(sql: """
                UPDATE model_TSInteraction
                SET expireStartedAt = 1, expiresAt = 2
                WHERE storedShouldStartExpireTimer IS TRUE
                    AND (expiresAt IS 0 OR expireStartedAt IS 0)
            """)

            // Since storedShouldStartExpireTimer isn't used in any queries, we
            // can drop this index.
            try tx.database.drop(index: "index_interactions_on_threadUniqueId_storedShouldStartExpireTimer_and_expiresAt")
            return .success(())
        }

        migrator.registerMigration(.addSession) { tx in
            try createSession(tx: tx)
            if BuildFlags.migrateDeprecatedSessions {
                try migrateSessions(tx: tx)
            }
            try dropOldSessions(tx: tx)
            return .success(())
        }

        migrator.registerMigration(.addRecipientStatus) { tx in
            try addRecipientStatus(tx: tx)
            try migrateRecipientWhitelist(tx: tx)
            return .success(())
        }

        // MARK: - Schema Migration Insertion Point
    }

    private static func registerDataMigrations(migrator: DatabaseMigratorWrapper) {

        // The migration blocks should never throw. If we introduce a crashing
        // migration, we want the crash logs reflect where it occurred.

        migrator.registerMigration(.dataMigration_enableV2RegistrationLockIfNecessary) { transaction in
            if DependenciesBridge.shared.svr.hasMasterKey(transaction: transaction) {
                KeyValueStore(collection: "kOWS2FAManager_Collection")
                    .setBool(true, key: "isRegistrationLockV2Enabled", transaction: transaction)
            }

            return .success(())
        }

        migrator.registerMigration(.dataMigration_resetStorageServiceData) { transaction in
            SSKEnvironment.shared.storageServiceManagerRef.resetLocalData(transaction: transaction)
            return .success(())
        }

        migrator.registerMigration(.dataMigration_markAllInteractionsAsNotDeleted) { transaction in
            try transaction.database.execute(sql: "UPDATE model_TSInteraction SET wasRemotelyDeleted = 0")
            return .success(())
        }

        migrator.registerMigration(.dataMigration_turnScreenSecurityOnForExistingUsers) { transaction in
            guard try hasAnyAccountManagerState(tx: transaction) else {
                return .success(())
            }
            // Declare the key value store here, since it's normally only
            // available in SignalMessaging.Preferences.
            let preferencesKeyValueStore = KeyValueStore(collection: "SignalPreferences")
            let screenSecurityKey = "Screen Security Key"
            guard
                !preferencesKeyValueStore.hasValue(
                    screenSecurityKey,
                    transaction: transaction,
                )
            else {
                return .success(())
            }

            preferencesKeyValueStore.setBool(true, key: screenSecurityKey, transaction: transaction)
            return .success(())
        }

        migrator.registerMigration(.dataMigration_groupIdMapping) { transaction in
            TSThread.anyEnumerate(transaction: transaction) { (thread: TSThread, _: UnsafeMutablePointer<ObjCBool>) in
                guard let groupThread = thread as? TSGroupThread else {
                    return
                }
                TSGroupThread.setGroupIdMappingForLegacyThread(
                    threadUniqueId: groupThread.uniqueId,
                    groupId: groupThread.groupId,
                    tx: transaction,
                )
            }
            return .success(())
        }

        migrator.registerMigration(.dataMigration_disableSharingSuggestionsForExistingUsers) { transaction in
            guard try hasAnyAccountManagerState(tx: transaction) else {
                return .success(())
            }
            SSKPreferences.setAreIntentDonationsEnabled(false, transaction: transaction)
            return .success(())
        }

        migrator.registerMigration(.dataMigration_removeOversizedGroupAvatars) { transaction in
            var thrownError: Error?
            TSGroupThread.anyEnumerate(transaction: transaction) { (thread: TSThread, stop: UnsafeMutablePointer<ObjCBool>) in
                guard let groupThread = thread as? TSGroupThread else { return }
                guard let avatarData = groupThread.groupModel.legacyAvatarData else { return }
                guard !TSGroupModel.isValidGroupAvatarData(avatarData) else { return }

                var builder = groupThread.groupModel.asBuilder
                builder.avatarDataState = .missing
                builder.avatarUrlPath = nil

                do {
                    let newGroupModel = try builder.build()
                    groupThread.update(with: newGroupModel, transaction: transaction)
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
                transaction: transaction,
            )

            while let thread = try cursor.next() {
                if let thread = thread as? TSContactThread {
                    SSKEnvironment.shared.storageServiceManagerRef.recordPendingUpdates(updatedAddresses: [thread.contactAddress])
                } else if let thread = thread as? TSGroupThread {
                    SSKEnvironment.shared.storageServiceManagerRef.recordPendingUpdates(groupModel: thread.groupModel)
                } else {
                    owsFail("Unexpected thread type \(thread)")
                }
            }
            return .success(())
        }

        migrator.registerMigration(.dataMigration_populateGroupMember) { transaction in
            let cursor = TSThread.grdbFetchCursor(
                sql: """
                    SELECT *
                    FROM \(ThreadRecord.databaseTableName)
                    WHERE \(threadColumn: .recordType) = \(SDSRecordType.groupThread.rawValue)
                """,
                transaction: transaction,
            )

            while let thread = try cursor.next() {
                guard let groupThread = thread as? TSGroupThread else {
                    owsFail("Unexpected thread type \(thread)")
                }

                let groupThreadId = groupThread.uniqueId
                let interactionFinder = InteractionFinder(threadUniqueId: groupThreadId)

                groupThread.groupMembership.fullMembers.forEach { address in
                    // Group member addresses are low-trust, and the address cache has
                    // not been populated yet at this point in time. We want to record
                    // as close to a fully qualified address as we can in the database,
                    // so defer to the address from the signal recipient (if one exists)
                    let recipient = DependenciesBridge.shared.recipientDatabaseTable
                        .fetchRecipient(address: address, tx: transaction)
                    let memberAddress = recipient?.address ?? address

                    guard let newAddress = NormalizedDatabaseRecordAddress(address: memberAddress) else {
                        return
                    }

                    guard
                        TSGroupMember.groupMember(
                            for: memberAddress,
                            in: groupThreadId,
                            transaction: transaction,
                        ) == nil
                    else {
                        // If we already have a group member populated, for
                        // example from an earlier data migration, we should
                        // _not_ try and insert.
                        return
                    }

                    let latestInteraction = interactionFinder.latestInteraction(
                        from: memberAddress,
                        transaction: transaction,
                    )
                    let memberRecord = TSGroupMember(
                        address: newAddress,
                        groupThreadId: groupThread.uniqueId,
                        lastInteractionTimestamp: latestInteraction?.timestamp ?? 0,
                    )
                    memberRecord.anyInsert(transaction: transaction)
                }
            }
            return .success(())
        }

        migrator.registerMigration(.dataMigration_cullInvalidIdentityKeySendingErrors) { transaction in
            let sql = """
                DELETE FROM \(InteractionRecord.databaseTableName)
                WHERE \(interactionColumn: .recordType) = ?
            """
            try transaction.database.execute(
                sql: sql,
                arguments: [SDSRecordType.invalidIdentityKeySendingErrorMessage.rawValue],
            )
            return .success(())
        }

        migrator.registerMigration(.dataMigration_moveToThreadAssociatedData) { transaction in
            var thrownError: Error?
            TSThread.anyEnumerate(transaction: transaction) { (thread, stop: UnsafeMutablePointer<ObjCBool>) in
                do {
                    try ThreadAssociatedData(
                        threadUniqueId: thread.uniqueId,
                        isArchived: thread.isArchivedObsolete,
                        isMarkedUnread: thread.isMarkedUnreadObsolete,
                        mutedUntilTimestamp: thread.mutedUntilTimestampObsolete,
                        // this didn't exist pre-migration, just write the default
                        audioPlaybackRate: 1,
                    ).insert(transaction.database)
                } catch {
                    thrownError = error
                    stop.pointee = true
                }
            }
            return thrownError.map { .failure($0) } ?? .success(())
        }

        migrator.registerMigration(.dataMigration_senderKeyStoreKeyIdMigration) { transaction in
            OldSenderKeyStore.performKeyIdMigration(transaction: transaction)
            return .success(())
        }

        migrator.registerMigration(.dataMigration_reindexGroupMembershipAndMigrateLegacyAvatarDataFixed) { transaction in
            let threadCursor = TSThread.grdbFetchCursor(
                sql: "SELECT * FROM \(ThreadRecord.databaseTableName) WHERE \(threadColumn: .recordType) = \(SDSRecordType.groupThread.rawValue)",
                transaction: transaction,
            )

            while let thread = try threadCursor.next() as? TSGroupThread {
                try autoreleasepool {
                    let groupModel = thread.groupModel

                    guard
                        let legacyAvatarData = groupModel.legacyAvatarData,
                        !legacyAvatarData.isEmpty,
                        TSGroupModel.isValidGroupAvatarData(legacyAvatarData)
                    else {
                        groupModel.avatarHash = nil
                        groupModel.legacyAvatarData = nil
                        return
                    }

                    try groupModel.persistAvatarData(legacyAvatarData)
                    groupModel.legacyAvatarData = nil

                    thread.anyUpsert(transaction: transaction)
                }
            }

            // We previously re-indexed threads and group members here, but those
            // migrations are obsoleted by dataMigration_indexSearchableNames.

            return .success(())
        }

        migrator.registerMigration(.dataMigration_repairAvatar) { transaction in
            guard try hasAnyAccountManagerState(tx: transaction) else {
                return .success(())
            }
            // Declare the key value store here, since it's normally only
            // available in SignalMessaging.Preferences.
            let preferencesKeyValueStore = KeyValueStore(collection: Self.migrationSideEffectsCollectionName)
            let key = Self.avatarRepairAttemptCount
            preferencesKeyValueStore.setInt(0, key: key, transaction: transaction)
            return .success(())
        }

        migrator.registerMigration(.dataMigration_dropEmojiAvailabilityStore) { transaction in
            // This is a bit of a layering violation, since these tables were previously managed in the app layer.
            // In the long run we'll have a general "unused KeyValueStore cleaner" migration,
            // but for now this should drop 2000 or so rows for free.
            KeyValueStore(collection: "Emoji+availableStore").removeAll(transaction: transaction)
            KeyValueStore(collection: "Emoji+metadataStore").removeAll(transaction: transaction)
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

        migrator.registerMigration(.dataMigration_syncGroupStories) { transaction in
            for thread in ThreadFinder().storyThreads(includeImplicitGroupThreads: false, transaction: transaction) {
                guard let thread = thread as? TSGroupThread else { continue }
                SSKEnvironment.shared.storageServiceManagerRef.recordPendingUpdates(groupModel: thread.groupModel)
            }
            return .success(())
        }

        migrator.registerMigration(.dataMigration_deleteOldGroupCapabilities) { transaction in
            let sql = """
                DELETE FROM \(KeyValueStore.tableName)
                WHERE \(KeyValueStore.collectionColumnName)
                IN ("GroupManager.senderKeyCapability", "GroupManager.announcementOnlyGroupsCapability", "GroupManager.groupsV2MigrationCapability")
            """
            try transaction.database.execute(sql: sql)
            return .success(())
        }

        migrator.registerMigration(.dataMigration_updateStoriesDisabledInAccountRecord) { transaction in
            SSKEnvironment.shared.storageServiceManagerRef.recordPendingLocalAccountUpdates()
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
                DELETE FROM \(FullTextSearchIndexer.contentTableName)
                WHERE \(FullTextSearchIndexer.uniqueIdColumn) IN (\(uniqueIds.map { "\"\($0)\"" }.joined(separator: ", ")))
                AND \(FullTextSearchIndexer.collectionColumn) = 'TSInteraction'
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

        migrator.registerMigration(.dataMigration_scheduleStorageServiceUpdateForSystemContacts) { transaction in
            // We've added fields on the StorageService ContactRecord proto for
            // their "system name", or the name of their associated system
            // contact, if present. Consequently, for all Signal contacts with
            // a system contact, we should schedule a StorageService update.
            //
            // We only want to do this if we are the primary device, since only
            // the primary device's system contacts are synced.

            let tsAccountManager = DependenciesBridge.shared.tsAccountManager
            guard tsAccountManager.registrationState(tx: transaction).isPrimaryDevice ?? false else {
                return .success(())
            }

            var accountsToRemove: Set<SignalAccount> = []

            SignalAccount.anyEnumerate(transaction: transaction) { account, _ in
                guard account.isFromLocalAddressBook else {
                    // Skip any accounts that do not have a system contact
                    return
                }

                accountsToRemove.insert(account)
            }

            SSKEnvironment.shared.storageServiceManagerRef.recordPendingUpdates(updatedAddresses: accountsToRemove.map { $0.recipientAddress })
            return .success(())
        }

        migrator.registerMigration(.dataMigration_ensureLocalDeviceId) { tx in
            let store = NewKeyValueStore(collection: "TSStorageUserAccountCollection")
            let localAci = try store.fetchValueOrThrow(String.self, forKey: "TSStorageRegisteredUUIDKey", tx: tx)
            if localAci != nil {
                let localDeviceId = try store.fetchValueOrThrow(Int64.self, forKey: "TSAccountManager_DeviceId", tx: tx)
                if localDeviceId == nil {
                    // If we don't have a device id written, put the primary device id.
                    try store.writeValueOrThrow(1, forKey: "TSAccountManager_DeviceId", tx: tx)
                }
            }
            return .success(())
        }

        migrator.registerMigration(.dataMigration_indexSearchableNames) { tx in
            // Drop everything in case somebody adds an unrelated migration that
            // populates this table. (This has happened in the past.)
            try tx.database.execute(sql: """
            DELETE FROM "\(SearchableNameIndexerImpl.Constants.databaseTableName)"
            """)
            let searchableNameIndexer = DependenciesBridge.shared.searchableNameIndexer
            searchableNameIndexer.indexEverything(tx: tx)
            return .success(())
        }

        migrator.registerMigration(.dataMigration_removeSystemContacts) { transaction in
            let keyValueCollections = [
                "ContactsManagerCache.uniqueIdStore",
                "ContactsManagerCache.phoneNumberStore",
                "ContactsManagerCache.allContacts",
            ]

            for collection in keyValueCollections {
                KeyValueStore(collection: collection).removeAll(transaction: transaction)
            }

            return .success(())
        }

        migrator.registerMigration(.dataMigration_clearLaunchScreenCache2) { _ in
            OWSFileSystem.deleteFileIfExists(NSHomeDirectory() + "/Library/SplashBoard")
            return .success(())
        }

        migrator.registerMigration(.dataMigration_resetLinkedDeviceAuthorMergeBuilder) { tx in
            let tsAccountManager = DependenciesBridge.shared.tsAccountManager
            guard tsAccountManager.registrationState(tx: tx).isPrimaryDevice != true else {
                return .success(())
            }

            let keyValueCollections = [
                "AuthorMergeMetadata",
                "AuthorMergeNextRowId",
            ]

            for collection in keyValueCollections {
                KeyValueStore(collection: collection).removeAll(transaction: tx)
            }
            return .success(())
        }

        // MARK: - Data Migration Insertion Point
    }

    // MARK: - Migrations

    static func createStoryContextAssociatedData(tx transaction: DBWriteTransaction) throws {
        try transaction.database.create(table: StoryContextAssociatedData.databaseTableName) { table in
            table.autoIncrementedPrimaryKey(StoryContextAssociatedData.columnName(.id))
                .notNull()
            table.column(StoryContextAssociatedData.columnName(.recordType), .integer)
                .notNull()
            table.column(StoryContextAssociatedData.columnName(.uniqueId))
                .notNull()
                .unique(onConflict: .fail)
            table.column(StoryContextAssociatedData.columnName(.contactAci), .text)
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
            columns: [StoryContextAssociatedData.columnName(.contactAci)],
        )
        try transaction.database.create(
            index: "index_story_context_associated_data_contact_on_group_id",
            on: StoryContextAssociatedData.databaseTableName,
            columns: [StoryContextAssociatedData.columnName(.groupId)],
        )
    }

    static func populateStoryContextAssociatedData(tx transaction: DBWriteTransaction) throws {
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
                    arguments: [threadUniqueId],
                )
            {
                let lastReceivedStoryTimestamp = (threadRow["lastReceivedStoryTimestamp"] as? NSNumber)?.uint64Value
                let latestUnexpiredTimestamp = (lastReceivedStoryTimestamp ?? 0) > Date().ows_millisecondsSince1970 - UInt64.dayInMs
                    ? lastReceivedStoryTimestamp : nil
                let lastViewedStoryTimestamp = (threadRow["lastViewedStoryTimestamp"] as? NSNumber)?.uint64Value
                if
                    let groupModelData = threadRow["groupModel"] as? Data,
                    let groupId = try decodeGroupIdFromGroupModelData(groupModelData)
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
                            lastViewedStoryTimestamp,
                        ],
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
                            lastViewedStoryTimestamp,
                        ],
                    )
                }
            } else {
                // If we couldn't find a thread, that means this associated data was
                // created for a group we don't know about yet.
                // Stories is in beta at the time of this migration, so we will just drop it.
                Logger.info("Dropping StoryContextAssociatedData migration for ThreadAssociatedData without a TSThread")
            }
        }
    }

    static func dropColumnsMigratedToStoryContextAssociatedData(tx transaction: DBWriteTransaction) throws {
        // Drop the old columns since they are no longer needed.
        try transaction.database.alter(table: "model_TSThread") { alteration in
            alteration.drop(column: "lastViewedStoryTimestamp")
            alteration.drop(column: "lastReceivedStoryTimestamp")
        }
        try transaction.database.alter(table: "thread_associated_data") { alteration in
            alteration.drop(column: "hideStory")
        }
    }

    static func populateStoryMessageReplyCount(tx transaction: DBWriteTransaction) throws {
        let storyMessagesSql = """
            SELECT id, timestamp, authorUuid, groupId
            FROM model_StoryMessage
        """
        let storyMessages = try Row.fetchAll(transaction.database, sql: storyMessagesSql)
        for storyMessage in storyMessages {
            guard
                let id = storyMessage["id"] as? Int64,
                let timestamp = storyMessage["timestamp"] as? Int64,
                let authorUuid = storyMessage["authorUuid"] as? String
            else {
                continue
            }
            guard authorUuid != "00000000-0000-0000-0000-000000000001" else {
                // Skip the system story
                continue
            }
            let groupId = storyMessage["groupId"] as? Data
            let isGroupStoryMessage = groupId != nil
            // Use the index we have on storyTimestamp, storyAuthorUuidString, isGroupStoryReply
            let replyCountSql = """
                SELECT COUNT(*)
                FROM model_TSInteraction
                WHERE (
                    storyTimestamp = ?
                    AND storyAuthorUuidString = ?
                    AND isGroupStoryReply = ?
                )
            """
            let replyCount = try Int.fetchOne(
                transaction.database,
                sql: replyCountSql,
                arguments: [timestamp, authorUuid, isGroupStoryMessage],
            ) ?? 0

            try transaction.database.execute(
                sql: """
                    UPDATE model_StoryMessage
                    SET replyCount = ?
                    WHERE id = ?
                """,
                arguments: [replyCount, id],
            )
        }
    }

    static func migrateThreadReplyInfos(transaction: DBWriteTransaction) throws {
        let collection = "TSThreadReplyInfo"
        try transaction.database.execute(
            sql: """
                UPDATE "keyvalue" SET
                    "value" = json_replace("value", '$.author', json_extract("value", '$.author.backingUuid'))
                WHERE
                    "collection" IS ?
                    AND json_valid("value")
            """,
            arguments: [collection],
        )
        try transaction.database.execute(
            sql: """
                DELETE FROM "keyvalue" WHERE
                    "collection" IS ?
                    AND json_valid("value")
                    AND json_extract("value", '$.author') IS NULL
            """,
            arguments: [collection],
        )
    }

    static func migrateVoiceMessageDrafts(
        transaction: DBWriteTransaction,
        appSharedDataUrl: URL,
        copyItem: (URL, URL) throws -> Void,
    ) throws {
        // In the future, this entire migration could be safely replaced by the
        // `DELETE FROM…` query. The impact of that change would be to delete old
        // voice memo drafts rather than migrate them to the current version.

        let collection = "DraftVoiceMessage"
        let baseUrl = URL(fileURLWithPath: "draft-voice-messages", isDirectory: true, relativeTo: appSharedDataUrl)

        let oldRows = try Row.fetchAll(
            transaction.database,
            sql: "SELECT key, value FROM keyvalue WHERE collection IS ?",
            arguments: [collection],
        )
        try transaction.database.execute(sql: "DELETE FROM keyvalue WHERE collection IS ?", arguments: [collection])
        for oldRow in oldRows {
            let uniqueThreadId: String = oldRow[0]
            let hasDraft = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSNumber.self, from: oldRow[1])?.boolValue
            guard hasDraft == true else {
                continue
            }
            let oldRelativePath = uniqueThreadId.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
            let newRelativePath = UUID().uuidString
            do {
                try copyItem(
                    baseUrl.appendingPathComponent(oldRelativePath, isDirectory: true),
                    baseUrl.appendingPathComponent(newRelativePath, isDirectory: true),
                )
            } catch {
                Logger.warn("Couldn't migrate voice message draft \(error.shortDescription)")
                continue
            }
            try transaction.database.execute(
                sql: "INSERT INTO keyvalue (collection, key, value) VALUES (?, ?, ?)",
                arguments: [
                    collection,
                    uniqueThreadId,
                    try NSKeyedArchiver.archivedData(withRootObject: newRelativePath, requiringSecureCoding: true),
                ],
            )
        }
    }

    static func createEditRecordTable(tx: DBWriteTransaction) throws {
        try tx.database.create(
            table: "EditRecord",
        ) { table in
            table.autoIncrementedPrimaryKey("id")
                .notNull()
            table.column("latestRevisionId", .text)
                .notNull()
                .references(
                    "model_TSInteraction",
                    column: "id",
                    onDelete: .cascade,
                )
            table.column("pastRevisionId", .text)
                .notNull()
                .references(
                    "model_TSInteraction",
                    column: "id",
                    onDelete: .cascade,
                )
        }

        try tx.database.create(
            index: "index_edit_record_on_latest_revision_id",
            on: "EditRecord",
            columns: ["latestRevisionId"],
        )

        try tx.database.create(
            index: "index_edit_record_on_past_revision_id",
            on: "EditRecord",
            columns: ["pastRevisionId"],
        )
    }

    static func migrateEditRecordTable(tx: DBWriteTransaction) throws {
        let finalTableName = EditRecord.databaseTableName
        let tempTableName = "\(finalTableName)_temp"

        // Create a temporary EditRecord with correct constraints/types
        try tx.database.create(
            table: tempTableName,
        ) { table in
            table.autoIncrementedPrimaryKey("id")
                .notNull()
            table.column("latestRevisionId", .integer)
                .notNull()
                .references(
                    "model_TSInteraction",
                    column: "id",
                    onDelete: .restrict,
                )
            table.column("pastRevisionId", .integer)
                .notNull()
                .references(
                    "model_TSInteraction",
                    column: "id",
                    onDelete: .restrict,
                )
        }

        // Migrate edit records from old table to new
        try tx.database.execute(sql: """
        INSERT INTO \(tempTableName)
            (id, latestRevisionId, pastRevisionId)
            SELECT id, latestRevisionId, pastRevisionId
            FROM \(finalTableName);
        """)

        // Remove the old Edit record table & indexes
        try tx.database.execute(sql: "DROP TABLE IF EXISTS \(finalTableName);")
        try tx.database.execute(sql: "DROP INDEX IF EXISTS index_edit_record_on_latest_revision_id;")
        try tx.database.execute(sql: "DROP INDEX IF EXISTS index_edit_record_on_past_revision_id;")

        // Rename the new table to the correct name
        try tx.database.execute(sql: "ALTER TABLE \(tempTableName) RENAME TO \(finalTableName);")

        // Rebuild the indexes
        try tx.database.create(
            index: "index_edit_record_on_latest_revision_id",
            on: "\(finalTableName)",
            columns: ["latestRevisionId"],
        )

        try tx.database.create(
            index: "index_edit_record_on_past_revision_id",
            on: "\(finalTableName)",
            columns: ["pastRevisionId"],
        )
    }

    private static func enableFts5SecureDelete(for tableName: StaticString, db: Database) throws {
        try db.execute(sql: """
            INSERT INTO "\(tableName)" ("\(tableName)", "rank") VALUES ('secure-delete', 1)
        """)
    }

    static func removeLocalProfileSignalRecipient(in db: Database) throws {
        try db.execute(sql: """
        DELETE FROM "model_SignalRecipient" WHERE "recipientPhoneNumber" = 'kLocalProfileUniqueId'
        """)
    }

    static func removeRedundantPhoneNumbers(
        in db: Database,
        tableName: StaticString,
        serviceIdColumn: StaticString,
        phoneNumberColumn: StaticString,
    ) throws {
        // If kLocalProfileUniqueId has a ServiceId, remove it. This should only
        // exist for OWSUserProfile (and it shouldn't have a ServiceId), but it
        // unfortunately exists for threads as well.
        try db.execute(sql: """
        UPDATE "\(tableName)"
        SET
            "\(serviceIdColumn)" = NULL
        WHERE
            "\(phoneNumberColumn)" = 'kLocalProfileUniqueId'
        """)

        // If there are any rows with an ACI & phone number, remove the latter.
        try db.execute(sql: """
        UPDATE "\(tableName)"
        SET
            "\(phoneNumberColumn)" = NULL
        WHERE
            "\(serviceIdColumn)" < 'PNI:'
            AND "\(phoneNumberColumn)" IS NOT NULL;
        """)

        // If there are any rows with just a phone number, try to replace it with the ACI.
        try db.execute(sql: """
        UPDATE "\(tableName)"
        SET
            "\(phoneNumberColumn)" = NULL,
            "\(serviceIdColumn)" = "signalRecipientAciString"
        FROM (
            SELECT
                "recipientUUID" AS "signalRecipientAciString",
                "recipientPhoneNumber" AS "signalRecipientPhoneNumber"
            FROM "model_SignalRecipient"
        )
        WHERE
            "\(serviceIdColumn)" IS NULL
            AND "\(phoneNumberColumn)" = "signalRecipientPhoneNumber"
            AND "signalRecipientAciString" IS NOT NULL;
        """)
    }

    static func createV2AttachmentTables(_ tx: DBWriteTransaction) throws -> Result<Void, Error> {

        // MARK: Attachment table

        try tx.database.create(table: "Attachment") { table in
            table.autoIncrementedPrimaryKey("id").notNull()
            table.column("blurHash", .text)
            // Sha256 hash of the plaintext contents.
            // Non-null for downloaded attachments.
            table.column("sha256ContentHash", .blob).unique(onConflict: .abort)
            // Used for addressing in the media tier.
            // Non-null for downloaded attachments even if media tier unavailable.
            table.column("mediaName", .text).unique(onConflict: .abort)
            // Byte count of the encrypted file on disk, including cryptography overhead and padding.
            // Non-null for downloaded attachments.
            table.column("encryptedByteCount", .integer)
            // Byte count of the decrypted plaintext contents, excluding padding.
            // Non-null for downloaded attachments.
            table.column("unencryptedByteCount", .integer)
            // MIME type for the attachment, from the sender.
            table.column("mimeType", .text).notNull()
            // Key used to encrypt the file on disk. Composed of { AES encryption key | HMAC key }
            table.column("encryptionKey", .blob).notNull()
            // Sha256 digest of the encrypted ciphertext on disk, including iv prefix and hmac suffix.
            // Non-null for downloaded attachments.
            table.column("digestSHA256Ciphertext", .blob)
            // Path to the encrypted fullsize file on disk, if downloaded.
            table.column("localRelativeFilePath", .text)
            // Validated type of attachment.
            // null - undownloaded
            // 0 - invalid (failed validation for the MIME type)
            // 1 - arbitrary file
            // 2 - image (from known image MIME types)
            // 3 - video (from known video MIME types)
            // 4 - animated image (from known animated image MIME types)
            // 5 - audio (from known audio MIME types)
            table.column("contentType", .integer)
            // "Transit tier" CDN info used for sending/receiving attachments.
            // Non-null if uploaded.
            table.column("transitCdnNumber", .integer)
            table.column("transitCdnKey", .text)
            table.column("transitUploadTimestamp", .integer)
            // Key used for the encrypted blob uploaded to transit tier CDN and used for sending.
            // May or may not be the same as `encryptionKey`.
            table.column("transitEncryptionKey", .blob)
            table.column("transitEncryptedByteCount", .integer)
            table.column("transitDigestSHA256Ciphertext", .blob)
            // Local timestamp when we last failed a download from transit tier CDN.
            // Set _after_ the download fails; nil if downloaded or if no attempt has been made.
            table.column("lastTransitDownloadAttemptTimestamp", .integer)
            // "Media tier" CDN info used for backing up full size attachments.
            // Non-null if uploaded to the media tier.
            table.column("mediaTierCdnNumber", .integer)
            table.column("mediaTierUploadEra", .text)
            // Local timestamp when we last failed a download from media tier CDN.
            // Set _after_ the download fails; nil if downloaded or if no attempt has been made.
            table.column("lastMediaTierDownloadAttemptTimestamp", .integer)
            // "Media tier" CDN info used for backing up attachment _thumbnails_.
            // Thumbnails are only used for visual media content types.
            // Non-null if uploaded to the media tier.
            table.column("thumbnailCdnNumber", .integer)
            table.column("thumbnailUploadEra", .text)
            // Local timestamp when we last failed a thumbnail download from media tier CDN.
            // Set _after_ the download fails; nil if downloaded or if no attempt has been made.
            table.column("lastThumbnailDownloadAttemptTimestamp", .integer)
            // Path to the encrypted thumbnail file on disk, if downloaded.
            // Encrypted using the `encryptionKey` column.
            table.column("localRelativeFilePathThumbnail", .text)
            // Cached pre-computed attributes set for downloaded media on a per-type basis.
            // Non-null for rows with respective contentTypes.
            table.column("cachedAudioDurationSeconds", .double)
            table.column("cachedMediaHeightPixels", .integer)
            table.column("cachedMediaWidthPixels", .integer)
            table.column("cachedVideoDurationSeconds", .double)
            // Path to the encrypted serialized audio waveform representation on disk.
            // Nullable even for audio attachments.
            // Encrypted using the `encryptionKey` column.
            table.column("audioWaveformRelativeFilePath", .text)
            // Path to the encrypted video still frame on disk.
            // Nullable even for video attachments.
            // Encrypted using the `encryptionKey` column.
            table.column("videoStillFrameRelativeFilePath", .text)
        }

        // MARK: Attachment indexes

        // Note: sha256ContentHash, mediaName indexes implicit from UNIQUE constraint.

        // For finding attachments by type.
        try tx.database.create(
            index: "index_attachment_on_contentType_and_mimeType",
            on: "Attachment",
            columns: [
                "contentType",
                "mimeType",
            ],
        )

        // MARK: MessageAttachmentReference table

        try tx.database.create(table: "MessageAttachmentReference") { table in
            // The type of message owner reference represented by this row.
            // 0 - message attachment
            // 1 - Long message body (text)
            // 2 - message link preview
            // 3 - quoted reply attachment
            // 4 - message sticker
            table.column("ownerType", .integer).notNull()
            // Row id of the owning message.
            table.column("ownerRowId", .integer)
                .references("model_TSInteraction", column: "id", onDelete: .cascade)
                .notNull()
            // Row id of the associated Attachment.
            table.column("attachmentRowId", .integer)
                .references("Attachment", column: "id", onDelete: .cascade)
                .notNull()
            // Local timestamp the message was received, or created if outgoing.
            table.column("receivedAtTimestamp", .integer).notNull()
            // Mirrored from `Attachment` table's `contentType`.
            table.column("contentType", .integer)
            // Rendering hint from the sender.
            // 0 - default
            // 1 - voice message
            // 2 - borderless image
            // 3 - looping video
            table.column("renderingFlag", .integer).notNull()
            // Uniquely identifies the attachment among other attachments on the same owning TSMessage.
            // Optional for message attachment owner type, null for other types.
            table.column("idInMessage", .text)
            // Ordering of the attachment on the same owning TSMessage.
            // Non-null for message attachment owner type, null for other types.
            table.column("orderInMessage", .integer)
            // Row id of the TSThread the owning message belongs to.
            table.column("threadRowId", .integer)
                .references("model_TSThread", column: "id", onDelete: .cascade)
                .notNull()
            // Unused for contemporary messages but may be non-null for legacy instances.
            table.column("caption", .text)
            // File name from sender for display purposes only.
            table.column("sourceFilename", .text)
            // Byte count of the decrypted plaintext contents excluding padding, according to the sender.
            // Will match `Attachment.unencryptedByteCount` once downloaded for well-behaving senders;
            // a mismatch results in a rejected download.
            table.column("sourceUnencryptedByteCount", .integer)
            // Pixel height/width of visual media according to the sender.
            table.column("sourceMediaHeightPixels", .integer)
            table.column("sourceMediaWidthPixels", .integer)
            // Non-null for message sticker owners, null for other types.
            table.column("stickerPackId", .blob)
            table.column("stickerId", .integer)
        }

        // MARK: MessageAttachmentReference indexes

        // For finding attachments associated with a given message owner.
        try tx.database.create(
            index: "index_message_attachment_reference_on_ownerRowId_and_ownerType",
            on: "MessageAttachmentReference",
            columns: [
                "ownerRowId",
                "ownerType",
            ],
        )

        // For getting all owners of a given attachment.
        try tx.database.create(
            index: "index_message_attachment_reference_on_attachmentRowId",
            on: "MessageAttachmentReference",
            columns: [
                "attachmentRowId",
            ],
        )

        // For finding specific attachments on a given message.
        try tx.database.create(
            index: "index_message_attachment_reference_on_ownerRowId_and_idInMessage",
            on: "MessageAttachmentReference",
            columns: [
                "ownerRowId",
                "idInMessage",
            ],
        )

        // For finding attachments associated with a given sticker.
        // Sticker messages attach the sticker image source itself. We might later acquire the actual
        // sticker data from its source pack; in this case we might want to find existing references
        // to the sticker and replace them with the new canonical reference.
        try tx.database.create(
            index: "index_message_attachment_reference_on_stickerPackId_and_stickerId",
            on: "MessageAttachmentReference",
            columns: [
                "stickerPackId",
                "stickerId",
            ],
        )

        // For the all media view; it shows message body media for a given thread,
        // filtered by content type + rendering flag, sorted by the timestamp and then
        // rowId of the owning message, and finally sorted by orderInMessage on that message.
        try tx.database.create(
            index:
            "index_message_attachment_reference_on"
                + "_threadRowId"
                + "_and_ownerType"
                + "_and_contentType"
                + "_and_renderingFlag"
                + "_and_receivedAtTimestamp"
                + "_and_ownerRowId"
                + "_and_orderInMessage",
            on: "MessageAttachmentReference",
            columns: [
                "threadRowId",
                "ownerType",
                "contentType",
                "renderingFlag",
                "receivedAtTimestamp",
                "ownerRowId",
                "orderInMessage",
            ],
        )

        // MARK: StoryMessageAttachmentReference table

        try tx.database.create(table: "StoryMessageAttachmentReference") { table in
            // The type of owner reference represented by this row.
            // 0 - media story message
            // 1 - text story link preview
            table.column("ownerType", .integer).notNull()
            // Row id of the owning story message.
            table.column("ownerRowId", .integer)
                .references("model_StoryMessage", column: "id", onDelete: .cascade)
                .notNull()
            // Row id of the associated Attachment.
            table.column("attachmentRowId", .integer)
                .references("Attachment", column: "id", onDelete: .cascade)
                .notNull()
            // Rendering hint from the sender.
            // Equivalent to `loop` or `gif` rendering flag.
            table.column("shouldLoop", .boolean).notNull()
            // Optional for media owner types. Null for text story owner types.
            table.column("caption", .text)
            // Serialized `Array<NSRangedValue<MessageBodyRanges.CollapsedStyle>>`
            // Optional for media owner types. Null for text story owner types.
            table.column("captionBodyRanges", .blob)
            // File name from sender for display purposes only.
            table.column("sourceFilename", .text)
            // Byte count of the decrypted plaintext contents excluding padding, according to the sender.
            // Will match `Attachment`'s `unencryptedByteCount` once downloaded for
            // well-behaving senders, a mismatch results in a rejected download.
            table.column("sourceUnencryptedByteCount", .integer)
            // Pixel height/width of visual media according to the sender.
            table.column("sourceMediaHeightPixels", .integer)
            table.column("sourceMediaWidthPixels", .integer)
        }

        // MARK: StoryMessageAttachmentReference indexes

        // For finding attachments associated with a given story message owner.
        try tx.database.create(
            index: "index_story_message_attachment_reference_on_ownerRowId_and_ownerType",
            on: "StoryMessageAttachmentReference",
            columns: [
                "ownerRowId",
                "ownerType",
            ],
        )

        // For getting all owners of a given attachment.
        try tx.database.create(
            index: "index_story_message_attachment_reference_on_attachmentRowId",
            on: "StoryMessageAttachmentReference",
            columns: [
                "attachmentRowId",
            ],
        )

        // MARK: ThreadAttachmentReference table/index

        try tx.database.create(table: "ThreadAttachmentReference") { table in
            // Row id of the owning thread. Each thread has just one wallpaper attachment.
            // If NULL, it's the global thread background image.
            table.column("ownerRowId", .integer)
                .references("model_TSThread", column: "id", onDelete: .cascade)
                .unique()
            // Row id of the associated Attachment.
            table.column("attachmentRowId", .integer)
                .references("Attachment", column: "id", onDelete: .cascade)
                .notNull()
            // Local timestamp this ownership reference was created.
            table.column("creationTimestamp", .integer).notNull()
        }

        // Note: ownerRowId index implicit from UNIQUE constraint.

        // For getting all owners of a given attachment.
        try tx.database.create(
            index: "index_thread_attachment_reference_on_attachmentRowId",
            on: "ThreadAttachmentReference",
            columns: [
                "attachmentRowId",
            ],
        )

        // MARK: OrphanedAttachment table

        /// Double-commit the actual file on disk for deletion; we mark it for deletion
        /// by inserting into this table, another job comes around and deletes for real.
        try tx.database.create(table: "OrphanedAttachment") { table in
            table.autoIncrementedPrimaryKey("id").notNull()
            table.column("localRelativeFilePath", .text)
            table.column("localRelativeFilePathThumbnail", .text)
            table.column("localRelativeFilePathAudioWaveform", .text)
            table.column("localRelativeFilePathVideoStillFrame", .text)
        }

        // MARK: Triggers

        /// Make sure the contentType column is mirrored on MessageAttachmentReference.
        try tx.database.execute(sql: """
            CREATE TRIGGER __Attachment_contentType_au AFTER UPDATE OF contentType ON Attachment
              BEGIN
                UPDATE MessageAttachmentReference
                  SET contentType = NEW.contentType
                  WHERE attachmentRowId = OLD.id;
              END;
        """)

        /// When we delete any owners (on all three tables), check if the associated attachment has any owners left.
        /// If it has no owners remaining, delete it.
        /// Note that application layer is responsible for ensuring we never insert unowned attachments to begin with,
        /// and that we always insert an attachment and at least one owner in the same transaction.
        /// This is unenforceable in SQL.
        for referenceTableName in [
            "MessageAttachmentReference",
            "StoryMessageAttachmentReference",
            "ThreadAttachmentReference",
        ] {
            try tx.database.execute(sql: """
                CREATE TRIGGER "__\(referenceTableName)_ad" AFTER DELETE ON "\(referenceTableName)"
                  BEGIN
                    DELETE FROM Attachment WHERE id = OLD.attachmentRowId
                      AND NOT EXISTS (SELECT 1 FROM MessageAttachmentReference WHERE attachmentRowId = OLD.attachmentRowId)
                      AND NOT EXISTS (SELECT 1 FROM StoryMessageAttachmentReference WHERE attachmentRowId = OLD.attachmentRowId)
                      AND NOT EXISTS (SELECT 1 FROM ThreadAttachmentReference WHERE attachmentRowId = OLD.attachmentRowId);
                  END;
            """)
        }

        /// When we delete an attachment row in the database, insert into the orphan table
        /// so we can clean up the files on disk.
        try tx.database.execute(sql: """
            CREATE TRIGGER "__Attachment_ad" AFTER DELETE ON "Attachment"
              BEGIN
                INSERT INTO OrphanedAttachment (
                  localRelativeFilePath
                  ,localRelativeFilePathThumbnail
                  ,localRelativeFilePathAudioWaveform
                  ,localRelativeFilePathVideoStillFrame
                ) VALUES (
                  OLD.localRelativeFilePath
                  ,OLD.localRelativeFilePathThumbnail
                  ,OLD.audioWaveformRelativeFilePath
                  ,OLD.videoStillFrameRelativeFilePath
                );
              END;
        """)

        return .success(())
    }

    static func addOriginalAttachmentIdForQuotedReplyColumn(_ tx: DBWriteTransaction) throws -> Result<Void, Error> {
        try tx.database.alter(table: "Attachment") { table in
            table.add(column: "originalAttachmentIdForQuotedReply", .integer)
                .references("Attachment", column: "id", onDelete: .setNull)
        }

        // For finding quoted reply attachments that reference an original attachment.
        try tx.database.create(
            index: "index_attachment_on_originalAttachmentIdForQuotedReply",
            on: "Attachment",
            columns: ["originalAttachmentIdForQuotedReply"],
        )

        return .success(())
    }

    /// Historically, we persisted a map of `[GroupId: ThreadUniqueId]` for
    /// all group threads. For V1 groups that were migrated to V2 groups
    /// this map would hold entries for both the V1 and V2 group ID to the
    /// same group thread; this allowed us to find the same logical group
    /// thread if we encountered either ID.
    ///
    /// However, it's possible that we could have persisted an entry for a
    /// given group ID without having actually created a `TSGroupThread`,
    /// since both the V2 group ID and the eventual `TSGroupThread/uniqueId`
    /// were derivable from the V1 group ID. For example, code that was
    /// removed in `72345f1` would have created a mapping when restoring a
    /// record of a V1 group from Storage Service, but not actually have
    /// created the `TSGroupThread`. A user who had run this code, but who
    /// never had reason to create the `TSGroupThread` (e.g., because the
    /// migrated group was inactive), would have a "dead-end" mapping of a
    /// V1 group ID and its derived V2 group ID to a `uniqueId` that did not
    /// actually belong to a `TSGroupThread`.
    ///
    /// Later, `f1f4e69` stopped checking for mappings when instantiating a
    /// new `TSGroupThread` for a V2 group. However, other sites such as (at
    /// the time of writing) `GroupManager.tryToUpsertExistingGroupThreadInDatabaseAndCreateInfoMessage`
    /// would consult the mapping to get a `uniqueId` for a given group ID,
    /// then check if a `TSGroupThread` exists for that `uniqueId`, and if
    /// not create a new one. This is problematic, since that new
    /// `TSGroupThread` will give itself a `uniqueId` derived from its V2
    /// group ID, rather than using the `uniqueId` persisted in the mapping
    /// that's based on the original V1 group ID. Phew.
    ///
    /// This in turn means that every time `GroupManager.tryToUpsert...` is
    /// called it will fail to find the `TSGroupThread` that was previously
    /// created, and will instead attempt to create a new `TSGroupThread`
    /// each time (with the same derived `uniqueId`), which we believe is at
    /// the root of an issue reported in the wild.
    ///
    /// This migration iterates through our persisted mappings and deletes
    /// any of these "dead-end" mappings, since V1 group IDs are no longer
    /// used anywhere and those mappings are therefore now useless.
    static func removeDeadEndGroupThreadIdMappings(tx: DBWriteTransaction) throws {
        let mappingStoreCollection = "TSGroupThread.uniqueIdMappingStore"

        let rows = try Row.fetchAll(
            tx.database,
            sql: "SELECT * FROM keyvalue WHERE collection = ?",
            arguments: [mappingStoreCollection],
        )

        /// Group IDs that have a mapping to a thread ID, but for which the
        /// thread ID has no actual thread.
        var deadEndGroupIds = [String]()

        for row in rows {
            guard
                let groupIdKey = row["key"] as? String,
                let targetThreadIdData = row["value"] as? Data,
                let targetThreadId = (try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSString.self, from: targetThreadIdData)) as String?
            else {
                continue
            }

            if
                try Bool.fetchOne(
                    tx.database,
                    sql: """
                        SELECT EXISTS(
                            SELECT 1
                            FROM model_TSThread
                            WHERE uniqueId = ?
                            LIMIT 1
                        )
                    """,
                    arguments: [targetThreadId],
                ) != true
            {
                deadEndGroupIds.append(groupIdKey)
            }
        }

        for deadEndGroupId in deadEndGroupIds {
            try tx.database.execute(
                sql: """
                    DELETE FROM keyvalue
                    WHERE collection = ? AND key = ?
                """,
                arguments: [mappingStoreCollection, deadEndGroupId],
            )

            Logger.warn("Deleting dead-end group ID mapping: \(deadEndGroupId)")
        }
    }

    static func migrateBlockedRecipients(tx: DBWriteTransaction) throws {
        try tx.database.create(table: "BlockedRecipient") { table in
            table.column("recipientId", .integer)
                .primaryKey()
                .references("model_SignalRecipient", column: "id", onDelete: .cascade, onUpdate: .cascade)
        }

        let blockedAciStrings = try fetchAndClearBlockedIdentifiers(key: "kOWSBlockingManager_BlockedUUIDsKey", tx: tx).compactMap {
            return UUID(uuidString: $0)?.uuidString
        }
        let blockedPhoneNumbers = Set(try fetchAndClearBlockedIdentifiers(key: "kOWSBlockingManager_BlockedPhoneNumbersKey", tx: tx)).filter {
            return !$0.isEmpty
        }
        var blockedRecipientIds = Set<Int64>()
        var outdatedRecipientIds = Set<Int64>()

        for blockedAciString in blockedAciStrings {
            let recipientId = try fetchOrCreateRecipient(.V1, aciString: blockedAciString, tx: tx)
            blockedRecipientIds.insert(recipientId)
        }

        for blockedPhoneNumber in blockedPhoneNumbers {
            let recipientId = try fetchOrCreateRecipient(.V1, phoneNumber: blockedPhoneNumber, tx: tx)
            if blockedRecipientIds.contains(recipientId) {
                // They're already blocked by their ACI.
                continue
            }
            let isBlocked = try { () -> Bool in
                if let aciString = try fetchRecipientAciString(recipientId: recipientId, tx: tx) {
                    return try isPhoneNumberVisible(phoneNumber: blockedPhoneNumber, aciString: aciString, tx: tx)
                } else {
                    return true
                }
            }()
            guard isBlocked else {
                // They're only blocked by phone number.
                outdatedRecipientIds.insert(recipientId)
                continue
            }
            blockedRecipientIds.insert(recipientId)
        }

        for blockedRecipientId in blockedRecipientIds {
            try tx.database.execute(
                sql: "INSERT INTO BlockedRecipient (recipientId) VALUES (?)",
                arguments: [blockedRecipientId],
            )
        }

        for outdatedRecipientId in outdatedRecipientIds {
            guard let recipientUniqueId = try fetchRecipientUniqueId(recipientId: outdatedRecipientId, tx: tx) else {
                Logger.warn("Couldn't fetch uniqueId for just-fetched recipient.")
                continue
            }
            guard UUID(uuidString: recipientUniqueId) != nil else {
                Logger.warn("Couldn't validate uniqueId for just-fetched recipient.")
                continue
            }
            do {
                // This assertion should never fail. If `.updated.rawValue` ever changes,
                // don't change `updatedValue`.
                let updatedValue = 1
                assert(updatedValue == StorageServiceOperation.State.ChangeState.updated.rawValue)
                try tx.database.execute(
                    sql: """
                    UPDATE "keyvalue" SET "value" = json_set("value", ?, ?) WHERE "collection" IS 'kOWSStorageServiceOperation_IdentifierMap' AND "key" IS 'state'
                    """,
                    arguments: ["$.accountIdChangeMap.\(recipientUniqueId)", updatedValue],
                )
            } catch DatabaseError.SQLITE_ERROR {
                // This likely means that we've never used Storage Service. In that case,
                // we don't need to apply these changes.
            }
        }
    }

    private static func isPhoneNumberVisible(phoneNumber: String, aciString: String, tx: DBWriteTransaction) throws -> Bool {
        let isSystemContact = try Int.fetchOne(
            tx.database,
            sql: "SELECT 1 FROM model_SignalAccount WHERE recipientPhoneNumber IS ?",
            arguments: [phoneNumber],
        ) != nil
        if isSystemContact {
            return true
        }
        let isPhoneNumberHidden = try Int.fetchOne(
            tx.database,
            sql: """
            SELECT 1 FROM model_OWSUserProfile WHERE recipientUUID IS ? AND (
                isPhoneNumberShared IS FALSE
                OR (isPhoneNumberShared IS NULL AND profileName IS NOT NULL)
            )
            """,
            arguments: [aciString],
        ) != nil
        return !isPhoneNumberHidden
    }

    private static func fetchAndClearBlockedIdentifiers(key: String, tx: DBWriteTransaction) throws -> [String] {
        let collection = "kOWSBlockingManager_BlockedPhoneNumbersCollection"
        let dataValue = try Data.fetchOne(
            tx.database,
            sql: "SELECT value FROM keyvalue WHERE collection IS ? AND key IS ?",
            arguments: [collection, key],
        )
        try tx.database.execute(sql: "DELETE FROM keyvalue WHERE collection IS ? AND key IS ?", arguments: [collection, key])
        guard let dataValue else {
            return []
        }
        do {
            let blockedIdentifiers = try NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSArray.self, NSString.self], from: dataValue)
            return (blockedIdentifiers as? [String]) ?? []
        } catch {
            Logger.warn("Couldn't decode blocked identifiers.")
            return []
        }
    }

    /// The representation of recipients has changed over time. Old migrations
    /// need to continue writing in the old format; new migrations need to write
    /// in the new format; when adding a migraton, you may need to define a new
    /// version if the latest version isn't compatible with the current schema.
    private enum RecipientVersion {
        case V1
        /// See migrateRecipientDeviceIds.
        case V2
    }

    private static func fetchOrCreateRecipient(_ version: RecipientVersion, aciString: String, tx: DBWriteTransaction) throws -> SignalRecipient.RowId {
        let db = tx.database
        let existingRecipientId = try Int64.fetchOne(db, sql: "SELECT id FROM model_SignalRecipient WHERE recipientUUID IS ?", arguments: [aciString])
        if let existingRecipientId {
            return existingRecipientId
        }
        return try createRecipient(version, aciString: aciString, phoneNumber: nil, pniString: nil, tx: tx)
    }

    private static func fetchOrCreateRecipient(_ version: RecipientVersion, phoneNumber: String, tx: DBWriteTransaction) throws -> SignalRecipient.RowId {
        let db = tx.database
        let existingRecipientId = try Int64.fetchOne(db, sql: "SELECT id FROM model_SignalRecipient WHERE recipientPhoneNumber IS ?", arguments: [phoneNumber])
        if let existingRecipientId {
            return existingRecipientId
        }
        return try createRecipient(version, aciString: nil, phoneNumber: phoneNumber, pniString: nil, tx: tx)
    }

    private static func fetchOrCreateRecipient(_ version: RecipientVersion, pniString: String, tx: DBWriteTransaction) throws -> SignalRecipient.RowId {
        let db = tx.database
        let existingRecipientId = try Int64.fetchOne(db, sql: "SELECT id FROM model_SignalRecipient WHERE pni IS ?", arguments: [pniString])
        if let existingRecipientId {
            return existingRecipientId
        }
        return try createRecipient(version, aciString: nil, phoneNumber: nil, pniString: pniString, tx: tx)
    }

    private static func fetchOrCreateRecipient(_ version: RecipientVersion, address: FrozenSignalServiceAddress, tx: DBWriteTransaction) throws -> SignalRecipient.RowId? {
        if let aci = address.serviceId as? Aci {
            let aciString = aci.serviceIdUppercaseString
            return try fetchOrCreateRecipient(version, aciString: aciString, tx: tx)
        }
        if let phoneNumber = address.phoneNumber {
            return try fetchOrCreateRecipient(version, phoneNumber: phoneNumber, tx: tx)
        }
        if let pni = address.serviceId as? Pni {
            let pniString = pni.serviceIdUppercaseString
            return try fetchOrCreateRecipient(version, pniString: pniString, tx: tx)
        }
        return nil
    }

    private static func createRecipient(_ version: RecipientVersion, aciString: String?, phoneNumber: String?, pniString: String?, tx: DBWriteTransaction) throws -> SignalRecipient.RowId {
        let emptyDevices: Data
        switch version {
        case .V1:
            emptyDevices = try NSKeyedArchiver.archivedData(withRootObject: NSOrderedSet(array: [] as [NSNumber]), requiringSecureCoding: true)
        case .V2:
            emptyDevices = Data()
        }
        try tx.database.execute(
            sql: """
            INSERT INTO "model_SignalRecipient" ("recordType", "uniqueId", "devices", "recipientPhoneNumber", "recipientUUID", "pni") VALUES (31, ?, ?, ?, ?, ?)
            """,
            arguments: [
                UUID().uuidString,
                emptyDevices,
                phoneNumber,
                aciString,
                pniString,
            ],
        )
        return tx.database.lastInsertedRowID
    }

    private static func fetchRecipientAciString(recipientId: SignalRecipient.RowId, tx: DBWriteTransaction) throws -> String? {
        return try String.fetchOne(tx.database, sql: "SELECT recipientUUID FROM model_SignalRecipient WHERE id = ?", arguments: [recipientId])
    }

    private static func fetchRecipientUniqueId(recipientId: SignalRecipient.RowId, tx: DBWriteTransaction) throws -> String? {
        return try String.fetchOne(tx.database, sql: "SELECT uniqueId FROM model_SignalRecipient WHERE id = ?", arguments: [recipientId])
    }

    static func addCallLinkTable(tx: DBWriteTransaction) throws {
        try tx.database.create(table: "CallLink") { table in
            table.column("id", .integer).primaryKey()
            table.column("roomId", .blob).notNull().unique()
            table.column("rootKey", .blob).notNull()
            table.column("adminPasskey", .blob)
            table.column("adminDeletedAtTimestampMs", .integer)
            table.column("activeCallId", .integer)
            table.column("isUpcoming", .boolean)
            table.column("pendingActionCounter", .integer).notNull().defaults(to: 0)
            table.column("name", .text)
            table.column("restrictions", .integer)
            table.column("revoked", .boolean)
            table.column("expiration", .integer)
            table.check(sql: #"LENGTH("roomId") IS 32"#)
            table.check(sql: #"LENGTH("rootKey") IS 16"#)
            table.check(sql: #"LENGTH("adminPasskey") > 0 OR "adminPasskey" IS NULL"#)
            table.check(sql: #"NOT("isUpcoming" IS TRUE AND "expiration" IS NULL)"#)
        }

        try tx.database.create(
            index: "CallLink_Upcoming",
            on: "CallLink",
            columns: ["expiration"],
            condition: Column("isUpcoming") == true,
        )

        try tx.database.create(
            index: "CallLink_Pending",
            on: "CallLink",
            columns: ["pendingActionCounter"],
            condition: Column("pendingActionCounter") > 0,
        )

        try tx.database.create(
            index: "CallLink_AdminDeleted",
            on: "CallLink",
            columns: ["adminDeletedAtTimestampMs"],
            condition: Column("adminDeletedAtTimestampMs") != nil,
        )

        let indexesToDrop = [
            "index_call_record_on_callId_and_threadId",
            "index_call_record_on_timestamp",
            "index_call_record_on_status_and_timestamp",
            "index_call_record_on_threadRowId_and_timestamp",
            "index_call_record_on_threadRowId_and_status_and_timestamp",
            "index_call_record_on_callStatus_and_unreadStatus_and_timestamp",
            "index_call_record_on_threadRowId_and_callStatus_and_unreadStatus_and_timestamp",
            "index_deleted_call_record_on_threadRowId_and_callId",
            "index_deleted_call_record_on_deletedAtTimestamp",
        ]
        for indexName in indexesToDrop {
            try tx.database.drop(index: indexName)
        }

        try tx.database.create(table: "new_CallRecord") { (table: TableDefinition) in
            table.column("id", .integer).primaryKey().notNull()
            table.column("callId", .text).notNull()
            table.column("interactionRowId", .integer).unique()
                .references("model_TSInteraction", column: "id", onDelete: .restrict, onUpdate: .cascade)
            table.column("threadRowId", .integer)
                .references("model_TSThread", column: "id", onDelete: .restrict, onUpdate: .cascade)
            table.column("callLinkRowId", .integer)
                .references("CallLink", column: "id", onDelete: .restrict, onUpdate: .cascade)
            table.column("type", .integer).notNull()
            table.column("direction", .integer).notNull()
            table.column("status", .integer).notNull()
            table.column("unreadStatus", .integer).notNull()
            table.column("callBeganTimestamp", .integer).notNull()
            table.column("callEndedTimestamp", .integer).notNull()
            table.column("groupCallRingerAci", .blob)
            table.check(sql: #"IIF("threadRowId" IS NOT NULL, "callLinkRowId" IS NULL, "callLinkRowId" IS NOT NULL)"#)
            table.check(sql: #"IIF("threadRowId" IS NOT NULL, "interactionRowId" IS NOT NULL, "interactionRowId" IS NULL)"#)
        }
        try tx.database.execute(sql: """
        INSERT INTO "new_CallRecord" (
            "id", "callId", "interactionRowId", "threadRowId", "type", "direction", "status", "unreadStatus", "callBeganTimestamp", "callEndedTimestamp", "groupCallRingerAci"
        ) SELECT "id", "callId", "interactionRowId", "threadRowId", "type", "direction", "status", "unreadStatus", "timestamp", "callEndedTimestamp", "groupCallRingerAci" FROM "CallRecord";
        """)
        try tx.database.drop(table: "CallRecord")
        try tx.database.rename(table: "new_CallRecord", to: "CallRecord")

        try tx.database.create(table: "new_DeletedCallRecord") { table in
            table.column("id", .integer).primaryKey().notNull()
            table.column("callId", .text).notNull()
            table.column("threadRowId", .integer)
                .references("model_TSThread", column: "id", onDelete: .restrict, onUpdate: .cascade)
            table.column("callLinkRowId", .integer)
                .references("CallLink", column: "id", onDelete: .restrict, onUpdate: .cascade)
            table.column("deletedAtTimestamp", .integer).notNull()
            table.check(sql: #"IIF("threadRowId" IS NOT NULL, "callLinkRowId" IS NULL, "callLinkRowId" IS NOT NULL)"#)
        }
        try tx.database.execute(sql: """
        INSERT INTO "new_DeletedCallRecord" (
            "id", "callId", "threadRowId", "deletedAtTimestamp"
        ) SELECT "id", "callId", "threadRowId", "deletedAtTimestamp" FROM "DeletedCallRecord";
        """)
        try tx.database.drop(table: "DeletedCallRecord")
        try tx.database.rename(table: "new_DeletedCallRecord", to: "DeletedCallRecord")

        try tx.database.create(
            index: "CallRecord_threadRowId_callId",
            on: "CallRecord",
            columns: ["threadRowId", "callId"],
            options: [.unique],
            condition: Column("threadRowId") != nil,
        )

        try tx.database.create(
            index: "CallRecord_callLinkRowId_callId",
            on: "CallRecord",
            columns: ["callLinkRowId", "callId"],
            options: [.unique],
            condition: Column("callLinkRowId") != nil,
        )

        try tx.database.create(
            index: "CallRecord_callBeganTimestamp",
            on: "CallRecord",
            columns: ["callBeganTimestamp"],
        )

        try tx.database.create(
            index: "CallRecord_status_callBeganTimestamp",
            on: "CallRecord",
            columns: ["status", "callBeganTimestamp"],
        )

        try tx.database.create(
            index: "CallRecord_threadRowId_callBeganTimestamp",
            on: "CallRecord",
            columns: ["threadRowId", "callBeganTimestamp"],
            condition: Column("threadRowId") != nil,
        )

        try tx.database.create(
            index: "CallRecord_callLinkRowId_callBeganTimestamp",
            on: "CallRecord",
            columns: ["callLinkRowId", "callBeganTimestamp"],
            condition: Column("callLinkRowId") != nil,
        )

        try tx.database.create(
            index: "CallRecord_threadRowId_status_callBeganTimestamp",
            on: "CallRecord",
            columns: ["threadRowId", "status", "callBeganTimestamp"],
            condition: Column("threadRowId") != nil,
        )

        try tx.database.create(
            index: "CallRecord_callStatus_unreadStatus_callBeganTimestamp",
            on: "CallRecord",
            columns: ["status", "unreadStatus", "callBeganTimestamp"],
        )

        try tx.database.create(
            index: "CallRecord_threadRowId_callStatus_unreadStatus_callBeganTimestamp",
            on: "CallRecord",
            columns: ["threadRowId", "status", "unreadStatus", "callBeganTimestamp"],
            condition: Column("threadRowId") != nil,
        )

        try tx.database.create(
            index: "DeletedCallRecord_threadRowId_callId",
            on: "DeletedCallRecord",
            columns: ["threadRowId", "callId"],
            options: [.unique],
            condition: Column("threadRowId") != nil,
        )

        try tx.database.create(
            index: "DeletedCallRecord_callLinkRowId_callId",
            on: "DeletedCallRecord",
            columns: ["callLinkRowId", "callId"],
            options: [.unique],
            condition: Column("callLinkRowId") != nil,
        )

        try tx.database.create(
            index: "DeletedCallRecord_deletedAtTimestamp",
            on: "DeletedCallRecord",
            columns: ["deletedAtTimestamp"],
        )
    }

    private static func fetchAndClearBlockedGroupIds(tx: DBWriteTransaction) throws -> [Data] {
        let collection = "kOWSBlockingManager_BlockedPhoneNumbersCollection"
        let key = "kOWSBlockingManager_BlockedGroupMapKey"
        let dataValue = try Data.fetchOne(
            tx.database,
            sql: "SELECT value FROM keyvalue WHERE collection IS ? AND key IS ?",
            arguments: [collection, key],
        )
        try tx.database.execute(sql: "DELETE FROM keyvalue WHERE collection IS ? AND key IS ?", arguments: [collection, key])
        guard let dataValue else {
            return []
        }
        do {
            return try decodeBlockedGroupIds(dataValue: dataValue)
        } catch {
            Logger.warn("Couldn't decode blocked identifiers.")
            return []
        }
    }

    static func decodeBlockedGroupIds(dataValue: Data) throws -> [Data] {
        @objc(TSBlockedGroupModel)
        class TSBlockedGroupModel: NSObject, NSSecureCoding {
            static var supportsSecureCoding: Bool { true }
            required init?(coder: NSCoder) {}
            func encode(with coder: NSCoder) {}
        }
        let coder = try NSKeyedUnarchiver(forReadingFrom: dataValue)
        coder.requiresSecureCoding = true
        coder.setClass(TSBlockedGroupModel.self, forClassName: "TSGroupModel")
        coder.setClass(TSBlockedGroupModel.self, forClassName: "SignalServiceKit.TSGroupModelV2")
        let groupIdMap = try coder.decodeTopLevelObject(of: [
            NSDictionary.self,
            NSData.self,
            TSBlockedGroupModel.self,
        ], forKey: NSKeyedArchiveRootObjectKey)
        return Array(((groupIdMap as? [Data: TSBlockedGroupModel]) ?? [:]).keys)
    }

    private static func rebuildIncompleteViewOnceIndex(tx: DBWriteTransaction) throws {
        try tx.database.execute(
            sql: """
            DROP INDEX IF EXISTS "index_interactions_on_view_once"
            """,
        )
        try tx.database.create(
            index: "Interaction_incompleteViewOnce_partial",
            on: "model_TSInteraction",
            columns: ["isViewOnceMessage", "isViewOnceComplete"],
            options: [.ifNotExists],
            condition: Column("isViewOnceMessage") == 1 && Column("isViewOnceComplete") == 0,
        )
    }

    public static func removeInteractionThreadUniqueIdUniqueIdIndex(tx: DBWriteTransaction) throws {
        try tx.database.execute(
            sql: """
            DROP INDEX IF EXISTS "index_interactions_on_uniqueId_and_threadUniqueId"
            """,
        )
    }

    public static func rebuildDisappearingMessagesIndex(tx: DBWriteTransaction) throws {
        try tx.database.execute(
            sql: """
            DROP INDEX IF EXISTS "index_interactions_on_expiresInSeconds_and_expiresAt"
            """,
        )
        try tx.database.create(
            index: "Interaction_disappearingMessages_partial",
            on: "model_TSInteraction",
            columns: ["expiresAt"],
            options: [.ifNotExists],
            condition: Column("expiresAt") > 0,
        )
    }

    public static func removeInteractionAttachmentIdsIndex(tx: DBWriteTransaction) throws {
        try tx.database.execute(
            sql: """
            DROP INDEX IF EXISTS "index_model_TSInteraction_on_uniqueThreadId_and_attachmentIds"
            """,
        )
    }

    public static func rebuildInteractionTimestampIndex(tx: DBWriteTransaction) throws {
        try tx.database.execute(
            sql: """
            DROP INDEX IF EXISTS "index_interactions_on_timestamp_sourceDeviceId_and_authorUUID"
            """,
        )
        try tx.database.execute(
            sql: """
            DROP INDEX IF EXISTS "index_interactions_on_timestamp_sourceDeviceId_and_authorPhoneNumber"
            """,
        )
        try tx.database.create(
            index: "Interaction_timestamp",
            on: "model_TSInteraction",
            columns: ["timestamp"],
            options: [.ifNotExists],
        )
    }

    public static func rebuildInteractionUnendedGroupCallIndex(tx: DBWriteTransaction) throws {
        try tx.database.execute(
            sql: """
            DROP INDEX IF EXISTS "index_model_TSInteraction_on_uniqueThreadId_and_hasEnded_and_recordType"
            """,
        )
        // This recordType constant can't ever change.
        assert(SDSRecordType.groupCallMessage.rawValue == 65)
        try tx.database.create(
            index: "Interaction_unendedGroupCall_partial",
            on: "model_TSInteraction",
            columns: ["recordType", "hasEnded", "uniqueThreadId"],
            options: [.ifNotExists],
            condition: Column("recordType") == 65 && Column("hasEnded") == 0,
        )
    }

    public static func rebuildInteractionGroupCallEraIdIndex(tx: DBWriteTransaction) throws {
        try tx.database.execute(
            sql: """
            DROP INDEX IF EXISTS "index_model_TSInteraction_on_uniqueThreadId_and_eraId_and_recordType"
            """,
        )
        try tx.database.create(
            index: "Interaction_groupCallEraId_partial",
            on: "model_TSInteraction",
            columns: ["uniqueThreadId", "recordType", "eraId"],
            options: [.ifNotExists],
            condition: Column("eraId") != nil,
        )
    }

    public static func rebuildInteractionStoryReplyIndex(tx: DBWriteTransaction) throws {
        try tx.database.execute(
            sql: """
            DROP INDEX IF EXISTS "index_model_TSInteraction_on_StoryContext"
            """,
        )
        try tx.database.create(
            index: "Interaction_storyReply_partial",
            on: "model_TSInteraction",
            columns: ["storyAuthorUuidString", "storyTimestamp", "isGroupStoryReply"],
            options: [.ifNotExists],
            condition: Column("storyAuthorUuidString") != nil && Column("storyTimestamp") != nil,
        )
    }

    public static func removeInteractionConversationLoadCountIndex(tx: DBWriteTransaction) throws {
        try tx.database.execute(
            sql: """
            DROP INDEX IF EXISTS "index_model_TSInteraction_ConversationLoadInteractionCount"
            """,
        )
    }

    public static func removeInteractionConversationLoadDistanceIndex(tx: DBWriteTransaction) throws {
        try tx.database.execute(
            sql: """
            DROP INDEX IF EXISTS "index_model_TSInteraction_ConversationLoadInteractionDistance"
            """,
        )
    }

    public static func createDefaultAvatarColorTable(tx: DBWriteTransaction) throws {
        try tx.database.create(
            table: "AvatarDefaultColor",
            options: [.ifNotExists],
        ) { table in
            table.column("recipientRowId", .integer)
                .unique()
                .references(
                    "model_SignalRecipient",
                    column: "id",
                    onDelete: .cascade,
                    onUpdate: .cascade,
                )
            table.column("groupId", .blob).unique()
            table.column("defaultColorIndex", .integer).notNull()
        }
    }

    public static func populateDefaultAvatarColorTable(tx: DBWriteTransaction) throws {
        /// This is the hashing algorithm historically used to compute the
        /// default avatar color index.
        func computeAvatarColorIndex(seedData: Data) -> Int {
            func rotateLeft(_ uint: UInt64, _ count: Int) -> UInt64 {
                let count = count % UInt64.bitWidth
                return (uint << count) | (uint >> (UInt64.bitWidth - count))
            }

            var hash: UInt64 = 0
            for value in seedData {
                hash = rotateLeft(hash, 3) ^ UInt64(value)
            }
            return Int(hash % 12)
        }

        func insertDefaultColorIndex(
            _ defaultColorIndex: Int,
            groupId: Data?,
            recipientRowId: Int64?,
        ) throws {
            try tx.database.execute(
                sql: """
                    INSERT INTO AvatarDefaultColor
                    VALUES (?, ?, ?)
                """,
                arguments: [recipientRowId, groupId, defaultColorIndex],
            )
        }

        /// The group ID is buried inside of an `NSKeyedArchiver`-serialized
        /// `TSGroupModel`. We'll grab the serialized blobs, then selectively
        /// decode the group ID from them. That avoids referencing production
        /// types here, and also avoids deserializing the rest of the group
        /// model, such as the membership (which can be very slow).
        let groupModelDataCursor = try Data.fetchCursor(tx.database, sql: """
            SELECT groupModel
            FROM model_TSThread
            WHERE groupModel IS NOT NULL
        """)
        while let groupModelData = try groupModelDataCursor.next() {
            if
                let groupId = try decodeGroupIdFromGroupModelData(groupModelData),
                groupId.count == 32
            {
                try insertDefaultColorIndex(
                    computeAvatarColorIndex(seedData: groupId),
                    groupId: groupId,
                    recipientRowId: nil,
                )
            }
        }

        var visitedRecipientIds = Set<Int64>()

        let aciRowCursor = try Row.fetchCursor(tx.database, sql: """
            SELECT id, recipientUUID
            FROM model_SignalRecipient
            WHERE recipientUUID IS NOT NULL
        """)
        while let row = try aciRowCursor.next() {
            let recipientRowId: Int64 = row["id"]
            let aciString: String = row["recipientUUID"]

            let (inserted, _) = visitedRecipientIds.insert(recipientRowId)
            if !inserted { continue }

            try insertDefaultColorIndex(
                computeAvatarColorIndex(seedData: Data(aciString.uppercased().utf8)),
                groupId: nil,
                recipientRowId: recipientRowId,
            )
        }

        let pniRowCursor = try Row.fetchCursor(tx.database, sql: """
            SELECT id, pni
            FROM model_SignalRecipient
            WHERE pni IS NOT NULL
        """)
        while let row = try pniRowCursor.next() {
            let recipientRowId: Int64 = row["id"]
            let pniString: String = row["pni"]

            let (inserted, _) = visitedRecipientIds.insert(recipientRowId)
            if !inserted { continue }

            try insertDefaultColorIndex(
                computeAvatarColorIndex(seedData: Data(pniString.uppercased().utf8)),
                groupId: nil,
                recipientRowId: recipientRowId,
            )
        }

        let phoneNumberRowCursor = try Row.fetchCursor(tx.database, sql: """
            SELECT id, recipientPhoneNumber
            FROM model_SignalRecipient
            WHERE recipientPhoneNumber IS NOT NULL
        """)
        while let row = try phoneNumberRowCursor.next() {
            let recipientRowId: Int64 = row["id"]
            let phoneNumber: String = row["recipientPhoneNumber"]

            let (inserted, _) = visitedRecipientIds.insert(recipientRowId)
            if !inserted { continue }

            try insertDefaultColorIndex(
                computeAvatarColorIndex(seedData: Data(phoneNumber.utf8)),
                groupId: nil,
                recipientRowId: recipientRowId,
            )
        }
    }

    private static func decodeGroupIdFromGroupModelData(
        _ groupModelData: Data,
    ) throws -> Data? {
        @objc(TSGroupModelForMigrations)
        class TSGroupModelForMigrations: NSObject, NSSecureCoding {
            static var supportsSecureCoding: Bool { true }
            let groupId: NSData?
            required init?(coder: NSCoder) {
                groupId = coder.decodeObject(of: NSData.self, forKey: "groupId")
            }

            func encode(with coder: NSCoder) { owsFail("Don't encode these!") }
        }

        let coder = try NSKeyedUnarchiver(forReadingFrom: groupModelData)
        coder.requiresSecureCoding = true
        coder.setClass(TSGroupModelForMigrations.self, forClassName: "TSGroupModel")
        coder.setClass(TSGroupModelForMigrations.self, forClassName: "SignalServiceKit.TSGroupModelV2")

        let groupModel = try coder.decodeTopLevelObject(
            of: TSGroupModelForMigrations.self,
            forKey: NSKeyedArchiveRootObjectKey,
        )
        return groupModel?.groupId as Data?
    }

    static func createStoryRecipients(tx: DBWriteTransaction) throws {
        try tx.database.create(table: "StoryRecipient", options: [.withoutRowID]) { table in
            table.primaryKey(["threadId", "recipientId"])
            table.column("threadId", .integer).notNull()
            table.foreignKey(["threadId"], references: "model_TSThread", columns: ["id"], onDelete: .cascade, onUpdate: .cascade)
            table.column("recipientId", .integer).notNull().indexed()
            table.foreignKey(["recipientId"], references: "model_SignalRecipient", columns: ["id"], onDelete: .cascade, onUpdate: .cascade)
        }
        try migrateStoryRecipients(tx: tx)
    }

    private static func migrateStoryRecipients(tx: DBWriteTransaction) throws {
        let storyThreads = try Row.fetchAll(
            tx.database,
            sql: "SELECT id, addresses FROM model_TSThread WHERE recordType = 72",
        )
        for storyThread in storyThreads {
            let storyThreadId: Int64 = storyThread[0]
            let addressesData: Data? = storyThread[1]
            guard let addressesData else {
                continue
            }
            let addresses: [FrozenSignalServiceAddress]
            do {
                addresses = try decodeSignalServiceAddresses(dataValue: addressesData)
            } catch {
                owsFailDebug("Couldn't decode story recipients: \(error)")
                continue
            }
            for address in addresses {
                guard let recipientId = try fetchOrCreateRecipient(.V1, address: address, tx: tx) else {
                    owsFailDebug("Couldn't include empty story recipient address")
                    continue
                }
                do {
                    try tx.database.execute(
                        sql: "INSERT INTO StoryRecipient (threadId, recipientId) VALUES (?, ?)",
                        arguments: [storyThreadId, recipientId],
                    )
                } catch DatabaseError.SQLITE_CONSTRAINT {
                    // This is fine.
                }
            }
        }
        try tx.database.execute(
            sql: "UPDATE model_TSThread SET addresses = NULL WHERE recordType = 72",
        )
    }

    /// A SignalServiceAddress without global magic; useful in migrations.
    @objc(FrozenSignalServiceAddress)
    class FrozenSignalServiceAddress: NSObject, NSSecureCoding {
        let serviceId: ServiceId?
        let phoneNumber: String?

        static var supportsSecureCoding: Bool { true }

        required init?(coder: NSCoder) {
            let serviceId: ServiceId?
            switch coder.decodeObject(of: [NSUUID.self, NSData.self], forKey: "backingUuid") {
            case nil:
                serviceId = nil
            case let serviceIdBinary as Data:
                do {
                    serviceId = try ServiceId.parseFrom(serviceIdBinary: serviceIdBinary)
                } catch {
                    owsFailDebug("Couldn't parse serviceIdBinary.")
                    return nil
                }
            case let deprecatedUuid as NSUUID:
                serviceId = Aci(fromUUID: deprecatedUuid as UUID)
            default:
                return nil
            }
            let phoneNumber = coder.decodeObject(of: NSString.self, forKey: "backingPhoneNumber") as String?
            self.serviceId = serviceId
            self.phoneNumber = phoneNumber
        }

        func encode(with coder: NSCoder) {
            owsFail("Not supported.")
        }
    }

    static func decodeSignalServiceAddresses(dataValue: Data) throws -> [FrozenSignalServiceAddress] {
        let coder = try NSKeyedUnarchiver(forReadingFrom: dataValue)
        coder.requiresSecureCoding = true
        coder.setClass(FrozenSignalServiceAddress.self, forClassName: "SignalServiceKit.SignalServiceAddress")
        let decodedValue = try coder.decodeTopLevelObject(
            of: [NSArray.self, FrozenSignalServiceAddress.self],
            forKey: NSKeyedArchiveRootObjectKey,
        )
        guard let result = decodedValue as? [FrozenSignalServiceAddress] else {
            throw OWSGenericError("Couldn't parse result as an array of addresses.")
        }
        return result
    }

    static func migrateRecipientDeviceIds(tx: DBWriteTransaction) throws {
        let rowIds = try Int64.fetchAll(tx.database, sql: "SELECT id FROM model_SignalRecipient")
        for rowId in rowIds {
            let oldEncodedValue = try Data.fetchOne(tx.database, sql: "SELECT devices FROM model_SignalRecipient WHERE id = ?", arguments: [rowId])
            guard let oldEncodedValue else { throw OWSGenericError("Missing oldEncodedValue") }
            let deviceIdsObjC = try NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSOrderedSet.self, NSNumber.self], from: oldEncodedValue) as? NSOrderedSet
            guard let deviceIdsObjC else { throw OWSGenericError("Missing deviceIdsObjC") }
            let deviceIds = (deviceIdsObjC.array as? [NSNumber])?.map { $0.uint32Value }
            let validDeviceIds = (deviceIds ?? []).compactMap(UInt8.init(exactly:)).filter({ 1 <= $0 && $0 <= 127 })
            let newEncodedValue = Data(validDeviceIds.sorted())
            try tx.database.execute(sql: "UPDATE model_SignalRecipient SET devices = ? WHERE id = ?", arguments: [newEncodedValue, rowId])
        }
    }

    static func createPreKey(tx: DBWriteTransaction) throws {
        try tx.database.create(table: "PreKey") {
            $0.column("rowId", .integer).primaryKey().notNull()
            $0.column("identity", .integer).notNull()
            $0.column("namespace", .integer).notNull()
            $0.column("keyId", .integer).notNull()
            $0.column("isOneTime", .boolean).notNull()
            $0.column("replacedAt", .date)
            $0.column("serializedRecord", .blob)
            $0.check(sql: #"CASE "namespace" WHEN 0 THEN "isOneTime"=1 WHEN 2 THEN "isOneTime"=0 ELSE TRUE END"#)
        }
        // For fetching keys when asked by LibSignal.
        try tx.database.create(
            index: "PreKey_Unique",
            on: "PreKey",
            columns: ["identity", "namespace", "keyId"],
            options: [.unique],
        )
        // For deleting keys that have been replaced and expired.
        try tx.database.create(
            index: "PreKey_Obsolete",
            on: "PreKey",
            columns: ["replacedAt"],
            condition: Column("replacedAt") != nil,
        )
        // For marking keys that have been replaced.
        try tx.database.create(
            index: "PreKey_Replaced",
            on: "PreKey",
            columns: ["identity", "namespace", "isOneTime", "keyId"],
            condition: Column("replacedAt") == nil,
        )
    }

    static func migratePreKeys(tx: DBWriteTransaction) throws {
        // If these ever change, you'll need to add a new migration to update the
        // PreKey table and replace the old constants with the new constants.
        assert(PreKey.Namespace.oneTime.rawValue == 0)
        assert(PreKey.Namespace.kyber.rawValue == 1)
        assert(PreKey.Namespace.signed.rawValue == 2)

        try migratePreKeys(
            in: (aci: "TSStorageManagerPreKeyStoreCollection", pni: "TSStorageManagerPNIPreKeyStoreCollection"),
            namespace: 0,
            tx: tx,
        ) { encodedValue in
            guard let decodedValue = try NSKeyedUnarchiver.unarchivedObject(ofClass: SignalServiceKit.PreKeyRecord.self, from: encodedValue) else {
                throw OWSGenericError("missing decoded value")
            }
            let keyId = UInt32(bitPattern: decodedValue.id)
            return (
                keyId: keyId,
                isOneTime: true,
                replacedAt: decodedValue.replacedAt,
                serializedRecord: try LibSignalClient.PreKeyRecord(
                    id: keyId,
                    privateKey: decodedValue.keyPair.keyPair.privateKey,
                ).serialize(),
            )
        }

        try migratePreKeys(
            in: (aci: "TSStorageManagerSignedPreKeyStoreCollection", pni: "TSStorageManagerPNISignedPreKeyStoreCollection"),
            namespace: 2,
            tx: tx,
        ) { encodedValue in
            guard let decodedValue = try NSKeyedUnarchiver.unarchivedObject(ofClass: SignalServiceKit.SignedPreKeyRecord.self, from: encodedValue) else {
                throw OWSGenericError("missing decoded value")
            }
            let keyId = UInt32(bitPattern: decodedValue.id)
            return (
                keyId: keyId,
                isOneTime: false,
                replacedAt: decodedValue.replacedAt,
                serializedRecord: try LibSignalClient.SignedPreKeyRecord(
                    id: keyId,
                    timestamp: decodedValue.createdAt?.ows_millisecondsSince1970 ?? 0,
                    privateKey: decodedValue.keyPair.keyPair.privateKey,
                    signature: decodedValue.signature,
                ).serialize(),
            )
        }

        try migratePreKeys(
            in: (aci: "SSKKyberPreKeyStoreACIKeyStore", pni: "SSKKyberPreKeyStorePNIKeyStore"),
            namespace: 1,
            tx: tx,
        ) { encodedValue in
            let decodedValue = try JSONDecoder().decode(SignalServiceKit.KyberPreKeyRecord.self, from: encodedValue)
            return (
                keyId: decodedValue.libSignalRecord.id,
                isOneTime: !decodedValue.isLastResort,
                replacedAt: decodedValue.replacedAt,
                serializedRecord: decodedValue.libSignalRecord.serialize(),
            )
        }
    }

    static func migratePreKeys(
        in collections: (aci: String, pni: String),
        namespace: Int64,
        tx: DBWriteTransaction,
        decodeValue: (Data) throws -> (keyId: UInt32, isOneTime: Bool, replacedAt: Date?, serializedRecord: Data),
    ) throws {
        // If these ever change, you'll need to add a new migration to update the
        // PreKey table and replace the old constants with the new constants.
        assert(OWSIdentity.aci.rawValue == 0)
        assert(OWSIdentity.pni.rawValue == 1)
        for (collection, identity) in [(collections.aci, 0), (collections.pni, 1)] {
            let keys = try String.fetchAll(
                tx.database,
                sql: "SELECT key FROM keyvalue WHERE collection = ?",
                arguments: [collection],
            )
            for key in keys { try autoreleasepool {
                let dataValue = try Data.fetchOne(
                    tx.database,
                    sql: "SELECT value FROM keyvalue WHERE collection = ? AND key = ?",
                    arguments: [collection, key],
                )!
                guard let decodedValue = try? decodeValue(dataValue) else {
                    // We don't expect any failures, but if there are failures, it's safe to
                    // throw away the malformed values. We'll eventually recover organically.
                    Logger.warn("Skipping \(key) in \(collection) that couldn't be decoded")
                    return
                }
                try tx.database.execute(
                    sql: "INSERT INTO PreKey (identity, namespace, keyId, isOneTime, replacedAt, serializedRecord) VALUES (?, ?, ?, ?, ?, ?)",
                    arguments: [
                        identity,
                        namespace,
                        decodedValue.keyId,
                        decodedValue.isOneTime,
                        decodedValue.replacedAt.map { Int64($0.timeIntervalSince1970) },
                        decodedValue.serializedRecord,
                    ],
                )
            }}
        }
    }

    static func dropOldPreKeys(tx: DBWriteTransaction) throws {
        let collections = [
            "TSStorageManagerPreKeyStoreCollection",
            "TSStorageManagerPNIPreKeyStoreCollection",
            "TSStorageManagerSignedPreKeyStoreCollection",
            "TSStorageManagerPNISignedPreKeyStoreCollection",
            "SSKKyberPreKeyStoreACIKeyStore",
            "SSKKyberPreKeyStorePNIKeyStore",
        ]
        for collection in collections {
            try tx.database.execute(sql: "DELETE FROM keyvalue WHERE collection = ?", arguments: [collection])
        }
    }

    static func uniquifyUsernameLookupRecord(
        caseInsensitive: Bool,
        tx: DBWriteTransaction,
    ) throws {
        // Iterate UsernameLookupRecord newest -> oldest, and record the ACIs of
        // any duplicate usernames.
        var seenUsernames: Set<String> = []
        var acisWithDupeUsernames: Set<Data> = []
        let cursor = try Row.fetchCursor(
            tx.database,
            sql: "SELECT * FROM UsernameLookupRecord ORDER BY rowid DESC",
        )
        while let row = try cursor.next() {
            let aci: Data = row["aci"]
            var username: String = row["username"]

            if caseInsensitive {
                username = username.lowercased()
            }

            if !seenUsernames.insert(username).inserted {
                acisWithDupeUsernames.insert(aci)
            }
        }

        // Delete duplicates.
        for aci in acisWithDupeUsernames {
            try tx.database.execute(
                sql: "DELETE FROM UsernameLookupRecord WHERE aci = ?",
                arguments: [aci],
            )
        }

        let usernameColumnExpr = if caseInsensitive {
            "\"username\" COLLATE NOCASE"
        } else {
            "\"username\""
        }

        try tx.database.execute(sql: """
            CREATE UNIQUE INDEX "UsernameLookupRecord_UniqueUsernames"
            ON "UsernameLookupRecord"(\(usernameColumnExpr))
        """)
    }

    static func fixUpcomingCallLinks(tx: DBWriteTransaction) throws {
        try tx.database.execute(
            sql: """
            UPDATE "CallLink" SET "isUpcoming"=0 WHERE "isUpcoming"=1 AND "adminPasskey" IS NULL
            """,
        )
    }

    static func fixRevokedForRestoredCallLinks(tx: DBWriteTransaction) throws {
        try tx.database.execute(
            sql: """
            UPDATE "CallLink" SET "revoked"=0 WHERE "revoked" IS NULL AND "expiration" IS NOT NULL
            """,
        )
    }

    static func fixNameForRestoredCallLinks(tx: DBWriteTransaction) throws {
        try tx.database.execute(
            sql: """
            UPDATE "CallLink" SET "name"=NULL WHERE "name" IS ''
            """,
        )
    }

    /// A very rough check for "is this a brand new installation?"
    private static func hasAnyAccountManagerState(tx: DBReadTransaction) throws -> Bool {
        return try Bool.fetchOne(
            tx.database,
            sql: "SELECT 1 FROM keyvalue WHERE collection = ?",
            arguments: ["TSStorageUserAccountCollection"],
        ) ?? false
    }

    static func createSession(tx: DBWriteTransaction) throws {
        try tx.database.create(table: "Session") {
            $0.column("id", .integer).primaryKey().notNull()
            $0.column("recipientId", .integer).notNull()
                .references("model_SignalRecipient", column: "id", onDelete: .cascade, onUpdate: .cascade)
            $0.column("localIdentity", .integer).notNull()
            $0.column("deviceId", .integer).notNull()
            $0.column("serializedRecord", .blob)
            $0.check(sql: #"1 <= "deviceId" AND "deviceId" <= 127"#)
        }
        // For fetching session(s) for a recipient.
        try tx.database.create(
            index: "Session_Unique",
            on: "Session",
            columns: ["recipientId", "localIdentity", "deviceId"],
            options: [.unique],
        )
    }

    static func migrateSessions(tx: DBWriteTransaction) throws {
        // If these ever change, you'll need to add a new migration to update the
        // Session table and replace the old constants with the new constants.
        assert(OWSIdentity.aci.rawValue == 0)
        assert(OWSIdentity.pni.rawValue == 1)

        try migrateSessions(in: "TSStorageManagerSessionStoreCollection", identity: 0, tx: tx)
        try migrateSessions(in: "TSStorageManagerPNISessionStoreCollection", identity: 1, tx: tx)
    }

    static func migrateSessions(
        in collection: String,
        identity: Int64,
        tx: DBWriteTransaction,
    ) throws {
        let keys = try String.fetchAll(
            tx.database,
            sql: "SELECT key FROM keyvalue WHERE collection = ?",
            arguments: [collection],
        )
        for key in keys { try autoreleasepool {
            let dataValue = try Data.fetchOne(
                tx.database,
                sql: "SELECT value FROM keyvalue WHERE collection = ? AND key = ?",
                arguments: [collection, key],
            )!
            let sessionDictionary: [Int32: Data?]
            let decodedValue = try? NSKeyedUnarchiver.unarchivedObject(
                ofClasses: [NSDictionary.self, NSNumber.self, NSData.self],
                from: dataValue,
            ) as? [Int32: Data]
            if let decodedValue {
                sessionDictionary = decodedValue
            } else {
                // We expect some failures (for legacy data), and if there are failures, we
                // want to remember that there was a session, even though we can't do
                // anything with that session. (See also `hasSessionRecords`).
                Logger.warn("Storing nil for \(key) in \(collection) that couldn't be decoded")
                sessionDictionary = [1: nil]
            }
            let recipientId = try Int64.fetchOne(
                tx.database,
                sql: "SELECT id FROM model_SignalRecipient WHERE uniqueId = ?",
                arguments: [key],
            )
            guard let recipientId else {
                // If we can't find the SignalRecipient, these sessions aren't reachable,
                // so we don't need to keep them. (Foreign key constraints will enforce
                // this moving forward.)
                Logger.warn("Skipping \(key) in \(collection) that's been orphaned")
                return
            }
            for (deviceId, serializedRecord) in sessionDictionary {
                guard deviceId >= 1, deviceId <= 127 else {
                    Logger.warn("Skipping \(deviceId) for \(key) in \(collection) that's not valid")
                    continue
                }
                try tx.database.execute(
                    sql: "INSERT INTO Session (recipientId, localIdentity, deviceId, serializedRecord) VALUES (?, ?, ?, ?)",
                    arguments: [
                        recipientId,
                        identity,
                        deviceId,
                        serializedRecord,
                    ],
                )
            }
        }}
    }

    static func dropOldSessions(tx: DBWriteTransaction) throws {
        let collections = [
            "TSStorageManagerSessionStoreCollection",
            "TSStorageManagerPNISessionStoreCollection",
        ]
        for collection in collections {
            try tx.database.execute(sql: "DELETE FROM keyvalue WHERE collection = ?", arguments: [collection])
        }
    }

    static func addRecipientStatus(tx: DBWriteTransaction) throws {
        try tx.database.alter(table: "model_SignalRecipient") {
            $0.add(column: "status", .integer).notNull().defaults(to: 0)
        }
        // For fetching whitelisted recipients.
        try tx.database.create(index: "Recipient_Status", on: "model_SignalRecipient", columns: ["status"])
    }

    static func migrateRecipientWhitelist(tx: DBWriteTransaction) throws {
        let serviceIdCollection = "kOWSProfileManager_UserUUIDWhitelistCollection"
        let phoneNumberCollection = "kOWSProfileManager_UserWhitelistCollection"

        var recipientIds = Set<SignalRecipient.RowId>()

        let serviceIdStrings = try String.fetchAll(
            tx.database,
            sql: "SELECT key FROM keyvalue WHERE collection = ?",
            arguments: [serviceIdCollection],
        )
        for serviceIdString in serviceIdStrings {
            guard let serviceId = try? ServiceId.parseFrom(serviceIdString: serviceIdString) else {
                continue
            }
            switch serviceId.concreteType {
            case .aci(let aci):
                recipientIds.insert(try fetchOrCreateRecipient(.V2, aciString: aci.serviceIdUppercaseString, tx: tx))
            case .pni(let pni):
                recipientIds.insert(try fetchOrCreateRecipient(.V2, pniString: pni.serviceIdUppercaseString, tx: tx))
            }
        }

        let phoneNumberStrings = try String.fetchAll(
            tx.database,
            sql: "SELECT key FROM keyvalue WHERE collection = ?",
            arguments: [phoneNumberCollection],
        )
        for phoneNumberString in phoneNumberStrings {
            guard let phoneNumber = E164(phoneNumberString) else {
                continue
            }
            recipientIds.insert(try fetchOrCreateRecipient(.V2, phoneNumber: phoneNumber.stringValue, tx: tx))
        }

        if !recipientIds.isEmpty {
            Logger.info("adding \(recipientIds.count) recipients to the whitelist (from \(serviceIdStrings.count) service ids & \(phoneNumberStrings.count) phone numbers)")
        }

        for recipientId in recipientIds {
            try tx.database.execute(sql: "UPDATE model_SignalRecipient SET status = 1 WHERE id = ?", arguments: [recipientId])
        }

        for collection in [serviceIdCollection, phoneNumberCollection] {
            try tx.database.execute(sql: "DELETE FROM keyvalue WHERE collection = ?", arguments: [collection])
        }
    }
}

// MARK: -

extension GRDBSchemaMigrator {
    static func dedupeSignalRecipients(tx: DBWriteTransaction) throws {
        struct Recipient: FetchableRecord, Decodable {
            var id: Int64
            var aciString: String?
            var phoneNumber: String?
        }
        let fetchAllRecipients = "SELECT id, recipientUUID aciString, recipientPhoneNumber phoneNumber FROM model_SignalRecipient"

        let recipientCursor = try Recipient.fetchCursor(tx.database, sql: fetchAllRecipients)
        var recipientsByAciString = [String: [Int64]]()
        var recipientsByPhoneNumber = [String: [Recipient]]()
        while let recipient = try recipientCursor.next() {
            if let aciString = recipient.aciString {
                recipientsByAciString[aciString, default: []].append(recipient.id)
            }
            if let phoneNumber = recipient.phoneNumber {
                recipientsByPhoneNumber[phoneNumber, default: []].append(recipient)
            }
        }

        // First, ensure there are no duplicate ACIs. If there are, we pick the one
        // with the lowest rowID because that's the one that would be returned when
        // fetching by ACI.
        for (_, rowIds) in recipientsByAciString {
            for duplicateRowId in rowIds.sorted().dropFirst() {
                try tx.database.execute(sql: "DELETE FROM model_SignalRecipient WHERE id = ?", arguments: [duplicateRowId])
            }
        }

        // Next, ensure there are no duplicate phone numbers. If there are, we
        // similarly keep the first one, and then we clear (if there's an ACI) or
        // delete (if there's not an ACI) the others.
        for (_, recipients) in recipientsByPhoneNumber {
            for recipient in recipients.sorted(by: { $0.id < $1.id }).dropFirst() {
                let mutationSql: String
                if recipient.aciString != nil {
                    mutationSql = "UPDATE model_SignalRecipient SET recipientPhoneNumber = NULL WHERE id = ?"
                } else {
                    mutationSql = "DELETE FROM model_SignalRecipient WHERE id = ?"
                }
                try tx.database.execute(sql: mutationSql, arguments: [recipient.id])
            }
        }
    }
}

private func hasRunMigration(_ identifier: String, transaction: DBReadTransaction) -> Bool {
    do {
        return try String.fetchOne(
            transaction.database,
            sql: "SELECT identifier FROM grdb_migrations WHERE identifier = ?",
            arguments: [identifier],
        ) != nil
    } catch {
        owsFail("Error: \(error.grdbErrorForLogging)")
    }
}

private func insertMigration(_ identifier: String, db: Database) {
    do {
        try db.execute(sql: "INSERT INTO grdb_migrations (identifier) VALUES (?)", arguments: [identifier])
    } catch {
        owsFail("Error: \(error.grdbErrorForLogging)")
    }
}

private func removeMigration(_ identifier: String, db: Database) {
    do {
        try db.execute(sql: "DELETE FROM grdb_migrations WHERE identifier = ?", arguments: [identifier])
    } catch {
        owsFail("Error: \(error.grdbErrorForLogging)")
    }
}
