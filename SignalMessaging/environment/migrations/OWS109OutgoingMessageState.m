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

    NSMutableArray<TSOutgoingMessage *> *outgoingMessages = [NSMutableArray new];
    [transaction enumerateKeysAndObjectsInCollection:TSOutgoingMessage.collection
                                          usingBlock:^(NSString *key, id value, BOOL *stop) {
                                              if (![value isKindOfClass:[TSOutgoingMessage class]]) {
                                                  return;
                                              }
                                              TSOutgoingMessage *outgoingMessage = (TSOutgoingMessage *)value;
                                              [outgoingMessages addObject:outgoingMessage];
                                          }];

    DDLogInfo(@"Saving %zd outgoing messages.", outgoingMessages.count);

    // Persist the migration of the outgoing message state.
    // For performance, we want to upgrade all existing outgoing messages in
    // a single transaction.
    for (TSOutgoingMessage *outgoingMessage in outgoingMessages) {
        [outgoingMessage saveWithTransaction:transaction];
    }
}

@end

NS_ASSUME_NONNULL_END
