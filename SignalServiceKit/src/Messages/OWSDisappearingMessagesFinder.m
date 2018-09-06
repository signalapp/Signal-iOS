//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSDisappearingMessagesFinder.h"
#import "NSDate+OWS.h"
#import "OWSPrimaryStorage.h"
#import "TSIncomingMessage.h"
#import "TSMessage.h"
#import "TSOutgoingMessage.h"
#import "TSThread.h"
#import <YapDatabase/YapDatabase.h>
#import <YapDatabase/YapDatabaseQuery.h>
#import <YapDatabase/YapDatabaseSecondaryIndex.h>

NS_ASSUME_NONNULL_BEGIN

static NSString *const OWSDisappearingMessageFinderThreadIdColumn = @"thread_id";
static NSString *const OWSDisappearingMessageFinderExpiresAtColumn = @"expires_at";
static NSString *const OWSDisappearingMessageFinderExpiresAtIndex = @"index_messages_on_expires_at_and_thread_id_v2";

@implementation OWSDisappearingMessagesFinder

- (NSArray<NSString *> *)fetchUnstartedExpiringMessageIdsInThread:(TSThread *)thread
                                                      transaction:(YapDatabaseReadTransaction *_Nonnull)transaction
{
    OWSAssertDebug(transaction);

    NSMutableArray<NSString *> *messageIds = [NSMutableArray new];
    NSString *formattedString = [NSString stringWithFormat:@"WHERE %@ = 0 AND %@ = \"%@\"",
                                          OWSDisappearingMessageFinderExpiresAtColumn,
                                          OWSDisappearingMessageFinderThreadIdColumn,
                                          thread.uniqueId];

    YapDatabaseQuery *query = [YapDatabaseQuery queryWithFormat:formattedString];
    [[transaction ext:OWSDisappearingMessageFinderExpiresAtIndex]
        enumerateKeysMatchingQuery:query
                        usingBlock:^void(NSString *collection, NSString *key, BOOL *stop) {
                            [messageIds addObject:key];
                        }];

    return [messageIds copy];
}

- (NSArray<NSString *> *)fetchMessageIdsWhichFailedToStartExpiring:(YapDatabaseReadTransaction *_Nonnull)transaction
{
    OWSAssertDebug(transaction);

    NSMutableArray<NSString *> *messageIds = [NSMutableArray new];
    NSString *formattedString =
        [NSString stringWithFormat:@"WHERE %@ = 0", OWSDisappearingMessageFinderExpiresAtColumn];

    YapDatabaseQuery *query = [YapDatabaseQuery queryWithFormat:formattedString];
    [[transaction ext:OWSDisappearingMessageFinderExpiresAtIndex]
        enumerateKeysAndObjectsMatchingQuery:query
                                  usingBlock:^void(NSString *collection, NSString *key, id object, BOOL *stop) {
                                      if (![object isKindOfClass:[TSMessage class]]) {
                                          OWSFailDebug(@"Object was unexpected class: %@", [object class]);
                                          return;
                                      }
                                      
                                      // We'll need to update if we ever support expiring other message types
                                      OWSAssertDebug([object isKindOfClass:[TSOutgoingMessage class]] || [object isKindOfClass:[TSIncomingMessage class]]);
                                      
                                      TSMessage *message = (TSMessage *)object;
                                      if ([message shouldStartExpireTimerWithTransaction:transaction]) {
                                          if ([message isKindOfClass:[TSIncomingMessage class]]) {
                                              TSIncomingMessage *incomingMessage = (TSIncomingMessage *)message;
                                              if (!incomingMessage.wasRead) {
                                                  return;
                                              }
                                          }
                                          [messageIds addObject:key];
                                      }
                                  }];

    return [messageIds copy];
}

- (NSArray<NSString *> *)fetchExpiredMessageIdsWithTransaction:(YapDatabaseReadTransaction *_Nonnull)transaction
{
    OWSAssertDebug(transaction);

    NSMutableArray<NSString *> *messageIds = [NSMutableArray new];

    uint64_t now = [NSDate ows_millisecondTimeStamp];
    // When (expiresAt == 0) the message SHOULD NOT expire. Careful ;)
    NSString *formattedString = [NSString stringWithFormat:@"WHERE %@ > 0 AND %@ <= %lld",
                                          OWSDisappearingMessageFinderExpiresAtColumn,
                                          OWSDisappearingMessageFinderExpiresAtColumn,
                                          now];
    YapDatabaseQuery *query = [YapDatabaseQuery queryWithFormat:formattedString];
    [[transaction ext:OWSDisappearingMessageFinderExpiresAtIndex]
        enumerateKeysMatchingQuery:query
                        usingBlock:^void(NSString *collection, NSString *key, BOOL *stop) {
                            [messageIds addObject:key];
                        }];

    return [messageIds copy];
}

- (nullable NSNumber *)nextExpirationTimestampWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    OWSAssertDebug(transaction);

    NSString *formattedString = [NSString stringWithFormat:@"WHERE %@ > 0 ORDER BY %@ ASC",
                                          OWSDisappearingMessageFinderExpiresAtColumn,
                                          OWSDisappearingMessageFinderExpiresAtColumn];
    YapDatabaseQuery *query = [YapDatabaseQuery queryWithFormat:formattedString];

    __block TSMessage *firstMessage;
    [[transaction ext:OWSDisappearingMessageFinderExpiresAtIndex]
        enumerateKeysAndObjectsMatchingQuery:query
                                  usingBlock:^void(NSString *collection, NSString *key, id object, BOOL *stop) {
                                      firstMessage = (TSMessage *)object;
                                      *stop = YES;
                                  }];

    if (firstMessage && firstMessage.expiresAt > 0) {
        return [NSNumber numberWithUnsignedLongLong:firstMessage.expiresAt];
    }

    return nil;
}

- (void)enumerateUnstartedExpiringMessagesInThread:(TSThread *)thread
                                             block:(void (^_Nonnull)(TSMessage *message))block
                                       transaction:(YapDatabaseReadTransaction *)transaction
{
    OWSAssertDebug(transaction);

    for (NSString *expiringMessageId in
        [self fetchUnstartedExpiringMessageIdsInThread:thread transaction:transaction]) {
        TSMessage *_Nullable message = [TSMessage fetchObjectWithUniqueID:expiringMessageId transaction:transaction];
        if ([message isKindOfClass:[TSMessage class]]) {
            block(message);
        } else {
            OWSFailDebug(@"unexpected object: %@", [message class]);
        }
    }
}

- (void)enumerateMessagesWhichFailedToStartExpiringWithBlock:(void (^_Nonnull)(TSMessage *message))block
                                                 transaction:(YapDatabaseReadTransaction *)transaction
{
    OWSAssertDebug(transaction);

    for (NSString *expiringMessageId in [self fetchMessageIdsWhichFailedToStartExpiring:transaction]) {

        TSMessage *_Nullable message = [TSMessage fetchObjectWithUniqueID:expiringMessageId transaction:transaction];
        if (![message isKindOfClass:[TSMessage class]]) {
            OWSFailDebug(@"unexpected object: %@", [message class]);
            continue;
        }

        if (![message shouldStartExpireTimerWithTransaction:transaction]) {
            OWSFailDebug(@"object: %@ shouldn't expire.", message);
            continue;
        }

        block(message);
    }
}

/**
 * Don't use this in production. Useful for testing.
 * We don't want to instantiate potentially many messages at once.
 */
- (NSArray<TSMessage *> *)fetchUnstartedExpiringMessagesInThread:(TSThread *)thread
                                                     transaction:(YapDatabaseReadTransaction *)transaction
{
    OWSAssertDebug(transaction);

    NSMutableArray<TSMessage *> *messages = [NSMutableArray new];
    [self enumerateUnstartedExpiringMessagesInThread:thread
                                               block:^(TSMessage *message) {
                                                   [messages addObject:message];
                                               }
                                         transaction:transaction];

    return [messages copy];
}


- (void)enumerateExpiredMessagesWithBlock:(void (^_Nonnull)(TSMessage *message))block
                              transaction:(YapDatabaseReadTransaction *)transaction
{
    OWSAssertDebug(transaction);

    // Since we can't directly mutate the enumerated expired messages, we store only their ids in hopes of saving a
    // little memory and then enumerate the (larger) TSMessage objects one at a time.
    for (NSString *expiredMessageId in [self fetchExpiredMessageIdsWithTransaction:transaction]) {
        TSMessage *_Nullable message = [TSMessage fetchObjectWithUniqueID:expiredMessageId transaction:transaction];
        if ([message isKindOfClass:[TSMessage class]]) {
            block(message);
        } else {
            OWSLogError(@"unexpected object: %@", message);
        }
    }
}

/**
 * Don't use this in production. Useful for testing.
 * We don't want to instantiate potentially many messages at once.
 */
- (NSArray<TSMessage *> *)fetchExpiredMessagesWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    OWSAssertDebug(transaction);

    NSMutableArray<TSMessage *> *messages = [NSMutableArray new];
    [self enumerateExpiredMessagesWithBlock:^(TSMessage *message) {
        [messages addObject:message];
    }
                                transaction:transaction];

    return [messages copy];
}

#pragma mark - YapDatabaseExtension

+ (YapDatabaseSecondaryIndex *)indexDatabaseExtension
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

            if (![message shouldStartExpireTimerWithTransaction:transaction]) {
                return;
            }

            dict[OWSDisappearingMessageFinderExpiresAtColumn] = @(message.expiresAt);
            dict[OWSDisappearingMessageFinderThreadIdColumn] = message.uniqueThreadId;
        }];

    return [[YapDatabaseSecondaryIndex alloc] initWithSetup:setup handler:handler versionTag:@"1"];
}

#ifdef DEBUG
// Useful for tests, don't use in app startup path because it's slow.
+ (void)blockingRegisterDatabaseExtensions:(OWSStorage *)storage
{
    [storage registerExtension:[self indexDatabaseExtension] withName:OWSDisappearingMessageFinderExpiresAtIndex];
}
#endif

+ (NSString *)databaseExtensionName
{
    return OWSDisappearingMessageFinderExpiresAtIndex;
}

+ (void)asyncRegisterDatabaseExtensions:(OWSStorage *)storage
{
    [storage asyncRegisterExtension:[self indexDatabaseExtension] withName:OWSDisappearingMessageFinderExpiresAtIndex];
}

@end

NS_ASSUME_NONNULL_END
