//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "DebugUITableViewController.h"
#import "DebugUIContacts.h"
#import "DebugUIDiskUsage.h"
#import "DebugUIMessages.h"
#import "DebugUIMisc.h"
#import "DebugUISessionState.h"
#import "Signal-Swift.h"
#import <SignalServiceKit/TSContactThread.h>
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

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    // Block device from sleeping while in the Debug UI.
    //
    // This is useful if you're using long-running actions in the
    // Debug UI, like "send 1k messages", etc.
    [DeviceSleepManager.sharedInstance addBlockWithBlockObject:self];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];

    [DeviceSleepManager.sharedInstance removeBlockWithBlockObject:self];
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

+ (OWSTableItem *)itemForSubsection:(DebugUIPage *)page
                     viewController:(DebugUITableViewController *)viewController
                             thread:(nullable TSThread *)thread
{
    OWSAssert(page);
    OWSAssert(viewController);

    __weak DebugUITableViewController *weakSelf = viewController;
    return [OWSTableItem disclosureItemWithText:page.name
                                    actionBlock:^{
                                        [weakSelf pushPageWithSection:[page sectionForThread:thread]];
                                    }];
}

+ (void)presentDebugUIForThread:(TSThread *)thread fromViewController:(UIViewController *)fromViewController
{
    OWSAssert(thread);
    OWSAssert(fromViewController);

    DebugUITableViewController *viewController = [DebugUITableViewController new];

    OWSTableContents *contents = [OWSTableContents new];
    contents.title = @"Debug: Conversation";

    NSMutableArray<OWSTableItem *> *subsectionItems = [NSMutableArray new];
    [subsectionItems
        addObject:[self itemForSubsection:[DebugUIMessages new] viewController:viewController thread:thread]];
    [subsectionItems
        addObject:[self itemForSubsection:[DebugUIContacts new] viewController:viewController thread:thread]];
    [subsectionItems
        addObject:[self itemForSubsection:[DebugUIDiskUsage new] viewController:viewController thread:thread]];
    if ([thread isKindOfClass:[TSContactThread class]]) {
        [subsectionItems
            addObject:[self itemForSubsection:[DebugUISessionState new] viewController:viewController thread:thread]];
    }
    [subsectionItems addObject:[self itemForSubsection:[DebugUIMisc new] viewController:viewController thread:thread]];

    [contents addSection:[OWSTableSection sectionWithTitle:@"Sections" items:subsectionItems]];

    if ([thread isKindOfClass:[TSContactThread class]]) {
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

    viewController.contents = contents;
    [viewController presentFromViewController:fromViewController];
}

+ (void)presentDebugUIFromViewController:(UIViewController *)fromViewController
{
    OWSAssert(fromViewController);

    DebugUITableViewController *viewController = [DebugUITableViewController new];

    OWSTableContents *contents = [OWSTableContents new];
    contents.title = @"Debug UI";

    NSMutableArray<OWSTableItem *> *subsectionItems = [NSMutableArray new];
    [subsectionItems addObject:[self itemForSubsection:[DebugUIContacts new] viewController:viewController thread:nil]];
    [subsectionItems
        addObject:[self itemForSubsection:[DebugUIDiskUsage new] viewController:viewController thread:nil]];
    [contents addSection:[OWSTableSection sectionWithTitle:@"Sections" items:subsectionItems]];

    viewController.contents = contents;
    [viewController presentFromViewController:fromViewController];
}

@end

NS_ASSUME_NONNULL_END
