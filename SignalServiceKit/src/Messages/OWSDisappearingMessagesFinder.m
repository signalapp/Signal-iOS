//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalServiceKit/OWSDisappearingMessagesFinder.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSIncomingMessage.h>
#import <SignalServiceKit/TSMessage.h>
#import <SignalServiceKit/TSOutgoingMessage.h>
#import <SignalServiceKit/TSThread.h>

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

@end

NS_ASSUME_NONNULL_END
