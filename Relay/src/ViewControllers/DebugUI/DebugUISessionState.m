//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "DebugUISessionState.h"
#import "OWSTableViewController.h"
#import "Relay-Swift.h"
#import <RelayServiceKit/OWSIdentityManager.h>
#import <RelayServiceKit/OWSPrimaryStorage+SessionStore.h>
#import <RelayServiceKit/TSThread.h>

NS_ASSUME_NONNULL_BEGIN

@implementation DebugUISessionState

- (NSString *)name
{
    return @"Session State";
}

- (nullable OWSTableSection *)sectionForThread:(nullable TSThread *)threadParameter
{
    NSMutableArray<OWSTableItem *> *items = [NSMutableArray new];
    if ([threadParameter isKindOfClass:[TSThread class]]) {
        TSThread *thread = (TSThread *)threadParameter;
        [items addObjectsFromArray:@[
            [OWSTableItem itemWithTitle:@"Log All Recipient Identities"
                            actionBlock:^{
                                [OWSRecipientIdentity printAllIdentities];
                            }],
            [OWSTableItem itemWithTitle:@"Log All Sessions"
                            actionBlock:^{
                                [[OWSPrimaryStorage sharedManager] printAllSessions];
                            }],
            [OWSTableItem itemWithTitle:@"Toggle Key Change"
                            actionBlock:^{
                                DDLogError(@"Flipping identity Key. Flip again to return.");

                                OWSIdentityManager *identityManager = [OWSIdentityManager sharedManager];
                                NSString *recipientId = [thread contactIdentifier];

                                NSData *currentKey = [identityManager identityKeyForRecipientId:recipientId];
                                NSMutableData *flippedKey = [NSMutableData new];
                                const char *currentKeyBytes = currentKey.bytes;
                                for (NSUInteger i = 0; i < currentKey.length; i++) {
                                    const char xorByte = currentKeyBytes[i] ^ 0xff;
                                    [flippedKey appendBytes:&xorByte length:1];
                                }
                                OWSAssert(flippedKey.length == currentKey.length);
                                [identityManager saveRemoteIdentity:flippedKey recipientId:recipientId];
                            }],
            [OWSTableItem itemWithTitle:@"Delete all sessions"
                            actionBlock:^{
                                [OWSPrimaryStorage.sharedManager.newDatabaseConnection
                                    readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                                        [[OWSPrimaryStorage sharedManager]
                                            deleteAllSessionsForContact:thread.contactIdentifier
                                                        protocolContext:transaction];
                                    }];
                            }],
            [OWSTableItem itemWithTitle:@"Archive all sessions"
                            actionBlock:^{
                                [OWSPrimaryStorage.sharedManager.newDatabaseConnection
                                    readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                                        [[OWSPrimaryStorage sharedManager]
                                            archiveAllSessionsForContact:thread.contactIdentifier
                                                         protocolContext:transaction];
                                    }];
                            }],
            [OWSTableItem itemWithTitle:@"Send session reset"
                            actionBlock:^{
                                [OWSSessionResetJob runWithContactThread:thread
                                                           messageSender:[Environment current].messageSender
                                                          primaryStorage:[OWSPrimaryStorage sharedManager]];
                            }],
        ]];
    }

#if DEBUG
    [items addObjectsFromArray:@[
        [OWSTableItem itemWithTitle:@"Clear Session and Identity Store"
                        actionBlock:^{
                            [DebugUISessionState clearSessionAndIdentityStore];
                        }],
        [OWSTableItem itemWithTitle:@"Snapshot Session and Identity Store"
                        actionBlock:^{
                            [DebugUISessionState snapshotSessionAndIdentityStore];
                        }],
        [OWSTableItem itemWithTitle:@"Restore Session and Identity Store"
                        actionBlock:^{
                            [DebugUISessionState restoreSessionAndIdentityStore];
                        }]
    ]];
#endif

    return [OWSTableSection sectionWithTitle:self.name items:items];
}

#if DEBUG
+ (void)clearSessionAndIdentityStore
{
    [OWSPrimaryStorage.sharedManager.newDatabaseConnection
        readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            [[OWSPrimaryStorage sharedManager] resetSessionStore:transaction];
            [[OWSIdentityManager sharedManager] clearIdentityState:transaction];
        }];
}

+ (void)snapshotSessionAndIdentityStore
{
    [OWSPrimaryStorage.sharedManager.newDatabaseConnection
        readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            [[OWSPrimaryStorage sharedManager] snapshotSessionStore:transaction];
            [[OWSIdentityManager sharedManager] snapshotIdentityState:transaction];
        }];
}

+ (void)restoreSessionAndIdentityStore
{
    [OWSPrimaryStorage.sharedManager.newDatabaseConnection
        readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            [[OWSPrimaryStorage sharedManager] restoreSessionStore:transaction];
            [[OWSIdentityManager sharedManager] restoreIdentityState:transaction];
        }];
}
#endif

@end

NS_ASSUME_NONNULL_END
