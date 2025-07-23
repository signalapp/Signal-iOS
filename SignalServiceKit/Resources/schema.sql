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
            ,"editTargetTimestamp" INTEGER
            ,"lastDraftInteractionRowId" INTEGER DEFAULT 0
            ,"lastDraftUpdateTimestamp" INTEGER DEFAULT 0
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
            ,"deprecated_attachmentIds" BLOB
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
            ,"wasNotCreatedLocally" INTEGER
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
            ,"deprecated_sourceDeviceId" INTEGER
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
            ,"editState" INTEGER DEFAULT 0
            ,"archivedPaymentInfo" BLOB
            ,"expireTimerVersion" INTEGER
            ,"isSmsMessageRestoredFromBackup" BOOLEAN DEFAULT 0
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
    TABLE
        IF NOT EXISTS "model_SSKJobRecord" (
            "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
            ,"recordType" INTEGER NOT NULL
            ,"uniqueId" TEXT NOT NULL UNIQUE
                ON CONFLICT FAIL
            ,"failureCount" INTEGER NOT NULL
            ,"label" TEXT NOT NULL
            ,"status" INTEGER NOT NULL
            ,"contactThreadId" TEXT
            ,"envelopeData" BLOB
            ,"invisibleMessage" BLOB
            ,"messageId" TEXT
            ,"removeMessageAfterSending" INTEGER
            ,"threadId" TEXT
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
            ,"paymentMethod" TEXT
            ,"isNewSubscription" BOOLEAN
            ,"shouldSuppressPaymentAlreadyRedeemed" BOOLEAN
            ,"CRDAJR_sendDeleteAllSyncMessage" BOOLEAN
            ,"CRDAJR_deleteAllBeforeTimestamp" INTEGER
            ,"CRDAJR_deleteAllBeforeCallId" TEXT
            ,"CRDAJR_deleteAllBeforeConversationId" BLOB
            ,"ICSJR_cdnNumber" INTEGER
            ,"ICSJR_cdnKey" TEXT
            ,"ICSJR_encryptionKey" BLOB
            ,"ICSJR_digest" BLOB
            ,"ICSJR_plaintextLength" INTEGER
            ,"BDIJR_anchorMessageRowId" INTEGER
            ,"BDIJR_fullThreadDeletionAnchorMessageRowId" INTEGER
            ,"BDIJR_threadUniqueId" TEXT
            ,"receiptCredential" BLOB
            ,"BRCRJR_state" BLOB
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
    TABLE
        IF NOT EXISTS "model_OWSDisappearingMessagesConfiguration" (
            "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
            ,"recordType" INTEGER NOT NULL
            ,"uniqueId" TEXT NOT NULL UNIQUE
                ON CONFLICT FAIL
            ,"durationSeconds" INTEGER NOT NULL
            ,"enabled" INTEGER NOT NULL
            ,"timerVersion" INTEGER NOT NULL DEFAULT 1
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
            ,"pni" TEXT
            ,"isPhoneNumberDiscoverable" BOOLEAN
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
            ,"isPhoneNumberShared" BOOLEAN
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
            ,"cnContactId" TEXT
            ,"givenName" TEXT NOT NULL DEFAULT ''
            ,"familyName" TEXT NOT NULL DEFAULT ''
            ,"nickname" TEXT NOT NULL DEFAULT ''
            ,"fullName" TEXT NOT NULL DEFAULT ''
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
    INDEX "index_model_TSInteraction_on_uniqueThreadId_recordType_messageType"
        ON "model_TSInteraction"("uniqueThreadId"
    ,"recordType"
    ,"messageType"
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
            ,"interactionUniqueId" TEXT
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
    INDEX "index_model_TSInteraction_UnreadMessages"
        ON "model_TSInteraction" (
        "read"
        ,"uniqueThreadId"
        ,"id"
        ,"isGroupStoryReply"
        ,"editState"
        ,"recordType"
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
    TABLE
        IF NOT EXISTS "EditRecord" (
            "id" INTEGER PRIMARY KEY AUTOINCREMENT
            ,"latestRevisionId" INTEGER NOT NULL REFERENCES "model_TSInteraction"("id"
        )
            ON DELETE
                RESTRICT
                ,"pastRevisionId" INTEGER NOT NULL REFERENCES "model_TSInteraction"("id"
)
    ON DELETE
        RESTRICT
        ,"read" BOOLEAN NOT NULL DEFAULT 0
)
;

CREATE
    INDEX "index_edit_record_on_latest_revision_id"
        ON "EditRecord"("latestRevisionId"
)
;

CREATE
    INDEX "index_edit_record_on_past_revision_id"
        ON "EditRecord"("pastRevisionId"
)
;

CREATE
    TABLE
        IF NOT EXISTS "HiddenRecipient" (
            "recipientId" INTEGER PRIMARY KEY NOT NULL
            ,"inKnownMessageRequestState" BOOLEAN NOT NULL DEFAULT 0
            ,FOREIGN KEY ("recipientId") REFERENCES "model_SignalRecipient"("id"
        )
            ON DELETE
                CASCADE
)
;

CREATE
    TABLE
        IF NOT EXISTS "TSPaymentsActivationRequestModel" (
            "id" INTEGER PRIMARY KEY AUTOINCREMENT
            ,"threadUniqueId" TEXT NOT NULL
            ,"senderAci" BLOB NOT NULL
        )
;

CREATE
    INDEX "index_TSPaymentsActivationRequestModel_on_threadUniqueId"
        ON "TSPaymentsActivationRequestModel"("threadUniqueId"
)
;

CREATE
    UNIQUE INDEX "index_signal_recipients_on_pni"
        ON "model_SignalRecipient"("pni"
)
;

CREATE
    TABLE
        IF NOT EXISTS "SearchableName" (
            "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
            ,"threadId" INTEGER UNIQUE
            ,"signalAccountId" INTEGER UNIQUE
            ,"userProfileId" INTEGER UNIQUE
            ,"signalRecipientId" INTEGER UNIQUE
            ,"usernameLookupRecordId" BLOB UNIQUE
            ,"value" TEXT NOT NULL
            ,"nicknameRecordRecipientId" INTEGER REFERENCES "NicknameRecord"("recipientRowID"
        )
            ON DELETE
                CASCADE
                ,FOREIGN KEY ("threadId") REFERENCES "model_TSThread"("id"
)
    ON DELETE
        CASCADE
            ON UPDATE
                CASCADE
                ,FOREIGN KEY ("signalAccountId") REFERENCES "model_SignalAccount"("id"
)
    ON DELETE
        CASCADE
            ON UPDATE
                CASCADE
                ,FOREIGN KEY ("userProfileId") REFERENCES "model_OWSUserProfile"("id"
)
    ON DELETE
        CASCADE
            ON UPDATE
                CASCADE
                ,FOREIGN KEY ("signalRecipientId") REFERENCES "model_SignalRecipient"("id"
)
    ON DELETE
        CASCADE
            ON UPDATE
                CASCADE
                ,FOREIGN KEY ("usernameLookupRecordId") REFERENCES "UsernameLookupRecord"("aci"
)
    ON DELETE
        CASCADE
            ON UPDATE
                CASCADE
)
;

CREATE
    VIRTUAL TABLE
        "SearchableNameFTS"
            USING fts5 (
            VALUE
            ,tokenize = 'unicode61'
            ,content = 'SearchableName'
            ,content_rowid = 'id'
        ) /* SearchableNameFTS(value) */
;

CREATE
    TRIGGER "__SearchableNameFTS_ai" AFTER INSERT
            ON "SearchableName" BEGIN INSERT
            INTO
                "SearchableNameFTS"("rowid"
                ,"value"
)
VALUES (
new. "id"
,new. "value"
)
;

END
;

CREATE
    TRIGGER "__SearchableNameFTS_ad" AFTER DELETE
                ON "SearchableName" BEGIN INSERT
                INTO
                    "SearchableNameFTS"("SearchableNameFTS"
                    ,"rowid"
                    ,"value"
)
VALUES (
'delete'
,old. "id"
,old. "value"
)
;

END
;

CREATE
    TRIGGER "__SearchableNameFTS_au" AFTER UPDATE
                ON "SearchableName" BEGIN INSERT
                INTO
                    "SearchableNameFTS"("SearchableNameFTS"
                    ,"rowid"
                    ,"value"
)
VALUES (
'delete'
,old. "id"
,old. "value"
)
;

INSERT
    INTO
        "SearchableNameFTS"("rowid"
        ,"value"
)
VALUES (
new. "id"
,new. "value"
)
;

END
;

CREATE
    TABLE
        IF NOT EXISTS "NicknameRecord" (
            "recipientRowID" INTEGER PRIMARY KEY NOT NULL REFERENCES "model_SignalRecipient"("id"
        )
            ON DELETE
                CASCADE
                ,"givenName" TEXT
                ,"familyName" TEXT
                ,"note" TEXT
)
;

CREATE
    TABLE
        IF NOT EXISTS "Attachment" (
            "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
            ,"blurHash" TEXT
            ,"sha256ContentHash" BLOB UNIQUE
            ,"mediaName" TEXT UNIQUE
            ,"encryptedByteCount" INTEGER
            ,"unencryptedByteCount" INTEGER
            ,"mimeType" TEXT NOT NULL
            ,"encryptionKey" BLOB NOT NULL
            ,"digestSHA256Ciphertext" BLOB
            ,"localRelativeFilePath" TEXT
            ,"contentType" INTEGER
            ,"transitCdnNumber" INTEGER
            ,"transitCdnKey" TEXT
            ,"transitUploadTimestamp" INTEGER
            ,"transitEncryptionKey" BLOB
            ,"transitDigestSHA256Ciphertext" BLOB
            ,"lastTransitDownloadAttemptTimestamp" INTEGER
            ,"mediaTierCdnNumber" INTEGER
            ,"mediaTierUploadEra" TEXT
            ,"lastMediaTierDownloadAttemptTimestamp" INTEGER
            ,"thumbnailCdnNumber" INTEGER
            ,"thumbnailUploadEra" TEXT
            ,"lastThumbnailDownloadAttemptTimestamp" INTEGER
            ,"localRelativeFilePathThumbnail" TEXT
            ,"cachedAudioDurationSeconds" DOUBLE
            ,"cachedMediaHeightPixels" INTEGER
            ,"cachedMediaWidthPixels" INTEGER
            ,"cachedVideoDurationSeconds" DOUBLE
            ,"audioWaveformRelativeFilePath" TEXT
            ,"videoStillFrameRelativeFilePath" TEXT
            ,"originalAttachmentIdForQuotedReply" INTEGER REFERENCES "Attachment"("id"
        )
            ON DELETE
            SET
                NULL
                ,"transitUnencryptedByteCount" INTEGER
                ,"mediaTierUnencryptedByteCount" INTEGER
                ,"mediaTierIncrementalMac" BLOB
                ,"mediaTierIncrementalMacChunkSize" INTEGER
                ,"transitTierIncrementalMac" BLOB
                ,"transitTierIncrementalMacChunkSize" INTEGER
                ,"lastFullscreenViewTimestamp" INTEGER
)
;

CREATE
    INDEX "index_attachment_on_contentType_and_mimeType"
        ON "Attachment"("contentType"
    ,"mimeType"
)
;

CREATE
    TABLE
        IF NOT EXISTS "MessageAttachmentReference" (
            "ownerType" INTEGER NOT NULL
            ,"ownerRowId" INTEGER NOT NULL REFERENCES "model_TSInteraction"("id"
        )
            ON DELETE
                CASCADE
                ,"attachmentRowId" INTEGER NOT NULL REFERENCES "Attachment"("id"
)
    ON DELETE
        CASCADE
        ,"receivedAtTimestamp" INTEGER NOT NULL
        ,"contentType" INTEGER
        ,"renderingFlag" INTEGER NOT NULL
        ,"idInMessage" TEXT
        ,"orderInMessage" INTEGER
        ,"threadRowId" INTEGER NOT NULL REFERENCES "model_TSThread"("id"
)
    ON DELETE
        CASCADE
        ,"caption" TEXT
        ,"sourceFilename" TEXT
        ,"sourceUnencryptedByteCount" INTEGER
        ,"sourceMediaHeightPixels" INTEGER
        ,"sourceMediaWidthPixels" INTEGER
        ,"stickerPackId" BLOB
        ,"stickerId" INTEGER
        ,isVisualMediaContentType AS (
            contentType = 2
            OR contentType = 3
            OR contentType = 4
        ) VIRTUAL
        ,isInvalidOrFileContentType AS (
            contentType = 0
            OR contentType = 1
        ) VIRTUAL
        ,"isViewOnce" BOOLEAN NOT NULL DEFAULT 0
        ,"ownerIsPastEditRevision" BOOLEAN DEFAULT 0
)
;

CREATE
    INDEX "index_message_attachment_reference_on_ownerRowId_and_ownerType"
        ON "MessageAttachmentReference"("ownerRowId"
    ,"ownerType"
)
;

CREATE
    INDEX "index_message_attachment_reference_on_attachmentRowId"
        ON "MessageAttachmentReference"("attachmentRowId"
)
;

CREATE
    INDEX "index_message_attachment_reference_on_ownerRowId_and_idInMessage"
        ON "MessageAttachmentReference"("ownerRowId"
    ,"idInMessage"
)
;

CREATE
    INDEX "index_message_attachment_reference_on_stickerPackId_and_stickerId"
        ON "MessageAttachmentReference"("stickerPackId"
    ,"stickerId"
)
;

CREATE
    TABLE
        IF NOT EXISTS "StoryMessageAttachmentReference" (
            "ownerType" INTEGER NOT NULL
            ,"ownerRowId" INTEGER NOT NULL REFERENCES "model_StoryMessage"("id"
        )
            ON DELETE
                CASCADE
                ,"attachmentRowId" INTEGER NOT NULL REFERENCES "Attachment"("id"
)
    ON DELETE
        CASCADE
        ,"shouldLoop" BOOLEAN NOT NULL
        ,"caption" TEXT
        ,"captionBodyRanges" BLOB
        ,"sourceFilename" TEXT
        ,"sourceUnencryptedByteCount" INTEGER
        ,"sourceMediaHeightPixels" INTEGER
        ,"sourceMediaWidthPixels" INTEGER
)
;

CREATE
    INDEX "index_story_message_attachment_reference_on_ownerRowId_and_ownerType"
        ON "StoryMessageAttachmentReference"("ownerRowId"
    ,"ownerType"
)
;

CREATE
    INDEX "index_story_message_attachment_reference_on_attachmentRowId"
        ON "StoryMessageAttachmentReference"("attachmentRowId"
)
;

CREATE
    TABLE
        IF NOT EXISTS "ThreadAttachmentReference" (
            "ownerRowId" INTEGER UNIQUE REFERENCES "model_TSThread"("id"
        )
            ON DELETE
                CASCADE
                ,"attachmentRowId" INTEGER NOT NULL REFERENCES "Attachment"("id"
)
    ON DELETE
        CASCADE
        ,"creationTimestamp" INTEGER NOT NULL
)
;

CREATE
    INDEX "index_thread_attachment_reference_on_attachmentRowId"
        ON "ThreadAttachmentReference"("attachmentRowId"
)
;

CREATE
    TABLE
        IF NOT EXISTS "OrphanedAttachment" (
            "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
            ,"localRelativeFilePath" TEXT
            ,"localRelativeFilePathThumbnail" TEXT
            ,"localRelativeFilePathAudioWaveform" TEXT
            ,"localRelativeFilePathVideoStillFrame" TEXT
            ,"isPendingAttachment" BOOLEAN NOT NULL DEFAULT 0
        )
;

CREATE
    TRIGGER __Attachment_contentType_au AFTER UPDATE
            OF contentType
                ON Attachment BEGIN UPDATE
                    MessageAttachmentReference
                SET
                    contentType = NEW.contentType
                WHERE
                    attachmentRowId = OLD.id
;

END
;

CREATE
    TRIGGER "__MessageAttachmentReference_ad" AFTER DELETE
                ON "MessageAttachmentReference" BEGIN DELETE
                FROM
                    Attachment
                WHERE
                    id = OLD.attachmentRowId
                    AND NOT EXISTS (
                        SELECT
                                1
                            FROM
                                MessageAttachmentReference
                            WHERE
                                attachmentRowId = OLD.attachmentRowId
                    )
                    AND NOT EXISTS (
                        SELECT
                                1
                            FROM
                                StoryMessageAttachmentReference
                            WHERE
                                attachmentRowId = OLD.attachmentRowId
                    )
                    AND NOT EXISTS (
                        SELECT
                                1
                            FROM
                                ThreadAttachmentReference
                            WHERE
                                attachmentRowId = OLD.attachmentRowId
                    )
;

END
;

CREATE
    TRIGGER "__StoryMessageAttachmentReference_ad" AFTER DELETE
                ON "StoryMessageAttachmentReference" BEGIN DELETE
                FROM
                    Attachment
                WHERE
                    id = OLD.attachmentRowId
                    AND NOT EXISTS (
                        SELECT
                                1
                            FROM
                                MessageAttachmentReference
                            WHERE
                                attachmentRowId = OLD.attachmentRowId
                    )
                    AND NOT EXISTS (
                        SELECT
                                1
                            FROM
                                StoryMessageAttachmentReference
                            WHERE
                                attachmentRowId = OLD.attachmentRowId
                    )
                    AND NOT EXISTS (
                        SELECT
                                1
                            FROM
                                ThreadAttachmentReference
                            WHERE
                                attachmentRowId = OLD.attachmentRowId
                    )
;

END
;

CREATE
    TRIGGER "__ThreadAttachmentReference_ad" AFTER DELETE
                ON "ThreadAttachmentReference" BEGIN DELETE
                FROM
                    Attachment
                WHERE
                    id = OLD.attachmentRowId
                    AND NOT EXISTS (
                        SELECT
                                1
                            FROM
                                MessageAttachmentReference
                            WHERE
                                attachmentRowId = OLD.attachmentRowId
                    )
                    AND NOT EXISTS (
                        SELECT
                                1
                            FROM
                                StoryMessageAttachmentReference
                            WHERE
                                attachmentRowId = OLD.attachmentRowId
                    )
                    AND NOT EXISTS (
                        SELECT
                                1
                            FROM
                                ThreadAttachmentReference
                            WHERE
                                attachmentRowId = OLD.attachmentRowId
                    )
;

END
;

CREATE
    TRIGGER "__Attachment_ad" AFTER DELETE
                ON "Attachment" BEGIN INSERT
                INTO
                    OrphanedAttachment (
                        localRelativeFilePath
                        ,localRelativeFilePathThumbnail
                        ,localRelativeFilePathAudioWaveform
                        ,localRelativeFilePathVideoStillFrame
                    )
                VALUES (
                    OLD.localRelativeFilePath
                    ,OLD.localRelativeFilePathThumbnail
                    ,OLD.audioWaveformRelativeFilePath
                    ,OLD.videoStillFrameRelativeFilePath
                )
;

END
;

CREATE
    INDEX "index_thread_on_shouldThreadBeVisible"
        ON "model_TSThread" (
        "shouldThreadBeVisible"
        ,"lastInteractionRowId" DESC
    )
;

CREATE
    INDEX "index_attachment_on_originalAttachmentIdForQuotedReply"
        ON "Attachment"("originalAttachmentIdForQuotedReply"
)
;

CREATE
    INDEX "message_attachment_reference_media_gallery_single_content_type_index"
        ON "MessageAttachmentReference"("threadRowId"
    ,"ownerType"
    ,"contentType"
    ,"receivedAtTimestamp"
    ,"ownerRowId"
    ,"orderInMessage"
)
;

CREATE
    INDEX "message_attachment_reference_media_gallery_visualMedia_content_type_index"
        ON "MessageAttachmentReference"("threadRowId"
    ,"ownerType"
    ,"isVisualMediaContentType"
    ,"receivedAtTimestamp"
    ,"ownerRowId"
    ,"orderInMessage"
)
;

CREATE
    INDEX "message_attachment_reference_media_gallery_fileOrInvalid_content_type_index"
        ON "MessageAttachmentReference"("threadRowId"
    ,"ownerType"
    ,"isInvalidOrFileContentType"
    ,"receivedAtTimestamp"
    ,"ownerRowId"
    ,"orderInMessage"
)
;

CREATE
    TABLE
        IF NOT EXISTS "AttachmentDownloadQueue" (
            "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
            ,"sourceType" INTEGER NOT NULL
            ,"attachmentId" INTEGER NOT NULL REFERENCES "Attachment"("id"
        )
            ON DELETE
                CASCADE
                ,"priority" INTEGER NOT NULL
                ,"minRetryTimestamp" INTEGER
                ,"retryAttempts" INTEGER NOT NULL
                ,"localRelativeFilePath" TEXT NOT NULL
)
;

CREATE
    INDEX "index_AttachmentDownloadQueue_on_attachmentId_and_sourceType"
        ON "AttachmentDownloadQueue"("attachmentId"
    ,"sourceType"
)
;

CREATE
    INDEX "index_AttachmentDownloadQueue_on_priority"
        ON "AttachmentDownloadQueue"("priority"
)
;

CREATE
    INDEX "partial_index_AttachmentDownloadQueue_on_priority_DESC_and_id_where_minRetryTimestamp_isNull"
        ON "AttachmentDownloadQueue" (
        "priority" DESC
        ,"id"
    )
WHERE
    minRetryTimestamp IS NULL
;

CREATE
    INDEX "partial_index_AttachmentDownloadQueue_on_minRetryTimestamp_where_isNotNull"
        ON "AttachmentDownloadQueue" ("minRetryTimestamp")
WHERE
    minRetryTimestamp IS NOT NULL
;

CREATE
    TRIGGER "__AttachmentDownloadQueue_ad" AFTER DELETE
                ON "AttachmentDownloadQueue" BEGIN INSERT
                INTO
                    OrphanedAttachment (localRelativeFilePath)
                VALUES (OLD.localRelativeFilePath)
;

END
;

CREATE
    TABLE
        IF NOT EXISTS "ArchivedPayment" (
            "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
            ,"amount" TEXT
            ,"fee" TEXT
            ,"note" TEXT
            ,"mobileCoinIdentification" BLOB
            ,"status" INTEGER
            ,"failureReason" INTEGER
            ,"timestamp" INTEGER
            ,"blockIndex" INTEGER
            ,"blockTimestamp" INTEGER
            ,"transaction" BLOB
            ,"receipt" BLOB
            ,"direction" INTEGER
            ,"senderOrRecipientAci" BLOB
            ,"interactionUniqueId" TEXT
        )
;

CREATE
    INDEX "index_archived_payment_on_interaction_unique_id"
        ON "ArchivedPayment"("interactionUniqueId"
)
;

CREATE
    INDEX "index_message_attachment_reference_on_receivedAtTimestamp"
        ON "MessageAttachmentReference"("receivedAtTimestamp"
)
;

CREATE
    TABLE
        IF NOT EXISTS "AttachmentUploadRecord" (
            "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
            ,"sourceType" INTEGER NOT NULL
            ,"attachmentId" INTEGER NOT NULL
            ,"uploadForm" BLOB
            ,"uploadFormTimestamp" INTEGER
            ,"localMetadata" BLOB
            ,"uploadSessionUrl" BLOB
            ,"attempt" INTEGER
        )
;

CREATE
    INDEX "index_attachment_upload_record_on_attachment_id"
        ON "AttachmentUploadRecord"("attachmentId"
)
;

CREATE
    TABLE
        IF NOT EXISTS "BlockedRecipient" (
            "recipientId" INTEGER PRIMARY KEY REFERENCES "model_SignalRecipient"("id"
        )
            ON DELETE
                CASCADE
                    ON UPDATE
                        CASCADE
)
;

CREATE
    TABLE
        IF NOT EXISTS "AttachmentValidationBackfillQueue" (
            "attachmentId" INTEGER PRIMARY KEY
                ON CONFLICT IGNORE NOT NULL REFERENCES "Attachment"("id"
        )
            ON DELETE
                CASCADE
)
;

CREATE
    TABLE
        IF NOT EXISTS "BackupStickerPackDownloadQueue" (
            "id" INTEGER PRIMARY KEY AUTOINCREMENT
            ,"packId" BLOB NOT NULL
            ,"packKey" BLOB NOT NULL
        )
;

CREATE
    TABLE
        IF NOT EXISTS "OrphanedBackupAttachment" (
            "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
            ,"cdnNumber" INTEGER NOT NULL
            ,"mediaName" TEXT
            ,"mediaId" BLOB
            ,"type" INTEGER
        )
;

CREATE
    INDEX "index_OrphanedBackupAttachment_on_mediaName"
        ON "OrphanedBackupAttachment"("mediaName"
)
;

CREATE
    INDEX "index_OrphanedBackupAttachment_on_mediaId"
        ON "OrphanedBackupAttachment"("mediaId"
)
;

CREATE
    TRIGGER "__Attachment_ad_backup_fullsize" AFTER DELETE
                ON "Attachment" WHEN (
                OLD.mediaTierCdnNumber IS NOT NULL
                AND OLD.mediaName IS NOT NULL
            ) BEGIN INSERT
                INTO
                    OrphanedBackupAttachment (
                        cdnNumber
                        ,mediaName
                        ,mediaId
                        ,type
                    )
                VALUES (
                    OLD.mediaTierCdnNumber
                    ,OLD.mediaName
                    ,NULL
                    ,0
                )
;

END
;

CREATE
    TRIGGER "__Attachment_ad_backup_thumbnail" AFTER DELETE
                ON "Attachment" WHEN (
                OLD.thumbnailCdnNumber IS NOT NULL
                AND OLD.mediaName IS NOT NULL
            ) BEGIN INSERT
                INTO
                    OrphanedBackupAttachment (
                        cdnNumber
                        ,mediaName
                        ,mediaId
                        ,type
                    )
                VALUES (
                    OLD.thumbnailCdnNumber
                    ,OLD.mediaName
                    ,NULL
                    ,1
                )
;

END
;

CREATE
    TABLE
        IF NOT EXISTS "CallLink" (
            "id" INTEGER PRIMARY KEY
            ,"roomId" BLOB NOT NULL UNIQUE
            ,"rootKey" BLOB NOT NULL
            ,"adminPasskey" BLOB
            ,"adminDeletedAtTimestampMs" INTEGER
            ,"activeCallId" INTEGER
            ,"isUpcoming" BOOLEAN
            ,"pendingActionCounter" INTEGER NOT NULL DEFAULT 0
            ,"name" TEXT
            ,"restrictions" INTEGER
            ,"revoked" BOOLEAN
            ,"expiration" INTEGER
            ,CHECK (
                LENGTH( "roomId" ) IS 32
            )
            ,CHECK (
                LENGTH( "rootKey" ) IS 16
            )
            ,CHECK (
                LENGTH( "adminPasskey" ) > 0
                OR "adminPasskey" IS NULL
            )
            ,CHECK (
                NOT (
                    "isUpcoming" IS TRUE
                    AND "expiration" IS NULL
                )
            )
        )
;

CREATE
    INDEX "CallLink_Upcoming"
        ON "CallLink"("expiration"
)
WHERE
"isUpcoming" = 1
;

CREATE
    INDEX "CallLink_Pending"
        ON "CallLink"("pendingActionCounter"
)
WHERE
"pendingActionCounter" > 0
;

CREATE
    INDEX "CallLink_AdminDeleted"
        ON "CallLink"("adminDeletedAtTimestampMs"
)
WHERE
"adminDeletedAtTimestampMs" IS NOT NULL
;

CREATE
    TABLE
        IF NOT EXISTS "CallRecord" (
            "id" INTEGER PRIMARY KEY NOT NULL
            ,"callId" TEXT NOT NULL
            ,"interactionRowId" INTEGER UNIQUE REFERENCES "model_TSInteraction"("id"
        )
            ON DELETE
                RESTRICT
                    ON UPDATE
                        CASCADE
                        ,"threadRowId" INTEGER REFERENCES "model_TSThread"("id"
)
    ON DELETE
        RESTRICT
            ON UPDATE
                CASCADE
                ,"callLinkRowId" INTEGER REFERENCES "CallLink"("id"
)
    ON DELETE
        RESTRICT
            ON UPDATE
                CASCADE
                ,"type" INTEGER NOT NULL
                ,"direction" INTEGER NOT NULL
                ,"status" INTEGER NOT NULL
                ,"unreadStatus" INTEGER NOT NULL
                ,"callBeganTimestamp" INTEGER NOT NULL
                ,"callEndedTimestamp" INTEGER NOT NULL
                ,"groupCallRingerAci" BLOB
                ,CHECK (
                    IIF (
                        "threadRowId" IS NOT NULL
                        ,"callLinkRowId" IS NULL
                        ,"callLinkRowId" IS NOT NULL
                    )
                )
                ,CHECK (
                    IIF (
                        "threadRowId" IS NOT NULL
                        ,"interactionRowId" IS NOT NULL
                        ,"interactionRowId" IS NULL
                    )
                )
)
;

CREATE
    TABLE
        IF NOT EXISTS "DeletedCallRecord" (
            "id" INTEGER PRIMARY KEY NOT NULL
            ,"callId" TEXT NOT NULL
            ,"threadRowId" INTEGER REFERENCES "model_TSThread"("id"
        )
            ON DELETE
                RESTRICT
                    ON UPDATE
                        CASCADE
                        ,"callLinkRowId" INTEGER REFERENCES "CallLink"("id"
)
    ON DELETE
        RESTRICT
            ON UPDATE
                CASCADE
                ,"deletedAtTimestamp" INTEGER NOT NULL
                ,CHECK (
                    IIF (
                        "threadRowId" IS NOT NULL
                        ,"callLinkRowId" IS NULL
                        ,"callLinkRowId" IS NOT NULL
                    )
                )
)
;

CREATE
    UNIQUE INDEX "CallRecord_threadRowId_callId"
        ON "CallRecord"("threadRowId"
    ,"callId"
)
WHERE
"threadRowId" IS NOT NULL
;

CREATE
    UNIQUE INDEX "CallRecord_callLinkRowId_callId"
        ON "CallRecord"("callLinkRowId"
    ,"callId"
)
WHERE
"callLinkRowId" IS NOT NULL
;

CREATE
    INDEX "CallRecord_callBeganTimestamp"
        ON "CallRecord"("callBeganTimestamp"
)
;

CREATE
    INDEX "CallRecord_status_callBeganTimestamp"
        ON "CallRecord"("status"
    ,"callBeganTimestamp"
)
;

CREATE
    INDEX "CallRecord_threadRowId_callBeganTimestamp"
        ON "CallRecord"("threadRowId"
    ,"callBeganTimestamp"
)
WHERE
"threadRowId" IS NOT NULL
;

CREATE
    INDEX "CallRecord_callLinkRowId_callBeganTimestamp"
        ON "CallRecord"("callLinkRowId"
    ,"callBeganTimestamp"
)
WHERE
"callLinkRowId" IS NOT NULL
;

CREATE
    INDEX "CallRecord_threadRowId_status_callBeganTimestamp"
        ON "CallRecord"("threadRowId"
    ,"status"
    ,"callBeganTimestamp"
)
WHERE
"threadRowId" IS NOT NULL
;

CREATE
    INDEX "CallRecord_callStatus_unreadStatus_callBeganTimestamp"
        ON "CallRecord"("status"
    ,"unreadStatus"
    ,"callBeganTimestamp"
)
;

CREATE
    INDEX "CallRecord_threadRowId_callStatus_unreadStatus_callBeganTimestamp"
        ON "CallRecord"("threadRowId"
    ,"status"
    ,"unreadStatus"
    ,"callBeganTimestamp"
)
WHERE
"threadRowId" IS NOT NULL
;

CREATE
    UNIQUE INDEX "DeletedCallRecord_threadRowId_callId"
        ON "DeletedCallRecord"("threadRowId"
    ,"callId"
)
WHERE
"threadRowId" IS NOT NULL
;

CREATE
    UNIQUE INDEX "DeletedCallRecord_callLinkRowId_callId"
        ON "DeletedCallRecord"("callLinkRowId"
    ,"callId"
)
WHERE
"callLinkRowId" IS NOT NULL
;

CREATE
    INDEX "DeletedCallRecord_deletedAtTimestamp"
        ON "DeletedCallRecord"("deletedAtTimestamp"
)
;

CREATE
    TABLE
        IF NOT EXISTS "MessageBackupAvatarFetchQueue" (
            "id" INTEGER PRIMARY KEY NOT NULL
            ,"groupThreadRowId" INTEGER REFERENCES "model_TSThread"("id"
        )
            ON DELETE
                CASCADE
                ,"groupAvatarUrl" TEXT
                ,"serviceId" BLOB
                ,"numRetries" INTEGER NOT NULL DEFAULT 0
                ,"nextRetryTimestamp" INTEGER NOT NULL DEFAULT 0
)
;

CREATE
    INDEX "index_MessageBackupAvatarFetchQueue_on_nextRetryTimestamp"
        ON "MessageBackupAvatarFetchQueue"("nextRetryTimestamp"
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
            ,"clientUuid" TEXT
        )
;

CREATE
    INDEX "index_model_TSAttachment_on_uniqueId_and_contentType"
        ON "model_TSAttachment"("uniqueId"
    ,"contentType"
)
;

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

CREATE
    INDEX "index_TSAttachmentMigration_on_interactionRowId"
        ON "TSAttachmentMigration" ("interactionRowId")
WHERE
    "interactionRowId" IS NOT NULL
;

CREATE
    INDEX "index_TSAttachmentMigration_on_storyMessageRowId"
        ON "TSAttachmentMigration" ("storyMessageRowId")
WHERE
    "storyMessageRowId" IS NOT NULL
;

CREATE
    TABLE
        IF NOT EXISTS "BlockedGroup" (
            "groupId" BLOB PRIMARY KEY NOT NULL
        ) WITHOUT ROWID
;

CREATE
    TABLE
        IF NOT EXISTS "CombinedGroupSendEndorsement" (
            "threadId" INTEGER PRIMARY KEY REFERENCES "model_TSThread"("id"
        )
            ON DELETE
                CASCADE
                    ON UPDATE
                        CASCADE
                        ,"endorsement" BLOB NOT NULL
                        ,"expiration" INTEGER NOT NULL
)
;

CREATE
    TABLE
        IF NOT EXISTS "IndividualGroupSendEndorsement" (
            "threadId" INTEGER NOT NULL REFERENCES "CombinedGroupSendEndorsement"("threadId"
        )
            ON DELETE
                CASCADE
                    ON UPDATE
                        CASCADE
                        ,"recipientId" INTEGER NOT NULL REFERENCES "model_SignalRecipient"("id"
)
    ON DELETE
        CASCADE
            ON UPDATE
                CASCADE
                ,"endorsement" BLOB NOT NULL
                ,PRIMARY KEY (
                    "threadId"
                    ,"recipientId"
                )
)
;

CREATE
    INDEX "IndividualGroupSendEndorsement_recipientId"
        ON "IndividualGroupSendEndorsement"("recipientId"
)
;

CREATE
    INDEX "Interaction_incompleteViewOnce_partial"
        ON "model_TSInteraction"("isViewOnceMessage"
    ,"isViewOnceComplete"
)
WHERE
(
    "isViewOnceMessage" = 1
)
AND (
    "isViewOnceComplete" = 0
)
;

CREATE
    INDEX "Interaction_disappearingMessages_partial"
        ON "model_TSInteraction"("expiresAt"
)
WHERE
"expiresAt" > 0
;

CREATE
    INDEX "Interaction_timestamp"
        ON "model_TSInteraction"("timestamp"
)
;

CREATE
    INDEX "Interaction_unendedGroupCall_partial"
        ON "model_TSInteraction"("recordType"
    ,"hasEnded"
    ,"uniqueThreadId"
)
WHERE
(
    "recordType" = 65
)
AND (
    "hasEnded" = 0
)
;

CREATE
    INDEX "Interaction_groupCallEraId_partial"
        ON "model_TSInteraction"("uniqueThreadId"
    ,"recordType"
    ,"eraId"
)
WHERE
"eraId" IS NOT NULL
;

CREATE
    INDEX "Interaction_storyReply_partial"
        ON "model_TSInteraction"("storyAuthorUuidString"
    ,"storyTimestamp"
    ,"isGroupStoryReply"
)
WHERE
(
    "storyAuthorUuidString" IS NOT NULL
)
AND (
    "storyTimestamp" IS NOT NULL
)
;

CREATE
    TABLE
        IF NOT EXISTS "AvatarDefaultColor" (
            "recipientRowId" INTEGER UNIQUE REFERENCES "model_SignalRecipient"("id"
        )
            ON DELETE
                CASCADE
                    ON UPDATE
                        CASCADE
                        ,"groupId" BLOB UNIQUE
                        ,"defaultColorIndex" INTEGER NOT NULL
)
;

CREATE
    TABLE
        IF NOT EXISTS "StoryRecipient" (
            "threadId" INTEGER NOT NULL
            ,"recipientId" INTEGER NOT NULL
            ,PRIMARY KEY (
                "threadId"
                ,"recipientId"
            )
            ,FOREIGN KEY ("threadId") REFERENCES "model_TSThread"("id"
        )
            ON DELETE
                CASCADE
                    ON UPDATE
                        CASCADE
                        ,FOREIGN KEY ("recipientId") REFERENCES "model_SignalRecipient"("id"
)
    ON DELETE
        CASCADE
            ON UPDATE
                CASCADE
) WITHOUT ROWID
;

CREATE
    INDEX "StoryRecipient_on_recipientId"
        ON "StoryRecipient"("recipientId"
)
;

CREATE
    TABLE
        IF NOT EXISTS "BackupAttachmentUploadQueue" (
            "id" INTEGER PRIMARY KEY AUTOINCREMENT
            ,"attachmentRowId" INTEGER NOT NULL REFERENCES "Attachment"("id"
        )
            ON DELETE
                CASCADE
                ,"maxOwnerTimestamp" INTEGER
                ,"estimatedByteCount" INTEGER NOT NULL
                ,"isFullsize" BOOLEAN NOT NULL
)
;

CREATE
    INDEX "index_BackupAttachmentUploadQueue_on_attachmentRowId"
        ON "BackupAttachmentUploadQueue"("attachmentRowId"
)
;

CREATE
    INDEX "index_BackupAttachmentUploadQueue_on_maxOwnerTimestamp_isFullsize"
        ON "BackupAttachmentUploadQueue"("maxOwnerTimestamp"
    ,"isFullsize"
)
;

CREATE
    TABLE
        IF NOT EXISTS "BackupAttachmentDownloadQueue" (
            "id" INTEGER PRIMARY KEY AUTOINCREMENT
            ,"attachmentRowId" INTEGER NOT NULL REFERENCES "Attachment"("id"
        )
            ON DELETE
                CASCADE
                ,"isThumbnail" BOOLEAN NOT NULL
                ,"maxOwnerTimestamp" INTEGER
                ,"canDownloadFromMediaTier" BOOLEAN NOT NULL
                ,"minRetryTimestamp" INTEGER NOT NULL
                ,"numRetries" INTEGER NOT NULL DEFAULT 0
                ,"state" INTEGER
                ,"estimatedByteCount" INTEGER NOT NULL
)
;

CREATE
    INDEX "index_BackupAttachmentDownloadQueue_on_attachmentRowId"
        ON "BackupAttachmentDownloadQueue"("attachmentRowId"
)
;

CREATE
    INDEX "index_BackupAttachmentDownloadQueue_on_state_isThumbnail_minRetryTimestamp"
        ON "BackupAttachmentDownloadQueue"("state"
    ,"isThumbnail"
    ,"minRetryTimestamp"
)
;

CREATE
    INDEX "index_BackupAttachmentDownloadQueue_on_isThumbnail_canDownloadFromMediaTier_state_maxOwnerTimestamp"
        ON "BackupAttachmentDownloadQueue"("isThumbnail"
    ,"canDownloadFromMediaTier"
    ,"state"
    ,"maxOwnerTimestamp"
)
;

CREATE
    INDEX "index_BackupAttachmentDownloadQueue_on_state_estimatedByteCount"
        ON "BackupAttachmentDownloadQueue"("state"
    ,"estimatedByteCount"
)
;

CREATE
    TABLE
        IF NOT EXISTS "ListedBackupMediaObject" (
            "id" INTEGER PRIMARY KEY AUTOINCREMENT
            ,"mediaId" BLOB NOT NULL
            ,"cdnNumber" INTEGER NOT NULL
            ,"objectLength" INTEGER NOT NULL
        )
;

CREATE
    INDEX "index_ListedBackupMediaObject_on_mediaId"
        ON "ListedBackupMediaObject"("mediaId"
)
;

CREATE
    TABLE
        IF NOT EXISTS "BackupOversizeTextCache" (
            "id" INTEGER PRIMARY KEY AUTOINCREMENT
            ,"attachmentRowId" INTEGER NOT NULL UNIQUE REFERENCES "Attachment"("id"
        )
            ON DELETE
                CASCADE
                ,"text" TEXT NOT NULL CHECK (
                    LENGTH( "text" ) <= 131072
                )
)
;
