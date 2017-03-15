//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "TSMessage.h"

NS_ASSUME_NONNULL_BEGIN

@class OWSSignalServiceProtosAttachmentPointer;
@class OWSSignalServiceProtosDataMessageBuilder;

@interface TSOutgoingMessage : TSMessage

typedef NS_ENUM(NSInteger, TSOutgoingMessageState) {
    // The message is either:
    // a) Enqueued for sending.
    // b) Waiting on attachment upload(s).
    // c) Being sent to the service.
    TSOutgoingMessageStateAttemptingOut,
    // The failure state.
    TSOutgoingMessageStateUnsent,
    // The message has been sent to the service, but not received by any recipient client.
    TSOutgoingMessageStateSent,
    // The message has been sent to the service and received by at least one recipient client.
    // A recipient may have more than one client, and group message may have more than one recipient.
    TSOutgoingMessageStateDelivered
};

- (instancetype)initWithTimestamp:(uint64_t)timestamp;
- (instancetype)initWithTimestamp:(uint64_t)timestamp inThread:(nullable TSThread *)thread;

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(nullable TSThread *)thread
                      messageBody:(nullable NSString *)body;

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
                      messageBody:(nullable NSString *)body
                    attachmentIds:(NSMutableArray<NSString *> *)attachmentIds
                 expiresInSeconds:(uint32_t)expiresInSeconds
                  expireStartedAt:(uint64_t)expireStartedAt NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

@property (nonatomic) TSOutgoingMessageState messageState;
@property BOOL hasSyncedTranscript;
@property NSString *customMessage;
@property (atomic, readonly) NSString *mostRecentFailureText;

/**
 * Whether the message should be serialized as a modern aka Content, or the old style legacy message.
 * Sync and Call messsages must be sent as Content, but other old style DataMessage payloads should be
 * sent as legacy message until we're confident no significant number of legacy clients exist in the wild.
 */
@property (nonatomic, readonly) BOOL isLegacyMessage;

- (void)setSendingError:(NSError *)error;

/**
 * Signal Identifier (e.g. e164 number) or nil if in a group thread.
 */
- (nullable NSString *)recipientIdentifier;

/**
 * The data representation of this message, to be encrypted, before being sent.
 */
- (NSData *)buildPlainTextData;

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
 * @return
 *      An attachment pointer protobuf suitable for including in various container protobuf builders
 */
- (OWSSignalServiceProtosAttachmentPointer *)buildAttachmentProtoForAttachmentId:(NSString *)attachmentId;

@end

NS_ASSUME_NONNULL_END
