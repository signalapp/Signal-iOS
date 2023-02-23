//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <SignalServiceKit/TSMessage.h>
#import <SignalServiceKit/TSPaymentModels.h>

NS_ASSUME_NONNULL_BEGIN

@class OWSOutgoingSyncMessage;
@class SignalServiceAddress;

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

typedef NS_CLOSED_ENUM(NSInteger, OWSOutgoingMessageRecipientState) {
    // Message could not be sent to recipient.
    OWSOutgoingMessageRecipientStateFailed = 0,
    // Message is being sent to the recipient (enqueued, uploading or sending).
    OWSOutgoingMessageRecipientStateSending,
    // The message was not sent because the recipient is not valid
    // or already has received the message via another channel.
    // For example, this recipient may have left the group
    OWSOutgoingMessageRecipientStateSkipped,
    // The message has been sent to the service.  It may also have been delivered or read.
    OWSOutgoingMessageRecipientStateSent,
    // The server rejected the message send request until some other condition is satisfied.
    // Currently, this only flags messages that the server suspects may be spam.
    OWSOutgoingMessageRecipientStatePending,

    OWSOutgoingMessageRecipientStateMin = OWSOutgoingMessageRecipientStateFailed,
    OWSOutgoingMessageRecipientStateMax = OWSOutgoingMessageRecipientStatePending,
};

NSString *NSStringForOutgoingMessageRecipientState(OWSOutgoingMessageRecipientState value);

typedef NS_ENUM(NSInteger, TSGroupMetaMessage) {
    TSGroupMetaMessageUnspecified,
    TSGroupMetaMessageNew,
    TSGroupMetaMessageUpdate,
    TSGroupMetaMessageDeliver,
    TSGroupMetaMessageQuit,
    TSGroupMetaMessageRequestInfo,
};

@protocol DeliveryReceiptContext;

@class SDSAnyWriteTransaction;
@class SSKProtoAttachmentPointer;
@class SSKProtoContentBuilder;
@class SSKProtoDataMessageBuilder;
@class SignalServiceAddress;
@class TSOutgoingMessageBuilder;

@interface TSOutgoingMessageRecipientState : MTLModel

@property (atomic, readonly) OWSOutgoingMessageRecipientState state;
// This property should only be set if state == .sent.
@property (atomic, nullable, readonly) NSNumber *deliveryTimestamp;
// This property should only be set if state == .sent.
@property (atomic, nullable, readonly) NSNumber *readTimestamp;
// This property should only be set if state == .sent.
@property (atomic, nullable, readonly) NSNumber *viewedTimestamp;
// This property should only be set if state == .failed or state == .sending (with a prior failure)
@property (atomic, nullable, readonly) NSNumber *errorCode;

@property (atomic, readonly) BOOL wasSentByUD;

@end

#pragma mark -

@interface TSOutgoingMessage : TSMessage

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

- (instancetype)initOutgoingMessageWithBuilder:(TSOutgoingMessageBuilder *)outgoingMessageBuilder
                                   transaction:(SDSAnyReadTransaction *)transaction NS_DESIGNATED_INITIALIZER
    NS_SWIFT_NAME(init(outgoingMessageWithBuilder:transaction:));

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
                groupMetaMessage:(TSGroupMetaMessage)groupMetaMessage
           hasLegacyMessageState:(BOOL)hasLegacyMessageState
             hasSyncedTranscript:(BOOL)hasSyncedTranscript
              isFromLinkedDevice:(BOOL)isFromLinkedDevice
                  isVoiceMessage:(BOOL)isVoiceMessage
              legacyMessageState:(TSOutgoingMessageState)legacyMessageState
              legacyWasDelivered:(BOOL)legacyWasDelivered
           mostRecentFailureText:(nullable NSString *)mostRecentFailureText
          recipientAddressStates:(nullable NSDictionary<SignalServiceAddress *,TSOutgoingMessageRecipientState *> *)recipientAddressStates
              storedMessageState:(TSOutgoingMessageState)storedMessageState
NS_DESIGNATED_INITIALIZER NS_SWIFT_NAME(init(grdbId:uniqueId:receivedAtTimestamp:sortId:timestamp:uniqueThreadId:attachmentIds:body:bodyRanges:contactShare:expireStartedAt:expiresAt:expiresInSeconds:giftBadge:isGroupStoryReply:isViewOnceComplete:isViewOnceMessage:linkPreview:messageSticker:quotedMessage:storedShouldStartExpireTimer:storyAuthorUuidString:storyReactionEmoji:storyTimestamp:wasRemotelyDeleted:customMessage:groupMetaMessage:hasLegacyMessageState:hasSyncedTranscript:isFromLinkedDevice:isVoiceMessage:legacyMessageState:legacyWasDelivered:mostRecentFailureText:recipientAddressStates:storedMessageState:));

// clang-format on

// --- CODE GENERATION MARKER

+ (instancetype)outgoingMessageInThread:(TSThread *)thread
                            messageBody:(nullable NSString *)body
                           attachmentId:(nullable NSString *)attachmentId;

+ (instancetype)outgoingMessageInThread:(TSThread *)thread
                            messageBody:(nullable NSString *)body
                           attachmentId:(nullable NSString *)attachmentId
                       expiresInSeconds:(uint32_t)expiresInSeconds;

+ (instancetype)outgoingMessageInThread:(TSThread *)thread
                            messageBody:(nullable NSString *)body
                           attachmentId:(nullable NSString *)attachmentId
                       expiresInSeconds:(uint32_t)expiresInSeconds
                          quotedMessage:(nullable TSQuotedMessage *)quotedMessage
                            linkPreview:(nullable OWSLinkPreview *)linkPreview
                         messageSticker:(nullable MessageSticker *)messageSticker;

- (void)removeTemporaryAttachmentsWithTransaction:(SDSAnyWriteTransaction *)transaction;

@property (nonatomic, readonly) TSOutgoingMessageState messageState;

@property (nonatomic, readonly) BOOL wasDeliveredToAnyRecipient;
@property (nonatomic, readonly) BOOL wasSentToAnyRecipient;

@property (atomic, readonly) BOOL hasSyncedTranscript;
@property (atomic, readonly, nullable) NSString *customMessage;
@property (atomic, readonly, nullable) NSString *mostRecentFailureText;

@property (atomic, readonly) TSGroupMetaMessage groupMetaMessage;

@property (nonatomic, readonly) BOOL isVoiceMessage;

// This property won't be accurate for legacy messages.
@property (atomic, readonly) BOOL isFromLinkedDevice;

@property (nonatomic, readonly) BOOL isOnline;

@property (nonatomic, readonly) BOOL isUrgent;

// NOTE: We do not persist this property; it is only used for
//       group updates which we don't insert into the database.
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

/**
 * Should this message be synced to the users other registered devices? This is
 * generally always true, except in the case of the sync messages themseleves
 * (so we don't end up in an infinite loop).
 */
- (BOOL)shouldSyncTranscript;

- (nullable OWSOutgoingSyncMessage *)buildTranscriptSyncMessageWithLocalThread:(TSThread *)localThread
                                                                   transaction:(SDSAnyWriteTransaction *)transaction
    NS_SWIFT_NAME(buildTranscriptSyncMessage(localThread:transaction:));

// All recipients of this message.
- (NSArray<SignalServiceAddress *> *)recipientAddresses;

// The states for all recipients.
@property (atomic, nullable, readonly)
    NSDictionary<SignalServiceAddress *, TSOutgoingMessageRecipientState *> *recipientAddressStates;

// All recipients of this message who we are currently trying to send to (pending, queued, uploading or during send).
- (NSArray<SignalServiceAddress *> *)sendingRecipientAddresses;

// All recipients of this message to whom it has been sent (and possibly delivered or read).
- (NSArray<SignalServiceAddress *> *)sentRecipientAddresses;

// All recipients of this message to whom it has been sent and delivered (and possibly read).
- (NSArray<SignalServiceAddress *> *)deliveredRecipientAddresses;

// All recipients of this message to whom it has been sent, delivered and read.
- (NSArray<SignalServiceAddress *> *)readRecipientAddresses;

// All recipients of this message to whom it has been sent, delivered and viewed.
- (NSArray<SignalServiceAddress *> *)viewedRecipientAddresses;

// Number of recipients of this message to whom it has been sent.
- (NSUInteger)sentRecipientsCount;

- (nullable TSOutgoingMessageRecipientState *)recipientStateForAddress:(SignalServiceAddress *)address;

#pragma mark - Update With... Methods

// This method is used to record a successful send to one recipient.
- (void)updateWithSentRecipient:(SignalServiceAddress *)recipientAddress
                    wasSentByUD:(BOOL)wasSentByUD
                    transaction:(SDSAnyWriteTransaction *)transaction;

// This method is used to record a skipped send to one recipient.
- (void)updateWithSkippedRecipient:(SignalServiceAddress *)recipientAddress
                       transaction:(SDSAnyWriteTransaction *)transaction;

// This method is used to record a failed send to one recipient.
- (void)updateWithFailedRecipient:(SignalServiceAddress *)recipientAddress
                            error:(NSError *)error
                      transaction:(SDSAnyWriteTransaction *)transaction;

// On app launch, all "sending" recipients should be marked as "failed".
- (void)updateWithAllSendingRecipientsMarkedAsFailedWithTransaction:(SDSAnyWriteTransaction *)transaction;

- (BOOL)hasFailedRecipients;

// When we start a message send, all "failed" recipients should be marked as "sending".
- (void)updateAllUnsentRecipientsAsSendingWithTransaction:(SDSAnyWriteTransaction *)transaction
    NS_SWIFT_NAME(updateAllUnsentRecipientsAsSending(transaction:));

// This method is used to forge the message state for fake messages.
//
// NOTE: This method should only be used by Debug UI, etc.
#ifdef TESTABLE_BUILD
- (void)updateWithFakeMessageState:(TSOutgoingMessageState)messageState
                       transaction:(SDSAnyWriteTransaction *)transaction;
#endif

// This method is used to record a failed send to all "sending" recipients.
- (void)updateWithSendingError:(NSError *)error
                   transaction:(SDSAnyWriteTransaction *)transaction NS_SWIFT_NAME(update(sendingError:transaction:));

- (void)updateWithHasSyncedTranscript:(BOOL)hasSyncedTranscript transaction:(SDSAnyWriteTransaction *)transaction;

// This method is used to record a successful delivery to one recipient.
- (void)updateWithDeliveredRecipient:(SignalServiceAddress *)recipientAddress
                   recipientDeviceId:(uint32_t)deviceId
                   deliveryTimestamp:(uint64_t)deliveryTimestamp
                             context:(id<DeliveryReceiptContext>)deliveryReceiptContext
                         transaction:(SDSAnyWriteTransaction *)transaction;

- (void)updateWithWasSentFromLinkedDeviceWithUDRecipientAddresses:
            (nullable NSArray<SignalServiceAddress *> *)udRecipientAddresses
                                          nonUdRecipientAddresses:
                                              (nullable NSArray<SignalServiceAddress *> *)nonUdRecipientAddresses
                                                     isSentUpdate:(BOOL)isSentUpdate
                                                      transaction:(SDSAnyWriteTransaction *)transaction;

// This method is used to rewrite the recipient list with a single recipient.
// It is used to reply to a "group info request", which should only be
// delivered to the requestor.
- (void)updateWithSendingToSingleGroupRecipient:(SignalServiceAddress *)singleGroupRecipient
                                    transaction:(SDSAnyWriteTransaction *)transaction;

// This method is used to record a successful "read" by one recipient.
- (void)updateWithReadRecipient:(SignalServiceAddress *)recipientAddress
              recipientDeviceId:(uint32_t)deviceId
                  readTimestamp:(uint64_t)readTimestamp
                    transaction:(SDSAnyWriteTransaction *)transaction;

- (void)updateWithViewedRecipient:(SignalServiceAddress *)recipientAddress
                recipientDeviceId:(uint32_t)deviceId
                  viewedTimestamp:(uint64_t)viewedTimestamp
                      transaction:(SDSAnyWriteTransaction *)transaction;

- (nullable NSNumber *)firstRecipientReadTimestamp;

- (void)updateWithRecipientAddressStates:
            (nullable NSDictionary<SignalServiceAddress *, TSOutgoingMessageRecipientState *> *)recipientAddressStates
                             transaction:(SDSAnyWriteTransaction *)transaction
    NS_SWIFT_NAME(updateWith(recipientAddressStates:transaction:));

- (NSString *)statusDescription;

@end

NS_ASSUME_NONNULL_END
