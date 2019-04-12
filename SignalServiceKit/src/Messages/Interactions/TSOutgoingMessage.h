//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "TSMessage.h"

NS_ASSUME_NONNULL_BEGIN

// Feature flag.
//
// TODO: Remove.
BOOL AreRecipientUpdatesEnabled(void);

typedef NS_ENUM(NSInteger, TSOutgoingMessageState) {
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
};

NSString *NSStringForOutgoingMessageState(TSOutgoingMessageState value);

typedef NS_ENUM(NSInteger, OWSOutgoingMessageRecipientState) {
    // Message could not be sent to recipient.
    OWSOutgoingMessageRecipientStateFailed = 0,
    // Message is being sent to the recipient (enqueued, uploading or sending).
    OWSOutgoingMessageRecipientStateSending,
    // The message was not sent because the recipient is not valid.
    // For example, this recipient may have left the group.
    OWSOutgoingMessageRecipientStateSkipped,
    // The message has been sent to the service.  It may also have been delivered or read.
    OWSOutgoingMessageRecipientStateSent,

    OWSOutgoingMessageRecipientStateMin = OWSOutgoingMessageRecipientStateFailed,
    OWSOutgoingMessageRecipientStateMax = OWSOutgoingMessageRecipientStateSent,
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

@class SSKProtoAttachmentPointer;
@class SSKProtoContentBuilder;
@class SSKProtoDataMessageBuilder;
@class SignalRecipient;

@interface TSOutgoingMessageRecipientState : MTLModel

@property (atomic, readonly) OWSOutgoingMessageRecipientState state;
// This property should only be set if state == .sent.
@property (atomic, nullable, readonly) NSNumber *deliveryTimestamp;
// This property should only be set if state == .sent.
@property (atomic, nullable, readonly) NSNumber *readTimestamp;

@property (atomic, readonly) BOOL wasSentByUD;

@end

#pragma mark -

@interface TSOutgoingMessage : TSMessage

- (instancetype)initMessageWithTimestamp:(uint64_t)timestamp
                                inThread:(nullable TSThread *)thread
                             messageBody:(nullable NSString *)body
                           attachmentIds:(NSArray<NSString *> *)attachmentIds
                        expiresInSeconds:(uint32_t)expiresInSeconds
                         expireStartedAt:(uint64_t)expireStartedAt
                           quotedMessage:(nullable TSQuotedMessage *)quotedMessage
                            contactShare:(nullable OWSContact *)contactShare
                             linkPreview:(nullable OWSLinkPreview *)linkPreview NS_UNAVAILABLE;

// MJK TODO - Can we remove the sender timestamp param?
- (instancetype)initOutgoingMessageWithTimestamp:(uint64_t)timestamp
                                        inThread:(nullable TSThread *)thread
                                     messageBody:(nullable NSString *)body
                                   attachmentIds:(NSMutableArray<NSString *> *)attachmentIds
                                expiresInSeconds:(uint32_t)expiresInSeconds
                                 expireStartedAt:(uint64_t)expireStartedAt
                                  isVoiceMessage:(BOOL)isVoiceMessage
                                groupMetaMessage:(TSGroupMetaMessage)groupMetaMessage
                                   quotedMessage:(nullable TSQuotedMessage *)quotedMessage
                                    contactShare:(nullable OWSContact *)contactShare
                                     linkPreview:(nullable OWSLinkPreview *)linkPreview NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithUniqueId:(NSString *)uniqueId
             receivedAtTimestamp:(unsigned long long)receivedAtTimestamp
                          sortId:(unsigned long long)sortId
                       timestamp:(unsigned long long)timestamp
                  uniqueThreadId:(NSString *)uniqueThreadId
                   attachmentIds:(NSArray<NSString *> *)attachmentIds
                            body:(nullable NSString *)body
                    contactShare:(nullable OWSContact *)contactShare
                 expireStartedAt:(unsigned long long)expireStartedAt
                       expiresAt:(unsigned long long)expiresAt
                expiresInSeconds:(unsigned int)expiresInSeconds
                     linkPreview:(nullable OWSLinkPreview *)linkPreview
                   quotedMessage:(nullable TSQuotedMessage *)quotedMessage
                   schemaVersion:(NSUInteger)schemaVersion
           attachmentFilenameMap:(NSDictionary<NSString *, NSString *> *)attachmentFilenameMap
                   customMessage:(NSString *)customMessage
                groupMetaMessage:(enum TSGroupMetaMessage)groupMetaMessage
           hasLegacyMessageState:(BOOL)hasLegacyMessageState
             hasSyncedTranscript:(BOOL)hasSyncedTranscript
              isFromLinkedDevice:(BOOL)isFromLinkedDevice
                  isVoiceMessage:(BOOL)isVoiceMessage
              legacyMessageState:(enum TSOutgoingMessageState)legacyMessageState
              legacyWasDelivered:(BOOL)legacyWasDelivered
           mostRecentFailureText:(NSString *)mostRecentFailureText
               recipientStateMap:
                   (nullable NSDictionary<NSString *, TSOutgoingMessageRecipientState *> *)recipientStateMap
    NS_DESIGNATED_INITIALIZER NS_SWIFT_NAME(init(uniqueId:receivedAtTimestamp:sortId:timestamp:uniqueThreadId:attachmentIds:body:contactShare:expireStartedAt:expiresAt:expiresInSeconds:linkPreview:quotedMessage:schemaVersion:attachmentFilenameMap:customMessage:groupMetaMessage:hasLegacyMessageState:hasSyncedTranscript:isFromLinkedDevice:isVoiceMessage:legacyMessageState:legacyWasDelivered:mostRecentFailureText:recipientStateMap:));

- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

+ (instancetype)outgoingMessageInThread:(nullable TSThread *)thread
                            messageBody:(nullable NSString *)body
                           attachmentId:(nullable NSString *)attachmentId;

+ (instancetype)outgoingMessageInThread:(nullable TSThread *)thread
                            messageBody:(nullable NSString *)body
                           attachmentId:(nullable NSString *)attachmentId
                       expiresInSeconds:(uint32_t)expiresInSeconds;

+ (instancetype)outgoingMessageInThread:(nullable TSThread *)thread
                            messageBody:(nullable NSString *)body
                           attachmentId:(nullable NSString *)attachmentId
                       expiresInSeconds:(uint32_t)expiresInSeconds
                          quotedMessage:(nullable TSQuotedMessage *)quotedMessage
                            linkPreview:(nullable OWSLinkPreview *)linkPreview;

+ (instancetype)outgoingMessageInThread:(nullable TSThread *)thread
                       groupMetaMessage:(TSGroupMetaMessage)groupMetaMessage
                       expiresInSeconds:(uint32_t)expiresInSeconds;

@property (readonly) TSOutgoingMessageState messageState;
@property (readonly) BOOL wasDeliveredToAnyRecipient;
@property (readonly) BOOL wasSentToAnyRecipient;

@property (atomic, readonly) BOOL hasSyncedTranscript;
@property (atomic, readonly) NSString *customMessage;
@property (atomic, readonly) NSString *mostRecentFailureText;
// A map of attachment id-to-"source" filename.
@property (nonatomic, readonly) NSMutableDictionary<NSString *, NSString *> *attachmentFilenameMap;

@property (atomic, readonly) TSGroupMetaMessage groupMetaMessage;

@property (nonatomic, readonly) BOOL isVoiceMessage;

// This property won't be accurate for legacy messages.
@property (atomic, readonly) BOOL isFromLinkedDevice;

@property (nonatomic, readonly) BOOL isSilent;

@property (nonatomic, readonly) BOOL isOnline;

/**
 * The data representation of this message, to be encrypted, before being sent.
 */
- (nullable NSData *)buildPlainTextData:(SignalRecipient *)recipient;

/**
 * Intermediate protobuf representation
 * Subclasses can augment if they want to manipulate the data message before building.
 */
- (nullable SSKProtoDataMessageBuilder *)dataMessageBuilder;

/**
 * Should this message be synced to the users other registered devices? This is
 * generally always true, except in the case of the sync messages themseleves
 * (so we don't end up in an infinite loop).
 */
- (BOOL)shouldSyncTranscript;

- (BOOL)shouldBeSaved;

// All recipients of this message.
- (NSArray<NSString *> *)recipientIds;

// All recipients of this message who we are currently trying to send to (queued, uploading or during send).
- (NSArray<NSString *> *)sendingRecipientIds;

// All recipients of this message to whom it has been sent (and possibly delivered or read).
- (NSArray<NSString *> *)sentRecipientIds;

// All recipients of this message to whom it has been sent and delivered (and possibly read).
- (NSArray<NSString *> *)deliveredRecipientIds;

// All recipients of this message to whom it has been sent, delivered and read.
- (NSArray<NSString *> *)readRecipientIds;

// Number of recipients of this message to whom it has been sent.
- (NSUInteger)sentRecipientsCount;

- (nullable TSOutgoingMessageRecipientState *)recipientStateForRecipientId:(NSString *)recipientId;

#pragma mark - Update With... Methods

// This method is used to record a successful send to one recipient.
- (void)updateWithSentRecipient:(NSString *)recipientId
                    wasSentByUD:(BOOL)wasSentByUD
                    transaction:(YapDatabaseReadWriteTransaction *)transaction;

// This method is used to record a skipped send to one recipient.
- (void)updateWithSkippedRecipient:(NSString *)recipientId transaction:(YapDatabaseReadWriteTransaction *)transaction;

// On app launch, all "sending" recipients should be marked as "failed".
- (void)updateWithAllSendingRecipientsMarkedAsFailedWithTansaction:(YapDatabaseReadWriteTransaction *)transaction;

// When we start a message send, all "failed" recipients should be marked as "sending".
- (void)updateWithMarkingAllUnsentRecipientsAsSendingWithTransaction:(YapDatabaseReadWriteTransaction *)transaction;

// This method is used to forge the message state for fake messages.
//
// NOTE: This method should only be used by Debug UI, etc.
- (void)updateWithFakeMessageState:(TSOutgoingMessageState)messageState
                       transaction:(YapDatabaseReadWriteTransaction *)transaction;

// This method is used to record a failed send to all "sending" recipients.
- (void)updateWithSendingError:(NSError *)error
                   transaction:(YapDatabaseReadWriteTransaction *)transaction
    NS_SWIFT_NAME(update(sendingError:transaction:));

- (void)updateWithHasSyncedTranscript:(BOOL)hasSyncedTranscript
                          transaction:(YapDatabaseReadWriteTransaction *)transaction;
- (void)updateWithCustomMessage:(NSString *)customMessage transaction:(YapDatabaseReadWriteTransaction *)transaction;
- (void)updateWithCustomMessage:(NSString *)customMessage;

// This method is used to record a successful delivery to one recipient.
//
// deliveryTimestamp is an optional parameter, since legacy
// delivery receipts don't have a "delivery timestamp".  Those
// messages repurpose the "timestamp" field to indicate when the
// corresponding message was originally sent.
- (void)updateWithDeliveredRecipient:(NSString *)recipientId
                   deliveryTimestamp:(NSNumber *_Nullable)deliveryTimestamp
                         transaction:(YapDatabaseReadWriteTransaction *)transaction;

- (void)updateWithWasSentFromLinkedDeviceWithUDRecipientIds:(nullable NSArray<NSString *> *)udRecipientIds
                                          nonUdRecipientIds:(nullable NSArray<NSString *> *)nonUdRecipientIds
                                               isSentUpdate:(BOOL)isSentUpdate
                                                transaction:(YapDatabaseReadWriteTransaction *)transaction;

// This method is used to rewrite the recipient list with a single recipient.
// It is used to reply to a "group info request", which should only be
// delivered to the requestor.
- (void)updateWithSendingToSingleGroupRecipient:(NSString *)singleGroupRecipient
                                    transaction:(YapDatabaseReadWriteTransaction *)transaction;

// This method is used to record a successful "read" by one recipient.
- (void)updateWithReadRecipientId:(NSString *)recipientId
                    readTimestamp:(uint64_t)readTimestamp
                      transaction:(YapDatabaseReadWriteTransaction *)transaction;

- (nullable NSNumber *)firstRecipientReadTimestamp;

- (NSString *)statusDescription;

@end

NS_ASSUME_NONNULL_END
