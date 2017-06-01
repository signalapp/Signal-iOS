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

+ (void)presentDebugUIForThread:(TSThread *)thread fromViewController:(UIViewController *)fromViewController
{
    OWSAssert(thread);
    OWSAssert(fromViewController);

    OWSTableContents *contents = [OWSTableContents new];
    contents.title = @"Debug: Conversation";

    [contents addSection:[DebugUIMessages sectionForThread:thread]];

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
                                      [OWSTableItem
                                          itemWithTitle:@"Delete session (Contact Thread Only)"
                                            actionBlock:^{
                                                if (![thread isKindOfClass:[TSContactThread class]]) {
                                                    DDLogError(@"Refusing to delete session for group thread.");
                                                    OWSAssert(NO);
                                                    return;
                                                }
                                                TSContactThread *contactThread = (TSContactThread *)thread;
                                                dispatch_async([OWSDispatch sessionStoreQueue], ^{
                                                    [[TSStorageManager sharedManager]
                                                        deleteAllSessionsForContact:contactThread.contactIdentifier];
                                                });
                                            }],
                                      [OWSTableItem
                                          itemWithTitle:@"Send session reset (Contact Thread Only)"
                                            actionBlock:^{
                                                if (![thread isKindOfClass:[TSContactThread class]]) {
                                                    DDLogError(@"Refusing to reset session for group thread.");
                                                    OWSAssert(NO);
                                                    return;
                                                }
                                                TSContactThread *contactThread = (TSContactThread *)thread;
                                                [OWSSessionResetJob
                                                    runWithContactThread:contactThread
                                                           messageSender:[Environment getCurrent].messageSender
                                                          storageManager:[TSStorageManager sharedManager]];
                                            }]
                                  ]]];

    [contents addSection:[DebugUIContacts section]];

    // After enqueing the notification you may want to background the app or lock the screen before it triggers, so we
    // give a little delay.
    uint64_t notificationDelay = 5;
    [contents
        addSection:[OWSTableSection
                       sectionWithTitle:[NSString stringWithFormat:@"Call Notifications (%llu second delay)",
                                                  notificationDelay]
                                  items:@[
                                      [OWSTableItem itemWithTitle:@"Missed Call"
                                                      actionBlock:^{
                                                          SignalCall *call = [SignalCall
                                                              incomingCallWithLocalId:[NSUUID new]
                                                                    remotePhoneNumber:thread.contactIdentifier
                                                                          signalingId:0];

                                                          dispatch_after(
                                                              dispatch_time(DISPATCH_TIME_NOW,
                                                                  (int64_t)(notificationDelay * NSEC_PER_SEC)),
                                                              dispatch_get_main_queue(),
                                                              ^{
                                                                  [[Environment getCurrent]
                                                                          .callService.notificationsAdapter
                                                                      presentMissedCall:call
                                                                             callerName:thread.name];
                                                              });
                                                      }],
                                      [OWSTableItem
                                          itemWithTitle:@"Rejected Call with Unseen Safety Number"
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
                                                            presentRejectedCallWithUnseenIdentityChange:call
                                                                                             callerName:thread.name];
                                                    });
                                            }],
                                  ]]];

    DebugUITableViewController *viewController = [DebugUITableViewController new];
    viewController.contents = contents;
    [viewController presentFromViewController:fromViewController];
}

@end

NS_ASSUME_NONNULL_END
