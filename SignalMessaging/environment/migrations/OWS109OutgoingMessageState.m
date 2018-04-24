//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWS109OutgoingMessageState.h"
#import <SignalServiceKit/OWSPrimaryStorage.h>
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

// Override parent migration
- (void)runUpWithCompletion:(OWSDatabaseMigrationCompletion)completion
{
    OWSAssert(completion);

    OWSDatabaseConnection *dbConnection = (OWSDatabaseConnection *)self.primaryStorage.newDatabaseConnection;

    [dbConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
        NSMutableArray<NSString *> *messageIds =
            [[transaction allKeysInCollection:TSOutgoingMessage.collection] mutableCopy];
        DDLogInfo(@"%@ Migrating %zd outgoing messages.", self.logTag, messageIds.count);

        [self processBatch:messageIds
              dbConnection:dbConnection
                completion:^{
                    DDLogInfo(@"Completed migration %@", self.uniqueId);

                    [self save];

                    completion();
                }];
    }];
}

- (void)processBatch:(NSMutableArray<NSString *> *)messageIds
        dbConnection:(OWSDatabaseConnection *)dbConnection
          completion:(OWSDatabaseMigrationCompletion)completion
{
    OWSAssert(dbConnection);
    OWSAssert(completion);

    DDLogVerbose(@"%@ %s: %zd", self.logTag, __PRETTY_FUNCTION__, messageIds.count);

    if (messageIds.count < 1) {
        completion();
        return;
    }

    [dbConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
        const int kBatchSize = 1000;
        for (int i = 0; i < kBatchSize && messageIds.count > 0; i++) {
            NSString *messageId = [messageIds lastObject];
            [messageIds removeLastObject];
            id message = [transaction objectForKey:messageId inCollection:TSOutgoingMessage.collection];
            if (![message isKindOfClass:[TSOutgoingMessage class]]) {
                continue;
            }
            TSOutgoingMessage *outgoingMessage = (TSOutgoingMessage *)message;
            [outgoingMessage saveWithTransaction:transaction];
        }
    }
        completionBlock:^{
            // Process the next batch.
            [self processBatch:messageIds dbConnection:dbConnection completion:completion];
        }];
}

@end

NS_ASSUME_NONNULL_END
