//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSRecoverableDecryptionPlaceholder.h"
#import "TSThread.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSRecoverableDecryptionPlaceholder

- (nullable instancetype)initWithFailedEnvelopeTimestamp:(uint64_t)timestamp
                                               sourceAci:(AciObjC *)sourceAci
                                        untrustedGroupId:(nullable NSData *)untrustedGroupId
                                             transaction:(SDSAnyWriteTransaction *)writeTx
{
    SignalServiceAddress *sender = [[SignalServiceAddress alloc] initWithServiceIdObjC:sourceAci];
    TSThread *thread;
    if (untrustedGroupId.length > 0) {
        TSGroupThread *_Nullable groupThread = [TSGroupThread fetchWithGroupId:untrustedGroupId transaction:writeTx];
        // If we aren't sure that the sender is a member of the reported groupId, we should fall back
        // to inserting the placeholder in the contact thread.
        if ([groupThread.groupMembership isFullMember:sender]) {
            thread = groupThread;
        }
        OWSAssertDebug(thread);
    }
    if (!thread) {
        thread = [TSContactThread getThreadWithContactAddress:sender transaction:writeTx];
        OWSAssertDebug(thread);
    }
    if (!thread) {
        return nil;
    }
    TSErrorMessageBuilder *builder = [[TSErrorMessageBuilder alloc] initWithThread:thread
                                                                         errorType:TSErrorMessageDecryptionFailure];
    builder.timestamp = timestamp;
    builder.senderAddress = sender;
    return [super initErrorMessageWithBuilder:builder];
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    return [super initWithCoder:coder];
}

- (instancetype)initWithGrdbId:(int64_t)grdbId
                          uniqueId:(NSString *)uniqueId
               receivedAtTimestamp:(uint64_t)receivedAtTimestamp
                            sortId:(uint64_t)sortId
                         timestamp:(uint64_t)timestamp
                    uniqueThreadId:(NSString *)uniqueThreadId
                              body:(nullable NSString *)body
                        bodyRanges:(nullable MessageBodyRanges *)bodyRanges
                      contactShare:(nullable OWSContact *)contactShare
          deprecated_attachmentIds:(nullable NSArray<NSString *> *)deprecated_attachmentIds
                         editState:(TSEditState)editState
                   expireStartedAt:(uint64_t)expireStartedAt
                expireTimerVersion:(nullable NSNumber *)expireTimerVersion
                         expiresAt:(uint64_t)expiresAt
                  expiresInSeconds:(unsigned int)expiresInSeconds
                         giftBadge:(nullable OWSGiftBadge *)giftBadge
                 isGroupStoryReply:(BOOL)isGroupStoryReply
    isSmsMessageRestoredFromBackup:(BOOL)isSmsMessageRestoredFromBackup
                isViewOnceComplete:(BOOL)isViewOnceComplete
                 isViewOnceMessage:(BOOL)isViewOnceMessage
                       linkPreview:(nullable OWSLinkPreview *)linkPreview
                    messageSticker:(nullable MessageSticker *)messageSticker
                     quotedMessage:(nullable TSQuotedMessage *)quotedMessage
      storedShouldStartExpireTimer:(BOOL)storedShouldStartExpireTimer
             storyAuthorUuidString:(nullable NSString *)storyAuthorUuidString
                storyReactionEmoji:(nullable NSString *)storyReactionEmoji
                    storyTimestamp:(nullable NSNumber *)storyTimestamp
                wasRemotelyDeleted:(BOOL)wasRemotelyDeleted
                         errorType:(TSErrorMessageType)errorType
                              read:(BOOL)read
                  recipientAddress:(nullable SignalServiceAddress *)recipientAddress
                            sender:(nullable SignalServiceAddress *)sender
               wasIdentityVerified:(BOOL)wasIdentityVerified
{
    self = [super initWithGrdbId:grdbId
                              uniqueId:uniqueId
                   receivedAtTimestamp:receivedAtTimestamp
                                sortId:sortId
                             timestamp:timestamp
                        uniqueThreadId:uniqueThreadId
                                  body:body
                            bodyRanges:bodyRanges
                          contactShare:contactShare
              deprecated_attachmentIds:deprecated_attachmentIds
                             editState:editState
                       expireStartedAt:expireStartedAt
                    expireTimerVersion:expireTimerVersion
                             expiresAt:expiresAt
                      expiresInSeconds:expiresInSeconds
                             giftBadge:giftBadge
                     isGroupStoryReply:isGroupStoryReply
        isSmsMessageRestoredFromBackup:isSmsMessageRestoredFromBackup
                    isViewOnceComplete:isViewOnceComplete
                     isViewOnceMessage:isViewOnceMessage
                           linkPreview:linkPreview
                        messageSticker:messageSticker
                         quotedMessage:quotedMessage
          storedShouldStartExpireTimer:storedShouldStartExpireTimer
                 storyAuthorUuidString:storyAuthorUuidString
                    storyReactionEmoji:storyReactionEmoji
                        storyTimestamp:storyTimestamp
                    wasRemotelyDeleted:wasRemotelyDeleted
                             errorType:errorType
                                  read:read
                      recipientAddress:recipientAddress
                                sender:sender
                   wasIdentityVerified:wasIdentityVerified];

    return self;
}

// --- CODE GENERATION MARKER

// This snippet is generated by /Scripts/sds_codegen/sds_generate.py. Do not manually edit it, instead run
// `sds_codegen.sh`.


// --- CODE GENERATION MARKER

#pragma mark - Methods

- (BOOL)supportsReplacement
{
    return [self.expirationDate isAfterNow] && !self.wasRead;
}

- (NSString *)previewTextWithTransaction:(SDSAnyReadTransaction *)transaction
{
    NSString *_Nullable senderName = nil;
    if (self.sender) {
        senderName = [SSKEnvironment.shared.contactManagerObjcRef shortDisplayNameStringForAddress:self.sender
                                                                                       transaction:transaction];
    }

    if (senderName) {
        OWSFailDebug(@"Should not be directly surfaced to user");
        NSString *formatString = OWSLocalizedString(@"ERROR_MESSAGE_DECRYPTION_FAILURE",
            @"Error message for a decryption failure. Embeds {{sender short name}}.");
        return [[NSString alloc] initWithFormat:formatString, senderName];
    } else {
        OWSFailDebug(@"Should not be directly surfaced to user");
        return OWSLocalizedString(
            @"ERROR_MESSAGE_DECRYPTION_FAILURE_UNKNOWN_SENDER", @"Error message for a decryption failure.");
    }
}

#pragma mark - <OWSReadTracking>

- (void)markAsReadAtTimestamp:(uint64_t)readTimestamp
                       thread:(TSThread *)thread
                 circumstance:(OWSReceiptCircumstance)circumstance
     shouldClearNotifications:(BOOL)shouldClearNotifications
                  transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSLogInfo(@"Marking placeholder as read. No longer eligible for inline replacement.");
    [super markAsReadAtTimestamp:readTimestamp
                          thread:thread
                    circumstance:circumstance
        shouldClearNotifications:shouldClearNotifications
                     transaction:transaction];
}

@end

NS_ASSUME_NONNULL_END
