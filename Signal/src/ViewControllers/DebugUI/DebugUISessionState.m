//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "DebugUISessionState.h"
#import "Signal-Swift.h"
#import <SignalServiceKit/OWSIdentityManager.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSContactThread.h>
#import <SignalUI/OWSTableViewController.h>

#ifdef DEBUG

NS_ASSUME_NONNULL_BEGIN

@implementation DebugUISessionState

- (NSString *)name
{
    return @"Session State";
}

#pragma mark -

- (nullable OWSTableSection *)sectionForThread:(nullable TSThread *)threadParameter
{
    NSMutableArray<OWSTableItem *> *items = [NSMutableArray new];
    if ([threadParameter isKindOfClass:[TSContactThread class]]) {
        TSContactThread *thread = (TSContactThread *)threadParameter;
        [items addObjectsFromArray:@[
            [OWSTableItem itemWithTitle:@"Log All Recipient Identities"
                            actionBlock:^{ [OWSRecipientIdentity printAllIdentities]; }],
            [OWSTableItem itemWithTitle:@"Log All Sessions"
                            actionBlock:^{
                                [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
                                    SSKSessionStore *sessionStore =
                                        [self signalProtocolStoreForIdentity:OWSIdentityACI].sessionStore;
                                    [sessionStore printAllSessionsWithTransaction:transaction];
                                }];
                            }],
            [OWSTableItem itemWithTitle:@"Toggle Key Change"
                            actionBlock:^{
                                OWSLogError(@"Flipping identity Key. Flip again to return.");

                                OWSIdentityManager *identityManager = [OWSIdentityManager shared];
                                SignalServiceAddress *address = thread.contactAddress;

                                NSData *currentKey = [identityManager identityKeyForAddress:address];
                                NSMutableData *flippedKey = [NSMutableData new];
                                const char *currentKeyBytes = currentKey.bytes;
                                for (NSUInteger i = 0; i < currentKey.length; i++) {
                                    const char xorByte = currentKeyBytes[i] ^ (char)0xff;
                                    [flippedKey appendBytes:&xorByte length:1];
                                }
                                OWSAssertDebug(flippedKey.length == currentKey.length);
                                [identityManager saveRemoteIdentity:flippedKey address:address];
                            }],
            [OWSTableItem itemWithTitle:@"Delete all sessions"
                            actionBlock:^{
                                DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
                                    SSKSessionStore *sessionStore =
                                        [self signalProtocolStoreForIdentity:OWSIdentityACI].sessionStore;
                                    [sessionStore deleteAllSessionsForAddress:thread.contactAddress
                                                                  transaction:transaction];
                                });
                            }],
            [OWSTableItem itemWithTitle:@"Archive all sessions"
                            actionBlock:^{
                                DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
                                    SSKSessionStore *sessionStore =
                                        [self signalProtocolStoreForIdentity:OWSIdentityACI].sessionStore;
                                    [sessionStore archiveAllSessionsForAddress:thread.contactAddress
                                                                   transaction:transaction];
                                });
                            }],
            [OWSTableItem itemWithTitle:@"Send session reset"
                            actionBlock:^{
                                DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
                                    [self.smJobQueues.sessionResetJobQueue addContactThread:thread
                                                                                transaction:transaction];
                                });
                            }],
        ]];
    }

    if ([threadParameter isKindOfClass:[TSGroupThread class]]) {
        TSGroupThread *groupThread = (TSGroupThread *)threadParameter;
        [items addObject:[OWSTableItem itemWithTitle:@"Rotate sender key"
                                         actionBlock:^{
                                             DatabaseStorageWrite(
                                                 self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
                                                     [self.senderKeyStore resetSenderKeySessionFor:groupThread
                                                                                       transaction:transaction];
                                                 });
                                         }]];
    }

    if (threadParameter) {
        [items addObject:[OWSTableItem itemWithTitle:@"Update verification state"
                                         actionBlock:^{ [self updateIdentityVerificationForThread:threadParameter]; }]];
    }

    [items addObjectsFromArray:@[
        [OWSTableItem itemWithTitle:@"Clear Session and Identity Store"
                        actionBlock:^{ [self clearSessionAndIdentityStore]; }],
    ]];

    [items addObject:[OWSTableItem itemWithTitle:@"Clear sender key store"
                                     actionBlock:^{
                                         DatabaseStorageWrite(
                                             self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
                                                 [self.senderKeyStore resetSenderKeyStoreWithTransaction:transaction];
                                             });
                                     }]];

    return [OWSTableSection sectionWithTitle:self.name items:items];
}

- (void)clearSessionAndIdentityStore
{
    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        SSKSessionStore *sessionStore = [self signalProtocolStoreForIdentity:OWSIdentityACI].sessionStore;
        [sessionStore resetSessionStore:transaction];
        [[OWSIdentityManager shared] clearIdentityState:transaction];
    });
}

- (void)updateIdentityVerificationForThread:(TSThread *)thread
{
    if (thread.recipientAddressesWithSneakyTransaction.count == 0) {
        OWSFailDebug(@"No recipients for thread %@", thread);
        return;
    }

    if (thread.recipientAddressesWithSneakyTransaction.count > 1) {
        ActionSheetController *recipientSelection = [[ActionSheetController alloc] initWithTitle:@"Select a recipient"
                                                                                         message:nil];
        [recipientSelection addAction:OWSActionSheets.cancelAction];

        __weak typeof(self) wSelf = self;
        for (SignalServiceAddress *address in thread.recipientAddressesWithSneakyTransaction) {
            NSString *name = [self.contactsManager displayNameForAddress:address];
            [recipientSelection
                addAction:[[ActionSheetAction alloc] initWithTitle:name
                                                             style:ActionSheetActionStyleDefault
                                                           handler:^(ActionSheetAction *action) {
                                                               [wSelf updateIdentityVerificationForAddress:address];
                                                           }]];
        }

        [OWSActionSheets showActionSheet:recipientSelection fromViewController:nil];

    } else {
        [self updateIdentityVerificationForAddress:thread.recipientAddressesWithSneakyTransaction.firstObject];
    }
}

- (void)updateIdentityVerificationForAddress:(SignalServiceAddress *)address
{
    OWSRecipientIdentity *identity = [OWSIdentityManager.shared recipientIdentityForAddress:address];
    NSString *name = [self.contactsManager displayNameForAddress:address];
    NSString *message = [NSString stringWithFormat:@"%@ is currently marked as %@",
                                  name,
                                  OWSVerificationStateToString(identity.verificationState)];

    ActionSheetController *stateSelection = [[ActionSheetController alloc] initWithTitle:@"Select a verification state"
                                                                                 message:message];
    [stateSelection addAction:OWSActionSheets.cancelAction];

    for (NSNumber *stateNum in
        @[ @(OWSVerificationStateVerified), @(OWSVerificationStateDefault), @(OWSVerificationStateNoLongerVerified) ]) {
        OWSVerificationState state = [stateNum unsignedIntegerValue];
        [stateSelection addAction:[[ActionSheetAction alloc] initWithTitle:OWSVerificationStateToString(state)
                                                                     style:ActionSheetActionStyleDefault
                                                                   handler:^(ActionSheetAction *action) {
                                                                       [OWSIdentityManager.shared
                                                                            setVerificationState:state
                                                                                     identityKey:identity.identityKey
                                                                                         address:address
                                                                           isUserInitiatedChange:NO];
                                                                   }]];
    }

    [OWSActionSheets showActionSheet:stateSelection fromViewController:nil];
}

@end

NS_ASSUME_NONNULL_END

#endif
