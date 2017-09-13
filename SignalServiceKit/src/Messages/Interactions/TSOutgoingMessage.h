//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "TSMessage.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, TSOutgoingMessageState) {
    // The message is either:
    // a) Enqueued for sending.
    // b) Waiting on attachment upload(s).
    // c) Being sent to the service.
    TSOutgoingMessageStateAttemptingOut,
    // The failure state.
    TSOutgoingMessageStateUnsent,
    // These two enum values have been combined into TSOutgoingMessageStateSentToService.
    TSOutgoingMessageStateSent_OBSOLETE,
    TSOutgoingMessageStateDelivered_OBSOLETE,
    // The message has been sent to the service.
    TSOutgoingMessageStateSentToService,
};

typedef NS_ENUM(NSInteger, TSGroupMetaMessage) {
    TSGroupMessageNone,
    TSGroupMessageNew,
    TSGroupMessageUpdate,
    TSGroupMessageDeliver,
    TSGroupMessageQuit,
    TSGroupMessageRequestInfo,
};

@class OWSSignalServiceProtosAttachmentPointer;
@class OWSSignalServiceProtosDataMessageBuilder;
@class OWSSignalServiceProtosContentBuilder;
@class SignalRecipient;

@interface TSOutgoingMessage : TSMessage

- (instancetype)initWithTimestamp:(uint64_t)timestamp;

- (instancetype)initWithTimestamp:(uint64_t)timestamp inThread:(nullable TSThread *)thread;

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(nullable TSThread *)thread
                      messageBody:(nullable NSString *)body;

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(nullable TSThread *)thread
                 groupMetaMessage:(TSGroupMetaMessage)groupMetaMessage;

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(nullable TSThread *)thread
                      messageBody:(nullable NSString *)body
                    attachmentIds:(NSMutableArray<NSString *> *)attachmentIds;

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(nullable TSThread *)thread
                      messageBody:(nullable NSString *)body
                    attachmentIds:(NSMutableArray<NSString *> *)attachmentIds
                 expiresInSeconds:(uint32_t)expiresInSeconds;

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(nullable TSThread *)thread
                   isVoiceMessage:(BOOL)isVoiceMessage
                 expiresInSeconds:(uint32_t)expiresInSeconds;

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(nullable TSThread *)thread
                      messageBody:(nullable NSString *)body
                    attachmentIds:(NSMutableArray<NSString *> *)attachmentIds
                 expiresInSeconds:(uint32_t)expiresInSeconds
                  expireStartedAt:(uint64_t)expireStartedAt;

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(nullable TSThread *)thread
                      messageBody:(nullable NSString *)body
                    attachmentIds:(NSMutableArray<NSString *> *)attachmentIds
                 expiresInSeconds:(uint32_t)expiresInSeconds
                  expireStartedAt:(uint64_t)expireStartedAt
                 groupMetaMessage:(TSGroupMetaMessage)groupMetaMessage NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

@property (atomic, readonly) TSOutgoingMessageState messageState;

// The message has been sent to the service and received by at least one recipient client.
// A recipient may have more than one client, and group message may have more than one recipient.
@property (atomic, readonly) BOOL wasDelivered;

@property (atomic, readonly) BOOL hasSyncedTranscript;
@property (atomic, readonly) NSString *customMessage;
@property (atomic, readonly) NSString *mostRecentFailureText;
// A map of attachment id-to-"source" filename.
@property (nonatomic, readonly) NSMutableDictionary<NSString *, NSString *> *attachmentFilenameMap;

@property (atomic, readonly) TSGroupMetaMessage groupMetaMessage;

// If set, this group message should only be sent to a single recipient.
@property (atomic, readonly) NSString *singleGroupRecipient;

@property (nonatomic, readonly) BOOL isVoiceMessage;

/**
 * Signal Identifier (e.g. e164 number) or nil if in a group thread.
 */
- (nullable NSString *)recipientIdentifier;

/**
 * The data representation of this message, to be encrypted, before being sent.
 */
- (NSData *)buildPlainTextData:(SignalRecipient *)recipient;

/**
 * Intermediate protobuf representation
 * Subclasses can augment if they want to manipulate the data message before building.
 */
- (OWSSignalServiceProtosDataMessageBuilder *)dataMessageBuilder;

/**
 * Should this message be synced to the users other registered devices? This is
 * generally always true, except in the case of the sync messages themseleves
 * (so we don't end up in an infinite loop).
 */
- (BOOL)shouldSyncTranscript;

/**
 * @param attachmentId
 *   id of an AttachmentStream containing the meta data used when populating the attachment proto
 *
 * @param filename
 *   optional filename of the attachment.
 *
 * @return
 *      An attachment pointer protobuf suitable for including in various container protobuf builders
 */
- (OWSSignalServiceProtosAttachmentPointer *)buildAttachmentProtoForAttachmentId:(NSString *)attachmentId
                                                                        filename:(nullable NSString *)filename;

// TSOutgoingMessage are updated from many threads. We don't want to save
// our local copy (this instance) since it may be out of date.  Instead, we
// use these "updateWith..." methods to:
//
// a) Update a property of this instance.
// b) Load an up-to-date instance of this model from from the data store.
// c) Update and save that fresh instance.
// d) If this message hasn't yet been saved, save this local instance.
//
// After "updateWith...":
//
// a) An updated copy of this message will always have been saved in the
//    data store.
// b) The local property on this instance will always have been updated.
// c) Other properties on this instance may be out of date.
//
// All mutable properties of this class have been made read-only to
// prevent accidentally modifying them directly.
//
// This isn't a perfect arrangement, but in practice this will prevent
// data loss and will resolve all known issues.
- (void)updateWithMessageState:(TSOutgoingMessageState)messageState;
- (void)updateWithMessageState:(TSOutgoingMessageState)messageState
                   transaction:(YapDatabaseReadWriteTransaction *)transaction;
- (void)updateWithSendingError:(NSError *)error;
- (void)updateWithHasSyncedTranscript:(BOOL)hasSyncedTranscript;
- (void)updateWithCustomMessage:(NSString *)customMessage transaction:(YapDatabaseReadWriteTransaction *)transaction;
- (void)updateWithCustomMessage:(NSString *)customMessage;
- (void)updateWithWasDeliveredWithTransaction:(YapDatabaseReadWriteTransaction *)transaction;
- (void)updateWithWasDelivered;
- (void)updateWithWasSentAndDeliveredWithTransaction:(YapDatabaseReadWriteTransaction *)transaction;
- (void)updateWithSingleGroupRecipient:(NSString *)singleGroupRecipient
                           transaction:(YapDatabaseReadWriteTransaction *)transaction;

#pragma mark - Sent Recipients

- (NSUInteger)sentRecipientsCount;
- (BOOL)wasSentToRecipient:(NSString *)contactId;
- (void)updateWithSentRecipient:(NSString *)contactId transaction:(YapDatabaseReadWriteTransaction *)transaction;
- (void)updateWithSentRecipient:(NSString *)contactId;

@end

NS_ASSUME_NONNULL_END
