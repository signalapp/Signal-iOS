//
// Copyright 2014 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "RecipientPickerViewController.h"
#import "SignalApp.h"
#import <SignalCoreKit/NSString+OWS.h>
#import <SignalCoreKit/SignalCoreKit-Swift.h>
#import <SignalMessaging/Environment.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/SignalAccount.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSAccountManager.h>
#import <SignalUI/ContactsViewHelper.h>
#import <SignalUI/OWSTableViewController.h>
#import <SignalUI/SignalUI-Swift.h>
#import <SignalUI/UIUtil.h>
#import <SignalUI/UIView+SignalUI.h>

NS_ASSUME_NONNULL_BEGIN

@interface SignalAccount (Collation)

- (NSString *)stringForCollation;

@end

@implementation SignalAccount (Collation)

- (NSString *)stringForCollation
{
    return [self.contactsManagerImpl comparableNameForSignalAccountWithSneakyTransaction:self];
}

@end

const NSUInteger kMinimumSearchLength = 1;

@interface RecipientPickerViewController () <UISearchBarDelegate,
    ContactsViewHelperObserver,
    OWSTableViewControllerDelegate>

@property (nonatomic, readonly) UIStackView *signalContactsStackView;

@property (nonatomic, readonly) UIView *noSignalContactsView;

@property (nonatomic, readonly) OWSTableViewController2 *tableViewController;

@property (nonatomic, readonly) UILocalizedIndexedCollation *collation;

@property (nonatomic, nullable, readonly) OWSSearchBar *searchBar;
@property (nonatomic, nullable) ComposeScreenSearchResultSet *searchResults;
@property (nonatomic, nullable) NSString *lastSearchText;

@property (nonatomic) BOOL isNoContactsModeActive;

@end

#pragma mark -

@implementation RecipientPickerViewController

@synthesize pickedRecipients = _pickedRecipients;

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    _allowsAddByPhoneNumber = YES;
    _shouldHideLocalRecipient = YES;
    _selectionMode = RecipientPickerViewControllerSelectionModeDefault;
    _groupsToShow = RecipientPickerViewControllerGroupsToShow_ShowGroupsThatUserIsMemberOfWhenSearching;
    _shouldShowInvites = NO;
    _shouldShowAlphabetSlider = YES;

    return self;
}

- (void)loadView
{
    [super loadView];

    _signalContactsStackView = [UIStackView new];
    self.signalContactsStackView.axis = UILayoutConstraintAxisVertical;
    self.signalContactsStackView.alignment = UIStackViewAlignmentFill;
    [self.view addSubview:self.signalContactsStackView];
    [self.signalContactsStackView autoPinEdgesToSuperviewEdges];

    _searchResults = nil;
    [self.contactsViewHelper addObserver:self];
    _collation = [UILocalizedIndexedCollation currentCollation];

    // Search
    OWSSearchBar *searchBar = [OWSSearchBar new];
    _searchBar = searchBar;
    searchBar.delegate = self;
    if (SSKFeatureFlags.usernames) {
        searchBar.placeholder = OWSLocalizedString(@"SEARCH_BY_NAME_OR_USERNAME_OR_NUMBER_PLACEHOLDER_TEXT",
            @"Placeholder text indicating the user can search for contacts by name, username, or phone number.");
    } else {
        searchBar.placeholder = OWSLocalizedString(@"SEARCH_BYNAMEORNUMBER_PLACEHOLDER_TEXT",
            @"Placeholder text indicating the user can search for contacts by name or phone number.");
    }
    [searchBar sizeToFit];

    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, searchBar);
    searchBar.textField.accessibilityIdentifier = ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"contact_search");
    [self.signalContactsStackView addArrangedSubview:searchBar];
    [searchBar setCompressionResistanceVerticalHigh];
    [searchBar setContentHuggingVerticalHigh];

    for (UIView *view in self.delegate.recipientPickerCustomHeaderViews) {
        [self.signalContactsStackView addArrangedSubview:view];
    }

    _tableViewController = [OWSTableViewController2 new];
    _tableViewController.delegate = self;

    self.tableViewController.defaultSeparatorInsetLeading = OWSTableViewController2.cellHInnerMargin
        + AvatarBuilder.smallAvatarSizePoints + ContactCellView.avatarTextHSpacing;

    [self addChildViewController:self.tableViewController];
    [self.signalContactsStackView addArrangedSubview:self.tableViewController.view];
    [self.tableViewController.view setCompressionResistanceVerticalLow];
    [self.tableViewController.view setContentHuggingVerticalLow];
    [self.tableViewController.tableView registerClass:[ContactTableViewCell class]
                               forCellReuseIdentifier:ContactTableViewCell.reuseIdentifier];
    [self.tableViewController.tableView registerClass:[NonContactTableViewCell class]
                               forCellReuseIdentifier:NonContactTableViewCell.reuseIdentifier];

    _noSignalContactsView = [self createNoSignalContactsView];
    self.noSignalContactsView.hidden = YES;
    [self.view addSubview:self.noSignalContactsView];
    [self.noSignalContactsView autoPinWidthToSuperview];
    [self.noSignalContactsView autoPinEdgeToSuperviewEdge:ALEdgeTop];
    [self.noSignalContactsView autoPinToBottomLayoutGuideOfViewController:self withInset:0];
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, _noSignalContactsView);

    UIRefreshControl *pullToRefreshView = [UIRefreshControl new];
    pullToRefreshView.tintColor = [UIColor grayColor];
    [pullToRefreshView addTarget:self
                          action:@selector(pullToRefreshPerformed:)
                forControlEvents:UIControlEventValueChanged];
    self.tableViewController.tableView.refreshControl = pullToRefreshView;
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, pullToRefreshView);

    [self updateTableContents];
}

- (UITableView *)tableView {
    return self.tableViewController.tableView;
}

- (void)viewSafeAreaInsetsDidChange
{
    [super viewSafeAreaInsetsDidChange];
    [self updateSearchBarMargins];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    [self updateSearchBarMargins];
}

- (void)updateSearchBarMargins
{
    // This should ideally compute the insets for self.tableView, but that
    // view's size hasn't been updated when the viewDidLayoutSubviews method is
    // called. As a quick fix, use self.view's size, which matches the eventual
    // width of self.tableView. (A more complete fix would likely add a
    // callback when self.tableView’s size is available.)
    self.searchBar.layoutMargins = [OWSTableViewController2 cellOuterInsetsIn:self.view];
}

- (void)pullToRefreshPerformed:(UIRefreshControl *)refreshControl
{
    OWSAssertIsOnMainThread();
    OWSLogInfo(@"beginning refreshing.");

    AnyPromise *refreshPromise;
    if (self.tsAccountManager.isRegisteredPrimaryDevice) {
        // primary *only* does contact refresh
        refreshPromise = [self.contactsManagerImpl userRequestedSystemContactsRefresh];
    } else if (!SSKFeatureFlags.contactDiscoveryV2) {
        refreshPromise = [self.contactsManagerImpl userRequestedSystemContactsRefresh].then(^(id value) {
            return [self.syncManager sendAllSyncRequestMessagesWithTimeout:20];
        });
    } else {
        refreshPromise = [self.syncManager sendAllSyncRequestMessagesWithTimeout:20];
    }

    refreshPromise.ensure(^{
        OWSLogInfo(@"ending refreshing.");
        [refreshControl endRefreshing];
    });
}

- (UIView *)createNoSignalContactsView
{
    UIImage *heroImage = [UIImage imageNamed:@"uiEmptyContact"];
    OWSAssertDebug(heroImage);
    UIImageView *heroImageView = [[UIImageView alloc] initWithImage:heroImage];
    heroImageView.layer.minificationFilter = kCAFilterTrilinear;
    heroImageView.layer.magnificationFilter = kCAFilterTrilinear;
    const CGFloat kHeroSize = ScaleFromIPhone5To7Plus(100, 150);
    [heroImageView autoSetDimension:ALDimensionWidth toSize:kHeroSize];
    [heroImageView autoSetDimension:ALDimensionHeight toSize:kHeroSize];

    UILabel *titleLabel = [UILabel new];
    titleLabel.text = OWSLocalizedString(
        @"EMPTY_CONTACTS_LABEL_LINE1", "Full width label displayed when attempting to compose message");
    titleLabel.textColor = Theme.primaryTextColor;
    titleLabel.font = [UIFont ows_semiboldFontWithSize:ScaleFromIPhone5To7Plus(17.f, 20.f)];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.lineBreakMode = NSLineBreakByWordWrapping;
    titleLabel.numberOfLines = 0;

    UILabel *subtitleLabel = [UILabel new];
    subtitleLabel.text = OWSLocalizedString(
        @"EMPTY_CONTACTS_LABEL_LINE2", "Full width label displayed when attempting to compose message");
    subtitleLabel.textColor = Theme.secondaryTextAndIconColor;
    subtitleLabel.font = [UIFont ows_regularFontWithSize:ScaleFromIPhone5To7Plus(12.f, 14.f)];
    subtitleLabel.textAlignment = NSTextAlignmentCenter;
    subtitleLabel.lineBreakMode = NSLineBreakByWordWrapping;
    subtitleLabel.numberOfLines = 0;

    UIStackView *headerStack = [[UIStackView alloc] initWithArrangedSubviews:@[
        heroImageView,
        [UIView spacerWithHeight:30],
        titleLabel,
        [UIView spacerWithHeight:15],
        subtitleLabel,
    ]];
    headerStack.axis = UILayoutConstraintAxisVertical;
    headerStack.alignment = UIStackViewAlignmentCenter;

    UIStackView *buttonStack = [[UIStackView alloc] init];
    buttonStack.axis = UILayoutConstraintAxisVertical;
    buttonStack.alignment = UIStackViewAlignmentFill;
    buttonStack.spacing = 16;

    void (^addButton)(NSString *, SEL, NSString *, ThemeIcon, NSUInteger)
        = ^(NSString *title,
            SEL selector,
            NSString *accessibilityIdentifierName,
            ThemeIcon icon,
            NSUInteger innerIconSize) {
              UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
              [button addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside];
              SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, button);
              button.accessibilityIdentifier = ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, accessibilityIdentifierName);
              [buttonStack addArrangedSubview:button];

              UIView *iconView = [OWSTableItem buildIconInCircleViewWithIcon:icon innerIconSize:innerIconSize];
              iconView.backgroundColor = self.tableViewController.cellBackgroundColor;

              UILabel *label = [UILabel new];
              label.text = title;
              label.font = [UIFont ows_regularFontWithSize:17.f];
              label.textColor = Theme.primaryTextColor;
              label.lineBreakMode = NSLineBreakByTruncatingTail;

              UIStackView *hStack = [[UIStackView alloc] initWithArrangedSubviews:@[
                  iconView,
                  label,
              ]];
              hStack.axis = UILayoutConstraintAxisHorizontal;
              hStack.alignment = UIStackViewAlignmentCenter;
              hStack.spacing = 12;
              hStack.userInteractionEnabled = NO;
              [button addSubview:hStack];
              [hStack autoPinEdgesToSuperviewEdges];
          };

    if (self.shouldShowNewGroup) {
        addButton(OWSLocalizedString(@"NEW_GROUP_BUTTON", comment
                                    : @"Label for the 'create new group' button."),
            @selector(newGroupButtonPressed),
            @"newGroupButton",
            ThemeIconComposeNewGroupLarge,
            35);
    }

    if (self.allowsAddByPhoneNumber) {
        addButton(OWSLocalizedString(@"NO_CONTACTS_SEARCH_BY_PHONE_NUMBER",
                      @"Label for a button that lets users search for contacts by phone number"),
            @selector(hideBackgroundView),
            @"searchByPhoneNumberButton",
            ThemeIconComposeFindByPhoneNumberLarge,
            42);
    }

    if (self.shouldShowInvites) {
        addButton(OWSLocalizedString(@"INVITE_FRIENDS_CONTACT_TABLE_BUTTON",
                      "Label for the cell that presents the 'invite contacts' workflow."),
            @selector(presentInviteFlow),
            @"inviteContactsButton",
            ThemeIconComposeInviteLarge,
            38);
    }

    UIStackView *stackView = [[UIStackView alloc] initWithArrangedSubviews:@[
        headerStack,
        buttonStack,
    ]];
    stackView.axis = UILayoutConstraintAxisVertical;
    stackView.alignment = UIStackViewAlignmentCenter;
    stackView.spacing = 50;
    stackView.layoutMarginsRelativeArrangement = YES;
    stackView.layoutMargins = UIEdgeInsetsMake(20, 20, 20, 20);

    UIView *view = [UIView new];
    view.backgroundColor = self.tableViewController.tableBackgroundColor;
    [view addSubview:stackView];
    [stackView autoPinWidthToSuperview];
    [stackView autoVCenterInSuperview];
    return view;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.title = OWSLocalizedString(@"MESSAGE_COMPOSEVIEW_TITLE", @"");

    [self applyTheme];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    // Make sure we have requested contact access at this point if, e.g.
    // the user has no messages in their inbox and they choose to compose
    // a message.
    [self.contactsManagerImpl requestSystemContactsOnce];

    [self showContactAppropriateViews];
}

#pragma mark - Table Contents

- (void)reloadContent
{
    [self updateTableContents];
}

- (void)updateTableContents
{
    OWSAssertIsOnMainThread();

    OWSTableContents *contents = [OWSTableContents new];

    if (self.isNoContactsModeActive) {
        self.tableViewController.contents = contents;
        return;
    }

    __weak __typeof(self) weakSelf = self;

    // App is killed and restarted when the user changes their contact
    // permissions, so no need to "observe" anything to re-render this.
    OWSTableSection *reminderSection = [self contactAccessReminderSection];
    if (reminderSection != nil) {
        [contents addSection:reminderSection];
    }

    OWSTableSection *staticSection = [OWSTableSection new];
    staticSection.separatorInsetLeading = @(OWSTableViewController2.cellHInnerMargin + 24 + OWSTableItem.iconSpacing);

    BOOL isSearching = self.searchResults != nil;

    if (self.shouldShowNewGroup && !isSearching) {
        [staticSection addItem:[OWSTableItem disclosureItemWithIcon:ThemeIconComposeNewGroup
                                                               name:OWSLocalizedString(
                                                                        @"NEW_GROUP_BUTTON", comment
                                                                        : @"Label for the 'create new group' button.")
                                                      accessoryText:nil
                                            accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(
                                                                        RecipientPickerViewController, @"new_group")
                                                        actionBlock:^{ [weakSelf newGroupButtonPressed]; }]];
    }

    // Find Non-Contacts by Phone Number
    if (self.allowsAddByPhoneNumber && !isSearching) {
        [staticSection
            addItem:[OWSTableItem
                         disclosureItemWithIcon:ThemeIconComposeFindByPhoneNumber
                                           name:OWSLocalizedString(@"NEW_CONVERSATION_FIND_BY_PHONE_NUMBER",
                                                    @"A label the cell that lets you add a new member to a group.")
                                  accessoryText:nil
                        accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(
                                                    RecipientPickerViewController, @"find_by_phone")
                                    actionBlock:^{
                                        typeof(self) strongSelf = weakSelf;
                                        if (!strongSelf) {
                                            return;
                                        }
                                        FindByPhoneNumberViewController *viewController =
                                            [[FindByPhoneNumberViewController alloc]
                                                        initWithDelegate:strongSelf
                                                              buttonText:strongSelf.findByPhoneNumberButtonTitle
                                                requiresRegisteredNumber:strongSelf.selectionMode !=
                                                RecipientPickerViewControllerSelectionModeBlocklist];
                                        [strongSelf.navigationController pushViewController:viewController
                                                                                   animated:YES];
                                    }]];
    }

    if (self.shouldShowInvites && !isSearching && self.contactsManagerImpl.sharingAuthorization != ContactAuthorizationForSharingDenied) {
        // Invite Contacts
        [staticSection
            addItem:[OWSTableItem
                         disclosureItemWithIcon:ThemeIconComposeInvite
                                           name:OWSLocalizedString(@"INVITE_FRIENDS_CONTACT_TABLE_BUTTON",
                                                    @"Label for the cell that presents the 'invite contacts' workflow.")
                                  accessoryText:nil
                        accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(
                                                    RecipientPickerViewController, @"invite_contacts")
                                    actionBlock:^{ [weakSelf presentInviteFlow]; }]];
    }

    if (staticSection.itemCount > 0) {
        [contents addSection:staticSection];
    }

    // Render any non-contact picked recipients
    if (self.pickedRecipients.count > 0 && self.searchResults == nil) {
        OWSTableSection *pickedSection = [OWSTableSection new];

        BOOL hadNonContactRecipient = NO;
        for (PickedRecipient *recipient in self.pickedRecipients) {
            if (self.shouldHideLocalRecipient &&
                [recipient.address isEqualToAddress:self.contactsViewHelper.localAddress]) {
                continue;
            }

            if (![self.contactsViewHelper fetchSignalAccountForAddress:recipient.address]) {
                hadNonContactRecipient = YES;
                [pickedSection addItem:[self itemForRecipient:recipient]];
            }
        }

        // If we have non-contact selections, add a title to the picked section
        if (hadNonContactRecipient) {
            pickedSection.headerTitle = OWSLocalizedString(@"NEW_GROUP_NON_CONTACTS_SECTION_TITLE",
                @"a title for the selected section of the 'recipient picker' view.");
            [contents addSection:pickedSection];
        }
    }

    if (self.searchResults != nil) {
        for (OWSTableSection *section in [self contactsSectionsForSearchResults:self.searchResults]) {
            [contents addSection:section];
        }
    } else {
        // Count the non-collated sections, before we add our collated sections.
        // Later we'll need to offset which sections our collation indexes reference
        // by this amount. e.g. otherwise the "B" index will reference names starting with "A"
        // And the "A" index will reference the static non-collated section(s).
        NSInteger beforeContactsSectionCount = (NSInteger)contents.sections.count;
        for (OWSTableSection *section in [self contactsSection]) {
            [contents addSection:section];
        }

        if (self.shouldShowAlphabetSlider) {
            __weak OWSTableContents *weakContents = contents;
            contents.sectionForSectionIndexTitleBlock = ^NSInteger(NSString *_Nonnull title, NSInteger index) {
                typeof(self) strongSelf = weakSelf;
                OWSTableContents *_Nullable strongContents = weakContents;
                if (strongSelf == nil || strongContents == nil) {
                    return 0;
                }

                // Offset the collation section to account for the noncollated sections.
                NSInteger sectionIndex =
                    [strongSelf.collation sectionForSectionIndexTitleAtIndex:index] + beforeContactsSectionCount;
                if (sectionIndex < 0) {
                    // Sentinel in case we change our section ordering in a surprising way.
                    OWSCFailDebug(@"Unexpected negative section index");
                    return 0;
                }
                if (sectionIndex >= (NSInteger)strongContents.sections.count) {
                    // Sentinel in case we change our section ordering in a surprising way.
                    OWSCFailDebug(@"Unexpectedly large index");
                    return 0;
                }

                return sectionIndex;
            };
            contents.sectionIndexTitlesForTableViewBlock = ^NSArray<NSString *> *_Nonnull
            {
                typeof(self) strongSelf = weakSelf;
                if (!strongSelf) {
                    return @[];
                }

                return strongSelf.collation.sectionTitles;
            };
        }
    }

    self.tableViewController.contents = contents;
}

- (NSArray<OWSTableSection *> *)contactsSection
{
    NSArray<SignalAccount *> *signalAccountsToShow = [self filteredSignalAccounts];

    if (signalAccountsToShow.count == 0) {
        return @[ [self noContactsTableSection] ];
    }

    NSMutableArray<OWSTableSection *> *contactSections = [NSMutableArray new];

    if (self.shouldShowAlphabetSlider) {
        NSMutableArray<NSMutableArray<SignalAccount *> *> *collatedSignalAccounts = [NSMutableArray new];
        for (NSUInteger i = 0; i < self.collation.sectionTitles.count; i++) {
            collatedSignalAccounts[i] = [NSMutableArray new];
        }
        for (SignalAccount *signalAccount in signalAccountsToShow) {
            NSInteger section = [self.collation sectionForObject:signalAccount
                                         collationStringSelector:@selector(stringForCollation)];

            if (section < 0) {
                OWSFailDebug(@"Unexpected collation for name:%@", signalAccount.stringForCollation);
                continue;
            }
            NSUInteger sectionIndex = (NSUInteger)section;

            [collatedSignalAccounts[sectionIndex] addObject:signalAccount];
        }

        for (NSUInteger i = 0; i < collatedSignalAccounts.count; i++) {
            NSArray<SignalAccount *> *signalAccounts = collatedSignalAccounts[i];
            NSMutableArray<OWSTableItem *> *contactItems = [NSMutableArray new];
            for (SignalAccount *signalAccount in signalAccounts) {
                PickedRecipient *recipient = [PickedRecipient forAddress:signalAccount.recipientAddress];
                [contactItems addObject:[self itemForRecipient:recipient]];
            }

            // Don't show empty sections.
            // To accomplish this we add a section with a blank title rather than omitting the section altogether,
            // in order for section indexes to match up correctly
            NSString *sectionTitle = contactItems.count > 0 ? self.collation.sectionTitles[i] : nil;
            [contactSections addObject:[self buildSectionWithTitle:sectionTitle.uppercaseString items:contactItems]];
        }
    } else {
        OWSTableSection *contactsSection =
            [self buildSectionWithTitle:OWSLocalizedString(@"COMPOSE_MESSAGE_CONTACT_SECTION_TITLE",
                                            @"Table section header for contact listing when composing a new message")];

        for (SignalAccount *signalAccount in signalAccountsToShow) {
            [contactsSection
                addItem:[self itemForRecipient:[PickedRecipient forAddress:signalAccount.recipientAddress]]];
        }

        [contactSections addObject:contactsSection];
    }

    return [contactSections copy];
}

- (OWSTableSection *)buildSectionWithTitle:(nullable NSString *)sectionTitle
{
    return [self buildSectionWithTitle:sectionTitle items:@[]];
}

- (OWSTableSection *)buildSectionWithTitle:(nullable NSString *)sectionTitle items:(NSArray<OWSTableItem *> *)items
{
    OWSTableSection *section = [OWSTableSection new];
    [section addItems:items];

    if (sectionTitle != nil) {
        section.headerTitle = sectionTitle;
    }

    return section;
}

- (NSArray<OWSTableSection *> *)contactsSectionsForSearchResults:(ComposeScreenSearchResultSet *)searchResults
{
    NSMutableArray<OWSTableSection *> *sections = [NSMutableArray new];

    // Contacts, filtered with the search text.
    NSArray<SignalAccount *> *filteredSignalAccounts = searchResults.signalAccounts;
    __block BOOL hasSearchResults = NO;

    NSMutableSet<NSString *> *matchedAccountPhoneNumbers = [NSMutableSet new];

    OWSTableSection *contactsSection =
        [self buildSectionWithTitle:OWSLocalizedString(@"COMPOSE_MESSAGE_CONTACT_SECTION_TITLE",
                                        @"Table section header for contact listing when composing a new message")];

    OWSAssertIsOnMainThread();
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        NSSet<SignalServiceAddress *> *addressesToSkip = [self.blockingManager blockedAddressesWithTransaction:transaction];

        for (SignalAccount *signalAccount in filteredSignalAccounts) {
            if ([addressesToSkip containsObject:signalAccount.recipientAddress]) {
                continue;
            }

            NSString *_Nullable phoneNumber = signalAccount.recipientAddress.phoneNumber;
            if (phoneNumber) {
                [matchedAccountPhoneNumbers addObject:phoneNumber];
            }

            PickedRecipient *recipient = [PickedRecipient forAddress:signalAccount.recipientAddress];
            [contactsSection addItem:[self itemForRecipient:recipient]];
        }
    }];
    if (contactsSection.itemCount > 0) {
        hasSearchResults = YES;
        [sections addObject:contactsSection];
    }

    OWSTableSection *groupSection = [self groupSectionForSearchResults:searchResults];
    if (groupSection != nil) {
        hasSearchResults = YES;
        [sections addObject:groupSection];
    }

    OWSTableSection *findByNumberSection = [self findByNumberSectionForSearchResults:searchResults
                                                                skippingPhoneNumbers:matchedAccountPhoneNumbers];
    if (findByNumberSection != nil) {
        hasSearchResults = YES;
        [sections addObject:findByNumberSection];
    }

    OWSTableSection *usernameSection = [self findByUsernameSectionForSearchResults:searchResults];
    if (usernameSection != nil) {
        hasSearchResults = YES;
        [sections addObject:usernameSection];
    }

    if (!hasSearchResults) {
        // No Search Results
        OWSTableSection *noResultsSection = [OWSTableSection new];
        [noResultsSection
            addItem:[OWSTableItem softCenterLabelItemWithText:
                     OWSLocalizedString(@"SETTINGS_BLOCK_LIST_NO_SEARCH_RESULTS",
                                          @"A label that indicates the user's search has no matching results.")
                                              customRowHeight:UITableViewAutomaticDimension]];

        [sections addObject:noResultsSection];
    }

    return [sections copy];
}


- (void)setPickedRecipients:(nullable NSArray<PickedRecipient *> *)pickedRecipients
{
    @synchronized(self) {
        _pickedRecipients = pickedRecipients;
    }
    [self updateTableContents];
}

- (nullable NSArray<PickedRecipient *> *)pickedRecipients
{
    @synchronized(self) {
        return _pickedRecipients;
    }
}

#pragma mark - No Contacts Mode

- (void)hideBackgroundView
{
    [Environment.shared.preferences setHasDeclinedNoContactsView:YES];

    [self showContactAppropriateViews];
}

- (void)presentInviteFlow
{
    OWSInviteFlow *inviteFlow = [[OWSInviteFlow alloc] initWithPresentingViewController:self];
    self.inviteFlow = inviteFlow;
    [inviteFlow presentWithIsAnimated:YES completion:nil];
}

- (void)showContactAppropriateViews
{
    self.isNoContactsModeActive = [self shouldNoContactsModeBeActive];
}

- (void)newGroupButtonPressed
{
    [self.delegate recipientPickerNewGroupButtonWasPressed];
}

- (void)setIsNoContactsModeActive:(BOOL)isNoContactsModeActive
{
    if (isNoContactsModeActive == _isNoContactsModeActive) {
        return;
    }

    _isNoContactsModeActive = isNoContactsModeActive;

    if (isNoContactsModeActive) {
        self.signalContactsStackView.hidden = YES;
        self.noSignalContactsView.hidden = NO;
    } else {
        self.signalContactsStackView.hidden = NO;
        self.noSignalContactsView.hidden = YES;
    }

    [self updateTableContents];
}

- (void)clearSearchText
{
    self.searchBar.text = @"";
    [self searchTextDidChange];
}

#pragma mark - OWSTableViewControllerDelegate

- (void)tableViewWillBeginDragging
{
    [self.searchBar resignFirstResponder];
    [self.delegate recipientPickerTableViewWillBeginDragging:self];
}

#pragma mark - ContactsViewHelperObserver

- (void)contactsViewHelperDidUpdateContacts
{
    [self updateTableContents];

    [self showContactAppropriateViews];
}

#pragma mark - UISearchBarDelegate

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText
{
    NSString *eventId = [NSString stringWithFormat:@"Compose Search - %@", searchText];
    [BenchManager startEventWithTitle:@"Compose Search" eventId:eventId];
    [self searchTextDidChange];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar
{
    [self searchTextDidChange];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar
{
    [self searchTextDidChange];
}

- (void)searchBarResultsListButtonClicked:(UISearchBar *)searchBar
{
    [self searchTextDidChange];
}

- (void)searchBar:(UISearchBar *)searchBar selectedScopeButtonIndexDidChange:(NSInteger)selectedScope
{
    [self searchTextDidChange];
}

- (void)setSearchResults:(nullable ComposeScreenSearchResultSet *)searchResults
{
    if (searchResults == nil) {
        if (self.searchText.length >= kMinimumSearchLength) {
            OWSLogVerbose(@"user has entered text since clearing results. Skipping stale results.");
            return;
        }
    } else {
        if (![searchResults.searchText isEqualToString:self.searchText]) {
            OWSLogVerbose(@"user has changed text since search started. Skipping stale results.");
            return;
        }
    }

    if (![NSObject isNullableObject:_searchResults equalTo:searchResults]) {
        OWSLogVerbose(@"showing search results for term: %@", searchResults.searchText);
        _searchResults = searchResults;
        [self updateTableContents];
    }
}

- (void)searchTextDidChange
{
    NSString *searchText = self.searchText;

    if (searchText.length < kMinimumSearchLength) {
        self.searchResults = nil;
        self.lastSearchText = nil;
        return;
    }

    if ([NSObject isNullableObject:self.lastSearchText equalTo:searchText]) {
        return;
    }

    self.lastSearchText = searchText;

    __weak __typeof(self) weakSelf = self;

    __block ComposeScreenSearchResultSet *searchResults;
    [self.databaseStorage
        asyncReadWithBlock:^(SDSAnyReadTransaction *transaction) {
            searchResults =
                [self.fullTextSearcher searchForComposeScreenWithSearchText:searchText
                                                              omitLocalUser:self.shouldHideLocalRecipient
                                                                 maxResults:FullTextSearcher.kDefaultMaxResults
                                                                transaction:transaction];
        }
        completion:^{
            __typeof(self) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }
            if (![NSObject isNullableObject:strongSelf.lastSearchText equalTo:searchText]) {
                // Discard obsolete search results.
                return;
            }
            strongSelf.searchResults = searchResults;
            NSString *eventId = [NSString stringWithFormat:@"Compose Search - %@", searchResults.searchText];
            [BenchManager completeEventWithEventId:eventId];
        }];
}

#pragma mark -

- (NSString *)searchText
{
    NSString *rawText = self.searchBar.text;
    return rawText.ows_stripped ?: @"";
}

#pragma mark - Theme

- (void)applyTheme
{
    OWSAssertIsOnMainThread();

    [super applyTheme];

    [self.tableViewController applyThemeToViewController:self];
    self.preferredNavigationBarStyle = OWSNavigationBarStyleSolid;
    self.navbarBackgroundColorOverride = self.tableViewController.tableBackgroundColor;
    self.searchBar.searchFieldBackgroundColorOverride = Theme.searchFieldElevatedBackgroundColor;
    self.tableViewController.tableView.sectionIndexColor = Theme.primaryTextColor;
    if ([self.navigationController isKindOfClass:[OWSNavigationController class]]) {
        [(OWSNavigationController *)self.navigationController updateNavbarAppearanceWithAnimated:NO];
    }
}

- (void)applyThemeToViewController:(UIViewController *)viewController
{
    [self.tableViewController applyThemeToViewController:viewController];
}

@end

NS_ASSUME_NONNULL_END
