//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "SignalsViewController.h"
#import "AppDelegate.h"
#import "InboxTableViewCell.h"
#import "MessageComposeTableViewController.h"
#import "MessagesViewController.h"
#import "NSDate+millisecondTimeStamp.h"
#import "OWSContactsManager.h"
#import "PropertyListPreferences.h"
#import "PushManager.h"
#import "Signal-Swift.h"
#import "TSAccountManager.h"
#import "TSDatabaseView.h"
#import "TSGroupThread.h"
#import "TSStorageManager.h"
#import "UIUtil.h"
#import "VersionMigrations.h"
#import <PromiseKit/AnyPromise.h>
#import <SignalServiceKit/OWSBlockingManager.h>
#import <SignalServiceKit/OWSDisappearingMessagesJob.h>
#import <SignalServiceKit/OWSMessageSender.h>
#import <SignalServiceKit/TSMessagesManager.h>
#import <SignalServiceKit/TSOutgoingMessage.h>
#import <YapDatabase/YapDatabaseViewChange.h>
#import <YapDatabase/YapDatabaseViewConnection.h>

#define CELL_HEIGHT 72.0f
#define HEADER_HEIGHT 44.0f

NSString *const SignalsViewControllerSegueShowIncomingCall = @"ShowIncomingCallSegue";

@interface SignalsViewController ()

@property (nonatomic) YapDatabaseConnection *editingDbConnection;
@property (nonatomic) YapDatabaseConnection *uiDatabaseConnection;
@property (nonatomic) YapDatabaseViewMappings *threadMappings;
@property (nonatomic) CellState viewingThreadsIn;
@property (nonatomic) long inboxCount;
@property (nonatomic) UISegmentedControl *segmentedControl;
@property (nonatomic) id previewingContext;
@property (nonatomic) NSSet<NSString *> *blockedPhoneNumberSet;

// Dependencies

@property (nonatomic, readonly) AccountManager *accountManager;
@property (nonatomic, readonly) OWSContactsManager *contactsManager;
@property (nonatomic, readonly) ExperienceUpgradeFinder *experienceUpgradeFinder;
@property (nonatomic, readonly) TSMessagesManager *messagesManager;
@property (nonatomic, readonly) OWSMessageSender *messageSender;
@property (nonatomic, readonly) OWSBlockingManager *blockingManager;

// Views

@property (weak, nonatomic) IBOutlet ReminderView *missingContactsPermissionView;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *hideMissingContactsPermissionViewConstraint;

@end

@implementation SignalsViewController

#pragma mark - Init

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    [self commonInit];

    return self;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (!self) {
        return self;
    }

    [self commonInit];

    return self;
}

- (void)commonInit
{
    _accountManager = [Environment getCurrent].accountManager;
    _contactsManager = [Environment getCurrent].contactsManager;
    _messagesManager = [TSMessagesManager sharedManager];
    _messageSender = [Environment getCurrent].messageSender;
    _blockingManager = [OWSBlockingManager sharedManager];
    _blockedPhoneNumberSet = [NSSet setWithArray:[_blockingManager blockedPhoneNumbers]];

    _experienceUpgradeFinder = [ExperienceUpgradeFinder new];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(blockedPhoneNumbersDidChange:)
                                                 name:kNSNotificationName_BlockedPhoneNumbersDidChange
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(signalAccountsDidChange:)
                                                 name:OWSContactsManagerSignalAccountsDidChangeNotification
                                               object:nil];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Notifications

- (void)blockedPhoneNumbersDidChange:(id)notification
{
    dispatch_async(dispatch_get_main_queue(), ^{
        _blockedPhoneNumberSet = [NSSet setWithArray:[_blockingManager blockedPhoneNumbers]];
        
        [self.tableView reloadData];
    });
}

- (void)signalAccountsDidChange:(id)notification
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.tableView reloadData];
    });
}

#pragma mark - View Life Cycle

- (void)awakeFromNib
{
    [super awakeFromNib];
    [[Environment getCurrent] setSignalsViewController:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.navigationController.navigationBar setTranslucent:NO];

    [self tableViewSetUp];

    self.editingDbConnection = TSStorageManager.sharedManager.newDatabaseConnection;

    [self.uiDatabaseConnection beginLongLivedReadTransaction];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(yapDatabaseModified:)
                                                 name:TSUIDatabaseConnectionDidUpdateNotification
                                               object:nil];
    [self selectedInbox:self];

    self.segmentedControl = [[UISegmentedControl alloc] initWithItems:@[
        NSLocalizedString(@"WHISPER_NAV_BAR_TITLE", nil),
        NSLocalizedString(@"ARCHIVE_NAV_BAR_TITLE", nil)
    ]];

    [self.segmentedControl addTarget:self
                              action:@selector(swappedSegmentedControl)
                    forControlEvents:UIControlEventValueChanged];
    UINavigationItem *navigationItem = self.navigationItem;
    navigationItem.titleView = self.segmentedControl;
    [self.segmentedControl setSelectedSegmentIndex:0];
    navigationItem.leftBarButtonItem.accessibilityLabel = NSLocalizedString(
        @"SETTINGS_BUTTON_ACCESSIBILITY", @"Accessibility hint for the settings button");


    self.missingContactsPermissionView.text = NSLocalizedString(@"INBOX_VIEW_MISSING_CONTACTS_PERMISSION",
        @"Multiline label explaining how to show names instead of phone numbers in your inbox");
    self.missingContactsPermissionView.tapAction = ^{
        [[UIApplication sharedApplication] openSystemSettings];
    };
    // Should only have to do this once per load (e.g. vs did appear) since app restarts when permissions change.
    self.hideMissingContactsPermissionViewConstraint.active = !self.shouldShowMissingContactsPermissionView;


    if ([self.traitCollection respondsToSelector:@selector(forceTouchCapability)] &&
        (self.traitCollection.forceTouchCapability == UIForceTouchCapabilityAvailable)) {
        [self registerForPreviewingWithDelegate:self sourceView:self.tableView];
    }
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleActiveCallNotification:)
                                                 name:[CallService callServiceActiveCallNotificationName]
                                               object:nil];
    
    [self updateBarButtonItems];
}

- (void)updateBarButtonItems {
    const CGFloat kBarButtonSize = 44;
    if (YES) {
        // We use UIButtons with [UIBarButtonItem initWithCustomView:...] instead of
        // UIBarButtonItem in order to ensure that these buttons are spaced tightly.
        // The contents of the navigation bar are cramped in this view.
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        UIImage *image = [UIImage imageNamed:@"button_settings_white"];
        [button setImage:image
                forState:UIControlStateNormal];
        UIEdgeInsets imageEdgeInsets = UIEdgeInsetsZero;
        // We normally would want to use left and right insets that ensure the button
        // is square and the icon is centered.  However UINavigationBar doesn't offer us
        // control over the margins and spacing of its content, and the buttons end up
        // too far apart and too far from the edge of the screen. So we use a smaller
        // left inset tighten up the layout.
        imageEdgeInsets.right = round((kBarButtonSize - image.size.width) * 0.5f);
        imageEdgeInsets.left = round((kBarButtonSize - (image.size.width + imageEdgeInsets.right)) * 0.5f);
        imageEdgeInsets.top = round((kBarButtonSize - image.size.height) * 0.5f);
        imageEdgeInsets.bottom = round(kBarButtonSize - (image.size.height + imageEdgeInsets.top));
        button.imageEdgeInsets = imageEdgeInsets;
        button.accessibilityLabel = NSLocalizedString(@"OPEN_SETTINGS_BUTTON", "Label for button which opens the settings UI");
        [button addTarget:self
                   action:@selector(settingsButtonPressed:)
             forControlEvents:UIControlEventTouchUpInside];
        button.frame = CGRectMake(0, 0,
                                  round(image.size.width + imageEdgeInsets.left + imageEdgeInsets.right),
                                  round(image.size.height + imageEdgeInsets.top + imageEdgeInsets.bottom));
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:button];
    }
}

- (void)settingsButtonPressed:(id)sender {
    [self performSegueWithIdentifier:@"ShowAppSettingsSegue" sender:sender];
}

- (UIViewController *)previewingContext:(id<UIViewControllerPreviewing>)previewingContext
              viewControllerForLocation:(CGPoint)location {
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:location];

    if (indexPath) {
        [previewingContext setSourceRect:[self.tableView rectForRowAtIndexPath:indexPath]];

        MessagesViewController *vc = [MessagesViewController new];
        TSThread *thread           = [self threadForIndexPath:indexPath];
        [vc configureForThread:thread keyboardOnViewAppearing:NO callOnViewAppearing:NO];
        [vc peekSetup];

        return vc;
    } else {
        return nil;
    }
}

- (void)handleActiveCallNotification:(NSNotification *)notification
{
    AssertIsOnMainThread();
    
    if (![notification.object isKindOfClass:[SignalCall class]]) {
        DDLogError(@"%@ expected presentCall observer to be notified with a SignalCall, but found %@",
                   self.tag,
                   notification.object);
        return;
    }
    
    SignalCall *call = (SignalCall *)notification.object;
    
    // Dismiss any other modals so we can present call modal.
    if (self.presentedViewController) {
        [self dismissViewControllerAnimated:YES
                                 completion:^{
            [self performSegueWithIdentifier:SignalsViewControllerSegueShowIncomingCall sender:call];
        }];
    } else {
        [self performSegueWithIdentifier:SignalsViewControllerSegueShowIncomingCall sender:call];
    }
}

- (void)previewingContext:(id<UIViewControllerPreviewing>)previewingContext
     commitViewController:(UIViewController *)viewControllerToCommit {
    MessagesViewController *vc = (MessagesViewController *)viewControllerToCommit;
    [vc popped];

    [self.navigationController pushViewController:vc animated:NO];
}

- (IBAction)composeNew
{
    MessageComposeTableViewController *viewController = [MessageComposeTableViewController new];

    [self.contactsManager requestSystemContactsOnceWithCompletion:^(NSError *_Nullable error) {
        if (error) {
            DDLogError(@"%@ Error when requesting contacts: %@", self.tag, error);
        }
        // Even if there is an error fetching contacts we proceed to the next screen.
        // As the compose view will present the proper thing depending on contact access.
        //
        // We just want to make sure contact access is *complete* before showing the compose
        // screen to avoid flicker.
        UINavigationController *navigationController =
            [[UINavigationController alloc] initWithRootViewController:viewController];
        [self presentTopLevelModalViewController:navigationController animateDismissal:YES animatePresentation:YES];
    }];
}

- (void)swappedSegmentedControl {
    if (self.segmentedControl.selectedSegmentIndex == 0) {
        [self selectedInbox:nil];
    } else {
        [self selectedArchive:nil];
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self checkIfEmptyView];
    if ([TSThread numberOfKeysInCollection] > 0) {
        [self.contactsManager requestSystemContactsOnce];
    }
    [self updateInboxCountLabel];
    [[self tableView] reloadData];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.newlyRegisteredUser) {
        [self.editingDbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction * _Nonnull transaction) {
            [self.experienceUpgradeFinder markAllAsSeenWithTransaction:transaction];
        }];
        [self ensureNotificationsUpToDate];

        // Clean up any messages that expired since last launch immediately
        // and continue cleaning in the background.
        [[OWSDisappearingMessagesJob sharedJob] startIfNecessary];
    } else {
        [self displayAnyUnseenUpgradeExperience];
    }
}

#pragma mark - startup

- (void)displayAnyUnseenUpgradeExperience
{
    AssertIsOnMainThread();

    __block NSArray<ExperienceUpgrade *> *unseenUpgrades;
    [self.editingDbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        unseenUpgrades = [self.experienceUpgradeFinder allUnseenWithTransaction:transaction];
    }];

    if (unseenUpgrades.count > 0) {
        ExperienceUpgradesPageViewController *experienceUpgradeViewController = [[ExperienceUpgradesPageViewController alloc] initWithExperienceUpgrades:unseenUpgrades];
        [self presentViewController:experienceUpgradeViewController animated:YES completion:^{
            [self.editingDbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction * _Nonnull transaction) {
                [self.experienceUpgradeFinder markAllAsSeenWithTransaction:transaction];
            }];
        }];
    }
}

- (void)ensureNotificationsUpToDate
{
    [OWSSyncPushTokensJob runWithPushManager:[PushManager sharedManager]
                              accountManager:self.accountManager
                                 preferences:[Environment preferences]
                                  showAlerts:NO];
}

- (void)tableViewSetUp {
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
}

- (BOOL)shouldShowMissingContactsPermissionView
{
    if ([TSContactThread numberOfKeysInCollection] == 0) {
        return NO;
    }

    return !self.contactsManager.isSystemContactsAuthorized;
}

#pragma mark - Table View Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return (NSInteger)[self.threadMappings numberOfSections];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)[self.threadMappings numberOfItemsInSection:(NSUInteger)section];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    InboxTableViewCell *cell =
        [self.tableView dequeueReusableCellWithIdentifier:NSStringFromClass([InboxTableViewCell class])];
    TSThread *thread = [self threadForIndexPath:indexPath];

    if (!cell) {
        cell = [InboxTableViewCell inboxTableViewCell];
    }

    [cell configureWithThread:thread contactsManager:self.contactsManager blockedPhoneNumberSet:_blockedPhoneNumberSet];

    if ((unsigned long)indexPath.row == [self.threadMappings numberOfItemsInSection:0] - 1) {
        cell.separatorInset = UIEdgeInsetsMake(0.f, cell.bounds.size.width, 0.f, 0.f);
    }

    return cell;
}

- (TSThread *)threadForIndexPath:(NSIndexPath *)indexPath {
    __block TSThread *thread = nil;
    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
      thread = [[transaction extension:TSThreadDatabaseViewExtensionName] objectAtIndexPath:indexPath
                                                                               withMappings:self.threadMappings];
    }];

    return thread;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return CELL_HEIGHT;
}

#pragma mark Table Swipe to Delete

- (void)tableView:(UITableView *)tableView
    commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
     forRowAtIndexPath:(NSIndexPath *)indexPath {
    return;
}


- (NSArray *)tableView:(UITableView *)tableView editActionsForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewRowAction *deleteAction =
        [UITableViewRowAction rowActionWithStyle:UITableViewRowActionStyleDefault
                                           title:NSLocalizedString(@"TXT_DELETE_TITLE", nil)
                                         handler:^(UITableViewRowAction *action, NSIndexPath *swipedIndexPath) {
                                           [self tableViewCellTappedDelete:swipedIndexPath];
                                         }];

    UITableViewRowAction *archiveAction;
    if (self.viewingThreadsIn == kInboxState) {
        archiveAction = [UITableViewRowAction
            rowActionWithStyle:UITableViewRowActionStyleNormal
                         title:NSLocalizedString(@"ARCHIVE_ACTION", @"Pressing this button moves a thread from the inbox to the archive")
                       handler:^(UITableViewRowAction *_Nonnull action, NSIndexPath *_Nonnull tappedIndexPath) {
                         [self archiveIndexPath:tappedIndexPath];
                         [Environment.preferences setHasArchivedAMessage:YES];
                       }];

    } else {
        archiveAction = [UITableViewRowAction
            rowActionWithStyle:UITableViewRowActionStyleNormal
                         title:NSLocalizedString(@"UNARCHIVE_ACTION", @"Pressing this button moves an archived thread from the archive back to the inbox")
                       handler:^(UITableViewRowAction *_Nonnull action, NSIndexPath *_Nonnull tappedIndexPath) {
                         [self archiveIndexPath:tappedIndexPath];
                       }];
    }


    return @[ deleteAction, archiveAction ];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

#pragma mark - HomeFeedTableViewCellDelegate

- (void)tableViewCellTappedDelete:(NSIndexPath *)indexPath {
    TSThread *thread = [self threadForIndexPath:indexPath];
    if ([thread isKindOfClass:[TSGroupThread class]]) {

        TSGroupThread *gThread = (TSGroupThread *)thread;
        if ([gThread.groupModel.groupMemberIds containsObject:[TSAccountManager localNumber]]) {
            UIAlertController *removingFromGroup = [UIAlertController
                                                    alertControllerWithTitle:[NSString
                                                                              stringWithFormat:NSLocalizedString(@"GROUP_REMOVING", nil), [thread name]]
                                                    message:nil
                                                    preferredStyle:UIAlertControllerStyleAlert];
            [self presentViewController:removingFromGroup animated:YES completion:nil];

            TSOutgoingMessage *message = [[TSOutgoingMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                                             inThread:thread
                                                                     groupMetaMessage:TSGroupMessageQuit];
            [self.messageSender sendMessage:message
                success:^{
                    [self dismissViewControllerAnimated:YES
                                             completion:^{
                                                 [self deleteThread:thread];
                                             }];
                }
                failure:^(NSError *error) {
                    [self dismissViewControllerAnimated:YES
                                             completion:^{
                                                 [OWSAlerts
                                                     showAlertWithTitle:
                                                         NSLocalizedString(@"GROUP_REMOVING_FAILED",
                                                             @"Title of alert indicating that group deletion failed.")
                                                                message:error.localizedRecoverySuggestion];
                                             }];
                }];
        } else {
            [self deleteThread:thread];
        }
    } else {
        [self deleteThread:thread];
    }
}

- (void)deleteThread:(TSThread *)thread {
    [self.editingDbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
      [thread removeWithTransaction:transaction];
    }];

    _inboxCount -= (self.viewingThreadsIn == kArchiveState) ? 1 : 0;
    [self checkIfEmptyView];
}

- (void)archiveIndexPath:(NSIndexPath *)indexPath {
    TSThread *thread = [self threadForIndexPath:indexPath];

    BOOL viewingThreadsIn = self.viewingThreadsIn;
    [self.editingDbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
      viewingThreadsIn == kInboxState ? [thread archiveThreadWithTransaction:transaction]
                                      : [thread unarchiveThreadWithTransaction:transaction];

    }];
    [self checkIfEmptyView];
}

- (NSNumber *)updateInboxCountLabel {
    NSUInteger numberOfItems = [self.messagesManager unreadMessagesCount];
    NSNumber *badgeNumber    = [NSNumber numberWithUnsignedInteger:numberOfItems];
    NSString *unreadString   = NSLocalizedString(@"WHISPER_NAV_BAR_TITLE", nil);

    if (![badgeNumber isEqualToNumber:@0]) {
        NSString *badgeValue = [badgeNumber stringValue];
        unreadString         = [unreadString stringByAppendingFormat:@" (%@)", badgeValue];
    }

    [_segmentedControl setTitle:unreadString forSegmentAtIndex:0];
    [_segmentedControl.superview setNeedsLayout];
    [_segmentedControl reloadInputViews];
    [[UIApplication sharedApplication] setApplicationIconBadgeNumber:badgeNumber.integerValue];

    return badgeNumber;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    TSThread *thread = [self threadForIndexPath:indexPath];
    [self presentThread:thread keyboardOnViewAppearing:NO callOnViewAppearing:NO];
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (void)presentThread:(TSThread *)thread
    keyboardOnViewAppearing:(BOOL)keyboardOnViewAppearing
        callOnViewAppearing:(BOOL)callOnViewAppearing
{
    dispatch_async(dispatch_get_main_queue(), ^{
        MessagesViewController *mvc = [[MessagesViewController alloc] initWithNibName:@"MessagesViewController"
                                                                               bundle:nil];
        [mvc configureForThread:thread
            keyboardOnViewAppearing:keyboardOnViewAppearing
                callOnViewAppearing:callOnViewAppearing];

        if (self.presentedViewController) {
            [self.presentedViewController dismissViewControllerAnimated:YES completion:nil];
        }
        [self.navigationController popToRootViewControllerAnimated:YES];
        [self.navigationController pushViewController:mvc animated:YES];
    });
}

- (void)presentTopLevelModalViewController:(UIViewController *)viewController
                          animateDismissal:(BOOL)animateDismissal
                       animatePresentation:(BOOL)animatePresentation
{
    OWSAssert([NSThread isMainThread]);
    OWSAssert(viewController);

    [self presentViewControllerWithBlock:^{
        [self presentViewController:viewController animated:animatePresentation completion:nil];
    }
                        animateDismissal:animateDismissal];
}

- (void)pushTopLevelViewController:(UIViewController *)viewController
                  animateDismissal:(BOOL)animateDismissal
               animatePresentation:(BOOL)animatePresentation
{
    OWSAssert([NSThread isMainThread]);
    OWSAssert(viewController);

    [self presentViewControllerWithBlock:^{
        [self.navigationController pushViewController:viewController animated:animatePresentation];
    }
                        animateDismissal:animateDismissal];
}

- (void)presentViewControllerWithBlock:(void (^)())presentationBlock animateDismissal:(BOOL)animateDismissal
{
    OWSAssert([NSThread isMainThread]);
    OWSAssert(presentationBlock);

    // Presenting a "top level" view controller has three steps:
    //
    // First, dismiss any presented modal.
    // Second, pop to the root view controller if necessary.
    // Third present the new view controller using presentationBlock.

    // Define a block to perform the second step.
    void (^dismissNavigationBlock)() = ^{
        if (self.navigationController.viewControllers.lastObject != self) {
            [CATransaction begin];
            [CATransaction setCompletionBlock:^{
                presentationBlock();
            }];

            [self.navigationController popToViewController:self animated:animateDismissal];

            [CATransaction commit];
        } else {
            presentationBlock();
        }
    };

    // Perform the first step.
    if (self.presentedViewController) {
        [self.presentedViewController dismissViewControllerAnimated:animateDismissal completion:dismissNavigationBlock];
    } else {
        dismissNavigationBlock();
    }
}

#pragma mark - Navigation

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if ([segue.identifier isEqualToString:SignalsViewControllerSegueShowIncomingCall]) {
        DDLogDebug(@"%@ preparing for incoming call segue", self.tag);
        if (![segue.destinationViewController isKindOfClass:[OWSCallViewController class]]) {
            DDLogError(@"%@ Received unexpected destination view controller: %@", self.tag, segue.destinationViewController);
            return;
        }
        OWSCallViewController *callViewController = (OWSCallViewController *)segue.destinationViewController;

        if (![sender isKindOfClass:[SignalCall class]]) {
            DDLogError(@"%@ expecting call segueu to be sent by a SignalCall, but found: %@", self.tag, sender);
            return;
        }
        SignalCall *call = (SignalCall *)sender;
        TSContactThread *thread = [TSContactThread getOrCreateThreadWithContactId:call.remotePhoneNumber];
        callViewController.thread = thread;
        callViewController.call = call;
    }
}

#pragma mark - IBAction

- (IBAction)selectedInbox:(id)sender {
    self.viewingThreadsIn = kInboxState;
    [self changeToGrouping:TSInboxGroup];
}

- (IBAction)selectedArchive:(id)sender {
    self.viewingThreadsIn = kArchiveState;
    [self changeToGrouping:TSArchiveGroup];
}

- (void)changeToGrouping:(NSString *)grouping {
    self.threadMappings =
        [[YapDatabaseViewMappings alloc] initWithGroups:@[ grouping ] view:TSThreadDatabaseViewExtensionName];
    [self.threadMappings setIsReversed:YES forGroup:grouping];

    [self.uiDatabaseConnection asyncReadWithBlock:^(YapDatabaseReadTransaction *transaction) {
      [self.threadMappings updateWithTransaction:transaction];

      dispatch_async(dispatch_get_main_queue(), ^{
        [self.tableView reloadData];
        [self checkIfEmptyView];
      });
    }];
}

#pragma mark Database delegates

- (YapDatabaseConnection *)uiDatabaseConnection {
    NSAssert([NSThread isMainThread], @"Must access uiDatabaseConnection on main thread!");
    if (!_uiDatabaseConnection) {
        YapDatabase *database = TSStorageManager.sharedManager.database;
        _uiDatabaseConnection = [database newConnection];
        [_uiDatabaseConnection beginLongLivedReadTransaction];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(yapDatabaseModified:)
                                                     name:YapDatabaseModifiedNotification
                                                   object:database];
    }
    return _uiDatabaseConnection;
}

- (void)yapDatabaseModified:(NSNotification *)notification {
    NSArray *notifications  = [self.uiDatabaseConnection beginLongLivedReadTransaction];
    NSArray *sectionChanges = nil;
    NSArray *rowChanges     = nil;

    // If the user hasn't already granted contact access
    // we don't want to request until they receive a message.
    if ([TSThread numberOfKeysInCollection] > 0) {
        [self.contactsManager requestSystemContactsOnce];
    }

    [[self.uiDatabaseConnection ext:TSThreadDatabaseViewExtensionName] getSectionChanges:&sectionChanges
                                                                              rowChanges:&rowChanges
                                                                        forNotifications:notifications
                                                                            withMappings:self.threadMappings];

    // We want this regardless of if we're currently viewing the archive.
    // So we run it before the early return
    [self updateInboxCountLabel];

    if ([sectionChanges count] == 0 && [rowChanges count] == 0) {
        return;
    }

    [self.tableView beginUpdates];

    for (YapDatabaseViewSectionChange *sectionChange in sectionChanges) {
        switch (sectionChange.type) {
            case YapDatabaseViewChangeDelete: {
                [self.tableView deleteSections:[NSIndexSet indexSetWithIndex:sectionChange.index]
                              withRowAnimation:UITableViewRowAnimationAutomatic];
                break;
            }
            case YapDatabaseViewChangeInsert: {
                [self.tableView insertSections:[NSIndexSet indexSetWithIndex:sectionChange.index]
                              withRowAnimation:UITableViewRowAnimationAutomatic];
                break;
            }
            case YapDatabaseViewChangeUpdate:
            case YapDatabaseViewChangeMove:
                break;
        }
    }

    for (YapDatabaseViewRowChange *rowChange in rowChanges) {
        switch (rowChange.type) {
            case YapDatabaseViewChangeDelete: {
                [self.tableView deleteRowsAtIndexPaths:@[ rowChange.indexPath ]
                                      withRowAnimation:UITableViewRowAnimationAutomatic];
                _inboxCount += (self.viewingThreadsIn == kArchiveState) ? 1 : 0;
                break;
            }
            case YapDatabaseViewChangeInsert: {
                [self.tableView insertRowsAtIndexPaths:@[ rowChange.newIndexPath ]
                                      withRowAnimation:UITableViewRowAnimationAutomatic];
                _inboxCount -= (self.viewingThreadsIn == kArchiveState) ? 1 : 0;
                break;
            }
            case YapDatabaseViewChangeMove: {
                [self.tableView deleteRowsAtIndexPaths:@[ rowChange.indexPath ]
                                      withRowAnimation:UITableViewRowAnimationAutomatic];
                [self.tableView insertRowsAtIndexPaths:@[ rowChange.newIndexPath ]
                                      withRowAnimation:UITableViewRowAnimationAutomatic];
                break;
            }
            case YapDatabaseViewChangeUpdate: {
                [self.tableView reloadRowsAtIndexPaths:@[ rowChange.indexPath ]
                                      withRowAnimation:UITableViewRowAnimationNone];
                break;
            }
        }
    }

    [self.tableView endUpdates];
    [self checkIfEmptyView];
}


- (IBAction)unwindSettingsDone:(UIStoryboardSegue *)segue {
}

- (IBAction)unwindMessagesView:(UIStoryboardSegue *)segue {
}

- (void)checkIfEmptyView {
    [_tableView setHidden:NO];
    [_emptyBoxLabel setHidden:NO];
    if (self.viewingThreadsIn == kInboxState && [self.threadMappings numberOfItemsInGroup:TSInboxGroup] == 0) {
        [self setEmptyBoxText];
        [_tableView setHidden:YES];
    } else if (self.viewingThreadsIn == kArchiveState &&
               [self.threadMappings numberOfItemsInGroup:TSArchiveGroup] == 0) {
        [self setEmptyBoxText];
        [_tableView setHidden:YES];
    } else {
        [_emptyBoxLabel setHidden:YES];
    }
}

- (void)setEmptyBoxText {
    _emptyBoxLabel.textColor     = [UIColor grayColor];
    _emptyBoxLabel.font          = [UIFont ows_regularFontWithSize:18.f];
    _emptyBoxLabel.textAlignment = NSTextAlignmentCenter;
    _emptyBoxLabel.numberOfLines = 4;

    NSString *firstLine  = @"";
    NSString *secondLine = @"";

    if (self.viewingThreadsIn == kInboxState) {
        if ([Environment.preferences getHasSentAMessage]) {
            firstLine  = NSLocalizedString(@"EMPTY_INBOX_FIRST_TITLE", @"");
            secondLine = NSLocalizedString(@"EMPTY_INBOX_FIRST_TEXT", @"");
        } else {
            // FIXME This looks wrong. Shouldn't we be showing inbox_title/text here?
            firstLine  = NSLocalizedString(@"EMPTY_ARCHIVE_FIRST_TITLE", @"");
            secondLine = NSLocalizedString(@"EMPTY_ARCHIVE_FIRST_TEXT", @"");
        }
    } else {
        if ([Environment.preferences getHasArchivedAMessage]) {
            // FIXME This looks wrong. Shouldn't we be showing first_archive_title/text here?
            firstLine  = NSLocalizedString(@"EMPTY_INBOX_TITLE", @"");
            secondLine = NSLocalizedString(@"EMPTY_INBOX_TEXT", @"");
        } else {
            firstLine  = NSLocalizedString(@"EMPTY_ARCHIVE_TITLE", @"");
            secondLine = NSLocalizedString(@"EMPTY_ARCHIVE_TEXT", @"");
        }
    }
    NSMutableAttributedString *fullLabelString =
        [[NSMutableAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@\n%@", firstLine, secondLine]];

    [fullLabelString addAttribute:NSFontAttributeName
                            value:[UIFont ows_boldFontWithSize:15.f]
                            range:NSMakeRange(0, firstLine.length)];
    [fullLabelString addAttribute:NSFontAttributeName
                            value:[UIFont ows_regularFontWithSize:14.f]
                            range:NSMakeRange(firstLine.length + 1, secondLine.length)];
    [fullLabelString addAttribute:NSForegroundColorAttributeName
                            value:[UIColor blackColor]
                            range:NSMakeRange(0, firstLine.length)];
    [fullLabelString addAttribute:NSForegroundColorAttributeName
                            value:[UIColor ows_darkGrayColor]
                            range:NSMakeRange(firstLine.length + 1, secondLine.length)];
    _emptyBoxLabel.attributedText = fullLabelString;
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
