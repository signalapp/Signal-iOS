//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSFailedMessagesJob.h"
#import "OWSStorage.h"
#import "TSMessage.h"
#import "TSOutgoingMessage.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <YapDatabase/YapDatabase.h>
#import <YapDatabase/YapDatabaseQuery.h>
#import <YapDatabase/YapDatabaseSecondaryIndex.h>

NS_ASSUME_NONNULL_BEGIN

static NSString *const OWSFailedMessagesJobMessageStateColumn = @"message_state";
static NSString *const OWSFailedMessagesJobMessageStateIndex = @"index_outoing_messages_on_message_state";

@implementation OWSFailedMessagesJob

#pragma mark - Dependencies

- (SDSDatabaseStorage *)databaseStorage
{
    return SDSDatabaseStorage.shared;
}

#pragma mark -

- (NSArray<NSString *> *)fetchAttemptingOutMessageIdsWithTransaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(transaction);

    return [InteractionFinder attemptingOutInteractionIdsWithTransaction:transaction];
}

+ (NSArray<NSString *> *)attemptingOutMessageIdsWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    OWSAssertDebug(transaction);

    NSMutableArray<NSString *> *messageIds = [NSMutableArray new];

    NSString *formattedString = [NSString
        stringWithFormat:@"WHERE %@ == %d", OWSFailedMessagesJobMessageStateColumn, (int)TSOutgoingMessageStateSending];
    YapDatabaseQuery *query = [YapDatabaseQuery queryWithFormat:formattedString];
    [[transaction ext:OWSFailedMessagesJobMessageStateIndex]
        enumerateKeysMatchingQuery:query
                        usingBlock:^void(NSString *collection, NSString *key, BOOL *stop) {
                            [messageIds addObject:key];
                        }];

    return [messageIds copy];
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

#pragma mark - YapDatabaseExtension

+ (YapDatabaseSecondaryIndex *)indexDatabaseExtension
{
    YapDatabaseSecondaryIndexSetup *setup = [YapDatabaseSecondaryIndexSetup new];
    [setup addColumn:OWSFailedMessagesJobMessageStateColumn withType:YapDatabaseSecondaryIndexTypeInteger];

    YapDatabaseSecondaryIndexHandler *handler =
        [YapDatabaseSecondaryIndexHandler withObjectBlock:^(YapDatabaseReadTransaction *transaction,
            NSMutableDictionary *dict,
            NSString *collection,
            NSString *key,
            id object) {
            if (![object isKindOfClass:[TSOutgoingMessage class]]) {
                return;
            }
            TSOutgoingMessage *message = (TSOutgoingMessage *)object;

            dict[OWSFailedMessagesJobMessageStateColumn] = @(message.messageState);
        }];

    return [[YapDatabaseSecondaryIndex alloc] initWithSetup:setup handler:handler versionTag:nil];
}

+ (NSString *)databaseExtensionName
{
    return OWSFailedMessagesJobMessageStateIndex;
}

+ (void)asyncRegisterDatabaseExtensionsWithPrimaryStorage:(OWSStorage *)storage
{
    [storage asyncRegisterExtension:[self indexDatabaseExtension] withName:OWSFailedMessagesJobMessageStateIndex];
}

@end

NS_ASSUME_NONNULL_END
