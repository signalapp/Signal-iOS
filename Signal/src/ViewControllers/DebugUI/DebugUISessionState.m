//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "DebugUISessionState.h"
#import "OWSTableViewController.h"
#import "Signal-Swift.h"
#import <SignalServiceKit/OWSIdentityManager.h>
#import <SignalServiceKit/OWSSessionStorage+SessionStore.h>
#import <SignalServiceKit/TSContactThread.h>

NS_ASSUME_NONNULL_BEGIN

@implementation DebugUISessionState

- (NSString *)name
{
    return @"Session State";
}

- (nullable OWSTableSection *)sectionForThread:(nullable TSThread *)threadParameter
{
    OWSAssert([threadParameter isKindOfClass:[TSContactThread class]]);

    TSContactThread *thread = (TSContactThread *)threadParameter;

    return [OWSTableSection
        sectionWithTitle:self.name
                   items:@[
                       [OWSTableItem itemWithTitle:@"Log All Recipient Identities"
                                       actionBlock:^{
                                           [OWSRecipientIdentity printAllIdentities];
                                       }],
                       [OWSTableItem itemWithTitle:@"Log All Sessions"
                                       actionBlock:^{
                                           dispatch_async([OWSDispatch sessionStoreQueue], ^{
                                               [[OWSSessionStorage sharedManager] printAllSessions];
                                           });
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
                       [OWSTableItem itemWithTitle:@"Set Verification State"
                                       actionBlock:^{
                                           [DebugUISessionState presentVerificationStatePickerForContactThread:thread];
                                       }],
                       [OWSTableItem itemWithTitle:@"Delete all sessions"
                                       actionBlock:^{
                                           dispatch_async([OWSDispatch sessionStoreQueue], ^{
                                               [[OWSSessionStorage sharedManager]
                                                   deleteAllSessionsForContact:thread.contactIdentifier];
                                           });
                                       }],
                       [OWSTableItem itemWithTitle:@"Archive all sessions"
                                       actionBlock:^{
                                           dispatch_async([OWSDispatch sessionStoreQueue], ^{
                                               [[OWSSessionStorage sharedManager]
                                                   archiveAllSessionsForContact:thread.contactIdentifier];
                                           });
                                       }],
                       [OWSTableItem itemWithTitle:@"Send session reset"
                                       actionBlock:^{
                                           [OWSSessionResetJob runWithContactThread:thread
                                                                      messageSender:[Environment current].messageSender
                                                                     sessionStorage:[OWSSessionStorage sharedManager]];
                                       }]
                   ]];
}

+ (void)presentVerificationStatePickerForContactThread:(TSContactThread *)contactThread
{
    DDLogError(@"%@ Choosing verification state.", self.logTag);

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
                                                              isUserInitiatedChange:NO];
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
                                                              isUserInitiatedChange:NO];
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
                                                              isUserInitiatedChange:NO];
                                                      }]];

    [[UIApplication sharedApplication].frontmostViewController presentViewController:alertController
                                                                            animated:YES
                                                                          completion:nil];
}

@end

NS_ASSUME_NONNULL_END
