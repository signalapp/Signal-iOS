//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <SignalServiceKit/OWSArchivedPaymentMessage.h>
#import <SignalServiceKit/SignalServiceKit.h>
#import <SignalServiceKit/TSOutgoingMessage.h>
#import <SignalServiceKit/TSPaymentModels.h>

NS_ASSUME_NONNULL_BEGIN

@class TSPaymentReference;

@interface OWSOutgoingArchivedPaymentMessage : TSOutgoingMessage <OWSArchivedPaymentMessage>

@property (nonatomic, readonly) TSArchivedPaymentInfo *archivedPaymentInfo;

- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)initOutgoingMessageWithBuilder:(TSOutgoingMessageBuilder *)outgoingMessageBuilder
                        recipientAddressStates:
                            (NSDictionary<SignalServiceAddress *, TSOutgoingMessageRecipientState *> *)
                                recipientAddressStates NS_UNAVAILABLE;
- (instancetype)initOutgoingMessageWithBuilder:(TSOutgoingMessageBuilder *)outgoingMessageBuilder
                          additionalRecipients:(NSArray<SignalServiceAddress *> *)additionalRecipients
                            explicitRecipients:(NSArray<AciObjC *> *)explicitRecipients
                             skippedRecipients:(NSArray<SignalServiceAddress *> *)skippedRecipients
                                   transaction:(SDSAnyReadTransaction *)transaction NS_UNAVAILABLE;

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
                  groupMetaMessage:(TSGroupMetaMessage)groupMetaMessage
             hasLegacyMessageState:(BOOL)hasLegacyMessageState
               hasSyncedTranscript:(BOOL)hasSyncedTranscript
                    isVoiceMessage:(BOOL)isVoiceMessage
                legacyMessageState:(TSOutgoingMessageState)legacyMessageState
                legacyWasDelivered:(BOOL)legacyWasDelivered
             mostRecentFailureText:(nullable NSString *)mostRecentFailureText
            recipientAddressStates:(nullable NSDictionary<SignalServiceAddress *, TSOutgoingMessageRecipientState *> *)
                                       recipientAddressStates
                storedMessageState:(TSOutgoingMessageState)storedMessageState
              wasNotCreatedLocally:(BOOL)wasNotCreatedLocally NS_UNAVAILABLE;

- (instancetype)initOutgoingArchivedPaymentMessageWithBuilder:(TSOutgoingMessageBuilder *)messageBuilder
                                                       amount:(nullable NSString *)amount
                                                          fee:(nullable NSString *)fee
                                                         note:(nullable NSString *)note
                                                  transaction:(SDSAnyReadTransaction *)transaction
    NS_DESIGNATED_INITIALIZER;

- (instancetype)initOutgoingArchivedPaymentMessageWithBuilder:(TSOutgoingMessageBuilder *)messageBuilder
                                                       amount:(nullable NSString *)amount
                                                          fee:(nullable NSString *)fee
                                                         note:(nullable NSString *)note
                                       recipientAddressStates:
                                           (NSDictionary<SignalServiceAddress *, TSOutgoingMessageRecipientState *> *)
                                               recipientAddressStates NS_DESIGNATED_INITIALIZER;

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
                groupMetaMessage:(TSGroupMetaMessage)groupMetaMessage
           hasLegacyMessageState:(BOOL)hasLegacyMessageState
             hasSyncedTranscript:(BOOL)hasSyncedTranscript
                  isVoiceMessage:(BOOL)isVoiceMessage
              legacyMessageState:(TSOutgoingMessageState)legacyMessageState
              legacyWasDelivered:(BOOL)legacyWasDelivered
           mostRecentFailureText:(nullable NSString *)mostRecentFailureText
          recipientAddressStates:(nullable NSDictionary<SignalServiceAddress *,TSOutgoingMessageRecipientState *> *)recipientAddressStates
              storedMessageState:(TSOutgoingMessageState)storedMessageState
            wasNotCreatedLocally:(BOOL)wasNotCreatedLocally
             archivedPaymentInfo:(TSArchivedPaymentInfo *)archivedPaymentInfo
NS_DESIGNATED_INITIALIZER NS_SWIFT_NAME(init(grdbId:uniqueId:receivedAtTimestamp:sortId:timestamp:uniqueThreadId:body:bodyRanges:contactShare:deprecated_attachmentIds:editState:expireStartedAt:expireTimerVersion:expiresAt:expiresInSeconds:giftBadge:isGroupStoryReply:isSmsMessageRestoredFromBackup:isViewOnceComplete:isViewOnceMessage:linkPreview:messageSticker:quotedMessage:storedShouldStartExpireTimer:storyAuthorUuidString:storyReactionEmoji:storyTimestamp:wasRemotelyDeleted:customMessage:groupMetaMessage:hasLegacyMessageState:hasSyncedTranscript:isVoiceMessage:legacyMessageState:legacyWasDelivered:mostRecentFailureText:recipientAddressStates:storedMessageState:wasNotCreatedLocally:archivedPaymentInfo:));

// clang-format on

// --- CODE GENERATION MARKER

@end

NS_ASSUME_NONNULL_END
