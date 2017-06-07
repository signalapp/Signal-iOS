//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "DebugUITableViewController.h"
#import "DebugUIContacts.h"
#import "DebugUIMessages.h"
#import "Signal-Swift.h"
#import <SignalServiceKit/TSContactThread.h>
#import <SignalServiceKit/TSStorageManager+SessionStore.h>
#import <SignalServiceKit/TSThread.h>

NS_ASSUME_NONNULL_BEGIN

@implementation DebugUITableViewController

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

#pragma mark - Factory Methods

- (void)pushPageWithSection:(OWSTableSection *)section
{
    DebugUITableViewController *viewController = [DebugUITableViewController new];
    OWSTableContents *contents = [OWSTableContents new];
    contents.title = section.headerTitle;
    [contents addSection:section];
    viewController.contents = contents;
    [self.navigationController pushViewController:viewController animated:YES];
}

+ (void)presentDebugUIForThread:(TSThread *)thread fromViewController:(UIViewController *)fromViewController
{
    OWSAssert(thread);
    OWSAssert(fromViewController);

    DebugUITableViewController *viewController = [DebugUITableViewController new];
    __weak DebugUITableViewController *weakSelf = viewController;

    OWSTableContents *contents = [OWSTableContents new];
    contents.title = @"Debug: Conversation";

    [contents
        addSection:[OWSTableSection
                       sectionWithTitle:[DebugUIMessages sectionForThread:thread].headerTitle
                                  items:@[
                                      [OWSTableItem
                                          disclosureItemWithText:[DebugUIMessages sectionForThread:thread].headerTitle
                                                     actionBlock:^{
                                                         [weakSelf pushPageWithSection:[DebugUIMessages
                                                                                           sectionForThread:thread]];
                                                     }],
                                  ]]];

    if ([thread isKindOfClass:[TSContactThread class]]) {
        TSContactThread *contactThread = (TSContactThread *)thread;

        [contents
            addSection:[OWSTableSection
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
                                                              DDLogError(
                                                                  @"Flipping identity Key. Flip again to return.");

                                                              OWSIdentityManager *identityManager =
                                                                  [OWSIdentityManager sharedManager];
                                                              NSString *recipientId = [contactThread contactIdentifier];

                                                              NSData *currentKey = [identityManager
                                                                  identityKeyForRecipientId:recipientId];
                                                              NSMutableData *flippedKey = [NSMutableData new];
                                                              const char *currentKeyBytes = currentKey.bytes;
                                                              for (NSUInteger i = 0; i < currentKey.length; i++) {
                                                                  const char xorByte = currentKeyBytes[i] ^ 0xff;
                                                                  [flippedKey appendBytes:&xorByte length:1];
                                                              }

                                                              OWSAssert(flippedKey.length == 32);


                                                              [identityManager saveRemoteIdentity:flippedKey
                                                                                      recipientId:recipientId];
                                                          }],
                                          [OWSTableItem
                                              itemWithTitle:@"Delete session (Contact Thread Only)"
                                                actionBlock:^{
                                                    dispatch_async([OWSDispatch sessionStoreQueue], ^{
                                                        [[TSStorageManager sharedManager]
                                                            deleteAllSessionsForContact:contactThread
                                                                                            .contactIdentifier];
                                                    });
                                                }],
                                          [OWSTableItem
                                              itemWithTitle:@"Send session reset (Contact Thread Only)"
                                                actionBlock:^{
                                                    [OWSSessionResetJob
                                                        runWithContactThread:contactThread
                                                               messageSender:[Environment getCurrent].messageSender
                                                              storageManager:[TSStorageManager sharedManager]];
                                                }]
                                      ]]];

        // After enqueing the notification you may want to background the app or lock the screen before it triggers, so
        // we give a little delay.
        uint64_t notificationDelay = 5;
        [contents
            addSection:
                [OWSTableSection
                    sectionWithTitle:[NSString
                                         stringWithFormat:@"Call Notifications (%llu second delay)", notificationDelay]
                               items:@[
                                   [OWSTableItem
                                       itemWithTitle:@"Missed Call"
                                         actionBlock:^{
                                             SignalCall *call =
                                                 [SignalCall incomingCallWithLocalId:[NSUUID new]
                                                                   remotePhoneNumber:thread.contactIdentifier
                                                                         signalingId:0];

                                             dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                                                (int64_t)(notificationDelay * NSEC_PER_SEC)),
                                                 dispatch_get_main_queue(),
                                                 ^{
                                                     [[Environment getCurrent].callService.notificationsAdapter
                                                         presentMissedCall:call
                                                                callerName:thread.name];
                                                 });
                                         }],
                                   [OWSTableItem
                                       itemWithTitle:@"Rejected Call with New Safety Number"
                                         actionBlock:^{
                                             SignalCall *call =
                                                 [SignalCall incomingCallWithLocalId:[NSUUID new]
                                                                   remotePhoneNumber:thread.contactIdentifier
                                                                         signalingId:0];

                                             dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                                                (int64_t)(notificationDelay * NSEC_PER_SEC)),
                                                 dispatch_get_main_queue(),
                                                 ^{
                                                     [[Environment getCurrent].callService.notificationsAdapter
                                                         presentMissedCallBecauseOfNewIdentityWithCall:call
                                                                                            callerName:thread.name];
                                                 });
                                         }],
                                   [OWSTableItem
                                       itemWithTitle:@"Rejected Call with No Longer Verified Safety Number"
                                         actionBlock:^{
                                             SignalCall *call =
                                                 [SignalCall incomingCallWithLocalId:[NSUUID new]
                                                                   remotePhoneNumber:thread.contactIdentifier
                                                                         signalingId:0];

                                             dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                                                (int64_t)(notificationDelay * NSEC_PER_SEC)),
                                                 dispatch_get_main_queue(),
                                                 ^{
                                                     [[Environment getCurrent].callService.notificationsAdapter
                                                         presentMissedCallBecauseOfNoLongerVerifiedIdentityWithCall:call
                                                                                                         callerName:
                                                                                                             thread
                                                                                                                 .name];
                                                 });
                                         }],
                               ]]];
    } // end contact thread section

    [contents addSection:[DebugUIContacts section]];

    viewController.contents = contents;
    [viewController presentFromViewController:fromViewController];
}

@end

NS_ASSUME_NONNULL_END
