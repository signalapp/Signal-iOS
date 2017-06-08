//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "DebugUISessionState.h"
#import "OWSTableViewController.h"
#import "Signal-Swift.h"
#import <SignalServiceKit/OWSIdentityManager.h>
#import <SignalServiceKit/TSContactThread.h>
#import <SignalServiceKit/TSStorageManager+SessionStore.h>

NS_ASSUME_NONNULL_BEGIN

@implementation DebugUISessionState

+ (OWSTableSection *)sectionForContactThread:(TSContactThread *)contactThread
{
    return [OWSTableSection
        sectionWithTitle:@"Session State"
                   items:@[
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
                                           NSString *recipientId = [contactThread contactIdentifier];

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
                       [OWSTableItem itemWithTitle:@"Set Verification State"
                                       actionBlock:^{
                                           [self presentVerificationStatePickerForContactThread:contactThread];
                                       }],
                       [OWSTableItem itemWithTitle:@"Delete all sessions"
                                       actionBlock:^{
                                           dispatch_async([OWSDispatch sessionStoreQueue], ^{
                                               [[TSStorageManager sharedManager]
                                                   deleteAllSessionsForContact:contactThread.contactIdentifier];
                                           });
                                       }],
                       [OWSTableItem itemWithTitle:@"Archive all sessions"
                                       actionBlock:^{
                                           dispatch_async([OWSDispatch sessionStoreQueue], ^{
                                               [[TSStorageManager sharedManager]
                                                   archiveAllSessionsForContact:contactThread.contactIdentifier];
                                           });
                                       }],
                       [OWSTableItem itemWithTitle:@"Send session reset"
                                       actionBlock:^{
                                           [OWSSessionResetJob
                                               runWithContactThread:contactThread
                                                      messageSender:[Environment getCurrent].messageSender
                                                     storageManager:[TSStorageManager sharedManager]];
                                       }]
                   ]];
}

+ (void)presentVerificationStatePickerForContactThread:(TSContactThread *)contactThread
{
    DDLogError(@"%@ Choosing verification state.", self.tag);

    NSString *title = [NSString stringWithFormat:@"Choose verification state for %@", contactThread.name];
    UIAlertController *alertController =
        [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleActionSheet];

    NSString *recipientId = [contactThread contactIdentifier];
    OWSIdentityManager *identityManger = [OWSIdentityManager sharedManager];

    [alertController addAction:[UIAlertAction actionWithTitle:@"Default"
                                                        style:UIAlertActionStyleDefault
                                                      handler:^(UIAlertAction *_Nonnull action) {
                                                          NSData *identityKey =
                                                              [identityManger identityKeyForRecipientId:recipientId];
                                                          [[OWSIdentityManager sharedManager]
                                                              setVerificationState:OWSVerificationStateDefault
                                                                       identityKey:identityKey
                                                                       recipientId:recipientId
                                                                   sendSyncMessage:NO];
                                                      }]];
    [alertController addAction:[UIAlertAction actionWithTitle:@"Verified"
                                                        style:UIAlertActionStyleDefault
                                                      handler:^(UIAlertAction *_Nonnull action) {
                                                          NSData *identityKey =
                                                              [identityManger identityKeyForRecipientId:recipientId];
                                                          [[OWSIdentityManager sharedManager]
                                                              setVerificationState:OWSVerificationStateVerified
                                                                       identityKey:identityKey
                                                                       recipientId:recipientId
                                                                   sendSyncMessage:NO];
                                                      }]];
    [alertController addAction:[UIAlertAction actionWithTitle:@"No Longer Verified"
                                                        style:UIAlertActionStyleDefault
                                                      handler:^(UIAlertAction *_Nonnull action) {
                                                          NSData *identityKey =
                                                              [identityManger identityKeyForRecipientId:recipientId];
                                                          [[OWSIdentityManager sharedManager]
                                                              setVerificationState:OWSVerificationStateNoLongerVerified
                                                                       identityKey:identityKey
                                                                       recipientId:recipientId
                                                                   sendSyncMessage:NO];
                                                      }]];

    [[UIApplication sharedApplication].frontmostViewController presentViewController:alertController
                                                                            animated:YES
                                                                          completion:nil];
}

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end

NS_ASSUME_NONNULL_END
