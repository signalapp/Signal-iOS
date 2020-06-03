//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class OWSStorage;
@class SDSAnyReadTransaction;
@class TSMessage;
@class TSThread;
@class YapDatabaseReadTransaction;

@interface OWSDisappearingMessagesFinder : NSObject

- (void)enumerateExpiredMessagesWithBlock:(void (^_Nonnull)(TSMessage *message))block
                              transaction:(SDSAnyReadTransaction *)transaction;

+ (void)ydb_enumerateMessagesWhichFailedToStartExpiringWithBlock:(void (^_Nonnull)(TSMessage *message, BOOL *stop))block
                                                     transaction:(YapDatabaseReadTransaction *)transaction;

- (void)enumerateMessagesWhichFailedToStartExpiringWithBlock:(void (^_Nonnull)(TSMessage *message, BOOL *stop))block
                                                 transaction:(SDSAnyReadTransaction *)transaction;

/**
 * @return
 *   uint64_t millisecond timestamp wrapped in a number. Retrieve with `unsignedLongLongvalue`.
 *   or nil if there are no upcoming expired messages
 */
- (nullable NSNumber *)nextExpirationTimestampWithTransaction:(SDSAnyReadTransaction *_Nonnull)transaction;

+ (void)ydb_enumerateMessagesWithStartedPerConversationExpirationWithBlock:(void (^_Nonnull)(
                                                                               TSMessage *message, BOOL *stop))block
                                                               transaction:(YapDatabaseReadTransaction *)transaction;

+ (NSArray<NSString *> *)ydb_interactionIdsWithExpiredPerConversationExpirationWithTransaction:
    (YapDatabaseReadTransaction *)transaction;

#ifdef DEBUG
+ (void)ydb_enumerateUnstartedExpiringMessagesWithThreadId:(NSString *)threadId
                                                     block:(void (^_Nonnull)(TSMessage *message, BOOL *stop))block
                                               transaction:(YapDatabaseReadTransaction *)transaction;
#endif

+ (NSString *)databaseExtensionName;

+ (void)asyncRegisterDatabaseExtensions:(OWSStorage *)storage;

@end

NS_ASSUME_NONNULL_END
