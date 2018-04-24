//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWS109OutgoingMessageState.h"
#import <SignalServiceKit/TSOutgoingMessage.h>
#import <YapDatabase/YapDatabaseTransaction.h>

NS_ASSUME_NONNULL_BEGIN

// Increment a similar constant for every future DBMigration
static NSString *const OWS109OutgoingMessageStateMigrationId = @"109";

@implementation OWS109OutgoingMessageState

+ (NSString *)migrationId
{
    return OWS109OutgoingMessageStateMigrationId;
}

- (void)runUpWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssert(transaction);

    // Persist the migration of the outgoing message state.
    // For performance, we want to upgrade all existing outgoing messages in
    // a single transaction.
    NSMutableArray<NSString *> *messageIds =
        [[transaction allKeysInCollection:TSOutgoingMessage.collection] mutableCopy];
    DDLogInfo(@"%@ Migrating %zd outgoing messages.", self.logTag, messageIds.count);
    while (messageIds.count > 0) {
        const int kBatchSize = 1000;
        @autoreleasepool {
            for (int i = 0; i < kBatchSize; i++) {
                if (messageIds.count == 0) {
                    break;
                }
                NSString *messageId = [messageIds lastObject];
                [messageIds removeLastObject];
                id message = [transaction objectForKey:messageId inCollection:TSOutgoingMessage.collection];
                if (![message isKindOfClass:[TSOutgoingMessage class]]) {
                    return;
                }
                TSOutgoingMessage *outgoingMessage = (TSOutgoingMessage *)message;
                [outgoingMessage saveWithTransaction:transaction];
            }
        }
    }
}

@end

NS_ASSUME_NONNULL_END
