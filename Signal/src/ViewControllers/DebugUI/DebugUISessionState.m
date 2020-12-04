//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
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

- (id<ContactsManagerProtocol>)contactsManager
{
    return SSKEnvironment.shared.contactsManager;
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

                                OWSIdentityManager *identityManager = [OWSIdentityManager shared];
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
                                DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
                                    [self.sessionStore deleteAllSessionsForAddress:thread.contactAddress
                                                                       transaction:transaction];
                                });
                            }],
            [OWSTableItem itemWithTitle:@"Archive all sessions"
                            actionBlock:^{
                                DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
                                    [self.sessionStore archiveAllSessionsForAddress:thread.contactAddress
                                                                        transaction:transaction];
                                });
                            }],
            [OWSTableItem itemWithTitle:@"Send session reset"
                            actionBlock:^{
                                DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
                                    [self.sessionResetJobQueue addContactThread:thread transaction:transaction];
                                });
                            }],
        ]];
    }

    if (threadParameter) {
        [items addObject:[OWSTableItem itemWithTitle:@"Update verification state"
                                         actionBlock:^{ [self updateIdentityVerificationForThread:threadParameter]; }]];
    }

    [items addObjectsFromArray:@[
        [OWSTableItem itemWithTitle:@"Clear Session and Identity Store"
                        actionBlock:^{ [self clearSessionAndIdentityStore]; }],
    ]];

    return [OWSTableSection sectionWithTitle:self.name items:items];
}

- (void)clearSessionAndIdentityStore
{
    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        [self.sessionStore resetSessionStore:transaction];
        [[OWSIdentityManager shared] clearIdentityState:transaction];
    });
}

- (void)updateIdentityVerificationForThread:(TSThread *)thread
{
    if (thread.recipientAddresses.count == 0) {
        OWSFailDebug(@"No recipients for thread %@", thread);
        return;
    }

    if (thread.recipientAddresses.count > 1) {
        ActionSheetController *recipientSelection = [[ActionSheetController alloc] initWithTitle:@"Select a recipient"
                                                                                         message:nil];
        [recipientSelection addAction:OWSActionSheets.cancelAction];

        __weak typeof(self) wSelf = self;
        for (SignalServiceAddress *address in thread.recipientAddresses) {
            NSString *name = [self.contactsManager displayNameForAddress:address];
            [recipientSelection
                addAction:[[ActionSheetAction alloc] initWithTitle:name
                                                             style:ActionSheetActionStyleDefault
                                                           handler:^(ActionSheetAction *action) {
                                                               [wSelf updateIdentityVerificationForAddress:address];
                                                           }]];
        }

        [OWSActionSheets showActionSheet:recipientSelection];

    } else {
        [self updateIdentityVerificationForAddress:thread.recipientAddresses.firstObject];
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

    [OWSActionSheets showActionSheet:stateSelection];
}

@end

NS_ASSUME_NONNULL_END

#endif
