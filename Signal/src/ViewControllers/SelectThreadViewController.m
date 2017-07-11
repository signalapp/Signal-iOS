//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "SelectThreadViewController.h"
#import "BlockListUIUtils.h"
#import "ContactTableViewCell.h"
#import "ContactsViewHelper.h"
#import "Environment.h"
#import "OWSContactsManager.h"
#import "OWSContactsSearcher.h"
#import "OWSTableViewController.h"
#import "ThreadViewHelper.h"
#import "UIColor+OWS.h"
#import "UIFont+OWS.h"
#import "UIView+OWS.h"
#import <SignalServiceKit/PhoneNumber.h>
#import <SignalServiceKit/SignalAccount.h>
#import <SignalServiceKit/TSAccountManager.h>
#import <SignalServiceKit/TSContactThread.h>
#import <SignalServiceKit/TSThread.h>

NS_ASSUME_NONNULL_BEGIN

@interface SelectThreadViewController () <OWSTableViewControllerDelegate,
    ThreadViewHelperDelegate,
    ContactsViewHelperDelegate,
    UISearchBarDelegate>

@property (nonatomic, readonly) ContactsViewHelper *contactsViewHelper;

@property (nonatomic, readonly) ThreadViewHelper *threadViewHelper;

@property (nonatomic, readonly) OWSTableViewController *tableViewController;

@property (nonatomic, readonly) UISearchBar *searchBar;

@end

#pragma mark -

@implementation SelectThreadViewController

- (void)loadView
{
    [super loadView];

    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemStop
                                                      target:self
                                                      action:@selector(dismissPressed:)];

    self.view.backgroundColor = [UIColor whiteColor];

    _contactsViewHelper = [[ContactsViewHelper alloc] initWithDelegate:self];
    _threadViewHelper = [ThreadViewHelper new];
    _threadViewHelper.delegate = self;

    [self createViews];

    [self updateTableContents];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self.navigationController.navigationBar setTranslucent:NO];
}

- (void)createViews
{
    OWSAssert(self.delegate);

    // Search
    UISearchBar *searchBar = [UISearchBar new];
    _searchBar = searchBar;
    searchBar.searchBarStyle = UISearchBarStyleMinimal;
    searchBar.delegate = self;
    searchBar.placeholder = NSLocalizedString(@"SEARCH_BYNAMEORNUMBER_PLACEHOLDER_TEXT", @"");
    searchBar.backgroundColor = [UIColor whiteColor];
    [searchBar sizeToFit];

    UIView *header = [self.delegate createHeaderWithSearchBar:searchBar];

    // Table
    _tableViewController = [OWSTableViewController new];
    _tableViewController.delegate = self;
    [self.view addSubview:self.tableViewController.view];
    [_tableViewController.view autoPinWidthToSuperview];
    [_tableViewController.view autoPinToTopLayoutGuideOfViewController:self withInset:0];
    if (header) {
        _tableViewController.tableView.tableHeaderView = header;
    } else {
        _tableViewController.tableView.tableHeaderView = searchBar;
    }
    [_tableViewController.view autoPinEdgeToSuperviewEdge:ALEdgeBottom];
}

#pragma mark - UISearchBarDelegate

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText
{
    [self updateTableContents];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar
{
    [self updateTableContents];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar
{
    [self updateTableContents];
}

- (void)searchBarResultsListButtonClicked:(UISearchBar *)searchBar
{
    [self updateTableContents];
}

- (void)searchBar:(UISearchBar *)searchBar selectedScopeButtonIndexDidChange:(NSInteger)selectedScope
{
    [self updateTableContents];
}

#pragma mark - Table Contents

- (void)updateTableContents
{
    __weak SelectThreadViewController *weakSelf = self;
    ContactsViewHelper *helper = self.contactsViewHelper;
    OWSTableContents *contents = [OWSTableContents new];
    OWSTableSection *section = [OWSTableSection new];

    // Threads
    for (TSThread *thread in [self filteredThreadsWithSearchText]) {
        [section addItem:[OWSTableItem itemWithCustomCellBlock:^{
            SelectThreadViewController *strongSelf = weakSelf;
            OWSAssert(strongSelf);

            // To be consistent with the threads (above), we use ContactTableViewCell
            // instead of InboxTableViewCell to present contacts and threads.
            ContactTableViewCell *cell = [ContactTableViewCell new];
            [cell configureWithThread:thread contactsManager:helper.contactsManager];
            return cell;
        }
                             customRowHeight:[ContactTableViewCell rowHeight]
                             actionBlock:^{
                                 [weakSelf.delegate threadWasSelected:thread];
                             }]];
    }

    // Contacts
    NSArray<SignalAccount *> *filteredSignalAccounts = [self filteredSignalAccountsWithSearchText];
    for (SignalAccount *signalAccount in filteredSignalAccounts) {
        [section addItem:[OWSTableItem itemWithCustomCellBlock:^{
            SelectThreadViewController *strongSelf = weakSelf;
            OWSAssert(strongSelf);

            ContactTableViewCell *cell = [ContactTableViewCell new];
            BOOL isBlocked = [helper isRecipientIdBlocked:signalAccount.recipientId];
            if (isBlocked) {
                cell.accessoryMessage
                    = NSLocalizedString(@"CONTACT_CELL_IS_BLOCKED", @"An indicator that a contact has been blocked.");
            } else {
                OWSAssert(cell.accessoryMessage == nil);
            }
            [cell configureWithSignalAccount:signalAccount contactsManager:helper.contactsManager];
            return cell;
        }
                             customRowHeight:[ContactTableViewCell rowHeight]
                             actionBlock:^{
                                 [weakSelf signalAccountWasSelected:signalAccount];
                             }]];
    }

    if (section.itemCount < 1) {
        [section addItem:[OWSTableItem itemWithCustomCellBlock:^{
            UITableViewCell *cell = [UITableViewCell new];
            cell.textLabel.text = NSLocalizedString(
                @"SETTINGS_BLOCK_LIST_NO_CONTACTS", @"A label that indicates the user has no Signal contacts.");
            cell.textLabel.font = [UIFont ows_regularFontWithSize:15.f];
            cell.textLabel.textColor = [UIColor colorWithWhite:0.5f alpha:1.f];
            cell.textLabel.textAlignment = NSTextAlignmentCenter;
            return cell;
        }
                                                   actionBlock:nil]];
    }
    [contents addSection:section];

    self.tableViewController.contents = contents;
}

- (void)signalAccountWasSelected:(SignalAccount *)signalAccount
{
    OWSAssert(signalAccount);
    OWSAssert(self.delegate);

    ContactsViewHelper *helper = self.contactsViewHelper;

    if ([helper isRecipientIdBlocked:signalAccount.recipientId] && ![self.delegate canSelectBlockedContact]) {

        __weak SelectThreadViewController *weakSelf = self;
        [BlockListUIUtils showUnblockSignalAccountActionSheet:signalAccount
                                           fromViewController:self
                                              blockingManager:helper.blockingManager
                                              contactsManager:helper.contactsManager
                                              completionBlock:^(BOOL isBlocked) {
                                                  if (!isBlocked) {
                                                      [weakSelf signalAccountWasSelected:signalAccount];
                                                  }
                                              }];
        return;
    }

    __block TSThread *thread = nil;
    [[TSStorageManager sharedManager].dbReadWriteConnection
        readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            thread = [TSContactThread getOrCreateThreadWithContactId:signalAccount.recipientId transaction:transaction];
        }];
    OWSAssert(thread);

    [self.delegate threadWasSelected:thread];
}

#pragma mark - Filter

- (NSArray<TSThread *> *)filteredThreadsWithSearchText
{
    NSArray<TSThread *> *threads = self.threadViewHelper.threads;

    NSString *searchTerm =
        [[self.searchBar text] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    if ([searchTerm isEqualToString:@""]) {
        return threads;
    }

    NSString *formattedNumber = [PhoneNumber removeFormattingCharacters:searchTerm];

    NSMutableArray *result = [NSMutableArray new];
    for (TSThread *thread in threads) {
        if ([thread.name containsString:searchTerm]) {
            [result addObject:thread];
        } else if ([thread isKindOfClass:[TSContactThread class]]) {
            TSContactThread *contactThread = (TSContactThread *)thread;
            if (formattedNumber.length > 0 && [contactThread.contactIdentifier containsString:formattedNumber]) {
                [result addObject:thread];
            }
        }
    }
    return result;
}

- (NSArray<SignalAccount *> *)filteredSignalAccountsWithSearchText
{
    // We don't want to show a 1:1 thread with Alice and Alice's contact,
    // so we de-duplicate by recipientId.
    NSArray<TSThread *> *threads = self.threadViewHelper.threads;
    NSMutableSet *contactIdsToIgnore = [NSMutableSet new];
    for (TSThread *thread in threads) {
        if ([thread isKindOfClass:[TSContactThread class]]) {
            TSContactThread *contactThread = (TSContactThread *)thread;
            [contactIdsToIgnore addObject:contactThread.contactIdentifier];
        }
    }

    NSString *searchString = [self.searchBar text];

    ContactsViewHelper *helper = self.contactsViewHelper;
    return [[helper signalAccountsMatchingSearchString:searchString]
        filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(SignalAccount *signalAccount,
                                        NSDictionary<NSString *, id> *_Nullable bindings) {
            return ![contactIdsToIgnore containsObject:signalAccount.recipientId];
        }]];
}

#pragma mark - Events

- (void)dismissPressed:(id)sender
{
    [self.searchBar resignFirstResponder];
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - OWSTableViewControllerDelegate

- (void)tableViewDidScroll
{
    [self.searchBar resignFirstResponder];
}

#pragma mark - ThreadViewHelperDelegate

- (void)threadListDidChange
{
    [self updateTableContents];
}

#pragma mark - ContactsViewHelperDelegate

- (void)contactsViewHelperDidUpdateContacts
{
    [self updateTableContents];
}

- (BOOL)shouldHideLocalNumber
{
    return NO;
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

NS_ASSUME_NONNULL_END
