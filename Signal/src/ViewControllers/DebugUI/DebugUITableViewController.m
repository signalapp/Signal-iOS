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

    DebugUITableViewController *viewController = [DebugUITableViewController new];
    viewController.contents = contents;
    [viewController presentFromViewController:fromViewController];
}

@end

NS_ASSUME_NONNULL_END
