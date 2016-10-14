//  Created by Frederic Jacobs on 12/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.

#import "TSInteraction.h"

NS_ASSUME_NONNULL_BEGIN

/**
 *  Abstract message class.
 */

@class TSAttachmentPointer;

typedef NS_ENUM(NSInteger, TSGroupMetaMessage) {
    TSGroupMessageNone,
    TSGroupMessageNew,
    TSGroupMessageUpdate,
    TSGroupMessageDeliver,
    TSGroupMessageQuit
};

@interface TSMessage : TSInteraction

@property (nonatomic, readonly) NSMutableArray<NSString *> *attachmentIds;
@property (nullable, nonatomic) NSString *body;
@property (nonatomic) TSGroupMetaMessage groupMetaMessage;
@property (nonatomic) uint32_t expiresInSeconds;
@property (nonatomic) uint64_t expireStartedAt;
@property (nonatomic, readonly) uint64_t expiresAt;
@property (nonatomic, readonly) BOOL isExpiringMessage;
@property (nonatomic, readonly) BOOL shouldStartExpireTimer;

- (instancetype)initWithTimestamp:(uint64_t)timestamp;

- (instancetype)initWithTimestamp:(uint64_t)timestamp inThread:(nullable TSThread *)thread;

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(nullable TSThread *)thread
                      messageBody:(nullable NSString *)body;

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(nullable TSThread *)thread
                      messageBody:(nullable NSString *)body
                    attachmentIds:(NSArray<NSString *> *)attachmentIds;

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(nullable TSThread *)thread
                      messageBody:(nullable NSString *)body
                    attachmentIds:(NSArray<NSString *> *)attachmentIds
                 expiresInSeconds:(uint32_t)expiresInSeconds;

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(nullable TSThread *)thread
                      messageBody:(nullable NSString *)body
                    attachmentIds:(NSArray<NSString *> *)attachmentIds
                 expiresInSeconds:(uint32_t)expiresInSeconds
                  expireStartedAt:(uint64_t)expireStartedAt NS_DESIGNATED_INITIALIZER;

- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

- (BOOL)hasAttachments;

@end

NS_ASSUME_NONNULL_END
