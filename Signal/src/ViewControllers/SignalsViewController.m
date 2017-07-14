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
#import "SettingsTableViewController.h"
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

@interface SignalsViewController () <UITableViewDelegate, UITableViewDataSource, UIViewControllerPreviewingDelegate>

@property (nonatomic) UITableView *tableView;
@property (nonatomic) UILabel *emptyBoxLabel;

@property (nonatomic) YapDatabaseConnection *editingDbConnection;
@property (nonatomic) YapDatabaseConnection *uiDatabaseConnection;
@property (nonatomic) YapDatabaseViewMappings *threadMappings;
@property (nonatomic) CellState viewingThreadsIn;
@property (nonatomic) long inboxCount;
@property (nonatomic) UISegmentedControl *segmentedControl;
@property (nonatomic) id previewingContext;
@property (nonatomic) NSSet<NSString *> *blockedPhoneNumberSet;

@property (nonatomic) BOOL isViewVisible;
@property (nonatomic) BOOL isAppInBackground;
@property (nonatomic) BOOL shouldObserveDBModifications;

// Dependencies

@property (nonatomic, readonly) AccountManager *accountManager;
@property (nonatomic, readonly) OWSContactsManager *contactsManager;
@property (nonatomic, readonly) ExperienceUpgradeFinder *experienceUpgradeFinder;
@property (nonatomic, readonly) TSMessagesManager *messagesManager;
@property (nonatomic, readonly) OWSMessageSender *messageSender;
@property (nonatomic, readonly) OWSBlockingManager *blockingManager;

// Views

@property (nonatomic) NSLayoutConstraint *hideArchiveReminderViewConstraint;
@property (nonatomic) NSLayoutConstraint *hideMissingContactsPermissionViewConstraint;

@property (nonatomic) TSThread *lastThread;

@end

#pragma mark -

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
    OWSFail(@"Do not load this from the storyboard.");

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
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationWillEnterForeground:)
                                                 name:UIApplicationWillEnterForegroundNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidEnterBackground:)
                                                 name:UIApplicationDidEnterBackgroundNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(yapDatabaseModified:)
                                                 name:YapDatabaseModifiedNotification
                                               object:nil];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Notifications

- (void)blockedPhoneNumbersDidChange:(id)notification
{
    OWSAssert([NSThread isMainThread]);

    _blockedPhoneNumberSet = [NSSet setWithArray:[_blockingManager blockedPhoneNumbers]];

    [self.tableView reloadData];
}

- (void)signalAccountsDidChange:(id)notification
{
    OWSAssert([NSThread isMainThread]);

    [self.tableView reloadData];
}

#pragma mark - View Life Cycle

- (void)loadView
{
    [super loadView];

    self.view.backgroundColor = [UIColor whiteColor];

    // TODO: Remove this.
    [[Environment getCurrent] setSignalsViewController:self];

    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCompose
                                                      target:self
                                                      action:@selector(composeNew)];

    ReminderView *archiveReminderView = [ReminderView new];
    archiveReminderView.text = NSLocalizedString(
        @"INBOX_VIEW_ARCHIVE_MODE_REMINDER", @"Label reminding the user that they are in archive mode.");
    __weak SignalsViewController *weakSelf = self;
    archiveReminderView.tapAction = ^{
        [weakSelf selectedInbox];
    };
    [self.view addSubview:archiveReminderView];
    [archiveReminderView autoPinWidthToSuperview];
    [archiveReminderView autoPinToTopLayoutGuideOfViewController:self withInset:0];
    self.hideArchiveReminderViewConstraint = [archiveReminderView autoSetDimension:ALDimensionHeight toSize:0];
    self.hideArchiveReminderViewConstraint.priority = UILayoutPriorityRequired;

    ReminderView *missingContactsPermissionView = [ReminderView new];
    missingContactsPermissionView.text = NSLocalizedString(@"INBOX_VIEW_MISSING_CONTACTS_PERMISSION",
        @"Multiline label explaining how to show names instead of phone numbers in your inbox");
    missingContactsPermissionView.tapAction = ^{
        [[UIApplication sharedApplication] openSystemSettings];
    };
    [self.view addSubview:missingContactsPermissionView];
    [missingContactsPermissionView autoPinWidthToSuperview];
    [missingContactsPermissionView autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:archiveReminderView];
    self.hideMissingContactsPermissionViewConstraint =
        [missingContactsPermissionView autoSetDimension:ALDimensionHeight toSize:0];
    self.hideMissingContactsPermissionViewConstraint.priority = UILayoutPriorityRequired;

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    [self.view addSubview:self.tableView];
    [self.tableView autoPinWidthToSuperview];
    [self.tableView autoPinToBottomLayoutGuideOfViewController:self withInset:0];
    [self.tableView autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:missingContactsPermissionView];

    UILabel *emptyBoxLabel = [UILabel new];
    self.emptyBoxLabel = emptyBoxLabel;
    [self.view addSubview:emptyBoxLabel];
    [emptyBoxLabel autoPinWidthToSuperview];
    [emptyBoxLabel autoPinToTopLayoutGuideOfViewController:self withInset:0];
    [emptyBoxLabel autoPinToBottomLayoutGuideOfViewController:self withInset:0];

    [self updateReminderViews];
}

- (void)updateReminderViews
{
    BOOL shouldHideArchiveReminderView = self.viewingThreadsIn != kArchiveState;
    BOOL shouldHideMissingContactsPermissionView = !self.shouldShowMissingContactsPermissionView;
    if (self.hideArchiveReminderViewConstraint.active == shouldHideArchiveReminderView
        && self.hideMissingContactsPermissionViewConstraint.active == shouldHideMissingContactsPermissionView) {
        return;
    }
    self.hideArchiveReminderViewConstraint.active = shouldHideArchiveReminderView;
    self.hideMissingContactsPermissionViewConstraint.active = shouldHideMissingContactsPermissionView;
    [self.view setNeedsLayout];
    [self.view layoutSubviews];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.navigationController.navigationBar setTranslucent:NO];

    [self tableViewSetUp];

    self.editingDbConnection = TSStorageManager.sharedManager.newDatabaseConnection;

    // Create the database connection.
    [self uiDatabaseConnection];

    [self selectedInbox];

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

    if ([self.traitCollection respondsToSelector:@selector(forceTouchCapability)] &&
        (self.traitCollection.forceTouchCapability == UIForceTouchCapabilityAvailable)) {
        [self registerForPreviewingWithDelegate:self sourceView:self.tableView];
    }

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
    SettingsTableViewController *vc = [SettingsTableViewController new];
    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:vc];
    [self presentViewController:navigationController animated:YES completion:nil];
}

- (UIViewController *)previewingContext:(id<UIViewControllerPreviewing>)previewingContext
              viewControllerForLocation:(CGPoint)location {
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:location];

    if (indexPath) {
        [previewingContext setSourceRect:[self.tableView rectForRowAtIndexPath:indexPath]];

        MessagesViewController *vc = [MessagesViewController new];
        TSThread *thread           = [self threadForIndexPath:indexPath];
        self.lastThread = thread;
        [vc configureForThread:thread keyboardOnViewAppearing:NO callOnViewAppearing:NO];
        [vc peekSetup];

        return vc;
    } else {
        return nil;
    }
}

- (void)previewingContext:(id<UIViewControllerPreviewing>)previewingContext
     commitViewController:(UIViewController *)viewControllerToCommit {
    MessagesViewController *vc = (MessagesViewController *)viewControllerToCommit;
    [vc popped];

    [self.navigationController pushViewController:vc animated:NO];
}

- (void)composeNew
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
        [self selectedInbox];
    } else {
        [self selectedArchive];
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if ([TSThread numberOfKeysInCollection] > 0) {
        [self.contactsManager requestSystemContactsOnceWithCompletion:^(NSError *_Nullable error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self updateReminderViews];
            });
        }];
    }

    [self updateInboxCountLabel];

    self.isViewVisible = YES;

    // When returning to home view, try to ensure that the "last" thread is still
    // visible.  The threads often change ordering while in conversation view due
    // to incoming & outgoing messages.
    if (self.lastThread) {
        __block NSIndexPath *indexPathOfLastThread = nil;
        [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
            indexPathOfLastThread =
                [[transaction extension:TSThreadDatabaseViewExtensionName] indexPathForKey:self.lastThread.uniqueId
                                                                              inCollection:[TSThread collection]
                                                                              withMappings:self.threadMappings];
        }];

        if (indexPathOfLastThread) {
            [self.tableView scrollToRowAtIndexPath:indexPathOfLastThread
                                  atScrollPosition:UITableViewScrollPositionNone
                                          animated:NO];
        }
    }

    [self checkIfEmptyView];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];

    self.isViewVisible = NO;
}

- (void)setIsViewVisible:(BOOL)isViewVisible
{
    _isViewVisible = isViewVisible;

    [self updateShouldObserveDBModifications];
}

- (void)setIsAppInBackground:(BOOL)isAppInBackground
{
    _isAppInBackground = isAppInBackground;

    [self updateShouldObserveDBModifications];
}

- (void)updateShouldObserveDBModifications
{
    self.shouldObserveDBModifications = self.isViewVisible && !self.isAppInBackground;
}

- (void)setShouldObserveDBModifications:(BOOL)shouldObserveDBModifications
{
    if (_shouldObserveDBModifications == shouldObserveDBModifications) {
        return;
    }

    _shouldObserveDBModifications = shouldObserveDBModifications;

    if (!self.shouldObserveDBModifications) {
        return;
    }

    // If we're entering "active" mode (e.g. view is visible and app is in foreground),
    // reset all state updated by yapDatabaseModified:.
    if (self.threadMappings != nil) {
        // Before we begin observing database modifications, make sure
        // our mapping and table state is up-to-date.
        //
        // We need to `beginLongLivedReadTransaction` before we update our
        // mapping in order to jump to the most recent commit.
        [self.uiDatabaseConnection beginLongLivedReadTransaction];
        [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
            [self.threadMappings updateWithTransaction:transaction];
        }];
    }

    [[self tableView] reloadData];
    [self checkIfEmptyView];
    [self updateInboxCountLabel];
}

- (void)applicationWillEnterForeground:(NSNotification *)notification
{
    self.isAppInBackground = NO;
    [self checkIfEmptyView];
}

- (void)applicationDidEnterBackground:(NSNotification *)notification
{
    self.isAppInBackground = YES;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    if (self.newlyRegisteredUser) {
        [self.editingDbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction * _Nonnull transaction) {
            [self.experienceUpgradeFinder markAllAsSeenWithTransaction:transaction];
        }];
        [self ensureNotificationsUpToDate];

        // Start running the disappearing messages job in case the newly registered user
        // enables this feature
        [[OWSDisappearingMessagesJob sharedJob] startIfNecessary];
    } else {
        [self displayAnyUnseenUpgradeExperience];
    }
}

#pragma mark - startup

- (NSArray<ExperienceUpgrade *> *)unseenUpgradeExperiences
{
    AssertIsOnMainThread();

    __block NSArray<ExperienceUpgrade *> *unseenUpgrades;
    [self.editingDbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        unseenUpgrades = [self.experienceUpgradeFinder allUnseenWithTransaction:transaction];
    }];
    return unseenUpgrades;
}

- (void)markAllUpgradeExperiencesAsSeen
{
    AssertIsOnMainThread();

    [self.editingDbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
        [self.experienceUpgradeFinder markAllAsSeenWithTransaction:transaction];
    }];
}

- (void)displayAnyUnseenUpgradeExperience
{
    AssertIsOnMainThread();

    NSArray<ExperienceUpgrade *> *unseenUpgrades = [self unseenUpgradeExperiences];

    if (unseenUpgrades.count > 0) {
        ExperienceUpgradesPageViewController *experienceUpgradeViewController = [[ExperienceUpgradesPageViewController alloc] initWithExperienceUpgrades:unseenUpgrades];
        [self presentViewController:experienceUpgradeViewController
                           animated:YES
                         completion:^{
                             [self markAllUpgradeExperiencesAsSeen];
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

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
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
        self.lastThread = thread;

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

#pragma mark - Groupings

- (void)selectedInbox
{
    self.segmentedControl.selectedSegmentIndex = 0;
    self.viewingThreadsIn = kInboxState;
    [self changeToGrouping:TSInboxGroup];
}

- (void)selectedArchive
{
    self.segmentedControl.selectedSegmentIndex = 1;
    self.viewingThreadsIn = kArchiveState;
    [self changeToGrouping:TSArchiveGroup];
}

- (void)changeToGrouping:(NSString *)grouping {
    OWSAssert([NSThread isMainThread]);

    self.shouldObserveDBModifications = NO;

    self.threadMappings =
        [[YapDatabaseViewMappings alloc] initWithGroups:@[ grouping ] view:TSThreadDatabaseViewExtensionName];
    [self.threadMappings setIsReversed:YES forGroup:grouping];

    [self updateShouldObserveDBModifications];

    [self checkIfEmptyView];
    [self updateReminderViews];
}

#pragma mark Database delegates

- (YapDatabaseConnection *)uiDatabaseConnection {
    NSAssert([NSThread isMainThread], @"Must access uiDatabaseConnection on main thread!");
    if (!_uiDatabaseConnection) {
        YapDatabase *database = TSStorageManager.sharedManager.database;
        _uiDatabaseConnection = [database newConnection];
        [_uiDatabaseConnection beginLongLivedReadTransaction];
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

    if (!self.shouldObserveDBModifications) {
        return;
    }

    [[self.uiDatabaseConnection ext:TSThreadDatabaseViewExtensionName] getSectionChanges:&sectionChanges
                                                                              rowChanges:&rowChanges
                                                                        forNotifications:notifications
                                                                            withMappings:self.threadMappings];

    // We want this regardless of if we're currently viewing the archive.
    // So we run it before the early return
    [self updateInboxCountLabel];

    if ([sectionChanges count] == 0 && [rowChanges count] == 0) {
        [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
            [self.threadMappings updateWithTransaction:transaction];
        }];
        [self checkIfEmptyView];
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

- (void)setViewingThreadsIn:(CellState)viewingThreadsIn
{
    _viewingThreadsIn = viewingThreadsIn;

    [self checkIfEmptyView];
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
