//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "SelectThreadViewController.h"
#import "BlockListUIUtils.h"
#import "ContactTableViewCell.h"
#import "Environment.h"
#import "InboxTableViewCell.h"
#import "OWSContactsManager.h"
#import "OWSContactsSearcher.h"
#import "OWSTableViewController.h"
#import "ThreadViewHelper.h"
#import "UIColor+OWS.h"
#import "UIFont+OWS.h"
#import "UIView+OWS.h"
#import <SignalServiceKit/OWSBlockingManager.h>
#import <SignalServiceKit/TSAccountManager.h>
#import <SignalServiceKit/TSContactThread.h>
#import <SignalServiceKit/TSThread.h>

NS_ASSUME_NONNULL_BEGIN

@interface SelectThreadViewController () <OWSTableViewControllerDelegate, ThreadViewHelperDelegate, UISearchBarDelegate>

@property (nonatomic, readonly) OWSBlockingManager *blockingManager;
@property (nonatomic) NSSet<NSString *> *blockedPhoneNumberSet;

@property (nonatomic, readonly) OWSContactsManager *contactsManager;
@property (nonatomic) NSArray<Contact *> *contacts;

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

    _blockingManager = [OWSBlockingManager sharedManager];
    _blockedPhoneNumberSet = [NSSet setWithArray:[_blockingManager blockedPhoneNumbers]];
    _contactsManager = [Environment getCurrent].contactsManager;
    self.contacts = [self filteredContacts];
    _threadViewHelper = [ThreadViewHelper new];
    _threadViewHelper.delegate = self;

    [self createViews];

    [self addNotificationListeners];

    [self updateTableContents];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self.navigationController.navigationBar setTranslucent:NO];
}

- (void)addNotificationListeners
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(blockedPhoneNumbersDidChange:)
                                                 name:kNSNotificationName_BlockedPhoneNumbersDidChange
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(signalRecipientsDidChange:)
                                                 name:OWSContactsManagerSignalRecipientsDidChangeNotification
                                               object:nil];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
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

#pragma mark - Actions

- (void)updateTableContents
{
    __weak SelectThreadViewController *weakSelf = self;
    OWSTableContents *contents = [OWSTableContents new];
    OWSTableSection *section = [OWSTableSection new];

    // Threads
    for (TSThread *thread in [self filteredThreadsWithSearchText]) {
        [section addItem:[OWSTableItem itemWithCustomCellBlock:^{
            SelectThreadViewController *strongSelf = weakSelf;
            if (!strongSelf) {
                return (ContactTableViewCell *)nil;
            }

            // To be consistent with the threads (above), we use ContactTableViewCell
            // instead of InboxTableViewCell to present contacts and threads.
            ContactTableViewCell *cell = [ContactTableViewCell new];
            [cell configureWithThread:thread contactsManager:strongSelf.contactsManager];
            return cell;
        }
                             customRowHeight:[ContactTableViewCell rowHeight]
                             actionBlock:^{
                                 [weakSelf.delegate threadWasSelected:thread];
                             }]];
    }

    // Contacts
    NSArray<Contact *> *filteredContacts = [self filteredContactsWithSearchText];
    for (Contact *contact in filteredContacts) {
        [section addItem:[OWSTableItem itemWithCustomCellBlock:^{
            SelectThreadViewController *strongSelf = weakSelf;
            if (!strongSelf) {
                return (ContactTableViewCell *)nil;
            }

            ContactTableViewCell *cell = [ContactTableViewCell new];
            BOOL isBlocked = [strongSelf isContactBlocked:contact];
            if (isBlocked) {
                cell.accessoryMessage
                    = NSLocalizedString(@"CONTACT_CELL_IS_BLOCKED", @"An indicator that a contact has been blocked.");
            } else {
                OWSAssert(cell.accessoryMessage == nil);
            }
            [cell configureWithContact:contact contactsManager:strongSelf.contactsManager];
            return cell;
        }
                             customRowHeight:[ContactTableViewCell rowHeight]
                             actionBlock:^{
                                 [weakSelf contactWasSelected:contact];
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

- (void)contactWasSelected:(Contact *)contact
{
    OWSAssert(contact);
    OWSAssert(self.delegate);

    // TODO: Use ContactAccount.
    NSString *recipientId = contact.textSecureIdentifiers.firstObject;
    
    if ([self isRecipientIdBlocked:recipientId] &&
        ![self.delegate canSelectBlockedContact]) {
        
        __weak SelectThreadViewController *weakSelf = self;
        [BlockListUIUtils showUnblockContactActionSheet:contact
                                     fromViewController:self
                                        blockingManager:self.blockingManager
                                        contactsManager:self.contactsManager
                                        completionBlock:^(BOOL isBlocked) {
                                            if (!isBlocked) {
                                                [weakSelf contactWasSelected:contact];
                                            }
                                        }];
        return;
    }

    __block TSThread *thread = nil;
    [[TSStorageManager sharedManager].dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        thread = [TSContactThread getOrCreateThreadWithContactId:recipientId transaction:transaction];
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

// TODO: Move this to contacts view helper.
- (NSArray<Contact *> *)filteredContactsWithSearchText
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

    NSArray *nonRedundantContacts =
        [self.contacts filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(Contact *contact,
                                                       NSDictionary<NSString *, id> *_Nullable bindings) {
            return ![contactIdsToIgnore containsObject:contact.textSecureIdentifiers.firstObject];
        }]];

    // TODO: Move this to contacts view helper.
    OWSContactsSearcher *contactsSearcher = [[OWSContactsSearcher alloc] initWithContacts:nonRedundantContacts];
    NSArray<Contact *> *filteredContacts = [contactsSearcher filterWithString:searchString];

    return filteredContacts;
}

#pragma mark - Contacts and Blocking

- (void)blockedPhoneNumbersDidChange:(id)notification
{
    dispatch_async(dispatch_get_main_queue(), ^{
        _blockedPhoneNumberSet = [NSSet setWithArray:[_blockingManager blockedPhoneNumbers]];

        [self updateContacts];
    });
}

- (void)signalRecipientsDidChange:(NSNotification *)notification
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateContacts];
    });
}

- (void)updateContacts
{
    OWSAssert([NSThread isMainThread]);

    self.contacts = [self filteredContacts];
    [self updateTableContents];
}

- (BOOL)isContactBlocked:(Contact *)contact
{
    if (contact.parsedPhoneNumbers.count < 1) {
        // Hide contacts without any valid phone numbers.
        return NO;
    }
    
    for (PhoneNumber *phoneNumber in contact.parsedPhoneNumbers) {
        if ([_blockedPhoneNumberSet containsObject:phoneNumber.toE164]) {
            return YES;
        }
    }
    
    return NO;
}

- (BOOL)isRecipientIdBlocked:(NSString *)recipientId
{
    OWSAssert(recipientId.length > 0);
    
    return [_blockedPhoneNumberSet containsObject:recipientId];
}

- (BOOL)isContactHidden:(Contact *)contact
{
    if (contact.parsedPhoneNumbers.count < 1) {
        // Hide contacts without any valid phone numbers.
        return YES;
    }

    return NO;
}

- (NSArray<Contact *> *_Nonnull)filteredContacts
{
    NSMutableArray<Contact *> *result = [NSMutableArray new];
    for (Contact *contact in self.contactsManager.signalContacts) {
        if (![self isContactHidden:contact]) {
            [result addObject:contact];
        }
    }
    return [result copy];
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
