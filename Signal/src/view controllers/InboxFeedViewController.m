#import "ContactDetailViewController.h"
#import "ContactTableViewCell.h"
#import "Environment.h"
#import "InboxFeedFooterCell.h"
#import "InboxFeedViewController.h"
#import "LeftSideMenuViewController.h"
#import "LocalizableText.h"
#import "PropertyListPreferences+Util.h"
#import "RecentCall.h"
#import "RecentCallManager.h"
#import "RegisterViewController.h"

#import <UIViewController+MMDrawerController.h>

#define CONTACT_TABLE_VIEW_CELL_HEIGHT 44
#define FOOTER_CELL_HEIGHT 44
#define INBOX_TABLE_VIEW_CELL_HEIGHT 71

#define SEARCH_TABLE_SECTION_FEED 0
#define SEARCH_TABLE_SECTION_REGISTERED 1
#define SEARCH_TABLE_SECTION_UNREGISTERED 2

#define TABLE_VIEW_NUM_SECTIONS_DEFAULT 1
#define TABLE_VIEW_NUM_SECTIONS_SEARCHING 3

static NSString *const INBOX_FEED_TABLE_VIEW_CELL_IDENTIFIER = @"InboxFeedTableViewCell";
static NSString *const CONTACT_TABLE_VIEW_CELL_IDENTIFIER = @"ContactTableViewCell";
static NSString *const FOOTER_TABLE_CELL_IDENTIFIER = @"InboxFeedFooterCell";

@interface InboxFeedViewController () {
    NSArray *_inboxFeed;
    BOOL _tableViewContentMutating;
    BOOL _isSearching;

    NSArray *_searchInboxFeed;
    NSArray *_searchRegisteredContacts;
    NSArray *_searchUnregisteredContacts;
}

@end

@implementation InboxFeedViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    [self observeRecentCalls];
    [self observeKeyboardNotifications];
    [self setupLabelLocalizationAndStyles];

    _inboxFeedTableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self markMissedCallsAsViewed];
    [self.navigationController setNavigationBarHidden:NO animated:YES];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:YES animated:NO];
    [_searchBarTitleView updateAutoCorrectionType];
    [_inboxFeedTableView reloadData];
    
    if (!Environment.isRegistered) {
        [Environment resetAppData];
        RegisterViewController *registerViewController = [RegisterViewController registerViewController];
        [self presentViewController:registerViewController animated:NO completion:nil];
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (void)observeRecentCalls {
    ObservableValue *observableContacts = Environment.getCurrent.contactsManager.getObservableContacts;

    [observableContacts watchLatestValue:^(id latestValue) {

        ObservableValue *observableRecents = Environment.getCurrent.recentCallManager.getObservableRecentCalls;
        
        [observableRecents watchLatestValue:^(NSArray *latestRecents) {
            _inboxFeed = [Environment.getCurrent.recentCallManager recentsForSearchString:nil
                                                                           andExcludeArchived:YES];
            [self updateTutorialVisibility];
            if (!_tableViewContentMutating) {
                [_inboxFeedTableView reloadData];
            }
            if (_isSearching) {
                [_searchBarTitleView textField:_searchBarTitleView.searchTextField
                 shouldChangeCharactersInRange:NSMakeRange(0, 0)
                             replacementString:SEARCH_BAR_DEFAULT_EMPTY_STRING];
            }
        } onThread:NSThread.mainThread untilCancelled:nil];

        
    } onThread:NSThread.mainThread untilCancelled:nil];
}

- (void)observeKeyboardNotifications {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillShow:)
                                                 name:UIKeyboardWillShowNotification
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillHide:)
                                                 name:UIKeyboardWillHideNotification
                                               object:nil];
}

- (void)setupLabelLocalizationAndStyles {
    _freshAppTutorialTopLabel.text = INBOX_VIEW_TUTORIAL_LABEL_TOP;
    _freshAppTutorialMiddleLabel.text = INBOX_VIEW_TUTORIAL_LABEL_MIDDLE;
}

#pragma mark - Viewed / Unviewed calls

- (void)markMissedCallsAsViewed {
    BOOL needsSave = NO;

    for (RecentCall *recent in _inboxFeed) {
        if (!recent.userNotified) {
            recent.userNotified = true;
            needsSave = true;
        }
    }
    if (needsSave) {
        [Environment.getCurrent.recentCallManager saveContactsToDefaults];
        [(TabBarParentViewController *)self.mm_drawerController.centerViewController updateMissedCallCountLabel];
        [_inboxFeedTableView reloadData];
    }
}

#pragma mark - Actions

- (void)showRecentCallViewControllerWithRecentCall:(RecentCall *)recent {
    [(TabBarParentViewController *)self.mm_drawerController.centerViewController showDialerViewControllerWithNumber:recent.phoneNumber];
}

- (void)showContactViewControllerWithContact:(Contact *)contact {
    ContactDetailViewController *vc = [ContactDetailViewController contactDetailViewControllerWithContact:contact];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)removeNewsFeedCell:(InboxFeedTableViewCell *)cell willDelete:(BOOL)delete {
    _tableViewContentMutating = YES;
    NSIndexPath *indexPath = [_inboxFeedTableView indexPathForCell:cell];

    [_inboxFeedTableView beginUpdates];

    RecentCall *recent;

    if (_isSearching) {
        recent = _searchInboxFeed[(NSUInteger)indexPath.row];
    } else {
        recent = _inboxFeed[(NSUInteger)indexPath.row];
    }

    recent.userNotified = YES;

    UITableViewRowAnimation animation;

    if (delete) {
        animation = UITableViewRowAnimationLeft;
        [Environment.getCurrent.recentCallManager removeRecentCall:recent];
    } else {
        animation = UITableViewRowAnimationRight;
        [Environment.getCurrent.recentCallManager archiveRecentCall:recent];
    }

    [_inboxFeedTableView deleteRowsAtIndexPaths:@[indexPath]
                               withRowAnimation:animation];

    [_inboxFeedTableView endUpdates];
    _tableViewContentMutating = NO;
}

- (void)updateTutorialVisibility {
    _freshInboxView.hidden = !Environment.preferences.getFreshInstallTutorialsEnabled;
    _inboxFeedTableView.hidden = !_freshInboxView.hidden;
}

#pragma mark - UITableViewDelegate

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    if (_isSearching) {
        return TABLE_VIEW_NUM_SECTIONS_SEARCHING;
    } else {
        return TABLE_VIEW_NUM_SECTIONS_DEFAULT;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (section == SEARCH_TABLE_SECTION_FEED) {
		return @"";
	} else if (section == SEARCH_TABLE_SECTION_REGISTERED) {
		return TABLE_SECTION_TITLE_REGISTERED;
	} else {
		return TABLE_SECTION_TITLE_UNREGISTERED;
	}
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {

    if (_isSearching) {
        if (section == SEARCH_TABLE_SECTION_FEED) {
            return (NSInteger)_searchInboxFeed.count;
        } else if (section == SEARCH_TABLE_SECTION_REGISTERED) {
            return (NSInteger)_searchRegisteredContacts.count;
        } else {
            return (NSInteger)_searchUnregisteredContacts.count;
        }
    } else {
        NSInteger inboxFeedAndInfoCellCount = (NSInteger)_inboxFeed.count + 1;
        return inboxFeedAndInfoCellCount;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (_isSearching) {
        return [self searchCellForIndexPath:indexPath];
    } else {
        return [self inboxFeedCellForIndexPath:indexPath];
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [_searchBarTitleView.searchTextField resignFirstResponder];

    if (_isSearching) {
        if (indexPath.section == SEARCH_TABLE_SECTION_FEED) {
            [self showRecentCallViewControllerWithRecentCall:_searchInboxFeed[(NSUInteger)indexPath.row]];
        } else if (indexPath.section == SEARCH_TABLE_SECTION_REGISTERED) {
            [self showContactViewControllerWithContact:_searchRegisteredContacts[(NSUInteger)indexPath.row]];
        } else {
            [self showContactViewControllerWithContact:_searchUnregisteredContacts[(NSUInteger)indexPath.row]];
        }
    } else {
        if (indexPath.row < (NSInteger)_inboxFeed.count) {
            [self showRecentCallViewControllerWithRecentCall:_inboxFeed[(NSUInteger)indexPath.row]];
        }
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == SEARCH_TABLE_SECTION_FEED) {
        if ((NSUInteger)indexPath.row == _inboxFeed.count) {
            return FOOTER_CELL_HEIGHT;
        } else {
            return INBOX_TABLE_VIEW_CELL_HEIGHT;
        }
    } else {
        return CONTACT_TABLE_VIEW_CELL_HEIGHT;
    }
}

#pragma mark - Table cell creation

- (UITableViewCell *)searchCellForIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == SEARCH_TABLE_SECTION_FEED) {
        return [self inboxCellForIndexPath:indexPath andIsSearching:YES];
    } else {
        return [self contactCellForIndexPath:indexPath];
    }
}

- (UITableViewCell *)inboxFeedCellForIndexPath:(NSIndexPath *)indexPath {
    if (!_isSearching && (NSUInteger)[indexPath row] == _inboxFeed.count) {
        return [self inboxFeedFooterCell];
    } else {
        return [self inboxCellForIndexPath:indexPath andIsSearching:NO];
    }
}

- (UITableViewCell *)inboxCellForIndexPath:(NSIndexPath *)indexPath andIsSearching:(BOOL)isSearching {
    InboxFeedTableViewCell *cell = [_inboxFeedTableView dequeueReusableCellWithIdentifier:INBOX_FEED_TABLE_VIEW_CELL_IDENTIFIER];

    if (!cell) {
        cell = [[InboxFeedTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                             reuseIdentifier:INBOX_FEED_TABLE_VIEW_CELL_IDENTIFIER];
        cell.delegate = self;
    }

    RecentCall *recent = isSearching ? _searchInboxFeed[(NSUInteger)indexPath.row] : _inboxFeed[(NSUInteger)indexPath.row];
    [cell configureWithRecentCall:recent];
    return cell;
}

- (UITableViewCell *)contactCellForIndexPath:(NSIndexPath *)indexPath {
    ContactTableViewCell *cell = [_inboxFeedTableView dequeueReusableCellWithIdentifier:CONTACT_TABLE_VIEW_CELL_IDENTIFIER];

    if (!cell) {
        cell = [[ContactTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                           reuseIdentifier:CONTACT_TABLE_VIEW_CELL_IDENTIFIER];
    }

    NSUInteger searchIndex = (NSUInteger)indexPath.row;
    Contact *contact;

    if (indexPath.section == SEARCH_TABLE_SECTION_REGISTERED) {
        contact = _searchRegisteredContacts[searchIndex];
    } else {
        contact = _searchUnregisteredContacts[searchIndex];
    }

    [cell configureWithContact:contact];

    return cell;
}

- (UITableViewCell *)inboxFeedFooterCell {
    InboxFeedFooterCell *cell = [_inboxFeedTableView dequeueReusableCellWithIdentifier:FOOTER_TABLE_CELL_IDENTIFIER];

    if (!cell) {
        cell = [[InboxFeedFooterCell alloc] initWithStyle:UITableViewCellStyleDefault
                                          reuseIdentifier:FOOTER_TABLE_CELL_IDENTIFIER];
    }

    return cell;
}

#pragma mark - HomeFeedTableViewCellDelegate

- (void)inboxFeedTableViewCellTappedDelete:(InboxFeedTableViewCell *)cell {
    [self removeNewsFeedCell:cell willDelete:YES];
}

- (void)inboxFeedTableViewCellTappedArchive:(InboxFeedTableViewCell *)cell {
    [self removeNewsFeedCell:cell willDelete:NO];
}

#pragma mark - SearchBarTitleViewDelegate

- (void)searchBarTitleView:(SearchBarTitleView *)view didSearchForTerm:(NSString *)term {
    BOOL searching = term.length > 0;
    _isSearching = searching;

    if (searching) {
        _freshInboxView.hidden = YES;
        _inboxFeedTableView.hidden = NO;
        _searchInboxFeed = [Environment.getCurrent.recentCallManager recentsForSearchString:term
                                                                             andExcludeArchived:YES];
        
        [self reloadSearchContactsForTerm:term];
    } else {
        [self updateTutorialVisibility];
        _searchInboxFeed = nil;
        _searchRegisteredContacts = nil;
    }
    [_inboxFeedTableView reloadData];
}

- (void)searchBarTitleViewDidTapMenu:(SearchBarTitleView *)view {
    [self.mm_drawerController openDrawerSide:MMDrawerSideLeft
                                    animated:YES
                                  completion:nil];
}

- (void)searchBarTitleViewDidEndSearching:(SearchBarTitleView *)view {
    _isSearching = false;
    [self updateTutorialVisibility];
    [_inboxFeedTableView reloadData];
}

- (void)reloadSearchContactsForTerm:(NSString *)term {
	
    NSArray *contacts = [Environment.getCurrent.contactsManager latestContactsWithSearchString:term];

    NSMutableArray *registeredContacts = [NSMutableArray array];
    NSMutableArray *unregisteredContacts = [NSMutableArray array];

    for (Contact *contact in contacts) {
        BOOL registeredContact = NO;

        for (PhoneNumber *phoneNumber in contact.parsedPhoneNumbers) {
            if ([Environment.getCurrent.phoneDirectoryManager.getCurrentFilter containsPhoneNumber:phoneNumber]) {
                registeredContact = YES;
            }
        }

        if (registeredContact) {
            [registeredContacts addObject:contact];
        } else {
            [unregisteredContacts addObject:contact];
        }
    }

    _searchRegisteredContacts = registeredContacts.copy;
    _searchUnregisteredContacts = unregisteredContacts.copy;
}

#pragma mark - Keyboard

- (void)keyboardWillShow:(NSNotification *)notification {
    double duration = [[notification userInfo][UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    [UIView animateWithDuration:duration animations:^{
        CGSize keyboardSize = [[notification userInfo][UIKeyboardFrameBeginUserInfoKey] CGRectValue].size;
        CGFloat height = CGRectGetHeight(_inboxFeedTableView.frame) - (keyboardSize.height-BOTTOM_TAB_BAR_HEIGHT);
        _inboxFeedTableView.frame = CGRectMake(CGRectGetMinX(_inboxFeedTableView.frame),
                                               CGRectGetMinY(_inboxFeedTableView.frame),
                                               CGRectGetWidth(_inboxFeedTableView.frame),
                                               height);
    }];
}

- (void)keyboardWillHide:(NSNotification *)notification {
    CGSize keyboardSize = [[notification userInfo][UIKeyboardFrameEndUserInfoKey] CGRectValue].size;
    CGFloat height = CGRectGetHeight(_inboxFeedTableView.frame) + (keyboardSize.height-BOTTOM_TAB_BAR_HEIGHT);
    _inboxFeedTableView.frame = CGRectMake(CGRectGetMinX(_inboxFeedTableView.frame),
                                           CGRectGetMinY(_inboxFeedTableView.frame),
                                           CGRectGetWidth(_inboxFeedTableView.frame),
                                           height);
    if (!_searchInboxFeed) {
        [self updateTutorialVisibility];
    }
}
@end
