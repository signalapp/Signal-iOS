//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSDisappearingMessagesFinder.h"
#import "OWSStorage.h"
#import "TSIncomingMessage.h"
#import "TSMessage.h"
#import "TSOutgoingMessage.h"
#import "TSThread.h"
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <YapDatabase/YapDatabase.h>
#import <YapDatabase/YapDatabaseQuery.h>
#import <YapDatabase/YapDatabaseSecondaryIndex.h>

NS_ASSUME_NONNULL_BEGIN

static NSString *const OWSDisappearingMessageFinderThreadIdColumn = @"thread_id";
static NSString *const OWSDisappearingMessageFinderExpiresAtColumn = @"expires_at";
static NSString *const OWSDisappearingMessageFinderExpiresAtIndex = @"index_messages_on_expires_at_and_thread_id_v2";

@implementation OWSDisappearingMessagesFinder

+ (NSArray<NSString *> *)ydb_unstartedExpiringMessageIdsWithThreadId:(NSString *)threadId
                                                         transaction:(YapDatabaseReadTransaction *)transaction
{
    OWSAssertDebug(transaction);

    NSMutableArray<NSString *> *messageIds = [NSMutableArray new];
    NSString *formattedString = [NSString stringWithFormat:@"WHERE %@ = 0 AND %@ = \"%@\"",
                                          OWSDisappearingMessageFinderExpiresAtColumn,
                                          OWSDisappearingMessageFinderThreadIdColumn,
                                          threadId];

    YapDatabaseQuery *query = [YapDatabaseQuery queryWithFormat:formattedString];
    YapDatabaseSecondaryIndexTransaction *_Nullable ext =
        [transaction ext:OWSDisappearingMessageFinderExpiresAtIndex];
    if (!ext) {
        [OWSStorage incrementVersionOfDatabaseExtension:OWSDisappearingMessageFinderExpiresAtIndex];
        return @[];
    }
    [ext enumerateKeysMatchingQuery:query
                         usingBlock:^void(NSString *collection, NSString *key, BOOL *stop) {
                             [messageIds addObject:key];
                         }];

    return [messageIds copy];
}

- (NSArray<NSString *> *)fetchExpiredMessageIdsWithTransaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(transaction);

    return [InteractionFinder interactionIdsWithExpiredPerConversationExpirationWithTransaction:transaction];
}

+ (NSArray<NSString *> *)ydb_interactionIdsWithExpiredPerConversationExpirationWithTransaction:
    (YapDatabaseReadTransaction *)transaction
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
    YapDatabaseSecondaryIndexTransaction *_Nullable ext = [transaction ext:OWSDisappearingMessageFinderExpiresAtIndex];
    if (!ext) {
        [OWSStorage incrementVersionOfDatabaseExtension:OWSDisappearingMessageFinderExpiresAtIndex];
        return @[];
    }
    [ext enumerateKeysMatchingQuery:query
                         usingBlock:^void(NSString *collection, NSString *key, BOOL *stop) {
                             [messageIds addObject:key];
                         }];
    return [messageIds copy];
}

- (nullable NSNumber *)nextExpirationTimestampWithTransaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(transaction);

    __block TSMessage *firstMessage;
    [InteractionFinder
        enumerateMessagesWithStartedPerConversationExpirationWithTransaction:transaction
                                                                       block:^(TSInteraction *interaction, BOOL *stop) {
                                                                           if (![interaction
                                                                                   isKindOfClass:[TSMessage class]]) {
                                                                               OWSFailDebug(@"Unexpected object: %@",
                                                                                   interaction.class);
                                                                               return;
                                                                           }
                                                                           firstMessage = (TSMessage *)interaction;
                                                                           *stop = YES;
                                                                       }];
    if (firstMessage && firstMessage.expiresAt > 0) {
        return [NSNumber numberWithUnsignedLongLong:firstMessage.expiresAt];
    }

    return nil;
}

+ (void)ydb_enumerateMessagesWithStartedPerConversationExpirationWithBlock:(void (^_Nonnull)(
                                                                               TSMessage *message, BOOL *stop))block
                                                               transaction:(YapDatabaseReadTransaction *)transaction
{
    OWSAssertDebug(block);
    OWSAssertDebug(transaction);

    NSString *formattedString = [NSString stringWithFormat:@"WHERE %@ > 0 ORDER BY %@ ASC",
                                          OWSDisappearingMessageFinderExpiresAtColumn,
                                          OWSDisappearingMessageFinderExpiresAtColumn];
    YapDatabaseQuery *query = [YapDatabaseQuery queryWithFormat:formattedString];

    YapDatabaseSecondaryIndexTransaction *_Nullable ext = [transaction ext:OWSDisappearingMessageFinderExpiresAtIndex];
    if (!ext) {
        [OWSStorage incrementVersionOfDatabaseExtension:OWSDisappearingMessageFinderExpiresAtIndex];
        return;
    }
    [ext enumerateKeysAndObjectsMatchingQuery:query
                                   usingBlock:^void(NSString *collection, NSString *key, id object, BOOL *stop) {
                                       if (![object isKindOfClass:[TSMessage class]]) {
                                           OWSFailDebug(@"Unexpected object.");
                                           return;
                                       }
                                       TSMessage *message = (TSMessage *)object;
                                       block(message, stop);
                                   }];
}

+ (void)ydb_enumerateMessagesWhichFailedToStartExpiringWithBlock:(void (^_Nonnull)(TSMessage *message, BOOL *stop))block
                                                     transaction:(YapDatabaseReadTransaction *)transaction
{
    OWSAssertDebug(transaction);

    NSString *formattedString =
        [NSString stringWithFormat:@"WHERE %@ = 0", OWSDisappearingMessageFinderExpiresAtColumn];
    YapDatabaseQuery *query = [YapDatabaseQuery queryWithFormat:formattedString];
    YapDatabaseSecondaryIndexTransaction *_Nullable ext = [transaction ext:OWSDisappearingMessageFinderExpiresAtIndex];
    if (!ext) {
        [OWSStorage incrementVersionOfDatabaseExtension:OWSDisappearingMessageFinderExpiresAtIndex];
        return;
    }
    [ext enumerateKeysAndObjectsMatchingQuery:query
                                   usingBlock:^void(NSString *collection, NSString *key, id object, BOOL *stop) {
                                       if (![object isKindOfClass:[TSMessage class]]) {
                                           OWSFailDebug(@"Object was unexpected class: %@", [object class]);
                                           return;
                                       }
                                       TSMessage *message = (TSMessage *)object;
                                       if (![message shouldStartExpireTimerWithTransaction:transaction.asAnyRead]) {
                                           OWSFailDebug(@"object: %@ shouldn't expire.", message);
                                           return;
                                       }

                                       if ([message isKindOfClass:[TSIncomingMessage class]]) {
                                           TSIncomingMessage *incomingMessage = (TSIncomingMessage *)message;
                                           if (!incomingMessage.wasRead) {
                                               return;
                                           }
                                       }
                                       block(message, stop);
                                   }];
}

- (void)enumerateMessagesWhichFailedToStartExpiringWithBlock:(void (^_Nonnull)(TSMessage *message, BOOL *stop))block
                                                 transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(transaction);

    [InteractionFinder enumerateMessagesWhichFailedToStartExpiringWithTransaction:transaction block:block];
}

#ifdef DEBUG

/**
 * Don't use this in production. Useful for testing.
 * We don't want to instantiate potentially many messages at once.
 */
+ (void)ydb_enumerateUnstartedExpiringMessagesWithThreadId:(NSString *)threadId
                                                     block:(void (^_Nonnull)(TSMessage *message, BOOL *stop))block
                                               transaction:(YapDatabaseReadTransaction *)transaction
{
    OWSAssertDebug(transaction);

    NSString *formattedString = [NSString stringWithFormat:@"WHERE %@ = 0 AND %@ = \"%@\"",
                                          OWSDisappearingMessageFinderExpiresAtColumn,
                                          OWSDisappearingMessageFinderThreadIdColumn,
                                          threadId];

    YapDatabaseQuery *query = [YapDatabaseQuery queryWithFormat:formattedString];
    YapDatabaseSecondaryIndexTransaction *_Nullable ext = [transaction ext:OWSDisappearingMessageFinderExpiresAtIndex];
    if (!ext) {
        [OWSStorage incrementVersionOfDatabaseExtension:OWSDisappearingMessageFinderExpiresAtIndex];
        return;
    }
    [ext enumerateKeysAndObjectsMatchingQuery:query
                                   usingBlock:^void(NSString *collection, NSString *key, id object, BOOL *stop) {
                                       if (![object isKindOfClass:[TSMessage class]]) {
                                           OWSFailDebug(@"Unexpected object.");
                                           return;
                                       }
                                       TSMessage *message = (TSMessage *)object;
                                       block(message, stop);
                                   }];
}

/**
 * Don't use this in production. Useful for testing.
 * We don't want to instantiate potentially many messages at once.
 */
- (NSArray<TSMessage *> *)fetchUnstartedExpiringMessagesInThread:(TSThread *)thread
                                                     transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(transaction);

    NSMutableArray<TSMessage *> *messages = [NSMutableArray new];
    InteractionFinder *interactionFinder = [[InteractionFinder alloc] initWithThreadUniqueId:thread.uniqueId];
    [interactionFinder enumerateUnstartedExpiringMessagesWithTransaction:transaction
                                                                   block:^(TSMessage *message, BOOL *stop) {
                                                                       [messages addObject:message];
                                                                   }];
    return [messages copy];
}

#endif

- (void)enumerateExpiredMessagesWithBlock:(void (^_Nonnull)(TSMessage *message))block
                              transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(transaction);

    // Since we can't directly mutate the enumerated expired messages, we store only their ids in hopes of saving a
    // little memory and then enumerate the (larger) TSMessage objects one at a time.
    for (NSString *expiredMessageId in [self fetchExpiredMessageIdsWithTransaction:transaction]) {
        TSMessage *_Nullable message = [TSMessage anyFetchMessageWithUniqueId:expiredMessageId transaction:transaction];
        if (message == nil) {
            OWSFailDebug(@"Missing interaction.");
            continue;
        }
        block(message);
    }
}

#ifdef DEBUG
/**
 * Don't use this in production. Useful for testing.
 * We don't want to instantiate potentially many messages at once.
 */
- (NSArray<TSMessage *> *)fetchExpiredMessagesWithTransaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(transaction);

    NSMutableArray<TSMessage *> *messages = [NSMutableArray new];
    [self enumerateExpiredMessagesWithBlock:^(TSMessage *message) {
        [messages addObject:message];
    }
                                transaction:transaction];

    return [messages copy];
}
#endif

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

            if (![message shouldStartExpireTimerWithTransaction:transaction.asAnyRead]) {
                return;
            }

            dict[OWSDisappearingMessageFinderExpiresAtColumn] = @(message.expiresAt);
            dict[OWSDisappearingMessageFinderThreadIdColumn] = message.uniqueThreadId;
        }];

    return [[YapDatabaseSecondaryIndex alloc] initWithSetup:setup handler:handler versionTag:@"3"];
}

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
