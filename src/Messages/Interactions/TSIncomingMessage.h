//  Created by Frederic Jacobs on 15/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.

#import "TSMessage.h"

NS_ASSUME_NONNULL_BEGIN

@class TSContactThread;
@class TSGroupThread;

extern NSString *const TSIncomingMessageWasReadOnThisDeviceNotification;

@interface TSIncomingMessage : TSMessage

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
                         inThread:(TSThread *)thread
                         authorId:(NSString *)authorId
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
                         inThread:(TSThread *)thread
                         authorId:(NSString *)authorId
                      messageBody:(nullable NSString *)body
                    attachmentIds:(NSArray<NSString *> *)attachmentIds;

/**
 *  Inits an incoming group message that expires.
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
 *    The uniqueIds for the message's attachments, possibly an empty list.
 *  @param expiresInSeconds
 *    Seconds from when the message is read until it is deleted.
 *
 *  @return initiated incoming group message
 */
- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(TSThread *)thread
                         authorId:(NSString *)authorId
                      messageBody:(nullable NSString *)body
                    attachmentIds:(NSArray<NSString *> *)attachmentIds
                 expiresInSeconds:(uint32_t)expiresInSeconds NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;


/**
 * For sake of a smaller API, you must specify an author id for all incoming messages
 * though we technically could get the author id from a contact thread.
 */
- (instancetype)initWithTimestamp:(uint64_t)timestamp NS_UNAVAILABLE;
- (instancetype)initWithTimestamp:(uint64_t)timestamp inThread:(nullable TSThread *)thread NS_UNAVAILABLE;
- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(nullable TSThread *)thread
                      messageBody:(nullable NSString *)body NS_UNAVAILABLE;
- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(nullable TSThread *)thread
                      messageBody:(nullable NSString *)body
                    attachmentIds:(NSArray<NSString *> *)attachmentIds NS_UNAVAILABLE;
- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(nullable TSThread *)thread
                      messageBody:(nullable NSString *)body
                    attachmentIds:(NSArray<NSString *> *)attachmentIds
                 expiresInSeconds:(uint32_t)expiresInSeconds NS_UNAVAILABLE;
- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(nullable TSThread *)thread
                      messageBody:(nullable NSString *)body
                    attachmentIds:(NSArray<NSString *> *)attachmentIds
                 expiresInSeconds:(uint32_t)expiresInSeconds
                  expireStartedAt:(uint64_t)expireStartedAt NS_UNAVAILABLE;

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
 * Marks a message as having been read on this device (as opposed to responding to a remote read receipt).
 *
 */
- (void)markAsReadLocally;
// TODO possible to remove?
- (void)markAsReadLocallyWithTransaction:(YapDatabaseReadWriteTransaction *)transaction;

/**
 * Similar to markAsReadWithTransaction, but doesn't send out read receipts.
 * Used for *responding* to a remote read receipt.
 */
- (void)markAsReadFromReadReceipt;

@end

NS_ASSUME_NONNULL_END
