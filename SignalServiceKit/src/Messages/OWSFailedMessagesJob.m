//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/OWSFailedMessagesJob.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSMessage.h>
#import <SignalServiceKit/TSOutgoingMessage.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSFailedMessagesJob

- (NSArray<NSString *> *)fetchAttemptingOutMessageIdsWithTransaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(transaction);

    return [InteractionFinder attemptingOutInteractionIdsWithTransaction:transaction];
}

- (void)enumerateAttemptingOutMessagesWithBlock:(void (^_Nonnull)(TSOutgoingMessage *message))block
                                    transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(transaction);

    // Since we can't directly mutate the enumerated "attempting out" expired messages, we store only their ids in hopes
    // of saving a little memory and then enumerate the (larger) TSMessage objects one at a time.
    for (NSString *expiredMessageId in [self fetchAttemptingOutMessageIdsWithTransaction:transaction]) {
        TSOutgoingMessage *_Nullable message =
            [TSOutgoingMessage anyFetchOutgoingMessageWithUniqueId:expiredMessageId transaction:transaction];
        if (message == nil) {
            OWSFailDebug(@"Missing interaction.");
            continue;
        }
        block(message);
    }
}

- (void)runSync
{
    __block uint count = 0;

    DatabaseStorageWrite(
        self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
            [self enumerateAttemptingOutMessagesWithBlock:^(TSOutgoingMessage *message) {
                // sanity check
                OWSAssertDebug(message.messageState == TSOutgoingMessageStateSending);
                if (message.messageState != TSOutgoingMessageStateSending) {
                    OWSLogError(@"Refusing to mark as unsent message with state: %d", (int)message.messageState);
                    return;
                }

                OWSLogDebug(@"marking message as unsent: %@", message.uniqueId);
                [message updateWithAllSendingRecipientsMarkedAsFailedWithTansaction:transaction];
                OWSAssertDebug(message.messageState == TSOutgoingMessageStateFailed);

                count++;
            }
                                              transaction:transaction];
        });

    OWSLogDebug(@"Marked %u messages as unsent", count);
}

@end

NS_ASSUME_NONNULL_END
