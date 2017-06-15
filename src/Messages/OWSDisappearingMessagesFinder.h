//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class TSStorageManager;
@class TSMessage;
@class TSThread;
@class YapDatabaseReadTransaction;

@interface OWSDisappearingMessagesFinder : NSObject

- (void)enumerateExpiredMessagesWithBlock:(void (^_Nonnull)(TSMessage *message))block
                              transaction:(YapDatabaseReadTransaction *)transaction;
- (void)enumerateUnstartedExpiringMessagesInThread:(TSThread *)thread
                                             block:(void (^_Nonnull)(TSMessage *message))block
                                       transaction:(YapDatabaseReadTransaction *)transaction;

/**
 * @return
 *   uint64_t millisecond timestamp wrapped in a number. Retrieve with `unsignedLongLongvalue`.
 *   or nil if there are no upcoming expired messages
 */
- (nullable NSNumber *)nextExpirationTimestampWithTransaction:(YapDatabaseReadTransaction *_Nonnull)transaction;

/**
 * Database extensions required for class to work.
 */
+ (void)asyncRegisterDatabaseExtensions:(TSStorageManager *)storageManager;

/**
 * Only use the sync version for testing, generally we'll want to register extensions async
 */
+ (void)blockingRegisterDatabaseExtensions:(TSStorageManager *)storageManager;

@end

NS_ASSUME_NONNULL_END
