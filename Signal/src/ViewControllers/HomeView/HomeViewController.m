//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "HomeViewController.h"
#import "AppDelegate.h"
#import "AppSettingsViewController.h"
#import "HomeViewCell.h"
#import "NewContactThreadViewController.h"
#import "OWSNavigationController.h"
#import "OWSPrimaryStorage.h"
#import "ProfileViewController.h"
#import "PushManager.h"
#import "Signal-Swift.h"
#import "SignalApp.h"
#import "TSAccountManager.h"
#import "TSDatabaseView.h"
#import "TSGroupThread.h"
#import "ViewControllerUtils.h"
#import <PromiseKit/AnyPromise.h>
#import <SignalMessaging/OWSContactsManager.h>
#import <SignalMessaging/OWSFormat.h>
#import <SignalMessaging/UIUtil.h>
#import <SignalServiceKit/NSDate+OWS.h>
#import <SignalServiceKit/OWSBlockingManager.h>
#import <SignalServiceKit/OWSMessageSender.h>
#import <SignalServiceKit/OWSMessageUtils.h>
#import <SignalServiceKit/TSOutgoingMessage.h>
#import <SignalServiceKit/Threading.h>
#import <YapDatabase/YapDatabase.h>
#import <YapDatabase/YapDatabaseViewChange.h>
#import <YapDatabase/YapDatabaseViewConnection.h>

typedef NS_ENUM(NSInteger, HomeViewMode) {
    HomeViewMode_Archive,
    HomeViewMode_Inbox,
};

NSString *const kArchivedConversationsReuseIdentifier = @"kArchivedConversationsReuseIdentifier";

@interface HomeViewController () <UITableViewDelegate, UITableViewDataSource, UIViewControllerPreviewingDelegate>

@property (nonatomic) UITableView *tableView;
@property (nonatomic) UILabel *emptyBoxLabel;

@property (nonatomic) YapDatabaseConnection *editingDbConnection;
@property (nonatomic) YapDatabaseConnection *uiDatabaseConnection;
@property (nonatomic) YapDatabaseViewMappings *threadMappings;
@property (nonatomic) HomeViewMode homeViewMode;
@property (nonatomic) id previewingContext;
@property (nonatomic) NSSet<NSString *> *blockedPhoneNumberSet;
@property (nonatomic, readonly) NSCache<NSString *, ThreadViewModel *> *threadViewModelCache;
@property (nonatomic) BOOL isViewVisible;
@property (nonatomic) BOOL isAppInBackground;
@property (nonatomic) BOOL shouldObserveDBModifications;
@property (nonatomic) BOOL hasBeenPresented;

// Dependencies

@property (nonatomic, readonly) AccountManager *accountManager;
@property (nonatomic, readonly) OWSContactsManager *contactsManager;
@property (nonatomic, readonly) OWSMessageSender *messageSender;
@property (nonatomic, readonly) OWSBlockingManager *blockingManager;

// Views

@property (nonatomic) NSLayoutConstraint *hideArchiveReminderViewConstraint;
@property (nonatomic) NSLayoutConstraint *hideMissingContactsPermissionViewConstraint;

@property (nonatomic) TSThread *lastThread;

@property (nonatomic) BOOL hasArchivedThreadsRow;

@end

#pragma mark -

@implementation HomeViewController

#pragma mark - Init

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    _homeViewMode = HomeViewMode_Inbox;

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
    _accountManager = SignalApp.sharedApp.accountManager;
    _contactsManager = [Environment current].contactsManager;
    _messageSender = [Environment current].messageSender;
    _blockingManager = [OWSBlockingManager sharedManager];
    _blockedPhoneNumberSet = [NSSet setWithArray:[_blockingManager blockedPhoneNumbers]];
    _threadViewModelCache = [NSCache new];

    // Ensure ExperienceUpgradeFinder has been initialized.
    [ExperienceUpgradeFinder sharedManager];

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
                                                 name:OWSApplicationWillEnterForegroundNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidEnterBackground:)
                                                 name:OWSApplicationDidEnterBackgroundNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidBecomeActive:)
                                                 name:OWSApplicationDidBecomeActiveNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(yapDatabaseModified:)
                                                 name:YapDatabaseModifiedNotification
                                               object:OWSPrimaryStorage.sharedManager.dbNotificationObject];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(yapDatabaseModifiedExternally:)
                                                 name:YapDatabaseModifiedExternallyNotification
                                               object:nil];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Notifications

- (void)blockedPhoneNumbersDidChange:(id)notification
{
    OWSAssertIsOnMainThread();

    _blockedPhoneNumberSet = [NSSet setWithArray:[_blockingManager blockedPhoneNumbers]];

    [self reloadTableViewData];
}

- (void)signalAccountsDidChange:(id)notification
{
    OWSAssertIsOnMainThread();

    [self reloadTableViewData];
}

#pragma mark - View Life Cycle

- (void)loadView
{
    [super loadView];

    self.view.backgroundColor = [UIColor whiteColor];

    // TODO: Remove this.
    if (self.homeViewMode == HomeViewMode_Inbox) {
        [SignalApp.sharedApp setHomeViewController:self];
    }

    ReminderView *archiveReminderView =
        [ReminderView explanationWithText:NSLocalizedString(@"INBOX_VIEW_ARCHIVE_MODE_REMINDER",
                                              @"Label reminding the user that they are in archive mode.")];
    [self.view addSubview:archiveReminderView];
    [archiveReminderView autoPinWidthToSuperview];
    [archiveReminderView autoPinToTopLayoutGuideOfViewController:self withInset:0];
    self.hideArchiveReminderViewConstraint = [archiveReminderView autoSetDimension:ALDimensionHeight toSize:0];
    self.hideArchiveReminderViewConstraint.priority = UILayoutPriorityRequired;

    ReminderView *missingContactsPermissionView = [ReminderView
        nagWithText:NSLocalizedString(@"INBOX_VIEW_MISSING_CONTACTS_PERMISSION",
                        @"Multi-line label explaining how to show names instead of phone numbers in your inbox")
          tapAction:^{
              [[UIApplication sharedApplication] openSystemSettings];
          }];
    [self.view addSubview:missingContactsPermissionView];
    [missingContactsPermissionView autoPinWidthToSuperview];
    [missingContactsPermissionView autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:archiveReminderView];
    self.hideMissingContactsPermissionViewConstraint =
        [missingContactsPermissionView autoSetDimension:ALDimensionHeight toSize:0];
    self.hideMissingContactsPermissionViewConstraint.priority = UILayoutPriorityRequired;

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    [self.tableView registerClass:[HomeViewCell class] forCellReuseIdentifier:HomeViewCell.cellReuseIdentifier];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:kArchivedConversationsReuseIdentifier];
    [self.view addSubview:self.tableView];
    [self.tableView autoPinWidthToSuperview];
    [self.tableView autoPinEdgeToSuperviewEdge:ALEdgeBottom];
    [self.tableView autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:missingContactsPermissionView];

    UILabel *emptyBoxLabel = [UILabel new];
    self.emptyBoxLabel = emptyBoxLabel;
    [self.view addSubview:emptyBoxLabel];
    [emptyBoxLabel autoPinWidthToSuperview];
    [emptyBoxLabel autoPinToTopLayoutGuideOfViewController:self withInset:0];
    [emptyBoxLabel autoPinToBottomLayoutGuideOfViewController:self withInset:0];

    UIRefreshControl *pullToRefreshView = [UIRefreshControl new];
    pullToRefreshView.tintColor = [UIColor grayColor];
    [pullToRefreshView addTarget:self
                          action:@selector(pullToRefreshPerformed:)
                forControlEvents:UIControlEventValueChanged];
    [self.tableView insertSubview:pullToRefreshView atIndex:0];

    [self updateReminderViews];
}

- (void)updateReminderViews
{
    BOOL shouldHideArchiveReminderView = self.homeViewMode != HomeViewMode_Archive;
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

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.editingDbConnection = OWSPrimaryStorage.sharedManager.newDatabaseConnection;

    // Create the database connection.
    [self uiDatabaseConnection];

    [self updateMappings];
    [self checkIfEmptyView];
    [self updateReminderViews];

    // because this uses the table data source, `tableViewSetup` must happen
    // after mappings have been set up in `showInboxGrouping`
    [self tableViewSetUp];

    switch (self.homeViewMode) {
        case HomeViewMode_Inbox:
            // TODO: Should our app name be translated?  Probably not.
            self.title = NSLocalizedString(@"HOME_VIEW_TITLE_INBOX", @"Title for the home view's default mode.");
            break;
        case HomeViewMode_Archive:
            self.title = NSLocalizedString(@"HOME_VIEW_TITLE_ARCHIVE", @"Title for the home view's 'archive' mode.");
            break;
    }

    [self applyDefaultBackButton];

    if ([self.traitCollection respondsToSelector:@selector(forceTouchCapability)]
        && (self.traitCollection.forceTouchCapability == UIForceTouchCapabilityAvailable)) {
        [self registerForPreviewingWithDelegate:self sourceView:self.tableView];
    }

    [self updateBarButtonItems];
}

- (void)applyDefaultBackButton
{
    // We don't show any text for the back button, so there's no need to localize it. But because we left align the
    // conversation title view, we add a little tappable padding after the back button, by having a title of spaces.
    // Admittedly this is kind of a hack and not super fine grained, but it's simple and results in the interactive pop
    // gesture animating our title view nicely vs. creating our own back button bar item with custom padding, which does
    // not properly animate with the "swipe to go back" or "swipe left for info" gestures.
    NSUInteger paddingLength = 3;
    NSString *paddingString = [@"" stringByPaddingToLength:paddingLength withString:@" " startingAtIndex:0];

    self.navigationItem.backBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:paddingString style:UIBarButtonItemStylePlain target:nil action:nil];
}

- (void)applyArchiveBackButton
{
    self.navigationItem.backBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"BACK_BUTTON", @"button text for back button")
                                         style:UIBarButtonItemStylePlain
                                        target:nil
                                        action:nil];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];

    [self displayAnyUnseenUpgradeExperience];
    [self applyDefaultBackButton];
}

- (void)updateBarButtonItems
{
    if (self.homeViewMode != HomeViewMode_Inbox) {
        return;
    }
    const CGFloat kBarButtonSize = 44;
    // We use UIButtons with [UIBarButtonItem initWithCustomView:...] instead of
    // UIBarButtonItem in order to ensure that these buttons are spaced tightly.
    // The contents of the navigation bar are cramped in this view.
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    UIImage *image = [UIImage imageNamed:@"button_settings_white"];
    [button setImage:image forState:UIControlStateNormal];
    UIEdgeInsets imageEdgeInsets = UIEdgeInsetsZero;
    // We normally would want to use left and right insets that ensure the button
    // is square and the icon is centered.  However UINavigationBar doesn't offer us
    // control over the margins and spacing of its content, and the buttons end up
    // too far apart and too far from the edge of the screen. So we use a smaller
    // leading inset tighten up the layout.
    CGFloat hInset = round((kBarButtonSize - image.size.width) * 0.5f);
    if (self.view.isRTL) {
        imageEdgeInsets.right = hInset;
        imageEdgeInsets.left = round((kBarButtonSize - (image.size.width + hInset)) * 0.5f);
    } else {
        imageEdgeInsets.left = hInset;
        imageEdgeInsets.right = round((kBarButtonSize - (image.size.width + hInset)) * 0.5f);
    }
    imageEdgeInsets.top = round((kBarButtonSize - image.size.height) * 0.5f);
    imageEdgeInsets.bottom = round(kBarButtonSize - (image.size.height + imageEdgeInsets.top));
    button.imageEdgeInsets = imageEdgeInsets;
    button.accessibilityLabel = CommonStrings.openSettingsButton;

    [button addTarget:self action:@selector(settingsButtonPressed:) forControlEvents:UIControlEventTouchUpInside];
    button.frame = CGRectMake(0,
        0,
        round(image.size.width + imageEdgeInsets.left + imageEdgeInsets.right),
        round(image.size.height + imageEdgeInsets.top + imageEdgeInsets.bottom));
    UIBarButtonItem *settingsButton = [[UIBarButtonItem alloc] initWithCustomView:button];
    settingsButton.accessibilityLabel
        = NSLocalizedString(@"SETTINGS_BUTTON_ACCESSIBILITY", @"Accessibility hint for the settings button");
    self.navigationItem.leftBarButtonItem = settingsButton;

    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCompose
                                                      target:self
                                                      action:@selector(showNewConversationView)];
}

- (void)settingsButtonPressed:(id)sender
{
    OWSNavigationController *navigationController = [AppSettingsViewController inModalNavigationController];
    [self presentViewController:navigationController animated:YES completion:nil];
}

- (UIViewController *)previewingContext:(id<UIViewControllerPreviewing>)previewingContext
              viewControllerForLocation:(CGPoint)location
{
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:location];

    if ([self isIndexPathForArchivedConversations:indexPath]) {
        return nil;
    }

    if (indexPath) {
        [previewingContext setSourceRect:[self.tableView rectForRowAtIndexPath:indexPath]];

        ConversationViewController *vc = [ConversationViewController new];
        TSThread *thread = [self threadForIndexPath:indexPath];
        self.lastThread = thread;
        [vc configureForThread:thread action:ConversationViewActionNone];
        [vc peekSetup];

        return vc;
    } else {
        return nil;
    }
}

- (void)previewingContext:(id<UIViewControllerPreviewing>)previewingContext
     commitViewController:(UIViewController *)viewControllerToCommit
{
    ConversationViewController *vc = (ConversationViewController *)viewControllerToCommit;
    [vc popped];

    [self.navigationController pushViewController:vc animated:NO];
}

- (void)showNewConversationView
{
    OWSAssertIsOnMainThread();

    DDLogInfo(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    NewContactThreadViewController *viewController = [NewContactThreadViewController new];

    [self.contactsManager requestSystemContactsOnceWithCompletion:^(NSError *_Nullable error) {
        if (error) {
            DDLogError(@"%@ Error when requesting contacts: %@", self.logTag, error);
        }
        // Even if there is an error fetching contacts we proceed to the next screen.
        // As the compose view will present the proper thing depending on contact access.
        //
        // We just want to make sure contact access is *complete* before showing the compose
        // screen to avoid flicker.
        OWSNavigationController *navigationController =
            [[OWSNavigationController alloc] initWithRootViewController:viewController];
        [self presentTopLevelModalViewController:navigationController animateDismissal:YES animatePresentation:YES];
    }];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    __block BOOL hasAnyMessages;
    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
        hasAnyMessages = [self hasAnyMessagesWithTransaction:transaction];
    }];
    if (hasAnyMessages) {
        [self.contactsManager requestSystemContactsOnceWithCompletion:^(NSError *_Nullable error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self updateReminderViews];
            });
        }];
    }

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
    [self applyDefaultBackButton];
    if ([self updateHasArchivedThreadsRow]) {
        [self.tableView reloadData];
    }
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

    if (self.shouldObserveDBModifications) {
        [self resetMappings];
    }
}

- (void)reloadTableViewData
{
    // PERF: come up with a more nuanced cache clearing scheme
    [self.threadViewModelCache removeAllObjects];
    [self.tableView reloadData];
}

- (void)resetMappings
{
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

    [self updateHasArchivedThreadsRow];
    [self reloadTableViewData];

    [self checkIfEmptyView];

    // If the user hasn't already granted contact access
    // we don't want to request until they receive a message.
    __block BOOL hasAnyMessages;
    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
        hasAnyMessages = [self hasAnyMessagesWithTransaction:transaction];
    }];
    if (hasAnyMessages) {
        [self.contactsManager requestSystemContactsOnce];
    }
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

- (BOOL)hasAnyMessagesWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    return [TSThread numberOfKeysInCollectionWithTransaction:transaction] > 0;
}

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    // It's possible a thread was created while we where in the background. But since we don't honor contact
    // requests unless the app is in the foregrond, we must check again here upon becoming active.
    __block BOOL hasAnyMessages;
    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
        hasAnyMessages = [self hasAnyMessagesWithTransaction:transaction];
    }];
    
    if (hasAnyMessages) {
        [self.contactsManager requestSystemContactsOnceWithCompletion:^(NSError *_Nullable error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self updateReminderViews];
            });
        }];
    }
}

#pragma mark - startup

- (NSArray<ExperienceUpgrade *> *)unseenUpgradeExperiences
{
    OWSAssertIsOnMainThread();

    __block NSArray<ExperienceUpgrade *> *unseenUpgrades;
    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        unseenUpgrades = [ExperienceUpgradeFinder.sharedManager allUnseenWithTransaction:transaction];
    }];
    return unseenUpgrades;
}

- (void)displayAnyUnseenUpgradeExperience
{
    OWSAssertIsOnMainThread();

    NSArray<ExperienceUpgrade *> *unseenUpgrades = [self unseenUpgradeExperiences];

    if (unseenUpgrades.count > 0) {
        ExperienceUpgradesPageViewController *experienceUpgradeViewController =
            [[ExperienceUpgradesPageViewController alloc] initWithExperienceUpgrades:unseenUpgrades];
        [self presentViewController:experienceUpgradeViewController animated:YES completion:nil];
    } else if (!self.hasBeenPresented && [ProfileViewController shouldDisplayProfileViewOnLaunch]) {
        [ProfileViewController presentForUpgradeOrNag:self];
    } else {
        [OWSAlerts showIOSUpgradeNagIfNecessary];
    }

    self.hasBeenPresented = YES;
}

- (void)tableViewSetUp
{
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
}

- (BOOL)shouldShowMissingContactsPermissionView
{
    if (!self.contactsManager.systemContactsHaveBeenRequestedAtLeastOnce) {
        return NO;
    }

    return !self.contactsManager.isSystemContactsAuthorized;
}

#pragma mark - Table View Data Source

// Returns YES IFF this value changes.
- (BOOL)updateHasArchivedThreadsRow
{
    BOOL hasArchivedThreadsRow = (self.homeViewMode == HomeViewMode_Inbox && self.numberOfArchivedThreads > 0);
    if (self.hasArchivedThreadsRow == hasArchivedThreadsRow) {
        return NO;
    }
    self.hasArchivedThreadsRow = hasArchivedThreadsRow;

    return YES;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return (NSInteger)[self.threadMappings numberOfSections];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    NSInteger result = (NSInteger)[self.threadMappings numberOfItemsInSection:(NSUInteger)section];
    if (self.hasArchivedThreadsRow) {
        // Add the "archived conversations" row.
        result++;
    }
    return result;
}

- (BOOL)isIndexPathForArchivedConversations:(NSIndexPath *)indexPath
{
    if (self.homeViewMode != HomeViewMode_Inbox) {
        return NO;
    }
    if (indexPath.section != 0) {
        return NO;
    }
    NSInteger cellCount = (NSInteger)[self.threadMappings numberOfItemsInSection:(NSUInteger)0];
    return indexPath.row == cellCount;
}

- (ThreadViewModel *)threadViewModelForIndexPath:(NSIndexPath *)indexPath
{
    TSThread *threadRecord = [self threadForIndexPath:indexPath];

    ThreadViewModel *_Nullable cachedThreadViewModel = [self.threadViewModelCache objectForKey:threadRecord.uniqueId];
    if (cachedThreadViewModel) {
        return cachedThreadViewModel;
    }

    __block ThreadViewModel *_Nullable newThreadViewModel;
    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
        newThreadViewModel = [[ThreadViewModel alloc] initWithThread:threadRecord transaction:transaction];
    }];
    [self.threadViewModelCache setObject:newThreadViewModel forKey:threadRecord.uniqueId];
    return newThreadViewModel;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if ([self isIndexPathForArchivedConversations:indexPath]) {
        return [self cellForArchivedConversationsRow:tableView];
    } else {
        return [self tableView:tableView cellForConversationAtIndexPath:indexPath];
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForConversationAtIndexPath:(NSIndexPath *)indexPath
{
    HomeViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:HomeViewCell.cellReuseIdentifier];
    OWSAssert(cell);

    ThreadViewModel *thread = [self threadViewModelForIndexPath:indexPath];
    [cell configureWithThread:thread
              contactsManager:self.contactsManager
        blockedPhoneNumberSet:self.blockedPhoneNumberSet];

    if ((unsigned long)indexPath.row == [self.threadMappings numberOfItemsInSection:0] - 1) {
        cell.separatorInset = UIEdgeInsetsMake(0.f, cell.bounds.size.width, 0.f, 0.f);
    }

    return cell;
}

- (UITableViewCell *)cellForArchivedConversationsRow:(UITableView *)tableView
{
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:kArchivedConversationsReuseIdentifier];
    OWSAssert(cell);

    for (UIView *subview in cell.contentView.subviews) {
        [subview removeFromSuperview];
    }

    cell.backgroundColor = [UIColor whiteColor];

    UIImage *disclosureImage = [UIImage imageNamed:(cell.isRTL ? @"NavBarBack" : @"NavBarBackRTL")];
    OWSAssert(disclosureImage);
    UIImageView *disclosureImageView = [UIImageView new];
    disclosureImageView.image = [disclosureImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    disclosureImageView.tintColor = [UIColor colorWithRGBHex:0xd1d1d6];
    [disclosureImageView setContentHuggingHigh];
    [disclosureImageView setCompressionResistanceHigh];

    UILabel *label = [UILabel new];
    label.text = NSLocalizedString(@"HOME_VIEW_ARCHIVED_CONVERSATIONS", @"Label for 'archived conversations' button.");
    label.textAlignment = NSTextAlignmentCenter;
    label.font = [UIFont ows_dynamicTypeBodyFont];
    label.textColor = [UIColor blackColor];

    UIStackView *stackView = [UIStackView new];
    stackView.axis = UILayoutConstraintAxisHorizontal;
    stackView.spacing = 5;
    // If alignment isn't set, UIStackView uses the height of
    // disclosureImageView, even if label has a higher desired height.
    stackView.alignment = UIStackViewAlignmentCenter;
    [stackView addArrangedSubview:label];
    [stackView addArrangedSubview:disclosureImageView];
    [cell.contentView addSubview:stackView];
    [stackView autoCenterInSuperview];
    // Constrain to cell margins.
    [stackView autoPinEdgeToSuperviewMargin:ALEdgeLeading relation:NSLayoutRelationGreaterThanOrEqual];
    [stackView autoPinEdgeToSuperviewMargin:ALEdgeTrailing relation:NSLayoutRelationGreaterThanOrEqual];
    // Ensure that the cell's contents never overflow the cell bounds.
    // We pin pin to the superview _edge_ and not _margin_ for the purposes
    // of overflow, so that changes to the margins do not trip these safe guards.
    [stackView autoPinEdgeToSuperviewEdge:ALEdgeTop withInset:0 relation:NSLayoutRelationGreaterThanOrEqual];
    [stackView autoPinEdgeToSuperviewEdge:ALEdgeBottom withInset:0 relation:NSLayoutRelationGreaterThanOrEqual];

    return cell;
}

- (TSThread *)threadForIndexPath:(NSIndexPath *)indexPath
{
    __block TSThread *thread = nil;
    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        thread = [[transaction extension:TSThreadDatabaseViewExtensionName] objectAtIndexPath:indexPath
                                                                                 withMappings:self.threadMappings];
    }];

    return thread;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return HomeViewCell.rowHeight;
}

- (void)pullToRefreshPerformed:(UIRefreshControl *)refreshControl
{
    OWSAssertIsOnMainThread();
    DDLogInfo(@"%@ beggining refreshing.", self.logTag);
    [SignalApp.sharedApp.messageFetcherJob run].always(^{
        DDLogInfo(@"%@ ending refreshing.", self.logTag);
        [refreshControl endRefreshing];
    });
}

#pragma mark Table Swipe to Delete

- (void)tableView:(UITableView *)tableView
    commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
     forRowAtIndexPath:(NSIndexPath *)indexPath
{
    return;
}

- (NSArray *)tableView:(UITableView *)tableView editActionsForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if ([self isIndexPathForArchivedConversations:indexPath]) {
        return @[];
    }

    UITableViewRowAction *deleteAction =
        [UITableViewRowAction rowActionWithStyle:UITableViewRowActionStyleDefault
                                           title:NSLocalizedString(@"TXT_DELETE_TITLE", nil)
                                         handler:^(UITableViewRowAction *action, NSIndexPath *swipedIndexPath) {
                                             [self tableViewCellTappedDelete:swipedIndexPath];
                                         }];

    UITableViewRowAction *archiveAction;
    if (self.homeViewMode == HomeViewMode_Inbox) {
        archiveAction = [UITableViewRowAction
            rowActionWithStyle:UITableViewRowActionStyleNormal
                         title:NSLocalizedString(@"ARCHIVE_ACTION",
                                   @"Pressing this button moves a thread from the inbox to the archive")
                       handler:^(UITableViewRowAction *_Nonnull action, NSIndexPath *_Nonnull tappedIndexPath) {
                           [self archiveIndexPath:tappedIndexPath];
                           [Environment.preferences setHasArchivedAMessage:YES];
                       }];

    } else {
        archiveAction = [UITableViewRowAction
            rowActionWithStyle:UITableViewRowActionStyleNormal
                         title:NSLocalizedString(@"UNARCHIVE_ACTION",
                                   @"Pressing this button moves an archived thread from the archive back to the inbox")
                       handler:^(UITableViewRowAction *_Nonnull action, NSIndexPath *_Nonnull tappedIndexPath) {
                           [self archiveIndexPath:tappedIndexPath];
                       }];
    }


    return @[ deleteAction, archiveAction ];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    if ([self isIndexPathForArchivedConversations:indexPath]) {
        return NO;
    }

    return YES;
}

#pragma mark - HomeFeedTableViewCellDelegate

- (void)tableViewCellTappedDelete:(NSIndexPath *)indexPath
{
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

            TSOutgoingMessage *message =
                [TSOutgoingMessage outgoingMessageInThread:thread groupMetaMessage:TSGroupMessageQuit];
            [self.messageSender enqueueMessage:message
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

- (void)deleteThread:(TSThread *)thread
{
    [self.editingDbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [thread removeWithTransaction:transaction];
    }];

    [self checkIfEmptyView];
}

- (void)archiveIndexPath:(NSIndexPath *)indexPath
{
    TSThread *thread = [self threadForIndexPath:indexPath];

    [self.editingDbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        switch (self.homeViewMode) {
            case HomeViewMode_Inbox:
                [thread archiveThreadWithTransaction:transaction];
                break;
            case HomeViewMode_Archive:
                [thread unarchiveThreadWithTransaction:transaction];
                break;
        }
    }];
    [self checkIfEmptyView];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    DDLogInfo(@"%@ %s %zd %zd", self.logTag, __PRETTY_FUNCTION__, indexPath.row, indexPath.section);

    if ([self isIndexPathForArchivedConversations:indexPath]) {
        [self showArchivedConversations];
        return;
    }

    TSThread *thread = [self threadForIndexPath:indexPath];
    [self presentThread:thread action:ConversationViewActionNone];
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (void)presentThread:(TSThread *)thread action:(ConversationViewAction)action
{
    if (thread == nil) {
        OWSFail(@"Thread unexpectedly nil");
        return;
    }

    // We do this synchronously if we're already on the main thread.
    DispatchMainThreadSafe(^{
        ConversationViewController *mvc = [ConversationViewController new];
        [mvc configureForThread:thread action:action];
        self.lastThread = thread;

        [self pushTopLevelViewController:mvc animateDismissal:YES animatePresentation:YES];
    });
}

- (void)presentTopLevelModalViewController:(UIViewController *)viewController
                          animateDismissal:(BOOL)animateDismissal
                       animatePresentation:(BOOL)animatePresentation
{
    OWSAssertIsOnMainThread();
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
    OWSAssertIsOnMainThread();
    OWSAssert(viewController);

    [self presentViewControllerWithBlock:^{
        [self.navigationController pushViewController:viewController animated:animatePresentation];
    }
                        animateDismissal:animateDismissal];
}

- (void)presentViewControllerWithBlock:(void (^)(void))presentationBlock animateDismissal:(BOOL)animateDismissal
{
    OWSAssertIsOnMainThread();
    OWSAssert(presentationBlock);

    // Presenting a "top level" view controller has three steps:
    //
    // First, dismiss any presented modal.
    // Second, pop to the root view controller if necessary.
    // Third present the new view controller using presentationBlock.

    // Define a block to perform the second step.
    void (^dismissNavigationBlock)(void) = ^{
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
        if ([self.presentedViewController isKindOfClass:[CallViewController class]]) {
            OWSProdInfo([OWSAnalyticsEvents errorCouldNotPresentViewDueToCall]);
            return;
        }
        [self.presentedViewController dismissViewControllerAnimated:animateDismissal completion:dismissNavigationBlock];
    } else {
        dismissNavigationBlock();
    }
}

#pragma mark - Groupings

- (YapDatabaseViewMappings *)threadMappings
{
    OWSAssert(_threadMappings != nil);
    return _threadMappings;
}

- (void)showInboxGrouping
{
    OWSAssert(self.homeViewMode == HomeViewMode_Archive);

    [self.navigationController popToRootViewControllerAnimated:YES];
}

- (void)showArchivedConversations
{
    OWSAssert(self.homeViewMode == HomeViewMode_Inbox);

    // When showing archived conversations, we want to use a conventional "back" button
    // to return to the "inbox" home view.
    [self applyArchiveBackButton];

    // Push a separate instance of this view using "archive" mode.
    HomeViewController *homeView = [HomeViewController new];
    homeView.homeViewMode = HomeViewMode_Archive;
    [self.navigationController pushViewController:homeView animated:YES];
}

- (NSString *)currentGrouping
{
    switch (self.homeViewMode) {
        case HomeViewMode_Inbox:
            return TSInboxGroup;
        case HomeViewMode_Archive:
            return TSArchiveGroup;
    }
}

- (void)updateMappings
{
    OWSAssertIsOnMainThread();

    self.threadMappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[ self.currentGrouping ]
                                                                     view:TSThreadDatabaseViewExtensionName];
    [self.threadMappings setIsReversed:YES forGroup:self.currentGrouping];

    [self resetMappings];

    [self reloadTableViewData];
    [self checkIfEmptyView];
    [self updateReminderViews];
}

#pragma mark Database delegates

- (YapDatabaseConnection *)uiDatabaseConnection
{
    OWSAssertIsOnMainThread();

    if (!_uiDatabaseConnection) {
        _uiDatabaseConnection = [OWSPrimaryStorage.sharedManager newDatabaseConnection];
        // default is 250
        _uiDatabaseConnection.objectCacheLimit = 500;
        [_uiDatabaseConnection beginLongLivedReadTransaction];
    }
    return _uiDatabaseConnection;
}

- (void)yapDatabaseModifiedExternally:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    DDLogVerbose(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    if (self.shouldObserveDBModifications) {
        // External database modifications can't be converted into incremental updates,
        // so rebuild everything.  This is expensive and usually isn't necessary, but
        // there's no alternative.
        //
        // We don't need to do this if we're not observing db modifications since we'll
        // do it when we resume.
        [self resetMappings];
    }
}

- (void)yapDatabaseModified:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    if (!self.shouldObserveDBModifications) {
        return;
    }

    DDLogVerbose(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    NSArray *notifications = [self.uiDatabaseConnection beginLongLivedReadTransaction];

    if (![[self.uiDatabaseConnection ext:TSThreadDatabaseViewExtensionName] hasChangesForGroup:self.currentGrouping
                                                                               inNotifications:notifications]) {
        [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
            [self.threadMappings updateWithTransaction:transaction];
        }];
        [self checkIfEmptyView];

        return;
    }

    // If the user hasn't already granted contact access
    // we don't want to request until they receive a message.
    __block BOOL hasAnyMessages;
    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
        hasAnyMessages = [self hasAnyMessagesWithTransaction:transaction];
    }];

    if (hasAnyMessages) {
        [self.contactsManager requestSystemContactsOnce];
    }

    NSArray *sectionChanges = nil;
    NSArray *rowChanges = nil;
    [[self.uiDatabaseConnection ext:TSThreadDatabaseViewExtensionName] getSectionChanges:&sectionChanges
                                                                              rowChanges:&rowChanges
                                                                        forNotifications:notifications
                                                                            withMappings:self.threadMappings];

    // We want this regardless of if we're currently viewing the archive.
    // So we run it before the early return
    [self checkIfEmptyView];

    if ([sectionChanges count] == 0 && [rowChanges count] == 0) {
        return;
    }

    if ([self updateHasArchivedThreadsRow]) {
        [self.tableView reloadData];
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
        NSString *key = rowChange.collectionKey.key;
        OWSAssert(key);
        [self.threadViewModelCache removeObjectForKey:key];

        switch (rowChange.type) {
            case YapDatabaseViewChangeDelete: {
                [self.tableView deleteRowsAtIndexPaths:@[ rowChange.indexPath ]
                                      withRowAnimation:UITableViewRowAnimationAutomatic];
                break;
            }
            case YapDatabaseViewChangeInsert: {
                [self.tableView insertRowsAtIndexPaths:@[ rowChange.newIndexPath ]
                                      withRowAnimation:UITableViewRowAnimationAutomatic];
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
}

- (NSUInteger)numberOfThreadsInGroup:(NSString *)group
{
    // We need to consult the db view, not the mapping since the mapping only knows about
    // the current group.
    __block NSUInteger result;
    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        YapDatabaseViewTransaction *viewTransaction = [transaction ext:TSThreadDatabaseViewExtensionName];
        result = [viewTransaction numberOfItemsInGroup:group];
    }];
    return result;
}

- (NSUInteger)numberOfInboxThreads
{
    return [self numberOfThreadsInGroup:TSInboxGroup];
}

- (NSUInteger)numberOfArchivedThreads
{
    return [self numberOfThreadsInGroup:TSArchiveGroup];
}

- (void)checkIfEmptyView
{
    NSUInteger inboxCount = self.numberOfInboxThreads;
    NSUInteger archiveCount = self.numberOfArchivedThreads;

    if (self.homeViewMode == HomeViewMode_Inbox && inboxCount == 0 && archiveCount == 0) {
        [self updateEmptyBoxText];
        [_tableView setHidden:YES];
        [_emptyBoxLabel setHidden:NO];
    } else if (self.homeViewMode == HomeViewMode_Archive && archiveCount == 0) {
        [self updateEmptyBoxText];
        [_tableView setHidden:YES];
        [_emptyBoxLabel setHidden:NO];
    } else {
        [_emptyBoxLabel setHidden:YES];
        [_tableView setHidden:NO];
    }
}

- (void)updateEmptyBoxText
{
    _emptyBoxLabel.textColor = [UIColor grayColor];
    _emptyBoxLabel.font = [UIFont ows_regularFontWithSize:18.f];
    _emptyBoxLabel.textAlignment = NSTextAlignmentCenter;
    _emptyBoxLabel.numberOfLines = 4;

    NSString *firstLine = @"";
    NSString *secondLine = @"";

    if (self.homeViewMode == HomeViewMode_Inbox) {
        if ([Environment.preferences getHasSentAMessage]) {
            firstLine = NSLocalizedString(@"EMPTY_INBOX_FIRST_TITLE", @"");
            secondLine = NSLocalizedString(@"EMPTY_INBOX_FIRST_TEXT", @"");
        } else {
            // FIXME This looks wrong. Shouldn't we be showing inbox_title/text here?
            firstLine = NSLocalizedString(@"EMPTY_ARCHIVE_FIRST_TITLE", @"");
            secondLine = NSLocalizedString(@"EMPTY_ARCHIVE_FIRST_TEXT", @"");
        }
    } else {
        if ([Environment.preferences getHasArchivedAMessage]) {
            // FIXME This looks wrong. Shouldn't we be showing first_archive_title/text here?
            firstLine = NSLocalizedString(@"EMPTY_INBOX_TITLE", @"");
            secondLine = NSLocalizedString(@"EMPTY_INBOX_TEXT", @"");
        } else {
            firstLine = NSLocalizedString(@"EMPTY_ARCHIVE_TITLE", @"");
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

@end
