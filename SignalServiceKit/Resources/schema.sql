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
            ,"isMarkedUnread" BOOLEAN NOT NULL DEFAULT 0
            ,"lastVisibleSortIdOnScreenPercentage" DOUBLE NOT NULL DEFAULT 0
            ,"lastVisibleSortId" INTEGER NOT NULL DEFAULT 0
            ,"messageDraftBodyRanges" BLOB
            ,"mentionNotificationMode" INTEGER NOT NULL DEFAULT 0
            ,"mutedUntilTimestamp" INTEGER NOT NULL DEFAULT 0
            ,"allowsReplies" BOOLEAN DEFAULT 0
            ,"lastSentStoryTimestamp" INTEGER
            ,"name" TEXT
            ,"addresses" BLOB
            ,"storyViewMode" INTEGER DEFAULT 0
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
            ,"infoMessageUserInfo" BLOB
            ,"wasRemotelyDeleted" BOOLEAN
            ,"bodyRanges" BLOB
            ,"offerType" INTEGER
            ,"serverDeliveryTimestamp" INTEGER
            ,"eraId" TEXT
            ,"hasEnded" BOOLEAN
            ,"creatorUuid" TEXT
            ,"joinedMemberUuids" BLOB
            ,"wasIdentityVerified" BOOLEAN
            ,"paymentCancellation" BLOB
            ,"paymentNotification" BLOB
            ,"paymentRequest" BLOB
            ,"viewed" BOOLEAN
            ,"serverGuid" TEXT
            ,"storyAuthorUuidString" TEXT
            ,"storyTimestamp" INTEGER
            ,"isGroupStoryReply" BOOLEAN DEFAULT 0
            ,"storyReactionEmoji" TEXT
            ,"giftBadge" BLOB
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
            ,"contentType" TEXT
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
            ,"uploadTimestamp" INTEGER NOT NULL DEFAULT 0
            ,"cdnKey" TEXT NOT NULL DEFAULT ''
            ,"cdnNumber" INTEGER NOT NULL DEFAULT 0
            ,"isAnimatedCached" INTEGER
            ,"attachmentSchemaVersion" INTEGER DEFAULT 0
            ,"videoDuration" DOUBLE
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
            ,"attachmentId" TEXT
            ,"isMediaMessage" BOOLEAN
            ,"serverDeliveryTimestamp" INTEGER
            ,"exclusiveProcessIdentifier" TEXT
            ,"isHighPriority" BOOLEAN
            ,"receiptCredentailRequest" BLOB
            ,"receiptCredentailRequestContext" BLOB
            ,"priorSubscriptionLevel" INTEGER
            ,"subscriberID" BLOB
            ,"targetSubscriptionLevel" INTEGER
            ,"boostPaymentIntentID" TEXT
            ,"isBoost" BOOLEAN
            ,"receiptCredentialPresentation" BLOB
            ,"amount" NUMERIC
            ,"currencyCode" TEXT
            ,"unsavedMessagesToSend" BLOB
            ,"messageText" TEXT
            ,"paymentIntentClientSecret" TEXT
            ,"paymentMethodId" TEXT
            ,"replacementAdminUuid" TEXT
            ,"waitForMessageProcessing" BOOLEAN
            ,"isCompleteContactSync" BOOLEAN DEFAULT 0
            ,"paymentProcessor" TEXT
            ,"paypalPayerId" TEXT
            ,"paypalPaymentId" TEXT
            ,"paypalPaymentToken" TEXT
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
            ,"serverDeliveryTimestamp" INTEGER NOT NULL DEFAULT 0
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
            ,"unregisteredAtTimestamp" INTEGER
        )
;

CREATE
    INDEX "index_model_SignalRecipient_on_uniqueId"
        ON "model_SignalRecipient"("uniqueId"
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
            ,"familyName" TEXT
            ,"lastFetchDate" DOUBLE
            ,"lastMessagingDate" DOUBLE
            ,"bio" TEXT
            ,"bioEmoji" TEXT
            ,"profileBadgeInfo" BLOB
            ,"isStoriesCapable" BOOLEAN NOT NULL DEFAULT 0
            ,"canReceiveGiftBadges" BOOLEAN NOT NULL DEFAULT 0
            ,"isPniCapable" BOOLEAN NOT NULL DEFAULT 0
        )
;

CREATE
    INDEX "index_model_OWSUserProfile_on_uniqueId"
        ON "model_OWSUserProfile"("uniqueId"
)
;

CREATE
    INDEX "index_model_OWSUserProfile_on_lastFetchDate_and_lastMessagingDate"
        ON "model_OWSUserProfile"("lastFetchDate"
    ,"lastMessagingDate"
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
    INDEX "index_interactions_on_expiresInSeconds_and_expiresAt"
        ON "model_TSInteraction"("expiresAt"
    ,"expiresInSeconds"
)
;

CREATE
    INDEX "index_attachments_on_lazyRestoreFragmentId"
        ON "model_TSAttachment"("lazyRestoreFragmentId"
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
            ,"contactAvatarHash" BLOB
            ,"contactAvatarJpegData" BLOB
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
    TABLE
        IF NOT EXISTS "media_gallery_items" (
            "attachmentId" INTEGER NOT NULL UNIQUE
            ,"albumMessageId" INTEGER NOT NULL
            ,"threadId" INTEGER NOT NULL
            ,"originalAlbumOrder" INTEGER NOT NULL
        )
;

CREATE
    INDEX "index_media_gallery_items_for_gallery"
        ON "media_gallery_items"("threadId"
    ,"albumMessageId"
    ,"originalAlbumOrder"
)
;

CREATE
    INDEX "index_media_gallery_items_on_attachmentId"
        ON "media_gallery_items"("attachmentId"
)
;

CREATE
    TABLE
        IF NOT EXISTS "model_OWSReaction" (
            "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
            ,"recordType" INTEGER NOT NULL
            ,"uniqueId" TEXT NOT NULL UNIQUE
                ON CONFLICT FAIL
            ,"emoji" TEXT NOT NULL
            ,"reactorE164" TEXT
            ,"reactorUUID" TEXT
            ,"receivedAtTimestamp" INTEGER NOT NULL
            ,"sentAtTimestamp" INTEGER NOT NULL
            ,"uniqueMessageId" TEXT NOT NULL
            ,"read" BOOLEAN NOT NULL DEFAULT 0
        )
;

CREATE
    INDEX "index_model_OWSReaction_on_uniqueId"
        ON "model_OWSReaction"("uniqueId"
)
;

CREATE
    INDEX "index_model_OWSReaction_on_uniqueMessageId_and_reactorE164"
        ON "model_OWSReaction"("uniqueMessageId"
    ,"reactorE164"
)
;

CREATE
    INDEX "index_model_OWSReaction_on_uniqueMessageId_and_reactorUUID"
        ON "model_OWSReaction"("uniqueMessageId"
    ,"reactorUUID"
)
;

CREATE
    UNIQUE INDEX "index_signal_recipients_on_recipientPhoneNumber"
        ON "model_SignalRecipient"("recipientPhoneNumber"
)
;

CREATE
    UNIQUE INDEX "index_signal_recipients_on_recipientUUID"
        ON "model_SignalRecipient"("recipientUUID"
)
;

CREATE
    UNIQUE INDEX "index_interactions_on_threadId_read_and_id"
        ON "model_TSInteraction"("uniqueThreadId"
    ,"read"
    ,"id"
)
;

CREATE
    TABLE
        IF NOT EXISTS "indexable_text" (
            "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
            ,"collection" TEXT NOT NULL
            ,"uniqueId" TEXT NOT NULL
            ,"ftsIndexableContent" TEXT NOT NULL
        )
;

CREATE
    UNIQUE INDEX "index_indexable_text_on_collection_and_uniqueId"
        ON "indexable_text"("collection"
    ,"uniqueId"
)
;

CREATE
    VIRTUAL TABLE
        "indexable_text_fts"
            USING fts5 (
            ftsIndexableContent
            ,tokenize = 'unicode61'
            ,content = 'indexable_text'
            ,content_rowid = 'id'
        ) /* indexable_text_fts(ftsIndexableContent) */
;

CREATE
    TABLE
        IF NOT EXISTS 'indexable_text_fts_data' (
            id INTEGER PRIMARY KEY
            ,block BLOB
        )
;

CREATE
    TABLE
        IF NOT EXISTS 'indexable_text_fts_idx' (
            segid
            ,term
            ,pgno
            ,PRIMARY KEY (
                segid
                ,term
            )
        ) WITHOUT ROWID
;

CREATE
    TABLE
        IF NOT EXISTS 'indexable_text_fts_docsize' (
            id INTEGER PRIMARY KEY
            ,sz BLOB
        )
;

CREATE
    TABLE
        IF NOT EXISTS 'indexable_text_fts_config' (
            k PRIMARY KEY
            ,v
        ) WITHOUT ROWID
;

CREATE
    TRIGGER "__indexable_text_fts_ai" AFTER INSERT
            ON "indexable_text" BEGIN INSERT
            INTO
                "indexable_text_fts"("rowid"
                ,"ftsIndexableContent"
)
VALUES (
new. "id"
,new. "ftsIndexableContent"
)
;

END
;

CREATE
    TRIGGER "__indexable_text_fts_ad" AFTER DELETE
                ON "indexable_text" BEGIN INSERT
                INTO
                    "indexable_text_fts"("indexable_text_fts"
                    ,"rowid"
                    ,"ftsIndexableContent"
)
VALUES (
'delete'
,old. "id"
,old. "ftsIndexableContent"
)
;

END
;

CREATE
    TRIGGER "__indexable_text_fts_au" AFTER UPDATE
                ON "indexable_text" BEGIN INSERT
                INTO
                    "indexable_text_fts"("indexable_text_fts"
                    ,"rowid"
                    ,"ftsIndexableContent"
)
VALUES (
'delete'
,old. "id"
,old. "ftsIndexableContent"
)
;

INSERT
    INTO
        "indexable_text_fts"("rowid"
        ,"ftsIndexableContent"
)
VALUES (
new. "id"
,new. "ftsIndexableContent"
)
;

END
;

CREATE
    INDEX "index_interaction_on_storedMessageState"
        ON "model_TSInteraction"("storedMessageState"
)
;

CREATE
    INDEX "index_interaction_on_recordType_and_callType"
        ON "model_TSInteraction"("recordType"
    ,"callType"
)
;

CREATE
    TABLE
        IF NOT EXISTS "model_IncomingGroupsV2MessageJob" (
            "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
            ,"recordType" INTEGER NOT NULL
            ,"uniqueId" TEXT NOT NULL UNIQUE
                ON CONFLICT FAIL
            ,"createdAt" DOUBLE NOT NULL
            ,"envelopeData" BLOB NOT NULL
            ,"plaintextData" BLOB
            ,"wasReceivedByUD" INTEGER NOT NULL
            ,"groupId" BLOB
            ,"serverDeliveryTimestamp" INTEGER NOT NULL DEFAULT 0
        )
;

CREATE
    INDEX "index_model_IncomingGroupsV2MessageJob_on_uniqueId"
        ON "model_IncomingGroupsV2MessageJob"("uniqueId"
)
;

CREATE
    TABLE
        IF NOT EXISTS "model_ExperienceUpgrade" (
            "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
            ,"recordType" INTEGER NOT NULL
            ,"uniqueId" TEXT NOT NULL UNIQUE
                ON CONFLICT FAIL
            ,"firstViewedTimestamp" DOUBLE NOT NULL
            ,"lastSnoozedTimestamp" DOUBLE NOT NULL
            ,"isComplete" BOOLEAN NOT NULL
            ,"manifest" BLOB
            ,"snoozeCount" INTEGER NOT NULL DEFAULT 0
        )
;

CREATE
    INDEX "index_model_ExperienceUpgrade_on_uniqueId"
        ON "model_ExperienceUpgrade"("uniqueId"
)
;

CREATE
    TABLE
        IF NOT EXISTS "pending_read_receipts" (
            "id" INTEGER PRIMARY KEY AUTOINCREMENT
            ,"threadId" INTEGER NOT NULL
            ,"messageTimestamp" INTEGER NOT NULL
            ,"authorPhoneNumber" TEXT
            ,"authorUuid" TEXT
            ,"messageUniqueId" TEXT
        )
;

CREATE
    INDEX "index_pending_read_receipts_on_threadId"
        ON "pending_read_receipts"("threadId"
)
;

CREATE
    INDEX "index_model_IncomingGroupsV2MessageJob_on_groupId_and_id"
        ON "model_IncomingGroupsV2MessageJob"("groupId"
    ,"id"
)
;

CREATE
    INDEX "index_model_OWSReaction_on_uniqueMessageId_and_read"
        ON "model_OWSReaction"("uniqueMessageId"
    ,"read"
)
;

CREATE
    INDEX "index_model_TSAttachment_on_uniqueId_and_contentType"
        ON "model_TSAttachment"("uniqueId"
    ,"contentType"
)
;

CREATE
    INDEX "index_model_TSAttachment_on_uniqueId"
        ON "model_TSAttachment"("uniqueId"
)
;

CREATE
    INDEX "index_model_TSInteraction_on_uniqueThreadId_recordType_messageType"
        ON "model_TSInteraction"("uniqueThreadId"
    ,"recordType"
    ,"messageType"
)
;

CREATE
    INDEX "index_model_TSInteraction_on_uniqueThreadId_and_attachmentIds"
        ON "model_TSInteraction"("uniqueThreadId"
    ,"attachmentIds"
)
;

CREATE
    TABLE
        IF NOT EXISTS "model_TSMention" (
            "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
            ,"recordType" INTEGER NOT NULL
            ,"uniqueId" TEXT NOT NULL UNIQUE
                ON CONFLICT FAIL
            ,"uniqueMessageId" TEXT NOT NULL
            ,"uniqueThreadId" TEXT NOT NULL
            ,"uuidString" TEXT NOT NULL
            ,"creationTimestamp" DOUBLE NOT NULL
        )
;

CREATE
    INDEX "index_model_TSMention_on_uniqueId"
        ON "model_TSMention"("uniqueId"
)
;

CREATE
    INDEX "index_model_TSMention_on_uuidString_and_uniqueThreadId"
        ON "model_TSMention"("uuidString"
    ,"uniqueThreadId"
)
;

CREATE
    UNIQUE INDEX "index_model_TSMention_on_uniqueMessageId_and_uuidString"
        ON "model_TSMention"("uniqueMessageId"
    ,"uuidString"
)
;

CREATE
    INDEX "index_model_TSThread_on_isMarkedUnread_and_shouldThreadBeVisible"
        ON "model_TSThread"("isMarkedUnread"
    ,"shouldThreadBeVisible"
)
;

CREATE
    INDEX "index_model_TSInteraction_on_uniqueThreadId_and_hasEnded_and_recordType"
        ON "model_TSInteraction"("uniqueThreadId"
    ,"hasEnded"
    ,"recordType"
)
;

CREATE
    INDEX "index_model_TSInteraction_on_uniqueThreadId_and_eraId_and_recordType"
        ON "model_TSInteraction"("uniqueThreadId"
    ,"eraId"
    ,"recordType"
)
;

CREATE
    TABLE
        IF NOT EXISTS "model_TSPaymentModel" (
            "id" INTEGER PRIMARY KEY AUTOINCREMENT
            ,"recordType" INTEGER NOT NULL
            ,"uniqueId" TEXT NOT NULL UNIQUE
                ON CONFLICT FAIL
            ,"addressUuidString" TEXT
            ,"createdTimestamp" INTEGER NOT NULL
            ,"isUnread" BOOLEAN NOT NULL
            ,"mcLedgerBlockIndex" INTEGER NOT NULL
            ,"mcReceiptData" BLOB
            ,"mcTransactionData" BLOB
            ,"memoMessage" TEXT
            ,"mobileCoin" BLOB
            ,"paymentAmount" BLOB
            ,"paymentFailure" INTEGER NOT NULL
            ,"paymentState" INTEGER NOT NULL
            ,"paymentType" INTEGER NOT NULL
            ,"requestUuidString" TEXT
        )
;

CREATE
    INDEX "index_model_TSPaymentModel_on_uniqueId"
        ON "model_TSPaymentModel"("uniqueId"
)
;

CREATE
    INDEX "index_model_TSPaymentModel_on_paymentState"
        ON "model_TSPaymentModel"("paymentState"
)
;

CREATE
    INDEX "index_model_TSPaymentModel_on_mcLedgerBlockIndex"
        ON "model_TSPaymentModel"("mcLedgerBlockIndex"
)
;

CREATE
    INDEX "index_model_TSPaymentModel_on_mcReceiptData"
        ON "model_TSPaymentModel"("mcReceiptData"
)
;

CREATE
    INDEX "index_model_TSPaymentModel_on_mcTransactionData"
        ON "model_TSPaymentModel"("mcTransactionData"
)
;

CREATE
    INDEX "index_model_TSPaymentModel_on_isUnread"
        ON "model_TSPaymentModel"("isUnread"
)
;

CREATE
    TABLE
        IF NOT EXISTS "model_TSGroupMember" (
            "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
            ,"recordType" INTEGER NOT NULL
            ,"uniqueId" TEXT NOT NULL UNIQUE
                ON CONFLICT FAIL
            ,"groupThreadId" TEXT NOT NULL
            ,"phoneNumber" TEXT
            ,"uuidString" TEXT
            ,"lastInteractionTimestamp" INTEGER NOT NULL DEFAULT 0
        )
;

CREATE
    INDEX "index_model_TSGroupMember_on_uniqueId"
        ON "model_TSGroupMember"("uniqueId"
)
;

CREATE
    INDEX "index_model_TSGroupMember_on_groupThreadId"
        ON "model_TSGroupMember"("groupThreadId"
)
;

CREATE
    UNIQUE INDEX "index_model_TSGroupMember_on_uuidString_and_groupThreadId"
        ON "model_TSGroupMember"("uuidString"
    ,"groupThreadId"
)
;

CREATE
    UNIQUE INDEX "index_model_TSGroupMember_on_phoneNumber_and_groupThreadId"
        ON "model_TSGroupMember"("phoneNumber"
    ,"groupThreadId"
)
;

CREATE
    TABLE
        IF NOT EXISTS "pending_viewed_receipts" (
            "id" INTEGER PRIMARY KEY AUTOINCREMENT
            ,"threadId" INTEGER NOT NULL
            ,"messageTimestamp" INTEGER NOT NULL
            ,"authorPhoneNumber" TEXT
            ,"authorUuid" TEXT
            ,"messageUniqueId" TEXT
        )
;

CREATE
    INDEX "index_pending_viewed_receipts_on_threadId"
        ON "pending_viewed_receipts"("threadId"
)
;

CREATE
    TABLE
        IF NOT EXISTS "thread_associated_data" (
            "id" INTEGER PRIMARY KEY AUTOINCREMENT
            ,"threadUniqueId" TEXT NOT NULL UNIQUE
                ON CONFLICT FAIL
            ,"isArchived" BOOLEAN NOT NULL DEFAULT 0
            ,"isMarkedUnread" BOOLEAN NOT NULL DEFAULT 0
            ,"mutedUntilTimestamp" INTEGER NOT NULL DEFAULT 0
            ,"audioPlaybackRate" DOUBLE NOT NULL DEFAULT 1
        )
;

CREATE
    UNIQUE INDEX "index_thread_associated_data_on_threadUniqueId"
        ON "thread_associated_data"("threadUniqueId"
)
;

CREATE
    INDEX "index_thread_associated_data_on_threadUniqueId_and_isMarkedUnread"
        ON "thread_associated_data"("threadUniqueId"
    ,"isMarkedUnread"
)
;

CREATE
    INDEX "index_thread_associated_data_on_threadUniqueId_and_isArchived"
        ON "thread_associated_data"("threadUniqueId"
    ,"isArchived"
)
;

CREATE
    TABLE
        IF NOT EXISTS "MessageSendLog_Payload" (
            "payloadId" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
            ,"plaintextContent" BLOB NOT NULL
            ,"contentHint" INTEGER NOT NULL
            ,"sentTimestamp" INTEGER NOT NULL
            ,"uniqueThreadId" TEXT NOT NULL
            ,"sendComplete" BOOLEAN NOT NULL DEFAULT 0
        )
;

CREATE
    TABLE
        IF NOT EXISTS "MessageSendLog_Message" (
            "payloadId" INTEGER NOT NULL
            ,"uniqueId" TEXT NOT NULL
            ,PRIMARY KEY (
                "payloadId"
                ,"uniqueId"
            )
            ,FOREIGN KEY ("payloadId") REFERENCES "MessageSendLog_Payload"("payloadId"
        )
            ON DELETE
                CASCADE
                    ON UPDATE
                        CASCADE
)
;

CREATE
    TABLE
        IF NOT EXISTS "MessageSendLog_Recipient" (
            "payloadId" INTEGER NOT NULL
            ,"recipientUUID" TEXT NOT NULL
            ,"recipientDeviceId" INTEGER NOT NULL
            ,PRIMARY KEY (
                "payloadId"
                ,"recipientUUID"
                ,"recipientDeviceId"
            )
            ,FOREIGN KEY ("payloadId") REFERENCES "MessageSendLog_Payload"("payloadId"
        )
            ON DELETE
                CASCADE
                    ON UPDATE
                        CASCADE
)
;

CREATE
    TRIGGER MSLRecipient_deliveryReceiptCleanup AFTER DELETE
                ON MessageSendLog_Recipient WHEN 0 = (
                SELECT
                        COUNT( * )
                    FROM
                        MessageSendLog_Recipient
                    WHERE
                        payloadId = old.payloadId
            ) BEGIN DELETE
                FROM
                    MessageSendLog_Payload
                WHERE
                    payloadId = old.payloadId
                    AND sendComplete = TRUE
;

END
;

CREATE
    TRIGGER MSLMessage_payloadCleanup AFTER DELETE
                ON MessageSendLog_Message BEGIN DELETE
                FROM
                    MessageSendLog_Payload
                WHERE
                    payloadId = old.payloadId
;

END
;

CREATE
    INDEX "MSLPayload_sentTimestampIndex"
        ON "MessageSendLog_Payload"("sentTimestamp"
)
;

CREATE
    INDEX "MSLMessage_relatedMessageId"
        ON "MessageSendLog_Message"("uniqueId"
)
;

CREATE
    TABLE
        IF NOT EXISTS "model_ProfileBadgeTable" (
            "id" TEXT PRIMARY KEY
            ,"rawCategory" TEXT NOT NULL
            ,"localizedName" TEXT NOT NULL
            ,"localizedDescriptionFormatString" TEXT NOT NULL
            ,"resourcePath" TEXT NOT NULL
            ,"badgeVariant" TEXT NOT NULL
            ,"localization" TEXT NOT NULL
            ,"duration" NUMERIC
        )
;

CREATE
    TABLE
        IF NOT EXISTS "model_StoryMessage" (
            "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
            ,"recordType" INTEGER NOT NULL
            ,"uniqueId" TEXT NOT NULL UNIQUE
                ON CONFLICT FAIL
            ,"timestamp" INTEGER NOT NULL
            ,"authorUuid" TEXT NOT NULL
            ,"groupId" BLOB
            ,"direction" INTEGER NOT NULL
            ,"manifest" BLOB NOT NULL
            ,"attachment" BLOB NOT NULL
            ,"replyCount" INTEGER NOT NULL DEFAULT 0
        )
;

CREATE
    INDEX "index_model_StoryMessage_on_uniqueId"
        ON "model_StoryMessage"("uniqueId"
)
;

CREATE
    INDEX "index_model_StoryMessage_on_timestamp_and_authorUuid"
        ON "model_StoryMessage"("timestamp"
    ,"authorUuid"
)
;

CREATE
    INDEX "index_model_StoryMessage_on_direction"
        ON "model_StoryMessage"("direction"
)
;

CREATE
    INDEX index_model_TSInteraction_ConversationLoadInteractionCount
        ON model_TSInteraction (
        uniqueThreadId
        ,isGroupStoryReply
        ,recordType
    )
WHERE
    recordType IS NOT 70
;

CREATE
    INDEX index_model_TSInteraction_ConversationLoadInteractionDistance
        ON model_TSInteraction (
        uniqueThreadId
        ,id
        ,isGroupStoryReply
        ,recordType
        ,uniqueId
    )
WHERE
    recordType IS NOT 70
;

CREATE
    INDEX index_model_TSInteraction_UnreadCount
        ON model_TSInteraction (
        READ
        ,isGroupStoryReply
        ,uniqueThreadId
        ,recordType
    )
;

CREATE
    INDEX "index_model_TSInteraction_on_StoryContext"
        ON "model_TSInteraction"("storyTimestamp"
    ,"storyAuthorUuidString"
    ,"isGroupStoryReply"
)
;

CREATE
    TABLE
        IF NOT EXISTS "model_DonationReceipt" (
            "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
            ,"uniqueId" TEXT NOT NULL UNIQUE
                ON CONFLICT FAIL
            ,"timestamp" INTEGER NOT NULL
            ,"subscriptionLevel" INTEGER
            ,"amount" NUMERIC NOT NULL
            ,"currencyCode" TEXT NOT NULL
            ,"receiptType" NUMERIC
        )
;

CREATE
    INDEX index_interactions_on_threadUniqueId_storedShouldStartExpireTimer_and_expiresAt
        ON model_TSInteraction (
        uniqueThreadId
        ,uniqueId
    )
WHERE
    storedShouldStartExpireTimer IS TRUE
    AND (
        expiresAt IS 0
        OR expireStartedAt IS 0
    )
;

CREATE
    INDEX "index_model_TSThread_on_storyViewMode"
        ON "model_TSThread"("storyViewMode"
    ,"lastSentStoryTimestamp"
    ,"allowsReplies"
)
;

CREATE
    INDEX index_model_StoryMessage_on_incoming_receivedState_viewedTimestamp
        ON model_StoryMessage (
        json_extract (
            manifest
            ,'$.incoming.receivedState.viewedTimestamp'
        )
    )
;

CREATE
    TABLE
        IF NOT EXISTS "model_StoryContextAssociatedData" (
            "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
            ,"recordType" INTEGER NOT NULL
            ,"uniqueId" NOT NULL UNIQUE
                ON CONFLICT FAIL
            ,"contactUuid" TEXT
            ,"groupId" BLOB
            ,"isHidden" BOOLEAN NOT NULL DEFAULT 0
            ,"latestUnexpiredTimestamp" INTEGER
            ,"lastReceivedTimestamp" INTEGER
            ,"lastViewedTimestamp" INTEGER
            ,"lastReadTimestamp" INTEGER
        )
;

CREATE
    INDEX "index_story_context_associated_data_contact_on_contact_uuid"
        ON "model_StoryContextAssociatedData"("contactUuid"
)
;

CREATE
    INDEX "index_story_context_associated_data_contact_on_group_id"
        ON "model_StoryContextAssociatedData"("groupId"
)
;

CREATE
    TABLE
        IF NOT EXISTS "cancelledGroupRing" (
            "id" INTEGER PRIMARY KEY NOT NULL
            ,"timestamp" INTEGER NOT NULL
        )
;

CREATE
    TABLE
        IF NOT EXISTS "CdsPreviousE164" (
            "id" INTEGER PRIMARY KEY NOT NULL
            ,"e164" TEXT NOT NULL
        )
;

CREATE
    TABLE
        IF NOT EXISTS "model_CallRecord" (
            "id" INTEGER PRIMARY KEY NOT NULL
            ,"uniqueId" TEXT NOT NULL UNIQUE
                ON CONFLICT FAIL
            ,"callId" TEXT NOT NULL UNIQUE
                ON CONFLICT IGNORE
            ,"interactionUniqueId" TEXT NOT NULL REFERENCES "model_TSInteraction"("uniqueId"
        )
            ON DELETE
                CASCADE
                ,"peerUuid" TEXT NOT NULL
                ,"type" INTEGER NOT NULL
                ,"direction" INTEGER NOT NULL
                ,"status" INTEGER NOT NULL
)
;

CREATE
    INDEX "index_call_record_on_interaction_unique_id"
        ON "model_CallRecord"("interactionUniqueId"
)
;

CREATE
    TABLE
        IF NOT EXISTS "spamReportingTokenRecords" (
            "sourceUuid" BLOB PRIMARY KEY NOT NULL
            ,"spamReportingToken" BLOB NOT NULL
        )
;

CREATE
    TABLE
        IF NOT EXISTS "UsernameLookupRecord" (
            "aci" BLOB PRIMARY KEY NOT NULL
            ,"username" TEXT NOT NULL
        )
;

CREATE
    INDEX "index_attachments_toMarkAsFailed"
        ON "model_TSAttachment" (
        "recordType"
        ,"state"
    )
WHERE
    "recordType" = 3
    AND "state" IN (
        0
        ,1
    )
;
