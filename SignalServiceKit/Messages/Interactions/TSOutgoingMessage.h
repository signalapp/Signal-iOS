//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <SignalServiceKit/TSMessage.h>
#import <SignalServiceKit/TSPaymentModels.h>

NS_ASSUME_NONNULL_BEGIN

extern const NSUInteger kOversizeTextMessageSizeThreshold;

@class OWSOutgoingSyncMessage;
@class SignalServiceAddress;
@class TSOutgoingMessageRecipientState;

typedef NS_ENUM(NSUInteger, OWSOutgoingMessageRecipientStatus);

typedef NS_CLOSED_ENUM(NSUInteger, OutgoingGroupProtoResult) {
    OutgoingGroupProtoResult_AddedWithoutGroupAvatar,
    OutgoingGroupProtoResult_Error
};

typedef NS_CLOSED_ENUM(NSInteger, TSOutgoingMessageState) {
    // The message is either:
    // a) Enqueued for sending.
    // b) Waiting on attachment upload(s).
    // c) Being sent to the service.
    TSOutgoingMessageStateSending,
    // The failure state.
    TSOutgoingMessageStateFailed,
    // These two enum values have been combined into TSOutgoingMessageStateSent.
    TSOutgoingMessageStateSent_OBSOLETE,
    TSOutgoingMessageStateDelivered_OBSOLETE,
    // The message has been sent to the service.
    TSOutgoingMessageStateSent,
    // The message is blocked behind some precondition.
    TSOutgoingMessageStatePending
};

NSString *NSStringForOutgoingMessageState(TSOutgoingMessageState value);

typedef NS_ENUM(NSInteger, TSGroupMetaMessage) {
    TSGroupMetaMessageUnspecified,
    TSGroupMetaMessageNew,
    TSGroupMetaMessageUpdate,
    TSGroupMetaMessageDeliver,
    TSGroupMetaMessageQuit,
    TSGroupMetaMessageRequestInfo,
};

typedef NS_ENUM(NSInteger, EncryptionStyle) {
    EncryptionStyleWhisper,
    EncryptionStylePlaintext
};

@protocol DeliveryReceiptContext;

@class SDSAnyWriteTransaction;
@class SSKProtoAttachmentPointer;
@class SSKProtoContentBuilder;
@class SSKProtoDataMessageBuilder;
@class ServiceIdObjC;
@class SignalServiceAddress;
@class TSOutgoingMessageBuilder;

#pragma mark -

@interface TSOutgoingMessage : TSMessage

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
                         editState:(unsigned int)editState
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

/// Create a `TSOutgoingMessage` with implicit recipients as well as the given
/// categories of recipient.
///
/// - Note
/// A transaction is required for this initializer in order to look up intended
/// recipients and compute `recipientAddressStates` on the fly.
- (instancetype)initOutgoingMessageWithBuilder:(TSOutgoingMessageBuilder *)outgoingMessageBuilder
                          additionalRecipients:(NSArray<SignalServiceAddress *> *)additionalRecipients
                            explicitRecipients:(NSArray<AciObjC *> *)explicitRecipients
                             skippedRecipients:(NSArray<SignalServiceAddress *> *)skippedRecipients
                                   transaction:(SDSAnyReadTransaction *)transaction NS_DESIGNATED_INITIALIZER;

/// Create a `TSOutgoingMessage` with precomputed recipient states.
- (instancetype)initOutgoingMessageWithBuilder:(TSOutgoingMessageBuilder *)outgoingMessageBuilder
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
NS_DESIGNATED_INITIALIZER NS_SWIFT_NAME(init(grdbId:uniqueId:receivedAtTimestamp:sortId:timestamp:uniqueThreadId:body:bodyRanges:contactShare:deprecated_attachmentIds:editState:expireStartedAt:expireTimerVersion:expiresAt:expiresInSeconds:giftBadge:isGroupStoryReply:isSmsMessageRestoredFromBackup:isViewOnceComplete:isViewOnceMessage:linkPreview:messageSticker:quotedMessage:storedShouldStartExpireTimer:storyAuthorUuidString:storyReactionEmoji:storyTimestamp:wasRemotelyDeleted:customMessage:groupMetaMessage:hasLegacyMessageState:hasSyncedTranscript:isVoiceMessage:legacyMessageState:legacyWasDelivered:mostRecentFailureText:recipientAddressStates:storedMessageState:wasNotCreatedLocally:));

// clang-format on

// --- CODE GENERATION MARKER

@property (nonatomic, readonly) TSOutgoingMessageState messageState;

// The states for all recipients.
@property (atomic, nullable)
    NSDictionary<SignalServiceAddress *, TSOutgoingMessageRecipientState *> *recipientAddressStates;

@property (nonatomic, readonly) BOOL wasDeliveredToAnyRecipient;
@property (nonatomic, readonly) BOOL wasSentToAnyRecipient;

@property (atomic, readonly) BOOL hasSyncedTranscript;
@property (atomic, readonly, nullable) NSString *customMessage;
@property (atomic, nullable) NSString *mostRecentFailureText;

@property (atomic, readonly) TSGroupMetaMessage groupMetaMessage;

@property (nonatomic, readonly) BOOL isVoiceMessage;

// This property won't be accurate for legacy messages.
@property (atomic) BOOL wasNotCreatedLocally;

@property (nonatomic, readonly) BOOL isOnline;

@property (nonatomic, readonly) BOOL isUrgent;

/// NOTE: We do not persist this property in a TSInteraction column;
/// however, we **do** persist it via NSKeyedArchiver. It is only used for
/// group updates that are inserted into MessageSenderJobQueue. It's also
/// misnamed: it actually stores a GroupChange, not a GroupChange.Actions.
@property (nonatomic, readonly, nullable) NSData *changeActionsProtoData;

/**
 * The data representation of this message, to be encrypted, before being sent.
 */
- (nullable NSData *)buildPlainTextData:(TSThread *)thread transaction:(SDSAnyWriteTransaction *)transaction;

/**
 * Intermediate protobuf representation
 * Subclasses can augment if they want to manipulate the Content message before building.
 */
- (nullable SSKProtoContentBuilder *)contentBuilderWithThread:(TSThread *)thread
                                                  transaction:(SDSAnyReadTransaction *)transaction
    NS_SWIFT_NAME(contentBuilder(thread:transaction:));

/**
 * Intermediate protobuf representation
 * Subclasses can augment if they want to manipulate the data message before building.
 */
- (nullable SSKProtoDataMessageBuilder *)dataMessageBuilderWithThread:(TSThread *)thread
                                                          transaction:(SDSAnyReadTransaction *)transaction;

- (nullable SSKProtoDataMessage *)buildDataMessage:(TSThread *)thread transaction:(SDSAnyReadTransaction *)transaction;

/**
 * Should this message be synced to the users other registered devices? This is
 * generally always true, except in the case of the sync messages themseleves
 * (so we don't end up in an infinite loop).
 */
- (BOOL)shouldSyncTranscript;

- (nullable OWSOutgoingSyncMessage *)buildTranscriptSyncMessageWithLocalThread:(TSThread *)localThread
                                                                   transaction:(SDSAnyWriteTransaction *)transaction
    NS_SWIFT_NAME(buildTranscriptSyncMessage(localThread:transaction:));

#pragma mark - Update With... Methods

- (void)updateWithHasSyncedTranscript:(BOOL)hasSyncedTranscript transaction:(SDSAnyWriteTransaction *)transaction;

/**
 * Sync the stored message state with the computed message state. Must be run before any insert/update.
 */
- (void)updateStoredMessageState;

@end

NS_ASSUME_NONNULL_END
