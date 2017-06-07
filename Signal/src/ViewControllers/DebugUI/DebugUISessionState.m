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
                       [OWSTableItem itemWithTitle:@"Toggle Key Change (Contact Thread Only)"
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
                       [OWSTableItem itemWithTitle:@"Delete session (Contact Thread Only)"
                                       actionBlock:^{
                                           dispatch_async([OWSDispatch sessionStoreQueue], ^{
                                               [[TSStorageManager sharedManager]
                                                   deleteAllSessionsForContact:contactThread.contactIdentifier];
                                           });
                                       }],
                       [OWSTableItem itemWithTitle:@"Send session reset (Contact Thread Only)"
                                       actionBlock:^{
                                           [OWSSessionResetJob
                                               runWithContactThread:contactThread
                                                      messageSender:[Environment getCurrent].messageSender
                                                     storageManager:[TSStorageManager sharedManager]];
                                       }]
                   ]];
}

@end

NS_ASSUME_NONNULL_END
