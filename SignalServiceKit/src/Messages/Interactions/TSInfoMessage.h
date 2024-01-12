//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <SignalServiceKit/OWSReadTracking.h>
#import <SignalServiceKit/TSMessage.h>

NS_ASSUME_NONNULL_BEGIN

@class SignalServiceAddress;

@interface TSInfoMessage : TSMessage <OWSReadTracking>

typedef NS_CLOSED_ENUM(NSInteger, TSInfoMessageType) {
    TSInfoMessageTypeSessionDidEnd,
    TSInfoMessageUserNotRegistered,
    // TSInfoMessageTypeUnsupportedMessage appears to be obsolete.
    TSInfoMessageTypeUnsupportedMessage,
    TSInfoMessageTypeGroupUpdate,
    TSInfoMessageTypeGroupQuit,
    TSInfoMessageTypeDisappearingMessagesUpdate,
    TSInfoMessageAddToContactsOffer,
    TSInfoMessageVerificationStateChange,
    TSInfoMessageAddUserToProfileWhitelistOffer,
    TSInfoMessageAddGroupToProfileWhitelistOffer,
    TSInfoMessageUnknownProtocolVersion,
    TSInfoMessageUserJoinedSignal,
    TSInfoMessageSyncedThread,
    TSInfoMessageProfileUpdate,
    TSInfoMessagePhoneNumberChange,
    TSInfoMessageRecipientHidden,
    TSInfoMessagePaymentsActivationRequest,
    TSInfoMessagePaymentsActivated,
    TSInfoMessageThreadMerge,
    TSInfoMessageSessionSwitchover,
};

typedef NSString *InfoMessageUserInfoKey NS_STRING_ENUM;

extern InfoMessageUserInfoKey const InfoMessageUserInfoKeyLegacyGroupUpdateItems;
extern InfoMessageUserInfoKey const InfoMessageUserInfoKeyGroupUpdateItems;
extern InfoMessageUserInfoKey const InfoMessageUserInfoKeyOldGroupModel;
extern InfoMessageUserInfoKey const InfoMessageUserInfoKeyNewGroupModel;
extern InfoMessageUserInfoKey const InfoMessageUserInfoKeyOldDisappearingMessageToken;
extern InfoMessageUserInfoKey const InfoMessageUserInfoKeyNewDisappearingMessageToken;
extern InfoMessageUserInfoKey const InfoMessageUserInfoKeyGroupUpdateSourceLegacyAddress;
extern InfoMessageUserInfoKey const InfoMessageUserInfoKeyGroupUpdateSourceType;
extern InfoMessageUserInfoKey const InfoMessageUserInfoKeyGroupUpdateSourceAciData;
extern InfoMessageUserInfoKey const InfoMessageUserInfoKeyGroupUpdateSourcePniData;
extern InfoMessageUserInfoKey const InfoMessageUserInfoKeyLegacyUpdaterKnownToBeLocalUser;
extern InfoMessageUserInfoKey const InfoMessageUserInfoKeyProfileChanges;
extern InfoMessageUserInfoKey const InfoMessageUserInfoKeyChangePhoneNumberAciString;
extern InfoMessageUserInfoKey const InfoMessageUserInfoKeyChangePhoneNumberOld;
extern InfoMessageUserInfoKey const InfoMessageUserInfoKeyChangePhoneNumberNew;
extern InfoMessageUserInfoKey const InfoMessageUserInfoKeyPaymentActivationRequestSenderAci;
extern InfoMessageUserInfoKey const InfoMessageUserInfoKeyPaymentActivatedAci;
extern InfoMessageUserInfoKey const InfoMessageUserInfoKeyThreadMergePhoneNumber;
extern InfoMessageUserInfoKey const InfoMessageUserInfoKeySessionSwitchoverPhoneNumber;

+ (instancetype)userNotRegisteredMessageInThread:(TSThread *)thread address:(SignalServiceAddress *)address;

@property (nonatomic, readonly) TSInfoMessageType messageType;
@property (nonatomic, readonly, nullable) NSString *customMessage;
@property (nonatomic, readonly, nullable) SignalServiceAddress *unregisteredAddress;

@property (nonatomic, nullable) NSDictionary<InfoMessageUserInfoKey, id> *infoMessageUserInfo;

- (instancetype)initMessageWithBuilder:(TSMessageBuilder *)messageBuilder NS_UNAVAILABLE;

- (instancetype)initWithGrdbId:(int64_t)grdbId
                        uniqueId:(NSString *)uniqueId
             receivedAtTimestamp:(uint64_t)receivedAtTimestamp
                          sortId:(uint64_t)sortId
                       timestamp:(uint64_t)timestamp
                  uniqueThreadId:(NSString *)uniqueThreadId
                   attachmentIds:(NSArray<NSString *> *)attachmentIds
                            body:(nullable NSString *)body
                      bodyRanges:(nullable MessageBodyRanges *)bodyRanges
                    contactShare:(nullable OWSContact *)contactShare
                       editState:(TSEditState)editState
                 expireStartedAt:(uint64_t)expireStartedAt
                       expiresAt:(uint64_t)expiresAt
                expiresInSeconds:(unsigned int)expiresInSeconds
                       giftBadge:(nullable OWSGiftBadge *)giftBadge
               isGroupStoryReply:(BOOL)isGroupStoryReply
              isViewOnceComplete:(BOOL)isViewOnceComplete
               isViewOnceMessage:(BOOL)isViewOnceMessage
                     linkPreview:(nullable OWSLinkPreview *)linkPreview
                  messageSticker:(nullable MessageSticker *)messageSticker
                   quotedMessage:(nullable TSQuotedMessage *)quotedMessage
    storedShouldStartExpireTimer:(BOOL)storedShouldStartExpireTimer
           storyAuthorUuidString:(nullable NSString *)storyAuthorUuidString
              storyReactionEmoji:(nullable NSString *)storyReactionEmoji
                  storyTimestamp:(nullable NSNumber *)storyTimestamp
              wasRemotelyDeleted:(BOOL)wasRemotelyDeleted NS_UNAVAILABLE;

- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithThread:(TSThread *)contact messageType:(TSInfoMessageType)infoMessage NS_DESIGNATED_INITIALIZER;

// Convenience initializer which is neither "designated" nor "unavailable".
- (instancetype)initWithThread:(TSThread *)thread
                   messageType:(TSInfoMessageType)infoMessage
                 customMessage:(NSString *)customMessage;

// Convenience initializer which is neither "designated" nor "unavailable".
- (instancetype)initWithThread:(TSThread *)thread
                   messageType:(TSInfoMessageType)infoMessage
           infoMessageUserInfo:(NSDictionary<InfoMessageUserInfoKey, id> *)infoMessageUserInfo;

// Convenience initializer which is neither "designated" nor "unavailable".
- (instancetype)initWithThread:(TSThread *)thread
                   messageType:(TSInfoMessageType)infoMessage
           unregisteredAddress:(SignalServiceAddress *)unregisteredAddress;

// --- CODE GENERATION MARKER

// This snippet is generated by /Scripts/sds_codegen/sds_generate.py. Do not manually edit it, instead run `sds_codegen.sh`.

// clang-format off

- (instancetype)initWithGrdbId:(int64_t)grdbId
                      uniqueId:(NSString *)uniqueId
             receivedAtTimestamp:(uint64_t)receivedAtTimestamp
                          sortId:(uint64_t)sortId
                       timestamp:(uint64_t)timestamp
                  uniqueThreadId:(NSString *)uniqueThreadId
                   attachmentIds:(NSArray<NSString *> *)attachmentIds
                            body:(nullable NSString *)body
                      bodyRanges:(nullable MessageBodyRanges *)bodyRanges
                    contactShare:(nullable OWSContact *)contactShare
                       editState:(TSEditState)editState
                 expireStartedAt:(uint64_t)expireStartedAt
                       expiresAt:(uint64_t)expiresAt
                expiresInSeconds:(unsigned int)expiresInSeconds
                       giftBadge:(nullable OWSGiftBadge *)giftBadge
               isGroupStoryReply:(BOOL)isGroupStoryReply
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
             unregisteredAddress:(nullable SignalServiceAddress *)unregisteredAddress
NS_DESIGNATED_INITIALIZER NS_SWIFT_NAME(init(grdbId:uniqueId:receivedAtTimestamp:sortId:timestamp:uniqueThreadId:attachmentIds:body:bodyRanges:contactShare:editState:expireStartedAt:expiresAt:expiresInSeconds:giftBadge:isGroupStoryReply:isViewOnceComplete:isViewOnceMessage:linkPreview:messageSticker:quotedMessage:storedShouldStartExpireTimer:storyAuthorUuidString:storyReactionEmoji:storyTimestamp:wasRemotelyDeleted:customMessage:infoMessageUserInfo:messageType:read:unregisteredAddress:));

// clang-format on

// --- CODE GENERATION MARKER

- (NSString *)conversationSystemMessageComponentTextWithTransaction:(SDSAnyReadTransaction *)transaction;


- (NSString *)infoMessagePreviewTextWithTransaction:(SDSAnyReadTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
