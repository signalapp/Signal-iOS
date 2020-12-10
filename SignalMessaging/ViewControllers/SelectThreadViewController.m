//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "SelectThreadViewController.h"
#import "BlockListUIUtils.h"
#import "ContactTableViewCell.h"
#import "ContactsViewHelper.h"
#import "Environment.h"
#import "OWSContactsManager.h"
#import "OWSSearchBar.h"
#import "OWSTableViewController.h"
#import "ThreadViewHelper.h"
#import "UIFont+OWS.h"
#import "UIView+OWS.h"
#import <SignalCoreKit/NSString+OWS.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/PhoneNumber.h>
#import <SignalServiceKit/SignalAccount.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSAccountManager.h>
#import <SignalServiceKit/TSContactThread.h>
#import <SignalServiceKit/TSThread.h>

NS_ASSUME_NONNULL_BEGIN

@interface SelectThreadViewController () <OWSTableViewControllerDelegate,
    ThreadViewHelperDelegate,
    ContactsViewHelperObserver,
    UISearchBarDelegate,
    FindByPhoneNumberDelegate,
    UIDatabaseSnapshotDelegate>

@property (nonatomic, readonly) FullTextSearcher *fullTextSearcher;
@property (nonatomic, readonly) ThreadViewHelper *threadViewHelper;

@property (nonatomic, readonly) OWSTableViewController *tableViewController;

@property (nonatomic, readonly) UISearchBar *searchBar;

@end

#pragma mark -

@implementation SelectThreadViewController

#pragma mark - Dependencies

- (SDSDatabaseStorage *)databaseStorage
{
    return SDSDatabaseStorage.shared;
}

- (ContactsViewHelper *)contactsViewHelper
{
    return Environment.shared.contactsViewHelper;
}

#pragma mark -

- (void)loadView
{
    [super loadView];

    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemStop
                                                      target:self
                                                      action:@selector(dismissPressed:)];

    self.view.backgroundColor = Theme.backgroundColor;

    [self.contactsViewHelper addObserver:self];
    _fullTextSearcher = FullTextSearcher.shared;
    _threadViewHelper = [ThreadViewHelper new];
    _threadViewHelper.delegate = self;

    [self.databaseStorage appendUIDatabaseSnapshotDelegate:self];

    [self createViews];

    [self updateTableContents];
}

- (void)createViews
{
    OWSAssertDebug(self.selectThreadViewDelegate);

    // Search
    UISearchBar *searchBar = [OWSSearchBar new];
    _searchBar = searchBar;
    searchBar.delegate = self;
    searchBar.placeholder = NSLocalizedString(@"SEARCH_BYNAMEORNUMBER_PLACEHOLDER_TEXT", @"");
    [searchBar sizeToFit];

    UIView *header = [self.selectThreadViewDelegate createHeaderWithSearchBar:searchBar];
    if (!header) {
        header = searchBar;
    }
    [self.view addSubview:header];
    [header autoPinWidthToSuperview];
    [header autoPinToTopLayoutGuideOfViewController:self withInset:0];
    [header setCompressionResistanceVerticalHigh];
    [header setContentHuggingVerticalHigh];

    // Table
    _tableViewController = [OWSTableViewController new];
    _tableViewController.delegate = self;
    _tableViewController.customSectionHeaderFooterBackgroundColor = Theme.backgroundColor;
    [self.view addSubview:self.tableViewController.view];
    [self.tableViewController.view autoPinEdgeToSuperviewSafeArea:ALEdgeLeading];
    [self.tableViewController.view autoPinEdgeToSuperviewSafeArea:ALEdgeTrailing];
    [_tableViewController.view autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:header];
    [_tableViewController.view autoPinEdgeToSuperviewEdge:ALEdgeBottom];
    self.tableViewController.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableViewController.tableView.estimatedRowHeight = 60;
}

#pragma mark - UIDatabaseSnapshotDelegate

- (void)uiDatabaseSnapshotWillUpdate
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(AppReadiness.isAppReady);
}

- (void)uiDatabaseSnapshotDidUpdateWithDatabaseChanges:(id<UIDatabaseChanges>)databaseChanges
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(AppReadiness.isAppReady);

    if (![databaseChanges didUpdateModelWithCollection:TSThread.collection]) {
        return;
    }

    [self updateTableContents];
}

- (void)uiDatabaseSnapshotDidUpdateExternally
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(AppReadiness.isAppReady);

    [self updateTableContents];
}

- (void)uiDatabaseSnapshotDidReset
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(AppReadiness.isAppReady);

    [self updateTableContents];
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

    OWSTableSection *findByPhoneSection = [OWSTableSection new];
    [findByPhoneSection
        addItem:[OWSTableItem disclosureItemWithText:NSLocalizedString(@"NEW_CONVERSATION_FIND_BY_PHONE_NUMBER",
                                                         @"A label the cell that lets you add a new member to a group.")
                                     customRowHeight:UITableViewAutomaticDimension
                                         actionBlock:^{
                                             FindByPhoneNumberViewController *viewController =
                                                 [[FindByPhoneNumberViewController alloc] initWithDelegate:weakSelf
                                                                                                buttonText:nil
                                                                                  requiresRegisteredNumber:YES];
                                             [weakSelf.navigationController pushViewController:viewController
                                                                                      animated:YES];
                                         }]];
    [contents addSection:findByPhoneSection];

    // Existing threads are listed first, ordered by most recently active
    OWSTableSection *recentChatsSection = [OWSTableSection new];
    recentChatsSection.headerTitle = NSLocalizedString(
        @"SELECT_THREAD_TABLE_RECENT_CHATS_TITLE", @"Table section header for recently active conversations");

    __block NSArray<TSThread *> *filteredThreads;
    [self.databaseStorage uiReadWithBlock:^(SDSAnyReadTransaction *transaction) {
        filteredThreads = [self filteredThreadsWithTransaction:transaction];
    }];

    for (TSThread *thread in filteredThreads) {
        [recentChatsSection
            addItem:[OWSTableItem
                        itemWithCustomCellBlock:^{
                            SelectThreadViewController *strongSelf = weakSelf;
                            OWSCAssertDebug(strongSelf);

                            // To be consistent with the threads (above), we use ContactTableViewCell
                            // instead of ConversationListCell to present contacts and threads.
                            ContactTableViewCell *cell = [ContactTableViewCell new];

                            BOOL isBlocked = [helper isThreadBlocked:thread];
                            if (isBlocked) {
                                cell.accessoryMessage = MessageStrings.conversationIsBlocked;
                            }

                            [strongSelf.databaseStorage uiReadWithBlock:^(SDSAnyReadTransaction *transaction) {
                                [cell configureWithThread:thread transaction:transaction];

                                if (!cell.hasAccessoryText) {
                                    // Don't add a disappearing messages indicator if we've already added a "blocked"
                                    // label.
                                    __block OWSDisappearingMessagesConfiguration *disappearingMessagesConfiguration;

                                    disappearingMessagesConfiguration =
                                        [thread disappearingMessagesConfigurationWithTransaction:transaction];

                                    if (disappearingMessagesConfiguration
                                        && disappearingMessagesConfiguration.isEnabled) {
                                        DisappearingTimerConfigurationView *disappearingTimerConfigurationView =
                                            [[DisappearingTimerConfigurationView alloc]
                                                initWithDurationSeconds:disappearingMessagesConfiguration
                                                                            .durationSeconds];

                                        disappearingTimerConfigurationView.tintColor = Theme.middleGrayColor;
                                        [disappearingTimerConfigurationView autoSetDimensionsToSize:CGSizeMake(44, 44)];

                                        [cell ows_setAccessoryView:disappearingTimerConfigurationView];
                                    }
                                }
                            }];

                            return cell;
                        }
                        actionBlock:^{
                            typeof(self) strongSelf = weakSelf;
                            if (!strongSelf) {
                                return;
                            }

                            BOOL isBlocked = [helper isThreadBlocked:thread];
                            if (isBlocked && ![strongSelf.selectThreadViewDelegate canSelectBlockedContact]) {
                                [BlockListUIUtils
                                    showUnblockThreadActionSheet:thread
                                              fromViewController:strongSelf
                                                 completionBlock:^(BOOL isStillBlocked) {
                                                     if (!isStillBlocked) {
                                                         [strongSelf.selectThreadViewDelegate threadWasSelected:thread];
                                                     }
                                                 }];
                                return;
                            }

                            [strongSelf.selectThreadViewDelegate threadWasSelected:thread];
                        }]];
    }

    if (recentChatsSection.itemCount > 0) {
        [contents addSection:recentChatsSection];
    }

    // Contacts who don't yet have a thread are listed last
    OWSTableSection *otherContactsSection = [OWSTableSection new];
    otherContactsSection.headerTitle = NSLocalizedString(
        @"SELECT_THREAD_TABLE_OTHER_CHATS_TITLE", @"Table section header for conversations you haven't recently used.");
    __block NSArray<SignalAccount *> *filteredSignalAccounts;
    [self.databaseStorage uiReadWithBlock:^(SDSAnyReadTransaction *transaction) {
        filteredSignalAccounts = [self filteredSignalAccountsWithTransaction:transaction];
    }];

    for (SignalAccount *signalAccount in filteredSignalAccounts) {
        [otherContactsSection
            addItem:[OWSTableItem
                        itemWithCustomCellBlock:^{
                            ContactTableViewCell *cell = [ContactTableViewCell new];
                            BOOL isBlocked = [helper isSignalServiceAddressBlocked:signalAccount.recipientAddress];
                            if (isBlocked) {
                                cell.accessoryMessage = MessageStrings.conversationIsBlocked;
                            }
                            [cell configureWithRecipientAddressWithSneakyTransaction:signalAccount.recipientAddress];
                            return cell;
                        }
                        actionBlock:^{
                            [weakSelf signalAccountWasSelected:signalAccount];
                        }]];
    }

    if (otherContactsSection.itemCount > 0) {
        [contents addSection:otherContactsSection];
    }

    if (recentChatsSection.itemCount + otherContactsSection.itemCount < 1) {
        OWSTableSection *emptySection = [OWSTableSection new];
        [emptySection
            addItem:[OWSTableItem
                        softCenterLabelItemWithText:NSLocalizedString(@"SETTINGS_BLOCK_LIST_NO_CONTACTS",
                                                        @"A label that indicates the user has no Signal contacts.")]];
        [contents addSection:emptySection];
    }

    self.tableViewController.contents = contents;
}

- (void)signalAccountWasSelected:(SignalAccount *)signalAccount
{
    OWSAssertDebug(signalAccount);
    OWSAssertDebug(self.selectThreadViewDelegate);

    ContactsViewHelper *helper = self.contactsViewHelper;

    if ([helper isSignalServiceAddressBlocked:signalAccount.recipientAddress]
        && ![self.selectThreadViewDelegate canSelectBlockedContact]) {

        __weak SelectThreadViewController *weakSelf = self;
        [BlockListUIUtils showUnblockSignalAccountActionSheet:signalAccount
                                           fromViewController:self
                                              completionBlock:^(BOOL isBlocked) {
                                                  if (!isBlocked) {
                                                      [weakSelf signalAccountWasSelected:signalAccount];
                                                  }
                                              }];
        return;
    }

    __block TSThread *thread = nil;
    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        thread = [TSContactThread getOrCreateThreadWithContactAddress:signalAccount.recipientAddress
                                                          transaction:transaction];
    });
    OWSAssertDebug(thread);

    [self.selectThreadViewDelegate threadWasSelected:thread];
}

#pragma mark - Filter

- (NSArray<TSThread *> *)filteredThreadsWithTransaction:(SDSAnyReadTransaction *)transaction
{
    NSString *searchTerm = [[self.searchBar text] ows_stripped];

    NSArray<TSThread *> *unfilteredThreads = [self.fullTextSearcher filterThreads:self.threadViewHelper.threads
                                                                   withSearchText:searchTerm
                                                                      transaction:transaction];
    NSMutableArray<TSThread *> *threads = [NSMutableArray new];
    for (TSThread *thread in unfilteredThreads) {
        if (thread.canSendToThread) {
            [threads addObject:thread];
        }
    }

    NSArray<NSString *> *pinnedThreadIds = PinnedThreadManager.pinnedThreadIds;

    return [threads sortedArrayUsingComparator:^NSComparisonResult(TSThread *lhs, TSThread *rhs) {
        NSUInteger lhsIndex = [pinnedThreadIds indexOfObject:lhs.uniqueId];
        NSUInteger rhsIndex = [pinnedThreadIds indexOfObject:rhs.uniqueId];

        // Sort pinned threads to the top.
        if (lhsIndex != NSNotFound && rhsIndex != NSNotFound) {
            if (lhsIndex > rhsIndex) {
                return NSOrderedDescending;
            } else if (lhsIndex < rhsIndex) {
                return NSOrderedAscending;
            } else {
                return NSOrderedSame;
            }
        } else if (lhsIndex != NSNotFound) {
            return NSOrderedAscending;
        } else if (rhsIndex != NSNotFound) {
            return NSOrderedDescending;
        }

        // Don't re-order non-pinned threads.
        return NSOrderedSame;
    }];
}

- (NSArray<SignalAccount *> *)filteredSignalAccountsWithTransaction:(SDSAnyReadTransaction *)transaction
{
    // We don't want to show a 1:1 thread with Alice and Alice's contact,
    // so we de-duplicate by recipientId.
    NSArray<TSThread *> *threads = self.threadViewHelper.threads;
    NSMutableSet<SignalServiceAddress *> *contactAddressesToIgnore = [NSMutableSet new];
    for (TSThread *thread in threads) {
        if ([thread isKindOfClass:[TSContactThread class]]) {
            TSContactThread *contactThread = (TSContactThread *)thread;
            [contactAddressesToIgnore addObject:contactThread.contactAddress];
        }
    }

    NSString *searchString = self.searchBar.text;
    NSArray<SignalAccount *> *matchingAccounts =
        [self.contactsViewHelper signalAccountsMatchingSearchString:searchString transaction:transaction];

    return [matchingAccounts
        filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(SignalAccount *signalAccount,
                                        NSDictionary<NSString *, id> *_Nullable bindings) {
            return ![contactAddressesToIgnore containsObject:signalAccount.recipientAddress];
        }]];
}

#pragma mark - Events

- (void)dismissPressed:(id)sender
{
    [self.searchBar resignFirstResponder];
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - OWSTableViewControllerDelegate

- (void)tableViewWillBeginDragging
{
    [self.searchBar resignFirstResponder];
}

#pragma mark - ThreadViewHelperDelegate

- (void)threadListDidChange
{
    [self updateTableContents];
}

#pragma mark - ContactsViewHelperObserver

- (void)contactsViewHelperDidUpdateContacts
{
    [self updateTableContents];
}

#pragma mark - FindByPhoneNumberDelegate

- (void)findByPhoneNumber:(FindByPhoneNumberViewController *)findByPhoneNumber
         didSelectAddress:(SignalServiceAddress *)address
{
    SignalAccount *signalAccount = [self.contactsViewHelper fetchOrBuildSignalAccountForAddress:address];
    [self signalAccountWasSelected:signalAccount];
}

@end

NS_ASSUME_NONNULL_END
