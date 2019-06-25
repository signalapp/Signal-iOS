//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class OWSStorage;
@class SDSAnyReadTransaction;
@class TSMessage;
@class TSThread;

@interface OWSDisappearingMessagesFinder : NSObject

- (void)enumerateExpiredMessagesWithBlock:(void (^_Nonnull)(TSMessage *message))block
                              transaction:(SDSAnyReadTransaction *)transaction;

- (void)enumerateUnstartedExpiringMessagesInThread:(TSThread *)thread
                                             block:(void (^_Nonnull)(TSMessage *message))block
                                       transaction:(SDSAnyReadTransaction *)transaction;

- (void)enumerateMessagesWhichFailedToStartExpiringWithBlock:(void (^_Nonnull)(TSMessage *message))block
                                                 transaction:(SDSAnyReadTransaction *)transaction;

/**
 * @return
 *   uint64_t millisecond timestamp wrapped in a number. Retrieve with `unsignedLongLongvalue`.
 *   or nil if there are no upcoming expired messages
 */
- (nullable NSNumber *)nextExpirationTimestampWithTransaction:(SDSAnyReadTransaction *_Nonnull)transaction;

+ (NSString *)databaseExtensionName;

+ (void)asyncRegisterDatabaseExtensions:(OWSStorage *)storage;

#ifdef DEBUG
/**
 * Only use the sync version for testing, generally we'll want to register extensions async
 */
+ (void)blockingRegisterDatabaseExtensions:(OWSStorage *)storage;
#endif

@end

NS_ASSUME_NONNULL_END
