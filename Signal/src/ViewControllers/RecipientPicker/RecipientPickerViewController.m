//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "RecipientPickerViewController.h"
#import "ContactTableViewCell.h"
#import "ContactsViewHelper.h"
#import "NewGroupViewController.h"
#import "OWSTableViewController.h"
#import "Signal-Swift.h"
#import "SignalApp.h"
#import "UIColor+OWS.h"
#import "UIView+OWS.h"
#import <MessageUI/MessageUI.h>
#import <SignalMessaging/Environment.h>
#import <SignalMessaging/UIUtil.h>
#import <SignalServiceKit/AppVersion.h>
#import <SignalServiceKit/PhoneNumberUtil.h>
#import <SignalServiceKit/SignalAccount.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSAccountManager.h>

NS_ASSUME_NONNULL_BEGIN

@interface SignalAccount (Collation)

- (NSString *)stringForCollation;

@end

@implementation SignalAccount (Collation)

- (NSString *)stringForCollation
{
    OWSContactsManager *contactsManager = Environment.shared.contactsManager;
    return [contactsManager comparableNameForSignalAccount:self];
}

@end

const NSUInteger kMinimumSearchLength = 2;

@interface RecipientPickerViewController () <UISearchBarDelegate,
    ContactsViewHelperDelegate,
    OWSTableViewControllerDelegate,
    FindByPhoneNumberDelegate,
    MFMessageComposeViewControllerDelegate>

@property (nonatomic, readonly) FullTextSearcher *fullTextSearcher;

@property (nonatomic, readonly) UIView *noSignalContactsView;

@property (nonatomic, readonly) OWSTableViewController *tableViewController;

@property (nonatomic, readonly) UILocalizedIndexedCollation *collation;

@property (nonatomic, readonly) UISearchBar *searchBar;
@property (nonatomic, nullable) ComposeScreenSearchResultSet *searchResults;
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

#pragma mark - Dependencies

- (FullTextSearcher *)fullTextSearcher
{
    return FullTextSearcher.shared;
}

- (OWSContactsManager *)contactsManager
{
    return Environment.shared.contactsManager;
}

- (SDSDatabaseStorage *)databaseStorage
{
    return SDSDatabaseStorage.shared;
}

#pragma mark -

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    _allowsAddByPhoneNumber = YES;
    _shouldHideLocalRecipient = YES;
    _allowsSelectingUnregisteredPhoneNumbers = YES;
    _shouldShowGroups = YES;
    _shouldShowInvites = NO;
    _shouldShowAlphabetSlider = YES;

    return self;
}

- (void)loadView
{
    [super loadView];

    _searchResults = nil;
    _contactsViewHelper = [[ContactsViewHelper alloc] initWithDelegate:self];
    _nonContactAccountSet = [NSMutableSet set];
    _collation = [UILocalizedIndexedCollation currentCollation];

    // Search
    UISearchBar *searchBar = [OWSSearchBar new];
    _searchBar = searchBar;
    searchBar.delegate = self;
    if (SSKFeatureFlags.usernames) {
        searchBar.placeholder = NSLocalizedString(@"SEARCH_BY_NAME_OR_USERNAME_OR_NUMBER_PLACEHOLDER_TEXT",
            @"Placeholder text indicating the user can search for contacts by name, username, or phone number.");
    } else {
        searchBar.placeholder = NSLocalizedString(@"SEARCH_BYNAMEORNUMBER_PLACEHOLDER_TEXT",
            @"Placeholder text indicating the user can search for contacts by name or phone number.");
    }
    [searchBar sizeToFit];
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, searchBar);
    searchBar.textField.accessibilityIdentifier = ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"contact_search");

    _tableViewController = [OWSTableViewController new];
    _tableViewController.delegate = self;
    _tableViewController.tableViewStyle = UITableViewStylePlain;

    // To automatically adjust our content inset appropriately on iOS9/10
    // 1. the tableViewController must be a childView
    // 2. the scrollable view (tableView in this case) must be at index 0.
    [self addChildViewController:self.tableViewController];
    [self.view insertSubview:self.tableViewController.view atIndex:0];

    [self.tableViewController.view autoPinEdgeToSuperviewSafeArea:ALEdgeLeading];
    [self.tableViewController.view autoPinEdgeToSuperviewSafeArea:ALEdgeTrailing];
    [_tableViewController.view autoPinEdgeToSuperviewEdge:ALEdgeTop];

    self.tableViewController.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableViewController.tableView.estimatedRowHeight = 60;

    [self autoPinViewToBottomOfViewControllerOrKeyboard:self.tableViewController.view avoidNotch:NO];
    _tableViewController.tableView.tableHeaderView = searchBar;

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
    [self.tableViewController.tableView insertSubview:pullToRefreshView atIndex:0];
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, pullToRefreshView);

    [self updateTableContents];

    [self applyTheme];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(themeDidChange:)
                                                 name:ThemeDidChangeNotification
                                               object:nil];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)pullToRefreshPerformed:(UIRefreshControl *)refreshControl
{
    OWSAssertIsOnMainThread();

    [self.contactsManager userRequestedSystemContactsRefreshWithCompletion:^(NSError *_Nullable error) {
        if (error) {
            OWSLogError(@"refreshing contacts failed with error: %@", error);
        }
        [refreshControl endRefreshing];
    }];
}

- (UIView *)createNoSignalContactsView
{
    UIView *view = [UIView new];
    view.backgroundColor = [Theme backgroundColor];

    UIView *contents = [UIView new];
    [view addSubview:contents];
    [contents autoCenterInSuperview];

    UIImage *heroImage = [UIImage imageNamed:@"uiEmptyContact"];
    OWSAssertDebug(heroImage);
    UIImageView *heroImageView = [[UIImageView alloc] initWithImage:heroImage];
    heroImageView.layer.minificationFilter = kCAFilterTrilinear;
    heroImageView.layer.magnificationFilter = kCAFilterTrilinear;
    [contents addSubview:heroImageView];
    [heroImageView autoHCenterInSuperview];
    [heroImageView autoPinEdgeToSuperviewEdge:ALEdgeTop];
    const CGFloat kHeroSize = ScaleFromIPhone5To7Plus(100, 150);
    [heroImageView autoSetDimension:ALDimensionWidth toSize:kHeroSize];
    [heroImageView autoSetDimension:ALDimensionHeight toSize:kHeroSize];
    UIView *lastSubview = heroImageView;

    UILabel *titleLabel = [UILabel new];
    titleLabel.text = NSLocalizedString(
        @"EMPTY_CONTACTS_LABEL_LINE1", "Full width label displayed when attempting to compose message");
    titleLabel.textColor = [Theme primaryColor];
    titleLabel.font = [UIFont ows_mediumFontWithSize:ScaleFromIPhone5To7Plus(17.f, 20.f)];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.lineBreakMode = NSLineBreakByWordWrapping;
    titleLabel.numberOfLines = 0;
    [contents addSubview:titleLabel];
    [titleLabel autoPinWidthToSuperview];
    [titleLabel autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:lastSubview withOffset:30];
    lastSubview = titleLabel;

    UILabel *subtitleLabel = [UILabel new];
    subtitleLabel.text = NSLocalizedString(
        @"EMPTY_CONTACTS_LABEL_LINE2", "Full width label displayed when attempting to compose message");
    subtitleLabel.textColor = [Theme secondaryColor];
    subtitleLabel.font = [UIFont ows_regularFontWithSize:ScaleFromIPhone5To7Plus(12.f, 14.f)];
    subtitleLabel.textAlignment = NSTextAlignmentCenter;
    subtitleLabel.lineBreakMode = NSLineBreakByWordWrapping;
    subtitleLabel.numberOfLines = 0;
    [contents addSubview:subtitleLabel];
    [subtitleLabel autoPinWidthToSuperview];
    [subtitleLabel autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:lastSubview withOffset:15];
    lastSubview = subtitleLabel;

    if (self.shouldShowInvites) {
        UIButton *inviteContactsButton = [UIButton buttonWithType:UIButtonTypeCustom];
        [inviteContactsButton setTitle:NSLocalizedString(@"INVITE_FRIENDS_CONTACT_TABLE_BUTTON",
                                           "Label for the cell that presents the 'invite contacts' workflow.")
                              forState:UIControlStateNormal];
        [inviteContactsButton setTitleColor:[UIColor ows_materialBlueColor] forState:UIControlStateNormal];
        [inviteContactsButton.titleLabel setFont:[UIFont ows_regularFontWithSize:17.f]];
        [contents addSubview:inviteContactsButton];
        [inviteContactsButton autoHCenterInSuperview];
        [inviteContactsButton autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:lastSubview withOffset:50];
        [inviteContactsButton addTarget:self
                                 action:@selector(presentInviteFlow)
                       forControlEvents:UIControlEventTouchUpInside];
        lastSubview = inviteContactsButton;
        SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, inviteContactsButton);
    }

    if (self.allowsAddByPhoneNumber) {
        UIButton *searchByPhoneNumberButton = [UIButton buttonWithType:UIButtonTypeCustom];
        [searchByPhoneNumberButton
            setTitle:NSLocalizedString(@"NO_CONTACTS_SEARCH_BY_PHONE_NUMBER",
                         @"Label for a button that lets users search for contacts by phone number")
            forState:UIControlStateNormal];
        [searchByPhoneNumberButton setTitleColor:[UIColor ows_materialBlueColor] forState:UIControlStateNormal];
        [searchByPhoneNumberButton.titleLabel setFont:[UIFont ows_regularFontWithSize:17.f]];
        [contents addSubview:searchByPhoneNumberButton];
        [searchByPhoneNumberButton autoHCenterInSuperview];
        [searchByPhoneNumberButton autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:lastSubview withOffset:20];
        [searchByPhoneNumberButton addTarget:self
                                      action:@selector(hideBackgroundView)
                            forControlEvents:UIControlEventTouchUpInside];
        lastSubview = searchByPhoneNumberButton;
        SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, searchByPhoneNumberButton);
    }

    [lastSubview autoPinEdgeToSuperviewMargin:ALEdgeBottom];

    return view;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    [self.contactsViewHelper warmNonSignalContactsCacheAsync];

    self.tableViewController.tableView.tableHeaderView = self.searchBar;

    self.title = NSLocalizedString(@"MESSAGE_COMPOSEVIEW_TITLE", @"");
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    // Make sure we have requested contact access at this point if, e.g.
    // the user has no messages in their inbox and they choose to compose
    // a message.
    [self.contactsManager requestSystemContactsOnce];

    [self showContactAppropriateViews];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];

    [OWSAlerts showIOSUpgradeNagIfNecessary];
}

#pragma mark - Table Contents

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
    if (self.contactsManager.isSystemContactsDenied) {
        OWSTableItem *contactReminderItem = [OWSTableItem
            itemWithCustomCellBlock:^{
                UITableViewCell *cell = [OWSTableItem newCell];

                ReminderView *reminderView = [ReminderView
                    nagWithText:NSLocalizedString(@"COMPOSE_SCREEN_MISSING_CONTACTS_PERMISSION",
                                    @"Multi-line label explaining why compose-screen contact picker is empty.")
                      tapAction:^{
                          [[UIApplication sharedApplication] openSystemSettings];
                      }];
                [cell.contentView addSubview:reminderView];
                [reminderView autoPinEdgesToSuperviewEdges];

                cell.accessibilityIdentifier
                    = ACCESSIBILITY_IDENTIFIER_WITH_NAME(RecipientPickerViewController, @"missing_contacts");

                return cell;
            }
                    customRowHeight:UITableViewAutomaticDimension
                        actionBlock:nil];

        OWSTableSection *reminderSection = [OWSTableSection new];
        [reminderSection addItem:contactReminderItem];
        [contents addSection:reminderSection];
    }

    OWSTableSection *staticSection = [OWSTableSection new];

    // Find Non-Contacts by Phone Number
    if (self.allowsAddByPhoneNumber) {
        [staticSection
            addItem:[OWSTableItem
                         disclosureItemWithText:NSLocalizedString(@"NEW_CONVERSATION_FIND_BY_PHONE_NUMBER",
                                                    @"A label the cell that lets you add a new member to a group.")
                        accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(
                                                    RecipientPickerViewController, @"find_by_phone")
                                customRowHeight:UITableViewAutomaticDimension
                                    actionBlock:^{
                                        FindByPhoneNumberViewController *viewController =
                                            [[FindByPhoneNumberViewController alloc]
                                                        initWithDelegate:self
                                                              buttonText:self.findByPhoneNumberButtonTitle
                                                requiresRegisteredNumber:!self.allowsSelectingUnregisteredPhoneNumbers];
                                        [weakSelf.navigationController pushViewController:viewController animated:YES];
                                    }]];
    }

    if (self.contactsManager.isSystemContactsAuthorized && self.shouldShowInvites) {
        // Invite Contacts
        [staticSection
            addItem:[OWSTableItem
                         disclosureItemWithText:NSLocalizedString(@"INVITE_FRIENDS_CONTACT_TABLE_BUTTON",
                                                    @"Label for the cell that presents the 'invite contacts' workflow.")
                        accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(
                                                    RecipientPickerViewController, @"invite_contacts")
                                customRowHeight:UITableViewAutomaticDimension
                                    actionBlock:^{
                                        [weakSelf presentInviteFlow];
                                    }]];
    }

    // Render any non-contact picked recipients
    if (self.pickedRecipients.count > 0 && self.searchResults == nil) {
        BOOL hadNonContactRecipient = NO;
        for (PickedRecipient *recipient in self.pickedRecipients) {
            if (self.shouldHideLocalRecipient &&
                [recipient.address isEqualToAddress:self.contactsViewHelper.localAddress]) {
                continue;
            }

            if (![self.contactsViewHelper fetchSignalAccountForAddress:recipient.address]) {
                hadNonContactRecipient = YES;
                [staticSection addItem:[self itemForRecipient:recipient]];
            }
        }

        // If we have non-contact selections, add a title to the static section
        if (hadNonContactRecipient) {
            staticSection.headerTitle = NSLocalizedString(@"NEW_GROUP_NON_CONTACTS_SECTION_TITLE",
                @"a title for the selected section of the 'recipient picker' view.");
        }
    }

    if (staticSection.itemCount > 0) {
        [contents addSection:staticSection];
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
            contents.sectionForSectionIndexTitleBlock = ^NSInteger(NSString *_Nonnull title, NSInteger index) {
                typeof(self) strongSelf = weakSelf;
                if (!strongSelf) {
                    return 0;
                }

                // Offset the collation section to account for the noncollated sections.
                NSInteger sectionIndex =
                    [strongSelf.collation sectionForSectionIndexTitleAtIndex:index] + beforeContactsSectionCount;
                if (sectionIndex < 0) {
                    // Sentinal in case we change our section ordering in a surprising way.
                    OWSCFailDebug(@"Unexpected negative section index");
                    return 0;
                }
                if (sectionIndex >= (NSInteger)contents.sections.count) {
                    // Sentinal in case we change our section ordering in a surprising way.
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
    if (self.contactsViewHelper.signalAccounts.count < 1) {
        // No Contacts
        OWSTableSection *contactsSection = [OWSTableSection new];

        if (self.contactsManager.isSystemContactsAuthorized) {
            if (self.contactsViewHelper.hasUpdatedContactsAtLeastOnce) {

                [contactsSection
                    addItem:[OWSTableItem softCenterLabelItemWithText:
                                              NSLocalizedString(@"SETTINGS_BLOCK_LIST_NO_CONTACTS",
                                                  @"A label that indicates the user has no Signal contacts.")
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

                OWSTableItem *loadingItem = [OWSTableItem itemWithCustomCell:loadingCell
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
        for (SignalAccount *signalAccount in self.contactsViewHelper.signalAccounts) {
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
            [contactSections addObject:[OWSTableSection sectionWithTitle:sectionTitle items:contactItems]];
        }
    } else {
        OWSTableSection *contactsSection = [OWSTableSection new];
        contactsSection.headerTitle = NSLocalizedString(@"COMPOSE_MESSAGE_CONTACT_SECTION_TITLE",
            @"Table section header for contact listing when composing a new message");

        for (SignalAccount *signalAccount in self.contactsViewHelper.signalAccounts) {
            [contactsSection
                addItem:[self itemForRecipient:[PickedRecipient forAddress:signalAccount.recipientAddress]]];
        }

        [contactSections addObject:contactsSection];
    }

    return [contactSections copy];
}

- (NSArray<OWSTableSection *> *)contactsSectionsForSearchResults:(ComposeScreenSearchResultSet *)searchResults
{
    __weak __typeof(self) weakSelf = self;

    NSMutableArray<OWSTableSection *> *sections = [NSMutableArray new];

    ContactsViewHelper *helper = self.contactsViewHelper;

    // Contacts, filtered with the search text.
    NSArray<SignalAccount *> *filteredSignalAccounts = searchResults.signalAccounts;
    __block BOOL hasSearchResults = NO;

    NSMutableSet<NSString *> *matchedAccountPhoneNumbers = [NSMutableSet new];
    NSMutableSet<NSString *> *matchedAccountUsernames = [NSMutableSet new];

    OWSTableSection *contactsSection = [OWSTableSection new];
    contactsSection.headerTitle = NSLocalizedString(@"COMPOSE_MESSAGE_CONTACT_SECTION_TITLE",
        @"Table section header for contact listing when composing a new message");

    OWSAssertIsOnMainThread();
    [self.databaseStorage uiReadWithBlock:^(SDSAnyReadTransaction *transaction) {
        for (SignalAccount *signalAccount in filteredSignalAccounts) {
            hasSearchResults = YES;

            NSString *_Nullable phoneNumber = signalAccount.recipientAddress.phoneNumber;
            if (phoneNumber) {
                [matchedAccountPhoneNumbers addObject:phoneNumber];
            }

            NSString *_Nullable username = [helper.profileManager usernameForAddress:signalAccount.recipientAddress
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

    if (self.shouldShowGroups) {
        // When searching, we include matching groups
        OWSTableSection *groupSection = [OWSTableSection new];
        groupSection.headerTitle = NSLocalizedString(@"COMPOSE_MESSAGE_GROUP_SECTION_TITLE",
            @"Table section header for group listing when composing a new message");
        NSArray<TSGroupThread *> *filteredGroupThreads = searchResults.groupThreads;
        for (TSGroupThread *thread in filteredGroupThreads) {
            hasSearchResults = YES;

            [groupSection addItem:[self itemForRecipient:[PickedRecipient forGroupThread:thread]]];
        }
        if (filteredGroupThreads.count > 0) {
            [sections addObject:groupSection];
        }
    }

    OWSTableSection *phoneNumbersSection = [OWSTableSection new];
    phoneNumbersSection.headerTitle = NSLocalizedString(@"COMPOSE_MESSAGE_PHONE_NUMBER_SEARCH_SECTION_TITLE",
        @"Table section header for phone number search when composing a new message");

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

                                if (![strongSelf.delegate recipientPicker:strongSelf canSelectRecipient:recipient]) {
                                    cell.selectionStyle = UITableViewCellSelectionStyleNone;
                                }

                                cell.accessoryMessage = [strongSelf.delegate recipientPicker:strongSelf
                                                                accessoryMessageForRecipient:recipient];

                                [cell configureWithPhoneNumber:phoneNumber
                                                  isRegistered:isRegistered
                                               hideHeaderLabel:!strongSelf.shouldShowInvites];

                                NSString *cellName = [NSString stringWithFormat:@"phone_number.%@", phoneNumber];
                                cell.accessibilityIdentifier
                                    = ACCESSIBILITY_IDENTIFIER_WITH_NAME(RecipientPickerViewController, cellName);

                                return cell;
                            }
                            customRowHeight:UITableViewAutomaticDimension
                            actionBlock:^{
                                __strong typeof(self) strongSelf = weakSelf;
                                if (!strongSelf) {
                                    return;
                                }

                                if (![strongSelf.delegate recipientPicker:strongSelf canSelectRecipient:recipient]) {
                                    return;
                                }

                                [strongSelf.delegate recipientPicker:strongSelf didSelectRecipient:recipient];
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
        NSString *_Nullable localUsername = helper.profileManager.localUsername;

        if (usernameMatch.length > 0 && ![NSObject isNullableObject:usernameMatch equalTo:localUsername]
            && ![matchedAccountUsernames containsObject:usernameMatch]) {
            hasSearchResults = YES;

            OWSTableSection *usernameSection = [OWSTableSection new];
            usernameSection.headerTitle = NSLocalizedString(@"COMPOSE_MESSAGE_USERNAME_SEARCH_SECTION_TITLE",
                @"Table section header for username search when composing a new message");

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
                                         customRowHeight:UITableViewAutomaticDimension
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
                                      NSLocalizedString(@"SETTINGS_BLOCK_LIST_NO_SEARCH_RESULTS",
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
    if (self.contactsManager.isSystemContactsAuthorized) {
        if (self.contactsViewHelper.hasUpdatedContactsAtLeastOnce && self.contactsViewHelper.signalAccounts.count < 1
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

- (void)setIsNoContactsModeActive:(BOOL)isNoContactsModeActive
{
    if (isNoContactsModeActive == _isNoContactsModeActive) {
        return;
    }

    _isNoContactsModeActive = isNoContactsModeActive;

    if (isNoContactsModeActive) {
        self.tableViewController.tableView.hidden = YES;
        self.searchBar.hidden = YES;
        self.noSignalContactsView.hidden = NO;
    } else {
        self.tableViewController.tableView.hidden = NO;
        self.searchBar.hidden = NO;
        self.noSignalContactsView.hidden = YES;
    }

    [self updateTableContents];
}

#pragma mark - Send Invite By SMS

- (void)sendTextToPhoneNumber:(NSString *)phoneNumber
{
    OWSInviteFlow *inviteFlow = [[OWSInviteFlow alloc] initWithPresentingViewController:self];
    self.inviteFlow = inviteFlow;

    OWSAssertDebug([phoneNumber length] > 0);
    NSString *confirmMessage = NSLocalizedString(@"SEND_SMS_CONFIRM_TITLE", @"");
    if ([phoneNumber length] > 0) {
        confirmMessage = [[NSLocalizedString(@"SEND_SMS_INVITE_TITLE", @"") stringByAppendingString:phoneNumber]
            stringByAppendingString:NSLocalizedString(@"QUESTIONMARK_PUNCTUATION", @"")];
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"CONFIRMATION_TITLE", @"")
                                                                   message:confirmMessage
                                                            preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *okAction = [UIAlertAction
                actionWithTitle:NSLocalizedString(@"OK", @"")
        accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"ok")
                          style:UIAlertActionStyleDefault
                        handler:^(UIAlertAction *action) {
                            [self.searchBar resignFirstResponder];
                            if ([MFMessageComposeViewController canSendText]) {
                                [inviteFlow sendSMSToPhoneNumbers:@[ phoneNumber ]];
                            } else {
                                [OWSAlerts
                                    showErrorAlertWithMessage:NSLocalizedString(@"UNSUPPORTED_FEATURE_ERROR", @"")];
                            }
                        }];

    [alert addAction:[OWSAlerts cancelAction]];
    [alert addAction:okAction];
    self.searchBar.text = @"";
    [self searchTextDidChange];

    // must dismiss search controller before presenting alert.
    if ([self presentedViewController]) {
        [self dismissViewControllerAnimated:YES
                                 completion:^{
                                     [self presentAlert:alert];
                                 }];
    } else {
        [self presentAlert:alert];
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
            [OWSAlerts showErrorAlertWithMessage:NSLocalizedString(@"SEND_INVITE_FAILURE", @"")];
            break;
        }
        case MessageComposeResultSent: {
            [self dismissViewControllerAnimated:NO
                                     completion:^{
                                         OWSLogDebug(@"view controller dismissed");
                                     }];
            [OWSAlerts
                showAlertWithTitle:NSLocalizedString(@"SEND_INVITE_SUCCESS", @"Alert body after invite succeeded")];
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
                      [self.contactsViewHelper.profileManager fetchProfileForUsername:username
                          success:^(SignalServiceAddress *address) {
                              dispatch_async(dispatch_get_main_queue(), ^{
                                  if (modal.wasCancelled) {
                                      return;
                                  }

                                  [modal dismissWithCompletion:^{
                                      __strong typeof(self) strongSelf = weakSelf;
                                      if (!strongSelf) {
                                          return;
                                      }

                                      [strongSelf.delegate recipientPicker:strongSelf
                                                        didSelectRecipient:[PickedRecipient forAddress:address]];
                                  }];
                              });
                          }
                          notFound:^{
                              dispatch_async(dispatch_get_main_queue(), ^{
                                  if (modal.wasCancelled) {
                                      return;
                                  }

                                  [modal dismissWithCompletion:^{
                                      NSString *usernameNotFoundFormat = NSLocalizedString(@"USERNAME_NOT_FOUND_FORMAT",
                                          @"A message indicating that the given username is not a registered signal "
                                          @"account. Embeds "
                                          @"{{username}}");
                                      [OWSAlerts showAlertWithTitle:
                                                     NSLocalizedString(@"USERNAME_NOT_FOUND_TITLE",
                                                         @"A message indicating that the given username was not "
                                                         @"registered with signal.")
                                                            message:[[NSString alloc]
                                                                        initWithFormat:usernameNotFoundFormat,
                                                                        [CommonFormats formatUsername:username]]];
                                  }];
                              });
                          }
                          failure:^(NSError *error) {
                              dispatch_async(dispatch_get_main_queue(), ^{
                                  if (modal.wasCancelled) {
                                      return;
                                  }

                                  [modal dismissWithCompletion:^{
                                      [OWSAlerts showErrorAlertWithMessage:
                                                     NSLocalizedString(@"USERNAME_LOOKUP_ERROR",
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

#pragma mark - ContactsViewHelperDelegate

- (void)contactsViewHelperDidUpdateContacts
{
    [self updateTableContents];

    [self showContactAppropriateViews];
}

- (BOOL)shouldHideLocalNumber
{
    return self.shouldHideLocalRecipient;
}

#pragma mark - FindByPhoneNumberDelegate

- (void)findByPhoneNumber:(FindByPhoneNumberViewController *)findByPhoneNumber
         didSelectAddress:(SignalServiceAddress *)address
{
    OWSAssertDebug(address.isValid);
    [self.delegate recipientPicker:self didSelectRecipient:[PickedRecipient forAddress:address]];
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
        return;
    }

    __weak __typeof(self) weakSelf = self;

    __block ComposeScreenSearchResultSet *searchResults;
    [self.databaseStorage
        asyncReadWithBlock:^(SDSAnyReadTransaction *transaction) {
            searchResults = [self.fullTextSearcher searchForComposeScreenWithSearchText:searchText
                                                                            transaction:transaction];
        }
        completion:^{
            __typeof(self) strongSelf = weakSelf;
            if (!strongSelf) {
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
        [PhoneNumber tryParsePhoneNumbersFromsUserSpecifiedText:searchText
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
    NSMutableArray<NSString *> *unknownPhoneNumbers = [NSMutableArray new];
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
    [[ContactsUpdater sharedUpdater] lookupIdentifiers:unknownPhoneNumbers
                                               success:^(NSArray<SignalRecipient *> *recipients) {
                                                   [weakSelf updateNonContactAccountSet:recipients];
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

- (void)themeDidChange:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    [self applyTheme];
}

- (void)applyTheme
{
    OWSAssertIsOnMainThread();

    self.view.backgroundColor = Theme.backgroundColor;
}

@end

NS_ASSUME_NONNULL_END
