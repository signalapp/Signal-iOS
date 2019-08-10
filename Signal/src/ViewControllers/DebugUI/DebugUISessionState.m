//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "DebugUISessionState.h"
#import "OWSTableViewController.h"
#import "Signal-Swift.h"
#import <SignalServiceKit/OWSIdentityManager.h>
#import <SignalServiceKit/SSKSessionStore.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSContactThread.h>

#ifdef DEBUG

NS_ASSUME_NONNULL_BEGIN

@implementation DebugUISessionState

- (NSString *)name
{
    return @"Session State";
}

#pragma mark -  Dependencies

- (SDSDatabaseStorage *)databaseStorage
{
    return SDSDatabaseStorage.shared;
}

- (SSKSessionStore *)sessionStore
{
    return SSKEnvironment.shared.sessionStore;
}

- (OWSSessionResetJobQueue *)sessionResetJobQueue
{
    return AppEnvironment.shared.sessionResetJobQueue;
}

#pragma mark -

- (nullable OWSTableSection *)sectionForThread:(nullable TSThread *)threadParameter
{
    NSMutableArray<OWSTableItem *> *items = [NSMutableArray new];
    if ([threadParameter isKindOfClass:[TSContactThread class]]) {
        TSContactThread *thread = (TSContactThread *)threadParameter;
        [items addObjectsFromArray:@[
            [OWSTableItem itemWithTitle:@"Log All Recipient Identities"
                            actionBlock:^{
                                [OWSRecipientIdentity printAllIdentities];
                            }],
            [OWSTableItem itemWithTitle:@"Log All Sessions"
                            actionBlock:^{
                                [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
                                    [self.sessionStore printAllSessionsWithTransaction:transaction];
                                }];
                            }],
            [OWSTableItem itemWithTitle:@"Toggle Key Change"
                            actionBlock:^{
                                OWSLogError(@"Flipping identity Key. Flip again to return.");

                                OWSIdentityManager *identityManager = [OWSIdentityManager sharedManager];
                                SignalServiceAddress *address = thread.contactAddress;

                                NSData *currentKey = [identityManager identityKeyForAddress:address];
                                NSMutableData *flippedKey = [NSMutableData new];
                                const char *currentKeyBytes = currentKey.bytes;
                                for (NSUInteger i = 0; i < currentKey.length; i++) {
                                    const char xorByte = currentKeyBytes[i] ^ 0xff;
                                    [flippedKey appendBytes:&xorByte length:1];
                                }
                                OWSAssertDebug(flippedKey.length == currentKey.length);
                                [identityManager saveRemoteIdentity:flippedKey address:address];
                            }],
            [OWSTableItem itemWithTitle:@"Delete all sessions"
                            actionBlock:^{
                                [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
                                    [self.sessionStore deleteAllSessionsForAddress:thread.contactAddress
                                                                       transaction:transaction];
                                }];
                            }],
            [OWSTableItem itemWithTitle:@"Archive all sessions"
                            actionBlock:^{
                                [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
                                    [self.sessionStore archiveAllSessionsForAddress:thread.contactAddress
                                                                        transaction:transaction];
                                }];
                            }],
            [OWSTableItem itemWithTitle:@"Send session reset"
                            actionBlock:^{
                                [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
                                    [self.sessionResetJobQueue addContactThread:thread transaction:transaction];
                                }];
                            }],
        ]];
    }

    [items addObjectsFromArray:@[ [OWSTableItem itemWithTitle:@"Clear Session and Identity Store"
                                                  actionBlock:^{
                                                      [self clearSessionAndIdentityStore];
                                                  }] ]];

    return [OWSTableSection sectionWithTitle:self.name items:items];
}

- (void)clearSessionAndIdentityStore
{
    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [self.sessionStore resetSessionStore:transaction];
        [[OWSIdentityManager sharedManager] clearIdentityState:transaction];
    }];
}

@end

NS_ASSUME_NONNULL_END

#endif
