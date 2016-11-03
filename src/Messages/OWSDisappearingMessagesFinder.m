//  Created by Michael Kirk on 9/23/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSDisappearingMessagesFinder.h"
#import "NSDate+millisecondTimeStamp.h"
#import "TSMessage.h"
#import "TSOutgoingMessage.h"
#import "TSStorageManager.h"
#import "TSThread.h"
#import <YapDatabase/YapDatabaseConnection.h>
#import <YapDatabase/YapDatabaseQuery.h>
#import <YapDatabase/YapDatabaseSecondaryIndex.h>

NS_ASSUME_NONNULL_BEGIN

static NSString *const OWSDisappearingMessageFinderThreadIdColumn = @"thread_id";
static NSString *const OWSDisappearingMessageFinderExpiresAtColumn = @"expires_at";
static NSString *const OWSDisappearingMessageFinderExpiresAtIndex = @"index_messages_on_expires_at_and_thread_id_v2";

@interface OWSDisappearingMessagesFinder ()

@property (nonatomic, readonly) TSStorageManager *storageManager;
@property (nonatomic, readonly) YapDatabaseConnection *dbConnection;

@end

@implementation OWSDisappearingMessagesFinder

- (instancetype)initWithStorageManager:(TSStorageManager *)storageManager
{
    self = [super init];
    if (!self) {
        return self;
    }

    _storageManager = storageManager;
    _dbConnection = [storageManager newDatabaseConnection];

    return self;
}

+ (instancetype)defaultInstance
{
    static OWSDisappearingMessagesFinder *defaultInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        defaultInstance = [[self alloc] initWithStorageManager:[TSStorageManager sharedManager]];
    });
    return defaultInstance;
}

- (NSArray<NSString *> *)fetchUnstartedExpiringMessageIdsInThread:(TSThread *)thread
{
    NSMutableArray<NSString *> *messageIds = [NSMutableArray new];
    NSString *formattedString = [NSString stringWithFormat:@"WHERE %@ = 0 AND %@ = \"%@\"",
                                          OWSDisappearingMessageFinderExpiresAtColumn,
                                          OWSDisappearingMessageFinderThreadIdColumn,
                                          thread.uniqueId];

    YapDatabaseQuery *query = [YapDatabaseQuery queryWithFormat:formattedString];
    [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
        [[transaction ext:OWSDisappearingMessageFinderExpiresAtIndex]
            enumerateKeysMatchingQuery:query
                            usingBlock:^void(NSString *collection, NSString *key, BOOL *stop) {
                                [messageIds addObject:key];
                            }];
    }];

    return [messageIds copy];
}

- (NSArray<NSString *> *)fetchExpiredMessageIds
{
    NSMutableArray<NSString *> *messageIds = [NSMutableArray new];

    uint64_t now = [NSDate ows_millisecondTimeStamp];
    // When (expiresAt == 0) the message SHOULD NOT expire. Careful ;)
    NSString *formattedString = [NSString stringWithFormat:@"WHERE %@ > 0 AND %@ <= %lld",
                                          OWSDisappearingMessageFinderExpiresAtColumn,
                                          OWSDisappearingMessageFinderExpiresAtColumn,
                                          now];
    YapDatabaseQuery *query = [YapDatabaseQuery queryWithFormat:formattedString];
    [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
        [[transaction ext:OWSDisappearingMessageFinderExpiresAtIndex]
            enumerateKeysMatchingQuery:query
                            usingBlock:^void(NSString *collection, NSString *key, BOOL *stop) {
                                [messageIds addObject:key];
                            }];
    }];

    return [messageIds copy];
}

- (nullable NSNumber *)nextExpirationTimestamp
{
    NSString *formattedString = [NSString stringWithFormat:@"WHERE %@ > 0 ORDER BY %@ ASC",
                                          OWSDisappearingMessageFinderExpiresAtColumn,
                                          OWSDisappearingMessageFinderExpiresAtColumn];
    YapDatabaseQuery *query = [YapDatabaseQuery queryWithFormat:formattedString];

    __block TSMessage *firstMessage;
    [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
        [[transaction ext:OWSDisappearingMessageFinderExpiresAtIndex]
            enumerateKeysAndObjectsMatchingQuery:query
                                      usingBlock:^void(NSString *collection, NSString *key, id object, BOOL *stop) {
                                          firstMessage = (TSMessage *)object;
                                          *stop = YES;
                                      }];
    }];

    if (firstMessage && firstMessage.expiresAt > 0) {
        return [NSNumber numberWithUnsignedLongLong:firstMessage.expiresAt];
    }

    return nil;
}

- (void)enumerateUnstartedExpiringMessagesInThread:(TSThread *)thread block:(void (^_Nonnull)(TSMessage *message))block
{
    for (NSString *expiringMessageId in [self fetchUnstartedExpiringMessageIdsInThread:thread]) {
        TSMessage *_Nullable message = [TSMessage fetchObjectWithUniqueID:expiringMessageId];
        if ([message isKindOfClass:[TSMessage class]]) {
            block(message);
        } else {
            DDLogError(@"%@ unexpected object: %@", self.tag, message);
        }
    }
}

/**
 * Don't use this in production. Useful for testing.
 * We don't want to instantiate potentially many messages at once.
 */
- (NSArray<TSMessage *> *)fetchUnstartedExpiringMessagesInThread:(TSThread *)thread
{
    NSMutableArray<TSMessage *> *messages = [NSMutableArray new];
    [self enumerateUnstartedExpiringMessagesInThread:thread
                                               block:^(TSMessage *_Nonnull message) {
                                                   [messages addObject:message];
                                               }];

    return [messages copy];
}


- (void)enumerateExpiredMessagesWithBlock:(void (^_Nonnull)(TSMessage *message))block
{
    // Since we can't directly mutate the enumerated expired messages, we store only their ids in hopes of saving a
    // little memory and then enumerate the (larger) TSMessage objects one at a time.
    for (NSString *expiredMessageId in [self fetchExpiredMessageIds]) {
        TSMessage *_Nullable message = [TSMessage fetchObjectWithUniqueID:expiredMessageId];
        if ([message isKindOfClass:[TSMessage class]]) {
            block(message);
        } else {
            DDLogError(@"%@ unexpected object: %@", self.tag, message);
        }
    }
}

/**
 * Don't use this in production. Useful for testing.
 * We don't want to instantiate potentially many messages at once.
 */
- (NSArray<TSMessage *> *)fetchExpiredMessages
{
    NSMutableArray<TSMessage *> *messages = [NSMutableArray new];
    [self enumerateExpiredMessagesWithBlock:^(TSMessage *_Nonnull message) {
        [messages addObject:message];
    }];

    return [messages copy];
}

#pragma mark - YapDatabaseExtension

- (YapDatabaseSecondaryIndex *)indexDatabaseExtension
{
    YapDatabaseSecondaryIndexSetup *setup = [YapDatabaseSecondaryIndexSetup new];
    [setup addColumn:OWSDisappearingMessageFinderExpiresAtColumn withType:YapDatabaseSecondaryIndexTypeInteger];
    [setup addColumn:OWSDisappearingMessageFinderThreadIdColumn withType:YapDatabaseSecondaryIndexTypeText];

    YapDatabaseSecondaryIndexHandler *handler =
        [YapDatabaseSecondaryIndexHandler withObjectBlock:^(YapDatabaseReadTransaction *transaction,
            NSMutableDictionary *dict,
            NSString *collection,
            NSString *key,
            id object) {
            if (![object isKindOfClass:[TSMessage class]]) {
                return;
            }
            TSMessage *message = (TSMessage *)object;

            if (!message.shouldStartExpireTimer) {
                return;
            }

            dict[OWSDisappearingMessageFinderExpiresAtColumn] = @(message.expiresAt);
            dict[OWSDisappearingMessageFinderThreadIdColumn] = message.uniqueThreadId;
        }];

    return [[YapDatabaseSecondaryIndex alloc] initWithSetup:setup handler:handler];
}

// Useful for tests, don't use in app startup path because it's slow.
- (void)blockingRegisterDatabaseExtensions
{
    [self.storageManager.database registerExtension:[self indexDatabaseExtension]
                                           withName:OWSDisappearingMessageFinderExpiresAtIndex];
}

- (void)asyncRegisterDatabaseExtensions
{
    [self.storageManager.database asyncRegisterExtension:[self indexDatabaseExtension]
                                                withName:OWSDisappearingMessageFinderExpiresAtIndex
                                         completionBlock:^(BOOL ready) {
                                             if (ready) {
                                                 DDLogDebug(@"%@ completed registering extension async.", self.tag);
                                             } else {
                                                 DDLogError(@"%@ failed registering extension async.", self.tag);
                                             }
                                         }];
}

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end

NS_ASSUME_NONNULL_END
