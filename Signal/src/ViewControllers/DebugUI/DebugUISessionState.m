//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "DebugUISessionState.h"
#import "OWSTableViewController.h"
#import "Signal-Swift.h"
#import <SignalServiceKit/OWSIdentityManager.h>
#import <SignalServiceKit/TSContactThread.h>
#import <SignalServiceKit/TSStorageManager+SessionStore.h>

NS_ASSUME_NONNULL_BEGIN

@implementation DebugUISessionState

- (NSString *)name
{
    return @"Session State";
}

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
                                dispatch_async([OWSDispatch sessionStoreQueue], ^{
                                    [[TSStorageManager sharedManager] printAllSessions];
                                });
                            }],
            [OWSTableItem itemWithTitle:@"Toggle Key Change"
                            actionBlock:^{
                                DDLogError(@"Flipping identity Key. Flip again to return.");

                                OWSIdentityManager *identityManager = [OWSIdentityManager sharedManager];
                                NSString *recipientId = [thread contactIdentifier];

                                NSData *currentKey = [identityManager identityKeyForRecipientIdWOT:recipientId];
                                NSMutableData *flippedKey = [NSMutableData new];
                                const char *currentKeyBytes = currentKey.bytes;
                                for (NSUInteger i = 0; i < currentKey.length; i++) {
                                    const char xorByte = currentKeyBytes[i] ^ 0xff;
                                    [flippedKey appendBytes:&xorByte length:1];
                                }
                                OWSAssert(flippedKey.length == currentKey.length);
                                [identityManager saveRemoteIdentity:flippedKey
                                                        recipientId:recipientId
                                                    protocolContext:protocolContext];
                            }],
            [OWSTableItem itemWithTitle:@"Delete all sessions"
                            actionBlock:^{
                                dispatch_async([OWSDispatch sessionStoreQueue], ^{
                                    [[TSStorageManager sharedManager]
                                        deleteAllSessionsForContact:thread.contactIdentifier
                                                    protocolContext:protocolContext];
                                });
                            }],
            [OWSTableItem itemWithTitle:@"Archive all sessions"
                            actionBlock:^{
                                dispatch_async([OWSDispatch sessionStoreQueue], ^{
                                    [[TSStorageManager sharedManager]
                                        archiveAllSessionsForContact:thread.contactIdentifier
                                                     protocolContext:protocolContext];
                                });
                            }],
            [OWSTableItem itemWithTitle:@"Send session reset"
                            actionBlock:^{
                                [OWSSessionResetJob runWithContactThread:thread
                                                           messageSender:[Environment current].messageSender
                                                          storageManager:[TSStorageManager sharedManager]];
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
    dispatch_async([OWSDispatch sessionStoreQueue], ^{
        [[TSStorageManager sharedManager] resetSessionStore];
        dispatch_async(dispatch_get_main_queue(), ^{
            [[OWSIdentityManager sharedManager] clearIdentityState];
        });
    });
}

+ (void)snapshotSessionAndIdentityStore
{
    dispatch_async([OWSDispatch sessionStoreQueue], ^{
        [[TSStorageManager sharedManager] snapshotSessionStore];
        dispatch_async(dispatch_get_main_queue(), ^{
            [[OWSIdentityManager sharedManager] snapshotIdentityState];
        });
    });
}

+ (void)restoreSessionAndIdentityStore
{
    dispatch_async([OWSDispatch sessionStoreQueue], ^{
        [[TSStorageManager sharedManager] restoreSessionStore];
        dispatch_async(dispatch_get_main_queue(), ^{
            [[OWSIdentityManager sharedManager] restoreIdentityState];
        });
    });
}
#endif

@end

NS_ASSUME_NONNULL_END
