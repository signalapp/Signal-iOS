//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSFailedMessagesJob.h"
#import "OWSPrimaryStorage.h"
#import "TSMessage.h"
#import "TSOutgoingMessage.h"
#import <YapDatabase/YapDatabase.h>
#import <YapDatabase/YapDatabaseQuery.h>
#import <YapDatabase/YapDatabaseSecondaryIndex.h>

NS_ASSUME_NONNULL_BEGIN

static NSString *const OWSFailedMessagesJobMessageStateColumn = @"message_state";
static NSString *const OWSFailedMessagesJobMessageStateIndex = @"index_outoing_messages_on_message_state";

@interface OWSFailedMessagesJob ()

@property (nonatomic, readonly) OWSPrimaryStorage *primaryStorage;

@end

#pragma mark -

@implementation OWSFailedMessagesJob

- (instancetype)initWithPrimaryStorage:(OWSPrimaryStorage *)primaryStorage
{
    self = [super init];
    if (!self) {
        return self;
    }

    _primaryStorage = primaryStorage;

    return self;
}

- (NSArray<NSString *> *)fetchAttemptingOutMessageIdsWithTransaction:
    (YapDatabaseReadWriteTransaction *_Nonnull)transaction
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
                                    transaction:(YapDatabaseReadWriteTransaction *_Nonnull)transaction
{
    OWSAssertDebug(transaction);

    // Since we can't directly mutate the enumerated "attempting out" expired messages, we store only their ids in hopes
    // of saving a little memory and then enumerate the (larger) TSMessage objects one at a time.
    for (NSString *expiredMessageId in [self fetchAttemptingOutMessageIdsWithTransaction:transaction]) {
        TSOutgoingMessage *_Nullable message =
            [TSOutgoingMessage fetchObjectWithUniqueID:expiredMessageId transaction:transaction];
        if ([message isKindOfClass:[TSOutgoingMessage class]]) {
            block(message);
        } else {
            OWSLogError(@"unexpected object: %@", message);
        }
    }
}

- (void)run
{
    __block uint count = 0;

    [[self.primaryStorage newDatabaseConnection]
        readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
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
        }];

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

#ifdef DEBUG
// Useful for tests, don't use in app startup path because it's slow.
- (void)blockingRegisterDatabaseExtensions
{
    [self.primaryStorage registerExtension:[self.class indexDatabaseExtension]
                                  withName:OWSFailedMessagesJobMessageStateIndex];
}
#endif

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
