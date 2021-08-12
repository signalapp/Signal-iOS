//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import "HomeViewController.h"
#import "AppDelegate.h"
#import "OWSNavigationController.h"
#import "RegistrationUtils.h"
#import "Signal-Swift.h"
#import "SignalApp.h"
#import "TSAccountManager.h"
#import "TSGroupThread.h"
#import "ViewControllerUtils.h"
#import <PromiseKit/AnyPromise.h>
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalCoreKit/Threading.h>
#import <SignalCoreKit/iOSVersions.h>
#import <SignalMessaging/OWSContactsManager.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalMessaging/Theme.h>
#import <SignalMessaging/UIUtil.h>
#import <SignalServiceKit/MessageSender.h>
#import <SignalServiceKit/OWSMessageUtils.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSAccountManager.h>
#import <SignalServiceKit/TSOutgoingMessage.h>
#import <StoreKit/StoreKit.h>

NS_ASSUME_NONNULL_BEGIN

// The bulk of the content in this view is driven by HVRenderState.
// However, we also want to optionally include ReminderView's at the top
// and an "Archived Conversations" button at the bottom. Rather than introduce
// index-offsets into the Mapping calculation, we introduce two pseudo groups
// to add a top and bottom section to the content, and create cells for those
// sections without consulting the HVRenderState.
// This is a bit of a hack, but it consolidates the hacks into the Reminder/Archive section
// and allows us to leaves the bulk of the content logic on the happy path.
NSString *const kReminderViewPseudoGroup = @"kReminderViewPseudoGroup";
NSString *const kArchiveButtonPseudoGroup = @"kArchiveButtonPseudoGroup";

@interface HomeViewController () <UIViewControllerPreviewingDelegate,
    UISearchBarDelegate,
    ConversationSearchViewDelegate,
    CameraFirstCaptureDelegate,
    OWSGetStartedBannerViewControllerDelegate>

@property (nonatomic) UIView *emptyInboxView;

@property (nonatomic) UILabel *firstConversationLabel;

// Get Started banner
@property (nonatomic, nullable) OWSInviteFlow *inviteFlow;
@property (nonatomic, nullable) OWSGetStartedBannerViewController *getStartedBanner;

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

    _viewState = [HVViewState new];
    self.tableDataSource.viewController = self;
    self.loadCoordinator.viewController = self;
    self.reminderViews.viewController = self;
    [self.viewState configure];

    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Theme

- (void)themeDidChange
{
    OWSAssertIsOnMainThread();

    [super themeDidChange];

    [self reloadTableDataAndResetCellContentCache];
}

- (void)applyTheme
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(self.tableView);
    OWSAssertDebug(self.searchBar);

    [super applyTheme];

    if (self.splitViewController.isCollapsed) {
        self.view.backgroundColor = Theme.backgroundColor;
        self.tableView.backgroundColor = Theme.backgroundColor;
        [self.searchBar switchToStyle:OWSSearchBarStyle_Default];
    } else {
        self.view.backgroundColor = Theme.secondaryBackgroundColor;
        self.tableView.backgroundColor = Theme.secondaryBackgroundColor;
        [self.searchBar switchToStyle:OWSSearchBarStyle_SecondaryBar];
    }

    [self updateBarButtonItems];
}

- (void)viewWillTransitionToSize:(CGSize)size
       withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];

    if (!self.isViewLoaded) {
        return;
    }

    // There is a subtle difference in when the split view controller
    // transitions between collapsed and expanded state on iPad vs
    // when it does on iPhone. We reloadData here in order to ensure
    // the background color of all of our cells is updated to reflect
    // the current state, so it's important that we're only doing this
    // once the state is ready, otherwise there will be a flash of the
    // wrong background color. For iPad, this moment is _before_ the
    // transition occurs. For iPhone, this moment is _during_ the
    // transition. We reload in the right places accordingly.

    if (UIDevice.currentDevice.isIPad) {
        [self reloadTableDataAndResetCellContentCache];
    }

    [coordinator
        animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
            [self applyTheme];
            if (!UIDevice.currentDevice.isIPad) {
                [self reloadTableDataAndResetCellContentCache];
            }

            // The Get Started banner will occupy most of the screen in landscape
            // If we're transitioning to landscape, fade out the view (if it exists)
            if (size.width > size.height) {
                self.getStartedBanner.view.alpha = 0;
            } else {
                self.getStartedBanner.view.alpha = 1;
            }
        }
                        completion:nil];
}

#pragma mark - View Life Cycle

- (void)loadView
{
    [super loadView];

    [self.view addSubview:self.tableView];
    [self.tableView autoPinEdgesToSuperviewEdges];
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, self.tableView);
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, self.searchBar);

    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 60;

    self.emptyInboxView = [self createEmptyInboxView];
    [self.view addSubview:self.emptyInboxView];
    [self.emptyInboxView autoPinWidthToSuperviewMargins];
    [self.emptyInboxView autoAlignAxis:ALAxisHorizontal toSameAxisOfView:self.view withMultiplier:0.85];
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, _emptyInboxView);

    [self createFirstConversationCueView];
    [self.view addSubview:self.firstConversationCueView];
    [self.firstConversationCueView autoPinToTopLayoutGuideOfViewController:self withInset:0.f];
    // This inset bakes in assumptions about UINavigationBar layout, but I'm not sure
    // there's a better way to do it, since it isn't safe to use iOS auto layout with
    // UINavigationBar contents.
    [self.firstConversationCueView autoPinEdgeToSuperviewEdge:ALEdgeTrailing withInset:6.f];
    [self.firstConversationCueView autoPinEdgeToSuperviewEdge:ALEdgeLeading
                                                    withInset:10
                                                     relation:NSLayoutRelationGreaterThanOrEqual];
    [self.firstConversationCueView autoPinEdgeToSuperviewMargin:ALEdgeBottom
                                                       relation:NSLayoutRelationGreaterThanOrEqual];
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, _firstConversationCueView);
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, _firstConversationLabel);

    UIRefreshControl *pullToRefreshView = [UIRefreshControl new];
    pullToRefreshView.tintColor = [UIColor grayColor];
    [pullToRefreshView addTarget:self
                          action:@selector(pullToRefreshPerformed:)
                forControlEvents:UIControlEventValueChanged];
    self.tableView.refreshControl = pullToRefreshView;
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, pullToRefreshView);
}

- (UIView *)createEmptyInboxView
{
    UILabel *emptyInboxLabel = [UILabel new];
    emptyInboxLabel.text = NSLocalizedString(
        @"INBOX_VIEW_EMPTY_INBOX", @"Message shown in the conversation list when the inbox is empty.");
    emptyInboxLabel.font = UIFont.ows_dynamicTypeSubheadlineClampedFont;
    emptyInboxLabel.textColor
        = Theme.isDarkThemeEnabled ? Theme.darkThemeSecondaryTextAndIconColor : UIColor.ows_gray45Color;
    emptyInboxLabel.textAlignment = NSTextAlignmentCenter;
    emptyInboxLabel.numberOfLines = 0;
    emptyInboxLabel.lineBreakMode = NSLineBreakByWordWrapping;

    return emptyInboxLabel;
}

- (void)createFirstConversationCueView
{
    const CGFloat kTailWidth = 16.f;
    const CGFloat kTailHeight = 8.f;
    const CGFloat kTailHMargin = 12.f;

    UILabel *label = [UILabel new];
    label.textColor = UIColor.ows_whiteColor;
    label.font = UIFont.ows_dynamicTypeBodyClampedFont;
    label.numberOfLines = 0;
    label.lineBreakMode = NSLineBreakByWordWrapping;

    OWSLayerView *layerView = [OWSLayerView new];
    layerView.layoutMargins = UIEdgeInsetsMake(11 + kTailHeight, 16, 11, 16);
    CAShapeLayer *shapeLayer = [CAShapeLayer new];
    shapeLayer.fillColor = UIColor.ows_accentBlueColor.CGColor;
    [layerView.layer addSublayer:shapeLayer];
    layerView.layoutCallback = ^(UIView *view) {
        UIBezierPath *bezierPath = [UIBezierPath new];
        
        // Bubble
        CGRect bubbleBounds = view.bounds;
        bubbleBounds.origin.y += kTailHeight;
        bubbleBounds.size.height -= kTailHeight;
        [bezierPath appendPath:[UIBezierPath bezierPathWithRoundedRect:bubbleBounds cornerRadius:8]];
        
        // Tail
        CGPoint tailTop = CGPointMake(kTailHMargin + kTailWidth * 0.5f, 0.f);
        CGPoint tailLeft = CGPointMake(kTailHMargin, kTailHeight);
        CGPoint tailRight = CGPointMake(kTailHMargin + kTailWidth, kTailHeight);
        if (!CurrentAppContext().isRTL) {
            tailTop.x = view.width - tailTop.x;
            tailLeft.x = view.width - tailLeft.x;
            tailRight.x = view.width - tailRight.x;
        }
        [bezierPath moveToPoint:tailTop];
        [bezierPath addLineToPoint:tailLeft];
        [bezierPath addLineToPoint:tailRight];
        [bezierPath addLineToPoint:tailTop];
        shapeLayer.path = bezierPath.CGPath;
        shapeLayer.frame = view.bounds;
    };

    [layerView addSubview:label];
    [label autoPinEdgesToSuperviewMargins];

    layerView.userInteractionEnabled = YES;
    [layerView
        addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self
                                                                     action:@selector(firstConversationCueWasTapped:)]];

    self.firstConversationCueView = layerView;
    self.firstConversationLabel = label;
}

- (void)firstConversationCueWasTapped:(UITapGestureRecognizer *)gestureRecognizer
{
    OWSLogInfo(@"");

    [self showNewConversationView];
}

- (NSArray<SignalAccount *> *)suggestedAccountsForFirstContact
{
    NSMutableArray<SignalAccount *> *accounts = [NSMutableArray new];

    for (SignalAccount *account in self.contactsManager.signalAccounts) {
        if (account.recipientAddress.isLocalAddress) {
            continue;
        }
        if (accounts.count >= 3) {
            break;
        }
        [accounts addObject:account];
    }

    return [accounts copy];
}

- (void)updateFirstConversationLabel
{

    NSArray<SignalAccount *> *signalAccounts = self.suggestedAccountsForFirstContact;

    NSString *formatString = @"";
    NSMutableArray<NSString *> *contactNames = [NSMutableArray new];
    if (signalAccounts.count >= 3) {
        [contactNames addObject:[self.contactsManager displayNameForSignalAccount:signalAccounts[0]]];
        [contactNames addObject:[self.contactsManager displayNameForSignalAccount:signalAccounts[1]]];
        [contactNames addObject:[self.contactsManager displayNameForSignalAccount:signalAccounts[2]]];

        formatString = NSLocalizedString(@"HOME_VIEW_FIRST_CONVERSATION_OFFER_3_CONTACTS_FORMAT",
            @"Format string for a label offering to start a new conversation with your contacts, if you have at least "
            @"3 Signal contacts.  Embeds {{The names of 3 of your Signal contacts}}.");
    } else if (signalAccounts.count == 2) {
        [contactNames addObject:[self.contactsManager displayNameForSignalAccount:signalAccounts[0]]];
        [contactNames addObject:[self.contactsManager displayNameForSignalAccount:signalAccounts[1]]];

        formatString = NSLocalizedString(@"HOME_VIEW_FIRST_CONVERSATION_OFFER_2_CONTACTS_FORMAT",
            @"Format string for a label offering to start a new conversation with your contacts, if you have 2 Signal "
            @"contacts.  Embeds {{The names of 2 of your Signal contacts}}.");
    } else if (signalAccounts.count == 1) {
        [contactNames addObject:[self.contactsManager displayNameForSignalAccount:signalAccounts[0]]];

        formatString = NSLocalizedString(@"HOME_VIEW_FIRST_CONVERSATION_OFFER_1_CONTACT_FORMAT",
            @"Format string for a label offering to start a new conversation with your contacts, if you have 1 Signal "
            @"contact.  Embeds {{The name of 1 of your Signal contacts}}.");
    }

    NSString *embedToken = @"%@";
    NSArray<NSString *> *formatSplits = [formatString componentsSeparatedByString:embedToken];
    // We need to use a complicated format string that possibly embeds multiple contact names.
    // Translator error could easily lead to an invalid format string.
    // We need to verify that it was translated properly.
    BOOL isValidFormatString = (contactNames.count > 0 && formatSplits.count == contactNames.count + 1);
    for (NSString *contactName in contactNames) {
        if ([contactName containsString:embedToken]) {
            isValidFormatString = NO;
        }
    }

    NSMutableAttributedString *_Nullable attributedString = nil;
    if (isValidFormatString) {
        attributedString = [[NSMutableAttributedString alloc] initWithString:formatString];
        while (contactNames.count > 0) {
            NSString *contactName = contactNames.firstObject;
            [contactNames removeObjectAtIndex:0];

            NSRange range = [attributedString.string rangeOfString:embedToken];
            if (range.location == NSNotFound) {
                // Error
                attributedString = nil;
                break;
            }

            NSAttributedString *formattedName =
                [[NSAttributedString alloc] initWithString:contactName
                                                attributes:@{
                                                    NSFontAttributeName : self.firstConversationLabel.font.ows_semibold,
                                                }];
            [attributedString replaceCharactersInRange:range withAttributedString:formattedName];
        }
    }

    if (!attributedString) {
        // The default case handles the no-contacts scenario and all error cases.
        NSString *defaultText = NSLocalizedString(@"HOME_VIEW_FIRST_CONVERSATION_OFFER_NO_CONTACTS",
            @"A label offering to start a new conversation with your contacts, if you have no Signal contacts.");
        attributedString = [[NSMutableAttributedString alloc] initWithString:defaultText];
    }

    self.firstConversationLabel.attributedText = [attributedString copy];
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    [self observeNotifications];

    switch (self.homeViewMode) {
        case HomeViewModeInbox:
            // TODO: Should our app name be translated?  Probably not.
            self.title
                = NSLocalizedString(@"HOME_VIEW_TITLE_INBOX", @"Title for the conversation list's default mode.");
            break;
        case HomeViewModeArchive:
            self.title
                = NSLocalizedString(@"HOME_VIEW_TITLE_ARCHIVE", @"Title for the conversation list's 'archive' mode.");
            break;
    }

    [self applyDefaultBackButton];

    if (@available(iOS 13, *)) {
        // Automatically handled by UITableViewDelegate callbacks
        // -tableView:contextMenuConfigurationForRowAtIndexPath:point:
        // -tableView:willPerformPreviewActionForMenuWithConfiguration:animator:
    } else if (self.traitCollection.forceTouchCapability == UIForceTouchCapabilityAvailable) {
        [self registerForPreviewingWithDelegate:self sourceView:self.tableView];
    }

    // Search

    UIView *searchBarContainer = [UIView new];
    searchBarContainer.layoutMargins = UIEdgeInsetsMake(0, 8, 0, 8);

    self.searchBar.placeholder = NSLocalizedString(@"HOME_VIEW_CONVERSATION_SEARCHBAR_PLACEHOLDER",
        @"Placeholder text for search bar which filters conversations.");
    self.searchBar.delegate = self;
    self.searchBar.textField.accessibilityIdentifier = ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"conversation_search");
    [self.searchBar sizeToFit];
    self.searchBar.layoutMargins = UIEdgeInsetsZero;

    searchBarContainer.frame = self.searchBar.frame;
    [searchBarContainer addSubview:self.searchBar];
    [self.searchBar autoPinEdgesToSuperviewMargins];

    // Setting tableHeader calls numberOfSections, which must happen after updateMappings has been called at least once.
    OWSAssertDebug(self.tableView.tableHeaderView == nil);
    self.tableView.tableHeaderView = searchBarContainer;
    // Hide search bar by default.  User can pull down to search.
    self.tableView.contentOffset = CGPointMake(0, CGRectGetHeight(self.searchBar.frame));

    self.searchResultsController.delegate = self;
    [self addChildViewController:self.searchResultsController];
    [self.view addSubview:self.searchResultsController.view];
    [self.searchResultsController.view autoPinEdgeToSuperviewEdge:ALEdgeBottom];
    [self.searchResultsController.view autoPinEdgeToSuperviewEdge:ALEdgeLeading];
    [self.searchResultsController.view autoPinEdgeToSuperviewEdge:ALEdgeTrailing];
    [self.searchResultsController.view autoPinTopToSuperviewMarginWithInset:56];
    self.searchResultsController.view.hidden = YES;

    [self updateReminderViews];
    [self updateBarButtonItems];

    [self applyTheme];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];

    if (!self.hasEverAppeared && ![ExperienceUpgradeManager presentNextFromViewController:self]) {
        [OWSActionSheets showIOSUpgradeNagIfNecessary];
        [self presentGetStartedBannerIfNecessary];
    }

    [self applyDefaultBackButton];

    // Whether or not the theme has changed, always ensure
    // the right theme is applied. The initial collapsed
    // state of the split view controller is determined between
    // `viewWillAppear` and `viewDidAppear`, so this is the soonest
    // we can know the right thing to display.
    [self applyTheme];

    [self requestReviewIfAppropriate];

    [self.searchResultsController viewDidAppear:animated];

    self.hasEverAppeared = YES;
}

- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];

    [self.searchResultsController viewDidDisappear:animated];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    BOOL isBannerVisible = self.getStartedBanner.view && !self.getStartedBanner.view.isHidden;

    UIEdgeInsets newContentInset = UIEdgeInsetsZero;
    newContentInset.bottom = isBannerVisible ? self.getStartedBanner.opaqueHeight : 0;

    if (!UIEdgeInsetsEqualToEdgeInsets(self.tableView.contentInset, newContentInset)) {
        [UIView animateWithDuration:0.25 animations:^{ self.tableView.contentInset = newContentInset; }];
    }
}

- (void)updateBarButtonItems
{
    if (self.homeViewMode != HomeViewModeInbox) {
        return;
    }

    // Settings button.
    const NSUInteger kAvatarSize = 28;
    __block UIImage *_Nullable avatarImage = [OWSProfileManager.shared localProfileAvatarImage];
    if (avatarImage == nil) {
        [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
            avatarImage = [self.avatarBuilder avatarImageForLocalUserWithDiameterPoints:kAvatarSize
                                                                   localUserDisplayMode:LocalUserDisplayModeAsLocalUser
                                                                            transaction:transaction];
        }];
    }
    OWSAssertDebug(avatarImage);

    UIButton *avatarButton = [AvatarImageButton buttonWithType:UIButtonTypeCustom];
    avatarButton.accessibilityLabel = CommonStrings.openSettingsButton;
    [avatarButton addTarget:self action:@selector(showAppSettings) forControlEvents:UIControlEventTouchUpInside];
    [avatarButton setImage:avatarImage forState:UIControlStateNormal];
    [avatarButton autoSetDimension:ALDimensionWidth toSize:kAvatarSize];
    [avatarButton autoSetDimension:ALDimensionHeight toSize:kAvatarSize];

    UIView *avatarWrapper = [UIView containerView];
    [avatarWrapper addSubview:avatarButton];
    [avatarButton autoPinEdgesToSuperviewEdges];

    if (self.unreadPaymentNotificationsCount > 0) {
        [PaymentsViewUtils addUnreadBadgeToView:avatarWrapper];
    }

    UIBarButtonItem *settingsButton = [[UIBarButtonItem alloc] initWithCustomView:avatarWrapper];

    settingsButton.accessibilityLabel = CommonStrings.openSettingsButton;
    self.navigationItem.leftBarButtonItem = settingsButton;
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, settingsButton);

    UIBarButtonItem *compose = [[UIBarButtonItem alloc] initWithImage:[Theme iconImage:ThemeIconCompose24]
                                                                style:UIBarButtonItemStylePlain
                                                               target:self
                                                               action:@selector(showNewConversationView)];
    compose.accessibilityLabel
        = NSLocalizedString(@"COMPOSE_BUTTON_LABEL", @"Accessibility label from compose button.");
    compose.accessibilityHint = NSLocalizedString(
        @"COMPOSE_BUTTON_HINT", @"Accessibility hint describing what you can do with the compose button");
    compose.accessibilityIdentifier = ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"compose");

    UIBarButtonItem *camera = [[UIBarButtonItem alloc] initWithImage:[Theme iconImage:ThemeIconCameraButton]
                                                               style:UIBarButtonItemStylePlain
                                                              target:self
                                                              action:@selector(showCameraView)];
    camera.accessibilityLabel = NSLocalizedString(@"CAMERA_BUTTON_LABEL", @"Accessibility label for camera button.");
    camera.accessibilityHint = NSLocalizedString(
        @"CAMERA_BUTTON_HINT", @"Accessibility hint describing what you can do with the camera button");
    camera.accessibilityIdentifier = ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"camera");

    self.navigationItem.rightBarButtonItems = @[ compose, camera ];
}

- (void)showNewConversationView
{
    OWSAssertIsOnMainThread();

    OWSLogInfo(@"");

    // Dismiss any message actions if they're presented
    if (SSKFeatureFlags.contextMenus) {
        [self.conversationSplitViewController.selectedConversationViewController
            dismissMessageContextMenuWithAnimated:YES];
    } else {
        [self.conversationSplitViewController.selectedConversationViewController dismissMessageActionsWithAnimated:YES];
    }

    ComposeViewController *viewController = [ComposeViewController new];

    [self.contactsManagerImpl requestSystemContactsOnceWithCompletion:^(NSError *_Nullable error) {
        if (error) {
            OWSLogError(@"Error when requesting contacts: %@", error);
        }
        // Even if there is an error fetching contacts we proceed to the next screen.
        // As the compose view will present the proper thing depending on contact access.
        //
        // We just want to make sure contact access is *complete* before showing the compose
        // screen to avoid flicker.
        OWSNavigationController *modal = [[OWSNavigationController alloc] initWithRootViewController:viewController];
        [self.navigationController presentFormSheetViewController:modal animated:YES completion:nil];
    }];
}

- (void)showNewGroupView
{
    OWSAssertIsOnMainThread();

    OWSLogInfo(@"");

    // Dismiss any message actions if they're presented
    if (SSKFeatureFlags.contextMenus) {
        [self.conversationSplitViewController.selectedConversationViewController
            dismissMessageContextMenuWithAnimated:YES];
    } else {
        [self.conversationSplitViewController.selectedConversationViewController dismissMessageActionsWithAnimated:YES];
    }

    UIViewController *newGroupViewController = [NewGroupMembersViewController new];

    [self.contactsManagerImpl requestSystemContactsOnceWithCompletion:^(NSError *_Nullable error) {
        if (error) {
            OWSLogError(@"Error when requesting contacts: %@", error);
        }
        // Even if there is an error fetching contacts we proceed to the next screen.
        // As the compose view will present the proper thing depending on contact access.
        //
        // We just want to make sure contact access is *complete* before showing the compose
        // screen to avoid flicker.
        OWSNavigationController *modal =
            [[OWSNavigationController alloc] initWithRootViewController:newGroupViewController];
        [self.navigationController presentFormSheetViewController:modal animated:YES completion:nil];
    }];
}

- (void)focusSearch
{
    OWSAssertIsOnMainThread();

    OWSLogInfo(@"");

    // If we have presented a conversation list (the archive) search there instead.
    if (self.presentedHomeViewController) {
        [self.presentedHomeViewController focusSearch];
        return;
    }

    [self.searchBar becomeFirstResponder];
}

- (void)archiveSelectedConversation
{
    OWSAssertIsOnMainThread();

    OWSLogInfo(@"");

    TSThread *_Nullable selectedThread = self.conversationSplitViewController.selectedThread;

    if (!selectedThread) {
        return;
    }

    __block ThreadAssociatedData *threadAssociatedData;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        threadAssociatedData = [ThreadAssociatedData fetchOrDefaultForThread:selectedThread transaction:transaction];
    }];

    if (threadAssociatedData.isArchived) {
        return;
    }

    [self.conversationSplitViewController closeSelectedConversationAnimated:YES];

    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        [threadAssociatedData updateWithIsArchived:YES updateStorageService:YES transaction:transaction];
    });
    [self updateViewState];
}

- (void)unarchiveSelectedConversation
{
    OWSAssertIsOnMainThread();

    OWSLogInfo(@"");

    TSThread *_Nullable selectedThread = self.conversationSplitViewController.selectedThread;

    if (!selectedThread) {
        return;
    }

    __block ThreadAssociatedData *threadAssociatedData;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        threadAssociatedData = [ThreadAssociatedData fetchOrDefaultForThread:selectedThread transaction:transaction];
    }];

    if (!threadAssociatedData.isArchived) {
        return;
    }

    [self.conversationSplitViewController closeSelectedConversationAnimated:YES];

    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        [threadAssociatedData updateWithIsArchived:NO updateStorageService:YES transaction:transaction];
    });
    [self updateViewState];
}

- (void)showCameraView
{
    // Dismiss any message actions if they're presented
    if (SSKFeatureFlags.contextMenus) {
        [self.conversationSplitViewController.selectedConversationViewController
            dismissMessageContextMenuWithAnimated:YES];
    } else {
        [self.conversationSplitViewController.selectedConversationViewController dismissMessageActionsWithAnimated:YES];
    }

    [self ows_askForCameraPermissions:^(BOOL cameraGranted) {
        if (!cameraGranted) {
            OWSLogWarn(@"camera permission denied.");
            return;
        }
        [self ows_askForMicrophonePermissions:^(BOOL micGranted) {
            if (!micGranted) {
                OWSLogWarn(@"proceeding, though mic permission denied.");
                // We can still continue without mic permissions, but any captured video will
                // be silent.
            }

            CameraFirstCaptureNavigationController *cameraModal =
                [CameraFirstCaptureNavigationController cameraFirstModal];
            cameraModal.cameraFirstCaptureSendFlow.delegate = self;
            cameraModal.modalPresentationStyle = UIModalPresentationOverFullScreen;

            [self presentViewController:cameraModal animated:YES completion:nil];
        }];
    }];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    self.isViewVisible = YES;

    BOOL isShowingSearchResults = !self.searchResultsController.view.hidden;
    if (isShowingSearchResults) {
        OWSAssertDebug(self.searchBar.text.ows_stripped.length > 0);
        [self scrollSearchBarToTopAnimated:NO];
        [self.searchBar becomeFirstResponder];
    } else if (self.lastViewedThread) {
        OWSAssertDebug(self.searchBar.text.ows_stripped.length == 0);

        // When returning to conversation list, try to ensure that the "last" thread is still
        // visible.  The threads often change ordering while in conversation view due
        // to incoming & outgoing messages.
        NSIndexPath *_Nullable indexPathOfLastThread =
            [self.renderState indexPathForUniqueId:self.lastViewedThread.uniqueId];
        if (indexPathOfLastThread) {
            [self.tableView scrollToRowAtIndexPath:indexPathOfLastThread
                                  atScrollPosition:UITableViewScrollPositionNone
                                          animated:NO];
        }
    }

    [self applyDefaultBackButton];

    [self.searchResultsController viewWillAppear:animated];

    [self updateUnreadPaymentNotificationsCountWithSneakyTransaction];

    // During main app launch, the home view becomes visible _before_
    // app is foreground and active.  Therefore we need to make an
    // exception and update the view contents; otherwise, the home
    // view will briefly appear empty after launch. But to avoid
    // hurting first launch perf, we only want to make an exception
    // for a single load.
    if (!self.hasEverAppeared) {
        [self.loadCoordinator ensureFirstLoad];
    } else {
        [self ensureCellAnimations];
    }

    NSIndexPath *_Nullable selectedIndexPath = self.tableView.indexPathForSelectedRow;
    if (selectedIndexPath != nil) {
        // Deselect row when swiping back/returning to home view.
        [self.tableView deselectRowAtIndexPath:selectedIndexPath animated:NO];
    }
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];

    self.isViewVisible = NO;

    [self.searchResultsController viewWillDisappear:animated];
}

#pragma mark -

- (void)pullToRefreshPerformed:(UIRefreshControl *)refreshControl
{
    OWSAssertIsOnMainThread();
    OWSLogInfo(@"beggining refreshing.");

    [self.messageFetcherJob runObjc]
        .then(^{
            if (TSAccountManager.shared.isRegisteredPrimaryDevice) {
                return [AnyPromise promiseWithValue:nil];
            }

            return [SSKEnvironment.shared.syncManager sendAllSyncRequestMessagesWithTimeout:20];
        })
        .ensure(^{
            OWSLogInfo(@"ending refreshing.");
            [refreshControl endRefreshing];
        });
}

#pragma mark - UISearchBarDelegate

- (void)searchBarTextDidBeginEditing:(UISearchBar *)searchBar
{
    [self scrollSearchBarToTopAnimated:NO];

    [self updateSearchResultsVisibility];

    [self ensureSearchBarCancelButton];
}

- (void)searchBarTextDidEndEditing:(UISearchBar *)searchBar
{
    [self updateSearchResultsVisibility];

    [self ensureSearchBarCancelButton];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText
{
    [self updateSearchResultsVisibility];

    [self ensureSearchBarCancelButton];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar
{
    [self updateSearchResultsVisibility];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar
{
    self.searchBar.text = nil;

    [self dismissSearchKeyboard];

    [self updateSearchResultsVisibility];

    [self ensureSearchBarCancelButton];
}

- (void)ensureSearchBarCancelButton
{
    BOOL shouldShowCancelButton = (self.searchBar.isFirstResponder || self.searchBar.text.length > 0);
    if (self.searchBar.showsCancelButton == shouldShowCancelButton) {
        return;
    }
    [self.searchBar setShowsCancelButton:shouldShowCancelButton animated:self.isViewVisible];
}

- (void)updateSearchResultsVisibility
{
    OWSAssertIsOnMainThread();

    NSString *searchText = self.searchBar.text.ows_stripped;
    self.searchResultsController.searchText = searchText;
    BOOL isSearching = searchText.length > 0;
    self.searchResultsController.view.hidden = !isSearching;

    if (isSearching) {
        [self scrollSearchBarToTopAnimated:NO];
        self.tableView.scrollEnabled = NO;
    } else {
        self.tableView.scrollEnabled = YES;
    }
}

- (void)scrollSearchBarToTopAnimated:(BOOL)isAnimated
{
    CGFloat topInset = self.topLayoutGuide.length;
    [self.tableView setContentOffset:CGPointMake(0, -topInset) animated:isAnimated];
}

#pragma mark - ConversationSearchViewDelegate

- (void)conversationSearchViewWillBeginDragging
{
    [self dismissSearchKeyboard];
}

#pragma mark - HomeFeedTableViewCellDelegate

- (BOOL)isThreadPinned:(ThreadViewModel *)threadViewModel
{
    return [PinnedThreadManager isThreadPinned:threadViewModel.threadRecord];
}

- (void)presentThread:(TSThread *)thread action:(ConversationViewAction)action animated:(BOOL)isAnimated
{
    [BenchManager startEventWithTitle:@"Presenting Conversation"
                              eventId:[NSString stringWithFormat:@"presenting-conversation-%@", thread.uniqueId]];
    [self presentThread:thread action:action focusMessageId:nil animated:isAnimated];
}

- (void)presentThread:(TSThread *)thread
               action:(ConversationViewAction)action
       focusMessageId:(nullable NSString *)focusMessageId
             animated:(BOOL)isAnimated
{
    if (thread == nil) {
        OWSFailDebug(@"Thread unexpectedly nil");
        return;
    }

    [self.conversationSplitViewController presentThread:thread
                                                 action:action
                                         focusMessageId:focusMessageId
                                               animated:isAnimated];
}

- (BOOL)isConversationActiveForThread:(TSThread *)thread
{
    OWSAssertDebug(thread);

    return [self.conversationSplitViewController.selectedThread.uniqueId isEqualToString:thread.uniqueId];
}

#pragma mark Old Style

- (nullable UIViewController *)previewingContext:(id<UIViewControllerPreviewing>)previewingContext
                       viewControllerForLocation:(CGPoint)location
{
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:location];
    if ([self canPresentPreviewFromIndexPath:indexPath] == NO) {
        return nil;
    }

    [previewingContext setSourceRect:[self.tableView rectForRowAtIndexPath:indexPath]];
    return [self createPreviewControllerAtIndexPath:indexPath];
}

- (void)previewingContext:(id<UIViewControllerPreviewing>)previewingContext
     commitViewController:(UIViewController *)viewControllerToCommit
{
    [self commitPreviewController:viewControllerToCommit];
}

#pragma mark -

- (void)updateViewState
{
    if (self.shouldShowEmptyInboxView) {
        [self.tableView setHidden:YES];
        [self.emptyInboxView setHidden:NO];
        [self.firstConversationCueView setHidden:!self.shouldShowFirstConversationCue];
        [self updateFirstConversationLabel];
    } else {
        [self.tableView setHidden:NO];
        [self.emptyInboxView setHidden:YES];
        [self.firstConversationCueView setHidden:YES];
    }
}

- (BOOL)shouldShowFirstConversationCue
{
    __block BOOL hasSavedThread;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        hasSavedThread = [SSKPreferences hasSavedThreadWithTransaction:transaction];
    }];

    return self.shouldShowEmptyInboxView && !hasSavedThread;
}

- (BOOL)shouldShowEmptyInboxView
{
    return self.homeViewMode == HomeViewModeInbox && self.numberOfInboxThreads == 0
        && self.numberOfArchivedThreads == 0;
}

// We want to delay asking for a review until an opportune time.
// If the user has *just* launched Signal they intend to do something, we don't want to interrupt them.
- (void)requestReviewIfAppropriate
{
    static NSUInteger callCount = 0;
    callCount++;
    if (self.hasEverAppeared && callCount > 25) {
        OWSLogDebug(@"requesting review");
        // In Debug this pops up *every* time, which is helpful, but annoying.
        // In Production this will pop up at most 3 times per 365 days.
#ifndef DEBUG
        static dispatch_once_t onceToken;
        // Despite `SKStoreReviewController` docs, some people have reported seeing the "request review" prompt
        // repeatedly after first installation. Let's make sure it only happens at most once per launch.
        dispatch_once(&onceToken, ^{ [SKStoreReviewController requestReview]; });
#endif
    } else {
        OWSLogDebug(@"not requesting review");
    }
}

#pragma mark - CameraFirstCaptureDelegate

- (void)cameraFirstCaptureSendFlowDidComplete:(CameraFirstCaptureSendFlow *)cameraFirstCaptureSendFlow
{
    [self dismissViewControllerAnimated:true completion:nil];
}

- (void)cameraFirstCaptureSendFlowDidCancel:(CameraFirstCaptureSendFlow *)cameraFirstCaptureSendFlow
{
    [self dismissViewControllerAnimated:true completion:nil];
}

#pragma mark - <OWSGetStartedBannerViewControllerDelegate>

- (void)presentGetStartedBannerIfNecessary
{
    if (self.getStartedBanner || self.homeViewMode != HomeViewModeInbox) {
        return;
    }

    OWSGetStartedBannerViewController *getStartedVC = [[OWSGetStartedBannerViewController alloc] initWithDelegate:self];
    if (getStartedVC.hasIncompleteCards) {
        self.getStartedBanner = getStartedVC;

        [self addChildViewController:getStartedVC];
        [self.view addSubview:getStartedVC.view];
        [getStartedVC.view autoPinEdgesToSuperviewEdgesWithInsets:UIEdgeInsetsZero excludingEdge:ALEdgeTop];

        // If we're in landscape, the banner covers most of the screen
        // Hide it until we transition to portrait
        if (self.view.bounds.size.width > self.view.bounds.size.height) {
            getStartedVC.view.alpha = 0;
        }
    }
}

- (void)getStartedBannerDidTapCreateGroup:(OWSGetStartedBannerViewController *)banner
{
    [self showNewGroupView];
}

- (void)getStartedBannerDidTapAppearance:(OWSGetStartedBannerViewController *)banner
{
    [self showAppSettingsInAppearanceMode];
}

- (void)getStartedBannerDidTapAvatarBuilder:(OWSGetStartedBannerViewController *)banner
{
    [self showAppSettingsInAvatarBuilderMode];
}

- (void)getStartedBannerDidTapInviteFriends:(OWSGetStartedBannerViewController *)banner
{
    self.inviteFlow = [[OWSInviteFlow alloc] initWithPresentingViewController:self];
    [self.inviteFlow presentWithIsAnimated:YES completion:nil];
}

- (void)getStartedBannerDidDismissAllCards:(OWSGetStartedBannerViewController *)banner animated:(BOOL)isAnimated
{
    void (^dismissBlock)(void) = ^{
        [self.getStartedBanner.view removeFromSuperview];
        [self.getStartedBanner removeFromParentViewController];
        self.getStartedBanner = nil;
    };

    if (isAnimated) {
        [UIView animateWithDuration:0.5
            animations:^{ self.getStartedBanner.view.alpha = 0; }
            completion:^(BOOL finished) { dismissBlock(); }];
    } else {
        dismissBlock();
    }
}

@end

NS_ASSUME_NONNULL_END
