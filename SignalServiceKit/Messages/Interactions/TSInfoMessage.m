//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "TSInfoMessage.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

const InfoMessageUserInfoKey InfoMessageUserInfoKeyLegacyGroupUpdateItems = @"InfoMessageUserInfoKeyUpdateMessages";
const InfoMessageUserInfoKey InfoMessageUserInfoKeyGroupUpdateItems = @"InfoMessageUserInfoKeyUpdateMessagesV2";
const InfoMessageUserInfoKey InfoMessageUserInfoKeyOldGroupModel = @"InfoMessageUserInfoKeyOldGroupModel";
const InfoMessageUserInfoKey InfoMessageUserInfoKeyNewGroupModel = @"InfoMessageUserInfoKeyNewGroupModel";
const InfoMessageUserInfoKey InfoMessageUserInfoKeyOldDisappearingMessageToken
    = @"InfoMessageUserInfoKeyOldDisappearingMessageToken";
const InfoMessageUserInfoKey InfoMessageUserInfoKeyNewDisappearingMessageToken
    = @"InfoMessageUserInfoKeyNewDisappearingMessageToken";
const InfoMessageUserInfoKey InfoMessageUserInfoKeyGroupUpdateSourceLegacyAddress
    = @"InfoMessageUserInfoKeyGroupUpdateSourceAddress";
const InfoMessageUserInfoKey InfoMessageUserInfoKeyLegacyUpdaterKnownToBeLocalUser
    = @"InfoMessageUserInfoKeyUpdaterWasLocalUser";
const InfoMessageUserInfoKey InfoMessageUserInfoKeyProfileChanges = @"InfoMessageUserInfoKeyProfileChanges";
const InfoMessageUserInfoKey InfoMessageUserInfoKeyChangePhoneNumberAciString
    = @"InfoMessageUserInfoKeyChangePhoneNumberUuid";
const InfoMessageUserInfoKey InfoMessageUserInfoKeyChangePhoneNumberOld = @"InfoMessageUserInfoKeyChangePhoneNumberOld";
const InfoMessageUserInfoKey InfoMessageUserInfoKeyChangePhoneNumberNew = @"InfoMessageUserInfoKeyChangePhoneNumberNew";
const InfoMessageUserInfoKey InfoMessageUserInfoKeyPaymentActivationRequestSenderAci
    = @"InfoMessageUserInfoKeyPaymentActivationRequestSenderAci";
const InfoMessageUserInfoKey InfoMessageUserInfoKeyPaymentActivatedAci = @"InfoMessageUserInfoKeyPaymentActivatedAci";
const InfoMessageUserInfoKey InfoMessageUserInfoKeyThreadMergePhoneNumber
    = @"InfoMessageUserInfoKeyThreadMergePhoneNumber";
const InfoMessageUserInfoKey InfoMessageUserInfoKeySessionSwitchoverPhoneNumber
    = @"InfoMessageUserInfoKeySessionSwitchoverPhoneNumber";
const InfoMessageUserInfoKey InfoMessageUserInfoKeyPhoneNumberDisplayNameBeforeLearningProfileName
    = @"InfoMessageUserInfoKeyPhoneNumberDisplayNameBeforeLearningProfileName";
const InfoMessageUserInfoKey InfoMessageUserInfoKeyUsernameDisplayNameBeforeLearningProfileName
    = @"InfoMessageUserInfoKeyUsernameDisplayNameBeforeLearningProfileName";
const InfoMessageUserInfoKey InfoMessageUserInfoKeySharedNameDisplayNameBeforeLearningProfileName
    = @"InfoMessageUserInfoKeySharedNameDisplayNameBeforeLearningProfileName";
const InfoMessageUserInfoKey InfoMessageUserInfoKeyEndPoll = @"InfoMessageUserInfoKeyEndPoll";
const InfoMessageUserInfoKey InfoMessageUserInfoKeyPinnedMessage = @"InfoMessageUserInfoKeyPinnedMessage";

@interface TSInfoMessage ()

@property (nonatomic, getter=wasRead) BOOL read;

@end

#pragma mark -

@implementation TSInfoMessage

+ (NSArray<Class> *)infoMessageUserInfoObjectClasses
{
    return @[
        [DisappearingMessageToken class],
        [NSDictionary class],
        [NSNull class],
        [NSNumber class],
        [NSString class],
        [PersistableEndPollItem class],
        [PersistablePinnedMessageItem class],
        [ProfileChanges class],
        [SignalServiceAddress class],
        [TSGroupModel class],
        [TSInfoMessageUpdateMessages class],
        [TSInfoMessageUpdateMessagesV2 class]
    ];
}

- (NSUInteger)hash
{
    NSUInteger result = [super hash];
    result ^= self.customMessage.hash;
    result ^= self.infoMessageUserInfo.hash;
    result ^= (NSUInteger)self.messageType;
    result ^= self.read;
    result ^= self.serverGuid.hash;
    result ^= self.unregisteredAddress.hash;
    return result;
}

- (BOOL)isEqual:(id)other
{
    if (![super isEqual:other]) {
        return NO;
    }
    TSInfoMessage *typedOther = (TSInfoMessage *)other;
    if (![NSObject isObject:self.customMessage equalToObject:typedOther.customMessage]) {
        return NO;
    }
    if (![NSObject isObject:self.infoMessageUserInfo equalToObject:typedOther.infoMessageUserInfo]) {
        return NO;
    }
    if (self.messageType != typedOther.messageType) {
        return NO;
    }
    if (self.read != typedOther.read) {
        return NO;
    }
    if (![NSObject isObject:self.serverGuid equalToObject:typedOther.serverGuid]) {
        return NO;
    }
    if (![NSObject isObject:self.unregisteredAddress equalToObject:typedOther.unregisteredAddress]) {
        return NO;
    }
    return YES;
}

- (instancetype)initWithThread:(TSThread *)thread
                     timestamp:(uint64_t)timestamp
                    serverGuid:(nullable NSString *)serverGuid
                   messageType:(TSInfoMessageType)messageType
            expireTimerVersion:(nullable NSNumber *)expireTimerVersion
              expiresInSeconds:(unsigned int)expiresInSeconds
               expireStartedAt:(uint64_t)expireStartedAt
           infoMessageUserInfo:(nullable NSDictionary<InfoMessageUserInfoKey, id> *)infoMessageUserInfo
{
    TSMessageBuilder *builder;
    if (timestamp > 0) {
        builder = [TSMessageBuilder messageBuilderWithThread:thread timestamp:timestamp];
    } else {
        builder = [TSMessageBuilder messageBuilderWithThread:thread];
    }

    builder.expireTimerVersion = expireTimerVersion;
    builder.expiresInSeconds = expiresInSeconds;
    builder.expireStartedAt = expireStartedAt;

    self = [super initMessageWithBuilder:builder];
    if (!self) {
        return self;
    }

    _serverGuid = serverGuid;
    _messageType = messageType;
    _infoMessageUserInfo = infoMessageUserInfo;

    if (self.isDynamicInteraction) {
        self.read = YES;
    }

    if (_messageType == TSInfoMessageTypeGroupQuit) {
        self.read = YES;
    }

    return self;
}

// --- CODE GENERATION MARKER

// This snippet is generated by /Scripts/sds_codegen/sds_generate.py. Do not manually edit it, instead run
// `sds_codegen.sh`.

// clang-format off

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
                          isPoll:(BOOL)isPoll
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
                   customMessage:(nullable NSString *)customMessage
             infoMessageUserInfo:(nullable NSDictionary<InfoMessageUserInfoKey, id> *)infoMessageUserInfo
                     messageType:(TSInfoMessageType)messageType
                            read:(BOOL)read
                      serverGuid:(nullable NSString *)serverGuid
             unregisteredAddress:(nullable SignalServiceAddress *)unregisteredAddress
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
                            isPoll:isPoll
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
                wasRemotelyDeleted:wasRemotelyDeleted];

    if (!self) {
        return self;
    }

    _customMessage = customMessage;
    _infoMessageUserInfo = infoMessageUserInfo;
    _messageType = messageType;
    _read = read;
    _serverGuid = serverGuid;
    _unregisteredAddress = unregisteredAddress;

    return self;
}

// clang-format on

// --- CODE GENERATION MARKER

- (OWSInteractionType)interactionType
{
    return OWSInteractionType_Info;
}

- (NSString *)conversationSystemMessageComponentTextWithTransaction:(DBReadTransaction *)transaction
{
    switch (self.messageType) {
        case TSInfoMessageSyncedThread:
            // This particular string is here, and not in `infoMessagePreviewTextWithTransaction`,
            // because we want it to be excluded from everywhere except chat list rendering.
            // e.g. not in the conversation list preview.
            return OWSLocalizedString(@"INFO_MESSAGE_SYNCED_THREAD",
                @"Shown in inbox and conversation after syncing as a placeholder indicating why your message history "
                @"is missing.");
        default:
            return [self infoMessagePreviewTextWithTransaction:transaction];
    }
}

- (NSString *)infoMessagePreviewTextWithTransaction:(DBReadTransaction *)transaction
{
    return [self _infoMessagePreviewTextWithTx:transaction];
}

#pragma mark - OWSReadTracking

- (void)markAsReadAtTimestamp:(uint64_t)readTimestamp
                       thread:(TSThread *)thread
                 circumstance:(OWSReceiptCircumstance)circumstance
     shouldClearNotifications:(BOOL)shouldClearNotifications
                  transaction:(DBWriteTransaction *)transaction
{
    OWSAssertDebug(transaction);

    if (self.read) {
        return;
    }

    [self anyUpdateInfoMessageWithTransaction:transaction block:^(TSInfoMessage *message) { message.read = YES; }];

    // Ignore `circumstance` - we never send read receipts for info messages.
}

@end

NS_ASSUME_NONNULL_END
