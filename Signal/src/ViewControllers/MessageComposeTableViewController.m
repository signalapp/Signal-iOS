//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "MessageComposeTableViewController.h"
#import "ContactTableViewCell.h"
#import "ContactsViewHelper.h"
#import "Environment.h"
#import "NewGroupViewController.h"
#import "NewNonContactConversationViewController.h"
#import "OWSContactsSearcher.h"
#import "OWSTableViewController.h"
#import "Signal-Swift.h"
#import "UIColor+OWS.h"
#import "UIUtil.h"
#import "UIView+OWS.h"
#import <MessageUI/MessageUI.h>
#import <SignalServiceKit/AppVersion.h>
#import <SignalServiceKit/PhoneNumberUtil.h>
#import <SignalServiceKit/SignalAccount.h>
#import <SignalServiceKit/TSAccountManager.h>

NS_ASSUME_NONNULL_BEGIN

@interface MessageComposeTableViewController () <UISearchBarDelegate,
    ContactsViewHelperDelegate,
    OWSTableViewControllerDelegate,
    NewNonContactConversationViewControllerDelegate,
    MFMessageComposeViewControllerDelegate>

@property (nonatomic, readonly) ContactsViewHelper *contactsViewHelper;

@property (nonatomic, readonly) UIView *noSignalContactsView;

@property (nonatomic, readonly) OWSTableViewController *tableViewController;

@property (nonatomic, readonly) UISearchBar *searchBar;
@property (nonatomic, readonly) NSLayoutConstraint *hideContactsPermissionReminderViewConstraint;

// A list of possible phone numbers parsed from the search text as
// E164 values.
@property (nonatomic) NSArray<NSString *> *searchPhoneNumbers;

// This set is used to cache the set of non-contact phone numbers
// which are known to correspond to Signal accounts.
@property (nonatomic, readonly) NSMutableSet *nonContactAccountSet;

@property (nonatomic) BOOL isNoContactsModeActive;

@end

#pragma mark -

@implementation MessageComposeTableViewController

- (void)loadView
{
    [super loadView];

    _contactsViewHelper = [[ContactsViewHelper alloc] initWithDelegate:self];
    _nonContactAccountSet = [NSMutableSet set];

    ReminderView *contactsPermissionReminderView = [[ReminderView alloc]
        initWithText:NSLocalizedString(@"COMPOSE_SCREEN_MISSING_CONTACTS_PERMISSION",
                         @"Multiline label explaining why compose-screen contact picker is empty.")
           tapAction:^{
               [[UIApplication sharedApplication] openSystemSettings];
           }];
    [self.view addSubview:contactsPermissionReminderView];
    [contactsPermissionReminderView autoPinWidthToSuperview];
    [contactsPermissionReminderView autoPinEdgeToSuperviewMargin:ALEdgeTop];
    _hideContactsPermissionReminderViewConstraint =
        [contactsPermissionReminderView autoSetDimension:ALDimensionHeight toSize:0];

    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemStop
                                                      target:self
                                                      action:@selector(dismissPressed)];
    // TODO:
    UIImage *newGroupImage = [UIImage imageNamed:@"btnGroup--white"];
    OWSAssert(newGroupImage);
    UIBarButtonItem *newGroupButton = [[UIBarButtonItem alloc] initWithImage:newGroupImage
                                                                       style:UIBarButtonItemStylePlain
                                                                      target:self
                                                                      action:@selector(showNewGroupView:)];
    newGroupButton.accessibilityLabel
        = NSLocalizedString(@"CREATE_NEW_GROUP", @"Accessibility label for the create group new group button");
    self.navigationItem.rightBarButtonItem = newGroupButton;

    // Search
    UISearchBar *searchBar = [UISearchBar new];
    _searchBar = searchBar;
    searchBar.searchBarStyle = UISearchBarStyleMinimal;
    searchBar.delegate = self;
    searchBar.placeholder = NSLocalizedString(@"SEARCH_BYNAMEORNUMBER_PLACEHOLDER_TEXT", @"");
    searchBar.backgroundColor = [UIColor whiteColor];
    [searchBar sizeToFit];

    _tableViewController = [OWSTableViewController new];
    _tableViewController.delegate = self;
    _tableViewController.tableViewStyle = UITableViewStylePlain;
    [self.view addSubview:self.tableViewController.view];
    [_tableViewController.view autoPinWidthToSuperview];

    [_tableViewController.view autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:contactsPermissionReminderView];
    [_tableViewController.view autoPinToBottomLayoutGuideOfViewController:self withInset:0];
    _tableViewController.tableView.tableHeaderView = searchBar;

    _noSignalContactsView = [self createNoSignalContactsView];
    self.noSignalContactsView.hidden = YES;
    [self.view addSubview:self.noSignalContactsView];
    [self.noSignalContactsView autoPinWidthToSuperview];
    [self.noSignalContactsView autoPinEdgeToSuperviewEdge:ALEdgeTop];
    [self.noSignalContactsView autoPinToBottomLayoutGuideOfViewController:self withInset:0];

    [self updateTableContents];
}

- (void)showContactsPermissionReminder:(BOOL)isVisible
{
    _hideContactsPermissionReminderViewConstraint.active = !isVisible;
}

- (void)showSearchBar:(BOOL)isVisible
{
    if (isVisible) {
        self.tableViewController.tableView.tableHeaderView = self.searchBar;
    } else {
        self.tableViewController.tableView.tableHeaderView = nil;
    }
}

- (UIView *)createNoSignalContactsView
{
    UIView *view = [UIView new];
    view.backgroundColor = [UIColor whiteColor];

    UIView *contents = [UIView new];
    [view addSubview:contents];
    [contents autoCenterInSuperview];

    UIImage *heroImage = [UIImage imageNamed:@"uiEmptyContact"];
    OWSAssert(heroImage);
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
    titleLabel.textColor = [UIColor blackColor];
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
    subtitleLabel.textColor = [UIColor colorWithWhite:0.32f alpha:1.f];
    subtitleLabel.font = [UIFont ows_regularFontWithSize:ScaleFromIPhone5To7Plus(12.f, 14.f)];
    subtitleLabel.textAlignment = NSTextAlignmentCenter;
    subtitleLabel.lineBreakMode = NSLineBreakByWordWrapping;
    subtitleLabel.numberOfLines = 0;
    [contents addSubview:subtitleLabel];
    [subtitleLabel autoPinWidthToSuperview];
    [subtitleLabel autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:lastSubview withOffset:15];
    lastSubview = subtitleLabel;

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

    UIButton *searchByPhoneNumberButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [searchByPhoneNumberButton setTitle:NSLocalizedString(@"NO_CONTACTS_SEARCH_BY_PHONE_NUMBER",
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

    [lastSubview autoPinEdgeToSuperviewMargin:ALEdgeBottom];

    return view;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = NSLocalizedString(@"MESSAGE_COMPOSEVIEW_TITLE", @"");
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    // Make sure we have requested contact access at this point if, e.g.
    // the user has no messages in their inbox and they choose to compose
    // a message.
    [self.contactsViewHelper.contactsManager requestSystemContactsOnce];

    [self.navigationController.navigationBar setTranslucent:NO];

    [self showContactAppropriateViews];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    [self showIOSUpgradeNagIfNecessary];
}

- (void)showIOSUpgradeNagIfNecessary {
    // Only show the nag to iOS 8 users.
    if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(9, 0)) {
        return;
    }

    // Don't show the nag to users who have just launched
    // the app for the first time.
    if (![AppVersion instance].lastAppVersion) {
        return;
    }

    // Only show the nag once per update of the app.
    NSString *currentAppVersion = [AppVersion instance].currentAppVersion;
    OWSAssert(currentAppVersion.length > 0);
    NSString *lastNagAppVersion = [Environment.preferences iOSUpgradeNagVersion];
    if (lastNagAppVersion &&
        ![lastNagAppVersion isEqualToString:currentAppVersion]) {
        
        [Environment.preferences setIOSUpgradeNagVersion:currentAppVersion];
        
        [OWSAlerts showAlertWithTitle:
         NSLocalizedString(@"UPGRADE_IOS_ALERT_TITLE",
                           @"Title for the alert indicating that user should upgrade iOS.")
                              message:NSLocalizedString(@"UPGRADE_IOS_ALERT_MESSAGE",
                                                        @"Message for the alert indicating that user should upgrade iOS.")];
    }
}

#pragma mark - Table Contents

- (void)updateTableContents
{
    OWSTableContents *contents = [OWSTableContents new];

    if (self.isNoContactsModeActive) {
        self.tableViewController.contents = contents;
        return;
    }

    __weak MessageComposeTableViewController *weakSelf = self;
    ContactsViewHelper *helper = self.contactsViewHelper;

    OWSTableSection *section = [OWSTableSection new];

    const CGFloat kActionCellHeight
        = ScaleFromIPhone5To7Plus(round((kOWSTable_DefaultCellHeight + [ContactTableViewCell rowHeight]) * 0.5f),
            [ContactTableViewCell rowHeight]);

    // Find Non-Contacts by Phone Number
    [section addItem:[OWSTableItem itemWithCustomCellBlock:^{
        UITableViewCell *cell = [UITableViewCell new];
        cell.textLabel.text = NSLocalizedString(
            @"NEW_CONVERSATION_FIND_BY_PHONE_NUMBER", @"A label the cell that lets you add a new member to a group.");
        cell.textLabel.font = [UIFont ows_regularFontWithSize:18.f];
        cell.textLabel.textColor = [UIColor blackColor];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }
                         customRowHeight:kActionCellHeight
                         actionBlock:^{
                             NewNonContactConversationViewController *viewController =
                                 [NewNonContactConversationViewController new];
                             viewController.nonContactConversationDelegate = weakSelf;
                             [weakSelf.navigationController pushViewController:viewController animated:YES];
                         }]];

    if (self.contactsViewHelper.contactsManager.isSystemContactsAuthorized) {
        // Invite Contacts
        [section addItem:[OWSTableItem itemWithCustomCellBlock:^{
            UITableViewCell *cell = [UITableViewCell new];
            cell.textLabel.text = NSLocalizedString(@"INVITE_FRIENDS_CONTACT_TABLE_BUTTON",
                @"Label for the cell that presents the 'invite contacts' workflow.");
            cell.textLabel.font = [UIFont ows_regularFontWithSize:18.f];
            cell.textLabel.textColor = [UIColor blackColor];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            return cell;
        }
                             customRowHeight:kActionCellHeight
                             actionBlock:^{
                                 [weakSelf presentInviteFlow];
                             }]];
    }

    // If the search string looks like a phone number, show either "new conversation..." cells and/or
    // "invite via SMS..." cells.
    NSArray<NSString *> *searchPhoneNumbers = [self parsePossibleSearchPhoneNumbers];
    for (NSString *phoneNumber in searchPhoneNumbers) {
        OWSAssert(phoneNumber.length > 0);

        if ([self.nonContactAccountSet containsObject:phoneNumber]) {
            [section addItem:[OWSTableItem itemWithCustomCellBlock:^{
                ContactTableViewCell *cell = [ContactTableViewCell new];
                BOOL isBlocked = [helper isRecipientIdBlocked:phoneNumber];
                if (isBlocked) {
                    cell.accessoryMessage = NSLocalizedString(
                        @"CONTACT_CELL_IS_BLOCKED", @"An indicator that a contact has been blocked.");
                }

                SignalAccount *signalAccount = [helper signalAccountForRecipientId:phoneNumber];
                if (signalAccount) {
                    [cell configureWithSignalAccount:signalAccount contactsManager:helper.contactsManager];
                } else {
                    [cell configureWithRecipientId:phoneNumber contactsManager:helper.contactsManager];
                }

                return cell;
            }
                                 customRowHeight:[ContactTableViewCell rowHeight]
                                 actionBlock:^{
                                     [weakSelf newConversationWith:phoneNumber];
                                 }]];
        } else {
            [section addItem:[OWSTableItem itemWithCustomCellBlock:^{
                UITableViewCell *cell = [UITableViewCell new];
                cell.textLabel.text =
                    [NSString stringWithFormat:NSLocalizedString(@"SEND_INVITE_VIA_SMS_BUTTON_FORMAT",
                                                   @"Text for button to send a Signal invite via SMS. %@ is "
                                                   @"placeholder for the receipient's phone number."),
                              phoneNumber];
                cell.textLabel.font = [UIFont ows_regularFontWithSize:18.f];
                cell.textLabel.textColor = [UIColor blackColor];
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                return cell;
            }
                                 customRowHeight:kActionCellHeight
                                 actionBlock:^{
                                     [weakSelf sendTextToPhoneNumber:phoneNumber];
                                 }]];
        }
    }

    // Contacts, possibly filtered with the search text.
    NSArray<SignalAccount *> *filteredSignalAccounts = [self filteredSignalAccounts];
    for (SignalAccount *signalAccount in filteredSignalAccounts) {
        if ([searchPhoneNumbers containsObject:signalAccount.recipientId]) {
            // Don't show a contact if they already appear in the "search phone numbers"
            // results.
            continue;
        }
        [section addItem:[OWSTableItem itemWithCustomCellBlock:^{
            ContactTableViewCell *cell = [ContactTableViewCell new];
            BOOL isBlocked = [helper isRecipientIdBlocked:signalAccount.recipientId];
            if (isBlocked) {
                cell.accessoryMessage
                    = NSLocalizedString(@"CONTACT_CELL_IS_BLOCKED", @"An indicator that a contact has been blocked.");
            }

            [cell configureWithSignalAccount:signalAccount contactsManager:helper.contactsManager];

            return cell;
        }
                             customRowHeight:[ContactTableViewCell rowHeight]
                             actionBlock:^{
                                 [weakSelf newConversationWith:signalAccount.recipientId];
                             }]];
    }

    BOOL hasSearchText = [self.searchBar text].length > 0;
    BOOL hasSearchResults = filteredSignalAccounts.count > 0;

    // Invitation offers for non-signal contacts
    if (hasSearchText) {
        for (Contact *contact in [helper nonSignalContactsMatchingSearchString:[self.searchBar text]]) {
            hasSearchResults = YES;

            OWSAssert(contact.parsedPhoneNumbers.count > 0);
            // TODO: Should we invite all of their phone numbers?
            PhoneNumber *phoneNumber = contact.parsedPhoneNumbers[0];
            NSString *displayName = contact.fullName;
            if (displayName.length < 1) {
                displayName = phoneNumber.toE164;
            }

            [section addItem:[OWSTableItem itemWithCustomCellBlock:^{
                UITableViewCell *cell = [UITableViewCell new];
                cell.textLabel.text =
                    [NSString stringWithFormat:NSLocalizedString(@"SEND_INVITE_VIA_SMS_BUTTON_FORMAT",
                                                   @"Text for button to send a Signal invite via SMS. %@ is "
                                                   @"placeholder for the receipient's phone number."),
                              displayName];
                cell.textLabel.font = [UIFont ows_regularFontWithSize:18.f];
                cell.textLabel.textColor = [UIColor blackColor];
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                return cell;
            }
                                 customRowHeight:kActionCellHeight
                                 actionBlock:^{
                                     [weakSelf sendTextToPhoneNumber:phoneNumber.toE164];
                                 }]];
        }
    }

    if (!hasSearchText && helper.signalAccounts.count < 1) {
        // No Contacts

        if (self.contactsViewHelper.contactsManager.isSystemContactsAuthorized
            && self.contactsViewHelper.hasUpdatedContactsAtLeastOnce) {
            [section addItem:[OWSTableItem itemWithCustomCellBlock:^{
                UITableViewCell *cell = [UITableViewCell new];
                cell.textLabel.text = NSLocalizedString(
                    @"SETTINGS_BLOCK_LIST_NO_CONTACTS", @"A label that indicates the user has no Signal contacts.");
                cell.textLabel.font = [UIFont ows_regularFontWithSize:15.f];
                cell.textLabel.textColor = [UIColor colorWithWhite:0.5f alpha:1.f];
                cell.textLabel.textAlignment = NSTextAlignmentCenter;
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
                return cell;
            }
                                                   customRowHeight:kActionCellHeight
                                                       actionBlock:nil]];
        }
    }

    if (hasSearchText && !hasSearchResults) {
        // No Search Results

        [section addItem:[OWSTableItem itemWithCustomCellBlock:^{
            UITableViewCell *cell = [UITableViewCell new];
            cell.textLabel.text = NSLocalizedString(@"SETTINGS_BLOCK_LIST_NO_SEARCH_RESULTS",
                @"A label that indicates the user's search has no matching results.");
            cell.textLabel.font = [UIFont ows_regularFontWithSize:15.f];
            cell.textLabel.textColor = [UIColor colorWithWhite:0.5f alpha:1.f];
            cell.textLabel.textAlignment = NSTextAlignmentCenter;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            return cell;
        }
                                               customRowHeight:kActionCellHeight
                                                   actionBlock:nil]];
    }

    [contents addSection:section];

    self.tableViewController.contents = contents;
}

- (NSArray<SignalAccount *> *)filteredSignalAccounts
{
    NSString *searchString = [self.searchBar text];

    ContactsViewHelper *helper = self.contactsViewHelper;
    return [helper signalAccountsMatchingSearchString:searchString];
}

#pragma mark - No Contacts Mode

- (void)hideBackgroundView
{
    [[Environment preferences] setHasDeclinedNoContactsView:YES];

    [self showContactAppropriateViews];
}

- (void)presentInviteFlow
{
    OWSInviteFlow *inviteFlow =
        [[OWSInviteFlow alloc] initWithPresentingViewController:self
                                                contactsManager:self.contactsViewHelper.contactsManager];
    [self presentViewController:inviteFlow.actionSheetController animated:YES completion:nil];
}

- (void)showContactAppropriateViews
{
    if (self.contactsViewHelper.contactsManager.isSystemContactsAuthorized) {
        if (self.contactsViewHelper.hasUpdatedContactsAtLeastOnce
            && self.contactsViewHelper.signalAccounts.count < 1
            && ![[Environment preferences] hasDeclinedNoContactsView]) {
            self.isNoContactsModeActive = YES;
        } else {
            self.isNoContactsModeActive = NO;
        }

        [self showContactsPermissionReminder:NO];
        [self showSearchBar:YES];
    } else {
        // don't show "no signal contacts", show "no contact access"
        self.isNoContactsModeActive = NO;
        [self showContactsPermissionReminder:YES];
        [self showSearchBar:NO];
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

- (void)sendTextToPhoneNumber:(NSString *)phoneNumber {
    OWSAssert([phoneNumber length] > 0);
    NSString *confirmMessage = NSLocalizedString(@"SEND_SMS_CONFIRM_TITLE", @"");
    if ([phoneNumber length] > 0) {
        confirmMessage = [[NSLocalizedString(@"SEND_SMS_INVITE_TITLE", @"")
                           stringByAppendingString:phoneNumber]
                          stringByAppendingString:NSLocalizedString(@"QUESTIONMARK_PUNCTUATION", @"")];
    }

    UIAlertController *alertController =
        [UIAlertController alertControllerWithTitle:NSLocalizedString(@"CONFIRMATION_TITLE", @"")
                                            message:confirmMessage
                                     preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"TXT_CANCEL_TITLE", @"")
                                                           style:UIAlertActionStyleCancel
                                                         handler:^(UIAlertAction *action) {
                                                             DDLogDebug(@"Cancel action");
                                                         }];

    UIAlertAction *okAction = [UIAlertAction
        actionWithTitle:NSLocalizedString(@"OK", @"")
                  style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *action) {
                    [self.searchBar resignFirstResponder];

                    if ([MFMessageComposeViewController canSendText]) {
                        MFMessageComposeViewController *picker = [[MFMessageComposeViewController alloc] init];
                        picker.messageComposeDelegate = self;

                        picker.recipients = @[
                            phoneNumber,
                        ];
                        picker.body = [NSLocalizedString(@"SMS_INVITE_BODY", @"")
                            stringByAppendingString:
                                @" https://itunes.apple.com/us/app/signal-private-messenger/id874139669?mt=8"];
                        [self presentViewController:picker animated:YES completion:[UIUtil modalCompletionBlock]];
                    } else {
                        [OWSAlerts showAlertWithTitle:NSLocalizedString(@"ALERT_ERROR_TITLE", @"")
                                              message:NSLocalizedString(@"UNSUPPORTED_FEATURE_ERROR", @"")];
                    }
                }];

    [alertController addAction:cancelAction];
    [alertController addAction:okAction];
    self.searchBar.text = @"";

    //must dismiss search controller before presenting alert.
    if ([self presentedViewController]) {
        [self dismissViewControllerAnimated:YES completion:^{
            [self presentViewController:alertController animated:YES completion:[UIUtil modalCompletionBlock]];
        }];
    } else {
        [self presentViewController:alertController animated:YES completion:[UIUtil modalCompletionBlock]];
    }
}

#pragma mark - SMS Composer Delegate

// called on completion of message screen
- (void)messageComposeViewController:(MFMessageComposeViewController *)controller
                 didFinishWithResult:(MessageComposeResult)result {
    switch (result) {
        case MessageComposeResultCancelled:
            break;
        case MessageComposeResultFailed: {
            UIAlertView *warningAlert =
                [[UIAlertView alloc] initWithTitle:@""
                                           message:NSLocalizedString(@"SEND_INVITE_FAILURE", @"")
                                          delegate:nil
                                 cancelButtonTitle:NSLocalizedString(@"OK", @"")
                                 otherButtonTitles:nil];
            [warningAlert show];
            break;
        }
        case MessageComposeResultSent: {
            [self dismissViewControllerAnimated:NO
                                     completion:^{
                                       DDLogDebug(@"view controller dismissed");
                                     }];
            UIAlertView *successAlert =
                [[UIAlertView alloc] initWithTitle:@""
                                           message:NSLocalizedString(@"SEND_INVITE_SUCCESS", @"Alert body after invite succeeded")
                                          delegate:nil
                                 cancelButtonTitle:NSLocalizedString(@"OK", @"")
                                 otherButtonTitles:nil];
            [successAlert show];
            break;
        }
        default:
            break;
    }

    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Methods

- (void)dismissPressed
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)newConversationWith:(NSString *)recipientId
{
    OWSAssert(recipientId.length > 0);

    [self dismissViewControllerAnimated:YES
                             completion:^() {
                                 [Environment messageIdentifier:recipientId withCompose:YES];
                             }];
}

- (void)showNewGroupView:(id)sender
{
    NewGroupViewController *newGroupViewController = [NewGroupViewController new];
    [self.navigationController pushViewController:newGroupViewController animated:YES];
}

#pragma mark - OWSTableViewControllerDelegate

- (void)tableViewDidScroll
{
    [self.searchBar resignFirstResponder];
}

#pragma mark - ContactsViewHelperDelegate

- (void)contactsViewHelperDidUpdateContacts
{
    [self updateTableContents];

    [self showContactAppropriateViews];
}

- (BOOL)shouldHideLocalNumber
{
    return NO;
}

#pragma mark - NewNonContactConversationViewControllerDelegate

- (void)recipientIdWasSelected:(NSString *)recipientId
{
    OWSAssert(recipientId.length > 0);

    [self newConversationWith:recipientId];
}

#pragma mark - UISearchBarDelegate

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText
{
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

- (void)searchTextDidChange
{
    [self updateSearchPhoneNumbers];

    [self updateTableContents];
}

- (NSDictionary<NSString *, NSString *> *)callingCodesToCountryCodeMap
{
    static NSDictionary<NSString *, NSString *> *result = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableDictionary *map = [NSMutableDictionary new];
        for (NSString *countryCode in [PhoneNumberUtil countryCodesForSearchTerm:nil]) {
            OWSAssert(countryCode.length > 0);
            NSString *callingCode = [PhoneNumberUtil callingCodeFromCountryCode:countryCode];
            OWSAssert(callingCode.length > 0);
            OWSAssert([callingCode hasPrefix:@"+"]);
            OWSAssert(![callingCode isEqualToString:@"+0"]);

            map[callingCode] = countryCode;
        }
        result = [map copy];
    });
    return result;
}

- (NSString *)callingCodeForPossiblePhoneNumber:(NSString *)phoneNumber
{
    OWSAssert([phoneNumber hasPrefix:@"+"]);

    for (NSString *callingCode in [self callingCodesToCountryCodeMap].allKeys) {
        if ([phoneNumber hasPrefix:callingCode]) {
            return callingCode;
        }
    }
    return nil;
}

- (NSArray<NSString *> *)parsePossibleSearchPhoneNumbers
{
    NSString *searchText = self.searchBar.text;

    if (searchText.length < 8) {
        return nil;
    }

    NSMutableSet<NSString *> *parsedPhoneNumbers = [NSMutableSet new];
    for (PhoneNumber *phoneNumber in
        [PhoneNumber tryParsePhoneNumbersFromsUserSpecifiedText:searchText
                                              clientPhoneNumber:[TSAccountManager localNumber]]) {

        NSString *phoneNumberString = phoneNumber.toE164;

        // Ignore phone numbers with an unrecognized calling code.
        NSString *callingCode = [self callingCodeForPossiblePhoneNumber:phoneNumberString];
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
        if (![self.nonContactAccountSet containsObject:phoneNumber]) {
            [unknownPhoneNumbers addObject:phoneNumber];
        }
    }
    if ([unknownPhoneNumbers count] < 1) {
        return;
    }

    __weak MessageComposeTableViewController *weakSelf = self;
    [[ContactsUpdater sharedUpdater] lookupIdentifiers:unknownPhoneNumbers
                                               success:^(NSArray<SignalRecipient *> *recipients) {
                                                   [weakSelf updateNonContactAccountSet:recipients];
                                               }
                                               failure:^(NSError *error){
                                                   // Ignore.
                                               }];
}

- (void)updateNonContactAccountSet:(NSArray<SignalRecipient *> *)recipients
{
    BOOL didUpdate = NO;
    for (SignalRecipient *recipient in recipients) {
        if ([self.nonContactAccountSet containsObject:recipient.recipientId]) {
            continue;
        }
        [self.nonContactAccountSet addObject:recipient.recipientId];
        didUpdate = YES;
    }
    if (didUpdate) {
        [self updateTableContents];
    }
}

@end

NS_ASSUME_NONNULL_END
