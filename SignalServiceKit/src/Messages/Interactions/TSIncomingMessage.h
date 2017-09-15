//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSReadTracking.h"
#import "TSMessage.h"

NS_ASSUME_NONNULL_BEGIN

@class TSContactThread;
@class TSGroupThread;

@interface TSIncomingMessage : TSMessage <OWSReadTracking>

/**
 *  Inits an incoming group message without attachments
 *
 *  @param timestamp
 *    When the message was created in milliseconds since epoch
 *  @param thread
 *    Thread to which the message belongs
 *  @param authorId
 *    Signal ID (i.e. e164) of the user who sent the message
 *  @param sourceDeviceId
 *    Numeric ID of the device used to send the message. Used to detect duplicate messages.
 *  @param body
 *    Body of the message
 *
 *  @return initiated incoming group message
 */
- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(TSThread *)thread
                         authorId:(NSString *)authorId
                   sourceDeviceId:(uint32_t)sourceDeviceId
                      messageBody:(nullable NSString *)body;

/**
 *  Inits an incoming group message that expires.
 *
 *  @param timestamp
 *    When the message was created in milliseconds since epoch
 *  @param thread
 *    Thread to which the message belongs
 *  @param authorId
 *    Signal ID (i.e. e164) of the user who sent the message
 *  @param sourceDeviceId
 *    Numeric ID of the device used to send the message. Used to detect duplicate messages.
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
                   sourceDeviceId:(uint32_t)sourceDeviceId
                      messageBody:(nullable NSString *)body
                    attachmentIds:(NSArray<NSString *> *)attachmentIds
                 expiresInSeconds:(uint32_t)expiresInSeconds NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;


/**
 * For sake of a smaller API, and simplifying assumptions elsewhere, you must specify an author id for *all* incoming
 * messages, even though we technically could infer the author id for a contact thread.
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
+ (nullable instancetype)findMessageWithAuthorId:(NSString *)authorId
                                       timestamp:(uint64_t)timestamp
                                     transaction:(YapDatabaseReadWriteTransaction *)transaction;

@property (nonatomic, readonly) NSString *authorId;

// This will be 0 for messages created before we were tracking sourceDeviceId
@property (nonatomic, readonly) UInt32 sourceDeviceId;

@end

NS_ASSUME_NONNULL_END
