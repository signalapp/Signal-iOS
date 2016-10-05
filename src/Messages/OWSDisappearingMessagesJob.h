//  Created by Michael Kirk on 9/23/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

NS_ASSUME_NONNULL_BEGIN

@class TSStorageManager;
@class TSMessage;
@class TSThread;

@interface OWSDisappearingMessagesJob : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithStorageManager:(TSStorageManager *)storageManager NS_DESIGNATED_INITIALIZER;

- (void)run;
- (void)setExpirationsForThread:(TSThread *)thread;
- (void)setExpirationForMessage:(TSMessage *)message;
- (void)setExpirationForMessage:(TSMessage *)message expirationStartedAt:(uint64_t)expirationStartedAt;
- (void)runBy:(uint64_t)millisecondTimestamp;

@end

NS_ASSUME_NONNULL_END
