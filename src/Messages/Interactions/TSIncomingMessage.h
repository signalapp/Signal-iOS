//  Created by Frederic Jacobs on 15/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.

#import "TSMessage.h"

NS_ASSUME_NONNULL_BEGIN

@class TSContactThread;
@class TSGroupThread;

@interface TSIncomingMessage : TSMessage

/**
 *  Inits an incoming (non-group) message with no attachments.
 *
 *  @param timestamp
 *    When the message was created in milliseconds since epoch
 *  @param thread
 *    Thread to which the message belongs
 *  @param body
 *    Body of the message
 *  @param attachmentIds
 *    The uniqueIds for the message's attachments
 *
 *  @return initiated incoming message
 */
- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(nullable TSContactThread *)thread
                      messageBody:(nullable NSString *)body;

/**
 *  Inits an incoming (non-group) message with attachments.
 *
 *  @param timestamp
 *    When the message was created in milliseconds since epoch
 *  @param thread
 *    Thread to which the message belongs
 *  @param body
 *    Body of the message
 *  @param attachmentIds
 *    The uniqueIds for the message's attachments
 *
 *  @return initiated incoming message
 */
- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(nullable TSContactThread *)thread
                      messageBody:(nullable NSString *)body
                    attachmentIds:(NSArray<NSString *> *)attachmentIds;

/**
 *  Inits an incoming group message without attachments
 *
 *  @param timestamp
 *    When the message was created in milliseconds since epoch
 *  @param thread
 *    Thread to which the message belongs
 *  @param authorId
 *    Signal ID (i.e. e164) of the user who sent the message
 *  @param body
 *    Body of the message
 *
 *  @return initiated incoming group message
 */
- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(nullable TSGroupThread *)thread
                         authorId:(nullable NSString *)authorId
                      messageBody:(nullable NSString *)body;

/**
 *  Inits an incoming group message with attachments
 *
 *  @param timestamp
 *    When the message was created in milliseconds since epoch
 *  @param thread
 *    Thread to which the message belongs
 *  @param authorId
 *    Signal ID (i.e. e164) of the user who sent the message
 *  @param body
 *    Body of the message
 *  @param attachmentIds
 *    The uniqueIds for the message's attachments
 *
 *  @return initiated incoming group message
 */
- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(nullable TSGroupThread *)thread
                         authorId:(nullable NSString *)authorId
                      messageBody:(nullable NSString *)body
                    attachmentIds:(NSArray<NSString *> *)attachmentIds;

/*
 * Find a message matching the senderId and timestamp, if any.
 *
 * @param authorId
 *   Signal ID (i.e. e164) of the user who sent the message
 * @params timestamp
 *   When the message was created in milliseconds since epoch
 *
 */
+ (nullable instancetype)findMessageWithAuthorId:(NSString *)authorId timestamp:(uint64_t)timestamp;

@property (nonatomic, readonly) NSString *authorId;
@property (nonatomic, readonly, getter=wasRead) BOOL read;
@property (nonatomic, readonly) NSDate *receivedAt;

/*
 * Marks a message as having been read and broadcasts a TSIncomingMessageWasReadNotification
 */
- (void)markAsRead;
- (void)markAsReadWithTransaction:(YapDatabaseReadWriteTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
