//
// Copyright 2014 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "RecipientPickerViewController.h"
#import "SignalApp.h"
#import <MessageUI/MessageUI.h>
#import <SignalCoreKit/NSString+OWS.h>
#import <SignalCoreKit/SignalCoreKit-Swift.h>
#import <SignalMessaging/Environment.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/AppVersion.h>
#import <SignalServiceKit/PhoneNumberUtil.h>
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
    OWSTableViewControllerDelegate,
    FindByPhoneNumberDelegate,
    MFMessageComposeViewControllerDelegate>

@property (nonatomic, readonly) UIStackView *signalContactsStackView;

@property (nonatomic, readonly) UIView *noSignalContactsView;

@property (nonatomic, readonly) OWSTableViewController2 *tableViewController;

@property (nonatomic, readonly) UILocalizedIndexedCollation *collation;

@property (nonatomic, nullable, readonly) OWSSearchBar *searchBar;
@property (nonatomic, nullable) ComposeScreenSearchResultSet *searchResults;
@property (nonatomic, nullable) NSString *lastSearchText;
@property (nonatomic, nullable) OWSInviteFlow *inviteFlow;

// A list of possible phone numbers parsed from the search text as
// E164 values.
@property (nonatomic) NSArray<NSString *> *searchPhoneNumbers;

// This set is used to cache the set of non-contact phone numbers
// which are known to correspond to Signal accounts.
@property (nonatomic, readonly) NSMutableSet<SignalServiceAddress *> *nonContactAccountSet;

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
    _allowsSelectingUnregisteredPhoneNumbers = YES;
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
    _nonContactAccountSet = [NSMutableSet set];
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

    [self.contactsManagerImpl userRequestedSystemContactsRefresh]
        .then(^(id value) {
            if (TSAccountManager.shared.isRegisteredPrimaryDevice) {
                return [AnyPromise promiseWithValue:@1];
            }

            return [SSKEnvironment.shared.syncManager sendAllSyncRequestMessagesWithTimeout:20];
        })
        .ensure(^{
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

    [self.contactsViewHelper warmNonSignalContactsCacheAsync];

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

    // App is killed and restarted when the user changes their contact permissions, so need need to "observe" anything
    // to re-render this.
    if (self.contactsManagerImpl.isSystemContactsDenied) {
        OWSTableItem *contactReminderItem = [OWSTableItem
            itemWithCustomCellBlock:^{
                UITableViewCell *cell = [OWSTableItem newCell];

                ReminderView *reminderView = [ReminderView
                    nagWithText:OWSLocalizedString(@"COMPOSE_SCREEN_MISSING_CONTACTS_PERMISSION",
                                    @"Multi-line label explaining why compose-screen contact picker is empty.")
                      tapAction:^{
                    [CurrentAppContext() openSystemSettings];
                      }];
                [cell.contentView addSubview:reminderView];
                [reminderView autoPinEdgesToSuperviewEdges];

                cell.accessibilityIdentifier
                    = ACCESSIBILITY_IDENTIFIER_WITH_NAME(RecipientPickerViewController, @"missing_contacts");

                return cell;
            }
                        actionBlock:nil];

        OWSTableSection *reminderSection = [OWSTableSection new];
        [reminderSection addItem:contactReminderItem];
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
                                                requiresRegisteredNumber:!strongSelf
                                                                              .allowsSelectingUnregisteredPhoneNumbers];
                                        [strongSelf.navigationController pushViewController:viewController
                                                                                   animated:YES];
                                    }]];
    }

    if (self.contactsManagerImpl.isSystemContactsAuthorized && self.shouldShowInvites && !isSearching) {
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

- (NSArray<SignalAccount *> *)allSignalAccounts
{
    return [self.contactsViewHelper signalAccountsIncludingLocalUser:!self.shouldHideLocalRecipient];
}

- (NSArray<OWSTableSection *> *)contactsSection
{
    NSArray<SignalAccount *> *signalAccountsToShow = self.allSignalAccounts;

    // As an optimization, we can skip the database lookup if you have no connections.
    if (self.allSignalAccounts.count > 0) {
        __block NSSet<SignalServiceAddress *> *addressesToSkip;
        [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
            addressesToSkip = [self.blockingManager blockedAddressesWithTransaction:transaction];
        }];

        // This is an optimization for users that have no blocked addresses.
        if (addressesToSkip.count > 0) {
            NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(SignalAccount *signalAccount,
                NSDictionary *bindings) { return ![addressesToSkip containsObject:signalAccount.recipientAddress]; }];
            signalAccountsToShow = [self.allSignalAccounts filteredArrayUsingPredicate:predicate];
        }
    }

    if (signalAccountsToShow.count < 1) {
        // No Contacts
        OWSTableSection *contactsSection = [OWSTableSection new];

        if (self.contactsManagerImpl.isSystemContactsAuthorized) {
            if (self.contactsViewHelper.hasUpdatedContactsAtLeastOnce) {

                [contactsSection
                    addItem:[OWSTableItem
                                softCenterLabelItemWithText:OWSLocalizedString(@"SETTINGS_BLOCK_LIST_NO_CONTACTS",
                                                                @"A label that indicates the user has no Signal "
                                                                @"contacts that they haven't blocked.")
                                            customRowHeight:UITableViewAutomaticDimension]];
            } else {
                UITableViewCell *loadingCell = [OWSTableItem newCell];
                OWSAssertDebug(loadingCell.contentView);

                UIActivityIndicatorView *activityIndicatorView =
                    [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
                [loadingCell.contentView addSubview:activityIndicatorView];
                [activityIndicatorView startAnimating];

                [activityIndicatorView autoCenterInSuperview];
                [activityIndicatorView setCompressionResistanceHigh];
                [activityIndicatorView setContentHuggingHigh];

                // hide separator for loading cell. The loading cell doesn't really feel like a cell
                loadingCell.backgroundView = [UIView new];

                loadingCell.accessibilityIdentifier
                    = ACCESSIBILITY_IDENTIFIER_WITH_NAME(RecipientPickerViewController, @"loading");

                OWSTableItem *loadingItem = [OWSTableItem
                    itemWithCustomCellBlock:^{ return loadingCell; }
                            customRowHeight:40
                                actionBlock:nil];
                [contactsSection addItem:loadingItem];
            }
        }

        return @[ contactsSection ];
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
    __weak __typeof(self) weakSelf = self;

    NSMutableArray<OWSTableSection *> *sections = [NSMutableArray new];

    // Contacts, filtered with the search text.
    NSArray<SignalAccount *> *filteredSignalAccounts = searchResults.signalAccounts;
    __block BOOL hasSearchResults = NO;

    NSMutableSet<NSString *> *matchedAccountPhoneNumbers = [NSMutableSet new];
    NSMutableSet<NSString *> *matchedAccountUsernames = [NSMutableSet new];

    OWSTableSection *contactsSection =
        [self buildSectionWithTitle:OWSLocalizedString(@"COMPOSE_MESSAGE_CONTACT_SECTION_TITLE",
                                        @"Table section header for contact listing when composing a new message")];

    OWSAssertIsOnMainThread();
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        NSSet<SignalServiceAddress *> *addressesToSkip = [self.blockingManager blockedAddressesWithTransaction:transaction];

        for (SignalAccount *signalAccount in filteredSignalAccounts) {
            hasSearchResults = YES;

            if ([addressesToSkip containsObject:signalAccount.recipientAddress]) {
                continue;
            }

            NSString *_Nullable phoneNumber = signalAccount.recipientAddress.phoneNumber;
            if (phoneNumber) {
                [matchedAccountPhoneNumbers addObject:phoneNumber];
            }

            NSString *_Nullable username = [self.profileManagerImpl usernameForAddress:signalAccount.recipientAddress
                                                                           transaction:transaction];
            if (username) {
                [matchedAccountUsernames addObject:username];
            }

            PickedRecipient *recipient = [PickedRecipient forAddress:signalAccount.recipientAddress];
            [contactsSection addItem:[self itemForRecipient:recipient]];
        }
    }];
    if (filteredSignalAccounts.count > 0) {
        [sections addObject:contactsSection];
    }

    OWSTableSection *groupSection = [self groupSectionForSearchResults:searchResults];
    if (groupSection != nil) {
        hasSearchResults = YES;
        [sections addObject:groupSection];
    }

    OWSTableSection *phoneNumbersSection =
        [self buildSectionWithTitle:OWSLocalizedString(@"COMPOSE_MESSAGE_PHONE_NUMBER_SEARCH_SECTION_TITLE",
                                        @"Table section header for phone number search when composing a new message")];

    NSArray<NSString *> *searchPhoneNumbers = [self parsePossibleSearchPhoneNumbers];
    for (NSString *phoneNumber in searchPhoneNumbers) {
        OWSAssertDebug(phoneNumber.length > 0);

        // We're already showing this user, skip it.
        if ([matchedAccountPhoneNumbers containsObject:phoneNumber]) {
            continue;
        }

        SignalServiceAddress *address = [[SignalServiceAddress alloc] initWithPhoneNumber:phoneNumber];

        BOOL isRegistered = [self.nonContactAccountSet containsObject:address];
        PickedRecipient *recipient = [PickedRecipient forAddress:address];

        if (self.shouldShowInvites) {
            [phoneNumbersSection
                addItem:[OWSTableItem
                            itemWithCustomCellBlock:^{
                                NonContactTableViewCell *cell = [NonContactTableViewCell new];

                                __strong typeof(self) strongSelf = weakSelf;
                                if (!strongSelf) {
                                    return cell;
                                }

                                if (![strongSelf.delegate recipientPicker:strongSelf getRecipientState:recipient]) {
                                    cell.selectionStyle = UITableViewCellSelectionStyleNone;
                                }

                                [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
                                    cell.accessoryMessage = [strongSelf.delegate recipientPicker:strongSelf
                                                                    accessoryMessageForRecipient:recipient
                                                                                     transaction:transaction];
                                }];

                                [cell configureWithPhoneNumber:phoneNumber
                                                  isRegistered:isRegistered
                                               hideHeaderLabel:!strongSelf.shouldShowInvites];

                                NSString *cellName = [NSString stringWithFormat:@"phone_number.%@", phoneNumber];
                                cell.accessibilityIdentifier
                                    = ACCESSIBILITY_IDENTIFIER_WITH_NAME(RecipientPickerViewController, cellName);

                                [strongSelf.delegate recipientPicker:strongSelf willRenderRecipient:recipient];

                                return cell;
                            }
                            actionBlock:^{
                                [weakSelf tryToSelectRecipient:recipient];
                            }]];
        } else if (isRegistered || self.allowsSelectingUnregisteredPhoneNumbers) {
            [phoneNumbersSection addItem:[self itemForRecipient:recipient]];
        }
    }

    if (phoneNumbersSection.itemCount > 0) {
        hasSearchResults = YES;
        [sections addObject:phoneNumbersSection];
    }

    // Username lookup
    if (SSKFeatureFlags.usernames) {
        NSString *usernameMatch = self.searchText;
        NSString *_Nullable localUsername = self.profileManager.localUsername;

        NSError *error;
        NSRegularExpression *startsWithNumberRegex = [[NSRegularExpression alloc] initWithPattern:@"^[0-9]+"
                                                                                          options:0
                                                                                            error:&error];
        if (!startsWithNumberRegex || error) {
            OWSFailDebug(@"Unexpected error creating regex %@", error.userErrorDescription);
        }
        BOOL startsWithNumber = [startsWithNumberRegex hasMatchWithInput:usernameMatch];
        // If user searches for e164 starting with +, don't treat that as a
        // username search.
        BOOL startsWithPlus = [usernameMatch hasPrefix:@"+"];
        // TODO: Should we use validUsernameRegex?

        if (usernameMatch.length > 0 && !startsWithNumber && !startsWithPlus
            && ![NSObject isNullableObject:usernameMatch equalTo:localUsername]
            && ![matchedAccountUsernames containsObject:usernameMatch]) {
            hasSearchResults = YES;

            OWSTableSection *usernameSection = [self
                buildSectionWithTitle:OWSLocalizedString(@"COMPOSE_MESSAGE_USERNAME_SEARCH_SECTION_TITLE",
                                          @"Table section header for username search when composing a new message")];

            [usernameSection addItem:[OWSTableItem
                                         itemWithCustomCellBlock:^{
                                             NonContactTableViewCell *cell = [NonContactTableViewCell new];

                                             __strong typeof(self) strongSelf = weakSelf;
                                             if (!strongSelf) {
                                                 return cell;
                                             }

                                             [cell configureWithUsername:usernameMatch
                                                         hideHeaderLabel:!strongSelf.shouldShowInvites];

                                             NSString *cellName =
                                                 [NSString stringWithFormat:@"username.%@", usernameMatch];
                                             cell.accessibilityIdentifier = ACCESSIBILITY_IDENTIFIER_WITH_NAME(
                                                 RecipientPickerViewController, cellName);

                                             return cell;
                                         }
                                         actionBlock:^{
                                             [weakSelf lookupUsername:usernameMatch];
                                         }]];

            [sections addObject:usernameSection];
        }
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
    if (self.contactsManagerImpl.isSystemContactsAuthorized) {
        if (self.contactsViewHelper.hasUpdatedContactsAtLeastOnce && self.allSignalAccounts.count < 1
            && ![Environment.shared.preferences hasDeclinedNoContactsView]) {
            self.isNoContactsModeActive = YES;
        } else {
            self.isNoContactsModeActive = NO;
        }
    } else {
        // don't show "no signal contacts", show "no contact access"
        self.isNoContactsModeActive = NO;
    }
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

#pragma mark - Send Invite By SMS

- (void)sendTextToPhoneNumber:(NSString *)phoneNumber
{
    OWSInviteFlow *inviteFlow = [[OWSInviteFlow alloc] initWithPresentingViewController:self];
    self.inviteFlow = inviteFlow;

    OWSAssertDebug([phoneNumber length] > 0);
    NSString *confirmMessage = OWSLocalizedString(@"SEND_SMS_CONFIRM_TITLE", @"");
    if ([phoneNumber length] > 0) {
        confirmMessage = [[OWSLocalizedString(@"SEND_SMS_INVITE_TITLE", @"") stringByAppendingString:phoneNumber]
            stringByAppendingString:OWSLocalizedString(@"QUESTIONMARK_PUNCTUATION", @"")];
    }

    ActionSheetController *alert =
        [[ActionSheetController alloc] initWithTitle:OWSLocalizedString(@"CONFIRMATION_TITLE", @"")
                                             message:confirmMessage];

    ActionSheetAction *okAction = [[ActionSheetAction alloc]
                  initWithTitle:CommonStrings.okButton
        accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"ok")
                          style:ActionSheetActionStyleDefault
                        handler:^(ActionSheetAction *action) {
                            [self.searchBar resignFirstResponder];
                            if ([MFMessageComposeViewController canSendText]) {
                                [inviteFlow sendSMSToPhoneNumbers:@[ phoneNumber ]];
                            } else {
                                [OWSActionSheets
                                    showErrorAlertWithMessage:OWSLocalizedString(@"UNSUPPORTED_FEATURE_ERROR", @"")];
                            }
                        }];

    [alert addAction:[OWSActionSheets cancelAction]];
    [alert addAction:okAction];
    [self clearSearchText];

    // must dismiss search controller before presenting alert.
    if ([self presentedViewController]) {
        [self dismissViewControllerAnimated:YES
                                 completion:^{
                                     [self presentActionSheet:alert];
                                 }];
    } else {
        [self presentActionSheet:alert];
    }
}

#pragma mark - SMS Composer Delegate

// called on completion of message screen
- (void)messageComposeViewController:(MFMessageComposeViewController *)controller
                 didFinishWithResult:(MessageComposeResult)result
{
    switch (result) {
        case MessageComposeResultCancelled:
            break;
        case MessageComposeResultFailed: {
            [OWSActionSheets showErrorAlertWithMessage:OWSLocalizedString(@"SEND_INVITE_FAILURE", @"")];
            break;
        }
        case MessageComposeResultSent: {
            [self dismissViewControllerAnimated:NO
                                     completion:^{
                                         OWSLogDebug(@"view controller dismissed");
                                     }];
            [OWSActionSheets showActionSheetWithTitle:OWSLocalizedString(@"SEND_INVITE_SUCCESS",
                                                          @"Alert body after invite succeeded")];
            break;
        }
        default:
            break;
    }

    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Methods

- (void)lookupUsername:(NSString *)username
{
    OWSAssertDebug(username.length > 0);

    __weak __typeof(self) weakSelf = self;

    [ModalActivityIndicatorViewController
        presentFromViewController:self
                        canCancel:YES
                  backgroundBlock:^(ModalActivityIndicatorViewController *modal) {
                      [self.profileManagerImpl fetchProfileForUsername:username
                          success:^(SignalServiceAddress *address) {
                              if (modal.wasCancelled) {
                                  return;
                              }

                              dispatch_async(dispatch_get_main_queue(), ^{
                                  [modal dismissWithCompletion:^{
                                      [weakSelf tryToSelectRecipient:[PickedRecipient forAddress:address]];
                                  }];
                              });
                          }
                          notFound:^{
                              if (modal.wasCancelled) {
                                  return;
                              }

                              dispatch_async(dispatch_get_main_queue(), ^{
                                  [modal dismissWithCompletion:^{
                                      NSString *usernameNotFoundFormat = OWSLocalizedString(@"USERNAME_NOT_FOUND_FORMAT",
                                          @"A message indicating that the given username is not a registered signal "
                                          @"account. Embeds "
                                          @"{{username}}");
                                      [OWSActionSheets
                                          showActionSheetWithTitle:
                                           OWSLocalizedString(@"USERNAME_NOT_FOUND_TITLE",
                                                  @"A message indicating that the given username was not "
                                                  @"registered with signal.")
                                                           message:[[NSString alloc]
                                                                       initWithFormat:usernameNotFoundFormat,
                                                                       [CommonFormats formatUsername:username]]];
                                  }];
                              });
                          }
                          failure:^(NSError *error) {
                              if (modal.wasCancelled) {
                                  return;
                              }

                              dispatch_async(dispatch_get_main_queue(), ^{
                                  [modal dismissWithCompletion:^{
                                      [OWSActionSheets showErrorAlertWithMessage:
                                       OWSLocalizedString(@"USERNAME_LOOKUP_ERROR",
                                                               @"A message indicating that username lookup failed.")];
                                  }];
                              });
                          }];
                  }];
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

#pragma mark - FindByPhoneNumberDelegate

- (void)findByPhoneNumber:(FindByPhoneNumberViewController *)findByPhoneNumber
         didSelectAddress:(SignalServiceAddress *)address
{
    OWSAssertDebug(address.isValid);

    [self tryToSelectRecipient:[PickedRecipient forAddress:address]];
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
        [self updateSearchPhoneNumbers];
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

- (NSDictionary<NSString *, NSString *> *)callingCodesToCountryCodeMap
{
    static NSDictionary<NSString *, NSString *> *result = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableDictionary *map = [NSMutableDictionary new];
        for (NSString *countryCode in [PhoneNumberUtil countryCodesForSearchTerm:nil]) {
            OWSAssertDebug(countryCode.length > 0);
            NSString *callingCode = [PhoneNumberUtil callingCodeFromCountryCode:countryCode];
            OWSAssertDebug(callingCode.length > 0);
            OWSAssertDebug([callingCode hasPrefix:@"+"]);
            OWSAssertDebug(![callingCode isEqualToString:@"+0"]);

            map[callingCode] = countryCode;
        }
        result = [map copy];
    });
    return result;
}

- (nullable NSString *)callingCodeForPossiblePhoneNumber:(NSString *)phoneNumber
{
    OWSAssertDebug([phoneNumber hasPrefix:@"+"]);

    for (NSString *callingCode in [self callingCodesToCountryCodeMap].allKeys) {
        if ([phoneNumber hasPrefix:callingCode]) {
            return callingCode;
        }
    }
    return nil;
}

- (NSString *)searchText
{
    NSString *rawText = self.searchBar.text;
    return rawText.ows_stripped ?: @"";
}

- (NSArray<NSString *> *)parsePossibleSearchPhoneNumbers
{
    NSString *searchText = self.searchText;

    if (searchText.length < 8) {
        return @[];
    }

    NSMutableSet<NSString *> *parsedPhoneNumbers = [NSMutableSet new];
    for (PhoneNumber *phoneNumber in
        [PhoneNumber tryParsePhoneNumbersFromUserSpecifiedText:searchText
                                              clientPhoneNumber:[TSAccountManager localNumber]]) {

        NSString *phoneNumberString = phoneNumber.toE164;

        // Ignore phone numbers with an unrecognized calling code.
        NSString *_Nullable callingCode = [self callingCodeForPossiblePhoneNumber:phoneNumberString];
        if (!callingCode) {
            continue;
        }

        // Ignore phone numbers which are too long.
        NSString *phoneNumberWithoutCallingCode = [phoneNumberString substringFromIndex:callingCode.length];
        if (phoneNumberWithoutCallingCode.length < 1 || phoneNumberWithoutCallingCode.length > 15) {
            continue;
        }
        [parsedPhoneNumbers addObject:phoneNumberString];
    }

    return [parsedPhoneNumbers.allObjects sortedArrayUsingSelector:@selector(compare:)];
}

- (void)updateSearchPhoneNumbers
{
    [self checkForAccountsForPhoneNumbers:[self parsePossibleSearchPhoneNumbers]];
}

- (void)checkForAccountsForPhoneNumbers:(NSArray<NSString *> *)phoneNumbers
{
    NSMutableSet<NSString *> *unknownPhoneNumbers = [NSMutableSet new];
    for (NSString *phoneNumber in phoneNumbers) {
        if (!
            [self.nonContactAccountSet containsObject:[[SignalServiceAddress alloc] initWithPhoneNumber:phoneNumber]]) {
            [unknownPhoneNumbers addObject:phoneNumber];
        }
    }
    if ([unknownPhoneNumbers count] < 1) {
        return;
    }

    __weak RecipientPickerViewController *weakSelf = self;

    OWSContactDiscoveryTask *discoveryTask = [[OWSContactDiscoveryTask alloc] initWithPhoneNumbers:unknownPhoneNumbers];
    [discoveryTask performAtQoS:QOS_CLASS_USER_INITIATED
                  callbackQueue:dispatch_get_main_queue()
                        success:^(NSSet<SignalRecipient *> *resultSet) {
                            [weakSelf updateNonContactAccountSet:[resultSet allObjects]];
                        }
                        failure:^(NSError *error) {
                            // Ignore.
                        }];
}

- (void)updateNonContactAccountSet:(NSArray<SignalRecipient *> *)recipients
{
    BOOL didUpdate = NO;
    for (SignalRecipient *recipient in recipients) {
        if ([self.nonContactAccountSet containsObject:recipient.address]) {
            continue;
        }
        [self.nonContactAccountSet addObject:recipient.address];
        didUpdate = YES;
    }
    if (didUpdate) {
        [self updateTableContents];
    }
}

#pragma mark - Theme

- (void)applyTheme
{
    OWSAssertIsOnMainThread();

    [super applyTheme];

    [self.tableViewController applyThemeToViewController:self];
    self.searchBar.searchFieldBackgroundColorOverride = Theme.searchFieldElevatedBackgroundColor;
    self.tableViewController.tableView.sectionIndexColor = Theme.primaryTextColor;
}

- (void)applyThemeToViewController:(UIViewController *)viewController
{
    [self.tableViewController applyThemeToViewController:viewController];
}

- (void)removeThemeFromViewController:(UIViewController *)viewController
{
    [self.tableViewController removeThemeFromViewController:viewController];
}

@end

NS_ASSUME_NONNULL_END
