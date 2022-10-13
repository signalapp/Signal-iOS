//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSDisappearingMessagesFinder.h"
#import "TSIncomingMessage.h"
#import "TSMessage.h"
#import "TSOutgoingMessage.h"
#import "TSThread.h"
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSDisappearingMessagesFinder

- (NSArray<NSString *> *)fetchExpiredMessageIdsWithTransaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(transaction);

    return [InteractionFinder interactionIdsWithExpiredPerConversationExpirationWithTransaction:transaction];
}

- (nullable NSNumber *)nextExpirationTimestampWithTransaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(transaction);
    TSMessage *_Nullable message = nil;
    message = [InteractionFinder nextMessageWithStartedPerConversationExpirationToExpireWithTransaction:transaction];

    if (message.expiresAt > 0) {
        return @(message.expiresAt);
    } else {
        return nil;
    }
}

- (NSArray<NSString *> *)fetchAllMessageUniqueIdsWhichFailedToStartExpiringWithTransaction:
    (SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(transaction);
    return [InteractionFinder fetchAllMessageUniqueIdsWhichFailedToStartExpiringWithTransaction:transaction];
}

#ifdef DEBUG
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
        @autoreleasepool {
            TSMessage *_Nullable message = [TSMessage anyFetchMessageWithUniqueId:expiredMessageId
                                                                      transaction:transaction];
            if (message == nil) {
                OWSFailDebug(@"Missing interaction.");
                continue;
            }
            block(message);
        }
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

@end

NS_ASSUME_NONNULL_END
