//  Created by Michael Kirk on 9/23/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

NS_ASSUME_NONNULL_BEGIN

@class TSStorageManager;
@class TSMessage;
@class TSThread;

@interface OWSDisappearingMessagesFinder : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithStorageManager:(TSStorageManager *)storageManager NS_DESIGNATED_INITIALIZER;

+ (instancetype)defaultInstance;

- (void)enumerateExpiredMessagesWithBlock:(void (^_Nonnull)(TSMessage *message))block;
- (void)enumerateUnstartedExpiringMessagesInThread:(TSThread *)thread block:(void (^_Nonnull)(TSMessage *message))block;

/**
 * @return
 *   uint64_t millisecond timestamp wrapped in a number. Retrieve with `unsignedLongLongvalue`.
 *   or nil if there are no upcoming expired messages
 */
- (nullable NSNumber *)nextExpirationTimestamp;

/**
 * Database extensions required for class to work.
 */
- (void)asyncRegisterDatabaseExtensions;

/**
 * Only use the sync version for testing, generally we'll want to register extensions async
 */
- (void)blockingRegisterDatabaseExtensions;

@end

NS_ASSUME_NONNULL_END
