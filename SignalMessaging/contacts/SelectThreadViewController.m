//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "SelectThreadViewController.h"
#import "BlockListUIUtils.h"
#import "ContactTableViewCell.h"
#import "ContactsViewHelper.h"
#import "Environment.h"
#import "NSString+OWS.h"
#import "NewNonContactConversationViewController.h"
#import "OWSContactsManager.h"
#import "OWSTableViewController.h"
#import "ThreadViewHelper.h"
#import "UIColor+OWS.h"
#import "UIFont+OWS.h"
#import "UIView+OWS.h"
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/PhoneNumber.h>
#import <SignalServiceKit/SignalAccount.h>
#import <SignalServiceKit/TSAccountManager.h>
#import <SignalServiceKit/TSContactThread.h>
#import <SignalServiceKit/TSThread.h>
#import <YapDatabase/YapDatabase.h>

NS_ASSUME_NONNULL_BEGIN

@interface SelectThreadViewController () <OWSTableViewControllerDelegate,
    ThreadViewHelperDelegate,
    ContactsViewHelperDelegate,
    UISearchBarDelegate,
    NewNonContactConversationViewControllerDelegate>

@property (nonatomic, readonly) ContactsViewHelper *contactsViewHelper;
@property (nonatomic, readonly) ConversationSearcher *conversationSearcher;
@property (nonatomic, readonly) ThreadViewHelper *threadViewHelper;
@property (nonatomic, readonly) YapDatabaseConnection *uiDatabaseConnection;

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
    _conversationSearcher = ConversationSearcher.shared;
    _threadViewHelper = [ThreadViewHelper new];
    _threadViewHelper.delegate = self;

    _uiDatabaseConnection = [[OWSPrimaryStorage sharedManager] newDatabaseConnection];
#ifdef DEBUG
    _uiDatabaseConnection.permittedTransactions = YDB_AnyReadTransaction;
#endif
    [_uiDatabaseConnection beginLongLivedReadTransaction];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(yapDatabaseModified:)
                                                 name:YapDatabaseModifiedNotification
                                               object:OWSPrimaryStorage.sharedManager.dbNotificationObject];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(yapDatabaseModifiedExternally:)
                                                 name:YapDatabaseModifiedExternallyNotification
                                               object:nil];

    [self createViews];

    [self updateTableContents];
}

- (void)createViews
{
    OWSAssert(self.selectThreadViewDelegate);

    // Search
    UISearchBar *searchBar = [UISearchBar new];
    _searchBar = searchBar;
    searchBar.searchBarStyle = UISearchBarStyleMinimal;
    searchBar.delegate = self;
    searchBar.placeholder = NSLocalizedString(@"SEARCH_BYNAMEORNUMBER_PLACEHOLDER_TEXT", @"");
    searchBar.backgroundColor = [UIColor whiteColor];
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
    [self.view addSubview:self.tableViewController.view];
    [_tableViewController.view autoPinWidthToSuperview];
    [_tableViewController.view autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:header];
    [_tableViewController.view autoPinEdgeToSuperviewEdge:ALEdgeBottom];
}

- (void)yapDatabaseModifiedExternally:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();
    
    DDLogVerbose(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);
    
    [self.uiDatabaseConnection beginLongLivedReadTransaction];
    [self updateTableContents];
}

- (void)yapDatabaseModified:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();
    
    [self.uiDatabaseConnection beginLongLivedReadTransaction];
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
                                     customRowHeight:[ContactTableViewCell rowHeight]
                                         actionBlock:^{
                                             NewNonContactConversationViewController *viewController =
                                                 [NewNonContactConversationViewController new];
                                             viewController.nonContactConversationDelegate = weakSelf;
                                             viewController.isPresentedInNavigationController = YES;
                                             [weakSelf.navigationController pushViewController:viewController
                                                                                      animated:YES];
                                         }]];
    [contents addSection:findByPhoneSection];

    // Existing threads are listed first, ordered by most recently active
    OWSTableSection *recentChatsSection = [OWSTableSection new];
    recentChatsSection.headerTitle = NSLocalizedString(
        @"SELECT_THREAD_TABLE_RECENT_CHATS_TITLE", @"Table section header for recently active conversations");
    for (TSThread *thread in [self filteredThreadsWithSearchText]) {
        [recentChatsSection addItem:[OWSTableItem itemWithCustomCellBlock:^{
            SelectThreadViewController *strongSelf = weakSelf;
            OWSCAssert(strongSelf);

            // To be consistent with the threads (above), we use ContactTableViewCell
            // instead of HomeViewCell to present contacts and threads.
            ContactTableViewCell *cell = [ContactTableViewCell new];
            
            if ([thread isKindOfClass:[TSContactThread class]]) {
                BOOL isBlocked = [helper isRecipientIdBlocked:thread.contactIdentifier];
                if (isBlocked) {
                    cell.accessoryMessage = NSLocalizedString(@"CONTACT_CELL_IS_BLOCKED", @"An indicator that a contact has been blocked.");
                }
            }
            
            [cell configureWithThread:thread contactsManager:helper.contactsManager];

            if (cell.accessoryView == nil) {
                // Don't add a disappearing messages indicator if we've already added a "blocked" label.
                __block OWSDisappearingMessagesConfiguration *disappearingMessagesConfiguration;
                [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
                    disappearingMessagesConfiguration =
                        [OWSDisappearingMessagesConfiguration fetchObjectWithUniqueID:thread.uniqueId
                                                                          transaction:transaction];
                }];

                if (disappearingMessagesConfiguration && disappearingMessagesConfiguration.isEnabled) {
                    DisappearingTimerConfigurationView *disappearingTimerConfigurationView =
                        [[DisappearingTimerConfigurationView alloc]
                            initWithDurationSeconds:disappearingMessagesConfiguration.durationSeconds];

                    disappearingTimerConfigurationView.frame = CGRectMake(0, 0, 44, 44);
                    disappearingTimerConfigurationView.tintColor = [UIColor colorWithWhite:0.5f alpha:1.f];

                    cell.accessoryView = disappearingTimerConfigurationView;
                }
            }

            return cell;
        }
                                        customRowHeight:[ContactTableViewCell rowHeight]
                                        actionBlock:^{
                                            typeof(self) strongSelf = weakSelf;
                                            if (!strongSelf) {
                                                return;
                                            }

                                            if ([thread isKindOfClass:[TSContactThread class]]) {
                                                BOOL isBlocked = [helper isRecipientIdBlocked:thread.contactIdentifier];
                                                if (isBlocked
                                                    && ![strongSelf.selectThreadViewDelegate canSelectBlockedContact]) {
                                                    [BlockListUIUtils
                                                        showUnblockPhoneNumberActionSheet:thread.contactIdentifier
                                                                       fromViewController:strongSelf
                                                                          blockingManager:helper.blockingManager
                                                                          contactsManager:helper.contactsManager
                                                                          completionBlock:^(BOOL isStillBlocked) {
                                                                              if (!isStillBlocked) {
                                                                                  [strongSelf.selectThreadViewDelegate
                                                                                      threadWasSelected:thread];
                                                                              }
                                                                          }];
                                                    return;
                                                }
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
    NSArray<SignalAccount *> *filteredSignalAccounts = [self filteredSignalAccountsWithSearchText];
    for (SignalAccount *signalAccount in filteredSignalAccounts) {
        [otherContactsSection addItem:[OWSTableItem itemWithCustomCellBlock:^{
            SelectThreadViewController *strongSelf = weakSelf;
            OWSCAssert(strongSelf);

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
    OWSAssert(signalAccount);
    OWSAssert(self.selectThreadViewDelegate);

    ContactsViewHelper *helper = self.contactsViewHelper;

    if ([helper isRecipientIdBlocked:signalAccount.recipientId]
        && ![self.selectThreadViewDelegate canSelectBlockedContact]) {

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
    [OWSPrimaryStorage.dbReadWriteConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        thread = [TSContactThread getOrCreateThreadWithContactId:signalAccount.recipientId transaction:transaction];
    }];
    OWSAssert(thread);

    [self.selectThreadViewDelegate threadWasSelected:thread];
}

#pragma mark - Filter

- (NSArray<TSThread *> *)filteredThreadsWithSearchText
{
    NSString *searchTerm = [[self.searchBar text] ows_stripped];

    return [self.conversationSearcher filterThreads:self.threadViewHelper.threads withSearchText:searchTerm];
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

    NSString *searchString = self.searchBar.text;
    NSArray<SignalAccount *> *matchingAccounts =
        [self.contactsViewHelper signalAccountsMatchingSearchString:searchString];

    return [matchingAccounts
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

- (void)tableViewWillBeginDragging
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

#pragma mark - NewNonContactConversationViewControllerDelegate

- (void)recipientIdWasSelected:(NSString *)recipientId
{
    SignalAccount *_Nullable signalAccount = [self.contactsViewHelper signalAccountForRecipientId:recipientId];
    if (!signalAccount) {
        signalAccount = [[SignalAccount alloc] initWithRecipientId:recipientId];
    }
    [self signalAccountWasSelected:signalAccount];
}

@end

NS_ASSUME_NONNULL_END
