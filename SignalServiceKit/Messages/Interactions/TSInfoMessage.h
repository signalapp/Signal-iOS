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
    /// Represents that the local user ended a 1:1 encryption session.
    /// - Note:
    /// Legacy info messages did not differentiate between the local and
    /// remote use ending the session. Those messages default to this case.
    /// - SeeAlso: ``TSInfoMessageTypeRemoteUserEndedSession``
    TSInfoMessageTypeLocalUserEndedSession,
    /// - Note This case is deprecated, but may be persisted in legacy messages.
    TSInfoMessageUserNotRegistered,
    /// - Note This case is deprecated, but may be persisted in legacy messages.
    TSInfoMessageTypeUnsupportedMessage,
    TSInfoMessageTypeGroupUpdate,
    /// - Note This case is deprecated, but may be persisted in legacy messages.
    TSInfoMessageTypeGroupQuit,
    TSInfoMessageTypeDisappearingMessagesUpdate,
    /// - Note This case is deprecated, but may be persisted in legacy messages.
    TSInfoMessageAddToContactsOffer,
    TSInfoMessageVerificationStateChange,
    /// - Note This case is deprecated, but may be persisted in legacy messages.
    TSInfoMessageAddUserToProfileWhitelistOffer,
    /// - Note This case is deprecated, but may be persisted in legacy messages.
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
    TSInfoMessageReportedSpam,
    TSInfoMessageLearnedProfileName,
    TSInfoMessageBlockedOtherUser,
    TSInfoMessageBlockedGroup,
    TSInfoMessageUnblockedOtherUser,
    TSInfoMessageUnblockedGroup,
    TSInfoMessageAcceptedMessageRequest,
    /// Represents that the remote user ended a 1:1 encryption session.
    /// - SeeAlso: ``TSInfoMessageTypeLocalUserEndedSession``
    TSInfoMessageTypeRemoteUserEndedSession,
};

typedef NSString *InfoMessageUserInfoKey NS_STRING_ENUM;

extern InfoMessageUserInfoKey const InfoMessageUserInfoKeyLegacyGroupUpdateItems;
extern InfoMessageUserInfoKey const InfoMessageUserInfoKeyGroupUpdateItems;
extern InfoMessageUserInfoKey const InfoMessageUserInfoKeyOldGroupModel;
extern InfoMessageUserInfoKey const InfoMessageUserInfoKeyNewGroupModel;
extern InfoMessageUserInfoKey const InfoMessageUserInfoKeyOldDisappearingMessageToken;
extern InfoMessageUserInfoKey const InfoMessageUserInfoKeyNewDisappearingMessageToken;
extern InfoMessageUserInfoKey const InfoMessageUserInfoKeyGroupUpdateSourceLegacyAddress;
extern InfoMessageUserInfoKey const InfoMessageUserInfoKeyLegacyUpdaterKnownToBeLocalUser;
extern InfoMessageUserInfoKey const InfoMessageUserInfoKeyProfileChanges;
extern InfoMessageUserInfoKey const InfoMessageUserInfoKeyChangePhoneNumberAciString;
extern InfoMessageUserInfoKey const InfoMessageUserInfoKeyChangePhoneNumberOld;
extern InfoMessageUserInfoKey const InfoMessageUserInfoKeyChangePhoneNumberNew;
extern InfoMessageUserInfoKey const InfoMessageUserInfoKeyPaymentActivationRequestSenderAci;
extern InfoMessageUserInfoKey const InfoMessageUserInfoKeyPaymentActivatedAci;
extern InfoMessageUserInfoKey const InfoMessageUserInfoKeyThreadMergePhoneNumber;
extern InfoMessageUserInfoKey const InfoMessageUserInfoKeySessionSwitchoverPhoneNumber;
extern InfoMessageUserInfoKey const InfoMessageUserInfoKeyPhoneNumberDisplayNameBeforeLearningProfileName;
extern InfoMessageUserInfoKey const InfoMessageUserInfoKeyUsernameDisplayNameBeforeLearningProfileName;

@property (nonatomic, readonly) TSInfoMessageType messageType;
@property (nonatomic, readonly, nullable) NSString *customMessage;
@property (nonatomic, readonly, nullable) SignalServiceAddress *unregisteredAddress;
@property (nonatomic, readonly, nullable) NSString *serverGuid;

@property (nonatomic, nullable) NSDictionary<InfoMessageUserInfoKey, id> *infoMessageUserInfo;

- (instancetype)initMessageWithBuilder:(TSMessageBuilder *)messageBuilder NS_UNAVAILABLE;

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
                wasRemotelyDeleted:(BOOL)wasRemotelyDeleted NS_UNAVAILABLE;

- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithThread:(TSThread *)thread
                     timestamp:(uint64_t)timestamp
                    serverGuid:(nullable NSString *)serverGuid
                   messageType:(TSInfoMessageType)messageType
           infoMessageUserInfo:(nullable NSDictionary<InfoMessageUserInfoKey, id> *)infoMessageUserInfo
    NS_DESIGNATED_INITIALIZER;

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
NS_DESIGNATED_INITIALIZER NS_SWIFT_NAME(init(grdbId:uniqueId:receivedAtTimestamp:sortId:timestamp:uniqueThreadId:body:bodyRanges:contactShare:deprecated_attachmentIds:editState:expireStartedAt:expireTimerVersion:expiresAt:expiresInSeconds:giftBadge:isGroupStoryReply:isSmsMessageRestoredFromBackup:isViewOnceComplete:isViewOnceMessage:linkPreview:messageSticker:quotedMessage:storedShouldStartExpireTimer:storyAuthorUuidString:storyReactionEmoji:storyTimestamp:wasRemotelyDeleted:customMessage:infoMessageUserInfo:messageType:read:serverGuid:unregisteredAddress:));

// clang-format on

// --- CODE GENERATION MARKER

- (NSString *)conversationSystemMessageComponentTextWithTransaction:(SDSAnyReadTransaction *)transaction;


- (NSString *)infoMessagePreviewTextWithTransaction:(SDSAnyReadTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
