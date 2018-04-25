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
    OWSAssert(transaction);

    NSMutableArray<NSString *> *messageIds = [NSMutableArray new];

    NSString *formattedString = [NSString stringWithFormat:@"WHERE %@ == %d",
                                          OWSFailedMessagesJobMessageStateColumn,
                                          (int)TSOutgoingMessageStateAttemptingOut];
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
    OWSAssert(transaction);

    // Since we can't directly mutate the enumerated "attempting out" expired messages, we store only their ids in hopes
    // of saving a little memory and then enumerate the (larger) TSMessage objects one at a time.
    for (NSString *expiredMessageId in [self fetchAttemptingOutMessageIdsWithTransaction:transaction]) {
        TSOutgoingMessage *_Nullable message =
            [TSOutgoingMessage fetchObjectWithUniqueID:expiredMessageId transaction:transaction];
        if ([message isKindOfClass:[TSOutgoingMessage class]]) {
            block(message);
        } else {
            DDLogError(@"%@ unexpected object: %@", self.logTag, message);
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
                OWSAssert(message.messageState == TSOutgoingMessageStateAttemptingOut);
                if (message.messageState != TSOutgoingMessageStateAttemptingOut) {
                    DDLogError(@"%@ Refusing to mark as unsent message with state: %d",
                        self.logTag,
                        (int)message.messageState);
                    return;
                }

                DDLogDebug(@"%@ marking message as unsent: %@", self.logTag, message.uniqueId);
                [message updateWithMessageState:TSOutgoingMessageStateUnsent transaction:transaction];
                OWSAssert(message.messageState == TSOutgoingMessageStateUnsent);

                count++;
            }
                                              transaction:transaction];
        }];

    DDLogDebug(@"%@ Marked %u messages as unsent", self.logTag, count);
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
