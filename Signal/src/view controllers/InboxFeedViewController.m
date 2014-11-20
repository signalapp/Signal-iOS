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

static NSString* const INBOX_FEED_TABLE_VIEW_CELL_IDENTIFIER = @"InboxFeedTableViewCell";
static NSString* const CONTACT_TABLE_VIEW_CELL_IDENTIFIER = @"ContactTableViewCell";
static NSString* const FOOTER_TABLE_CELL_IDENTIFIER = @"InboxFeedFooterCell";

@interface InboxFeedViewController ()

@property (strong, nonatomic) NSArray* inboxFeed;
@property (nonatomic) BOOL tableViewContentMutating;
@property (nonatomic) BOOL isSearching;

@property (strong, nonatomic) NSArray* searchInboxFeed;
@property (strong, nonatomic) NSArray* searchRegisteredContacts;
@property (strong, nonatomic) NSArray* searchUnregisteredContacts;

@end

@implementation InboxFeedViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    [self observeRecentCalls];
    [self observeKeyboardNotifications];
    [self setupLabelLocalizationAndStyles];

    self.inboxFeedTableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self markMissedCallsAsViewed];
    [self.navigationController setNavigationBarHidden:NO animated:YES];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:YES animated:NO];
    [self.searchBarTitleView updateAutoCorrectionType];
    [self.inboxFeedTableView reloadData];
    
    if (!Environment.isRegistered) {
        [Environment resetAppData];
        [self presentViewController:[[RegisterViewController alloc] init] animated:NO completion:nil];
    }
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (void)observeRecentCalls {
    ObservableValue* observableContacts = Environment.getCurrent.contactsManager.getObservableContacts;

    [observableContacts watchLatestValue:^(id latestValue) {

        ObservableValue* observableRecents = Environment.getCurrent.recentCallManager.getObservableRecentCalls;
        
        [observableRecents watchLatestValue:^(NSArray* latestRecents) {
            self.inboxFeed = [Environment.getCurrent.recentCallManager recentsForSearchString:nil
                                                                           andExcludeArchived:YES];
            [self updateTutorialVisibility];
            if (!self.tableViewContentMutating) {
                [self.inboxFeedTableView reloadData];
            }
            if (self.isSearching) {
                [self.searchBarTitleView textField:self.searchBarTitleView.searchTextField
                 shouldChangeCharactersInRange:NSMakeRange(0, 0)
                             replacementString:SEARCH_BAR_DEFAULT_EMPTY_STRING];
            }
        } onThread:NSThread.mainThread untilCancelled:nil];

        
    } onThread:NSThread.mainThread untilCancelled:nil];
}

- (void)observeKeyboardNotifications {
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(keyboardWillShow:)
                                               name:UIKeyboardWillShowNotification
                                             object:nil];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(keyboardWillHide:)
                                               name:UIKeyboardWillHideNotification
                                             object:nil];
}

- (void)setupLabelLocalizationAndStyles {
    self.freshAppTutorialTopLabel.text = INBOX_VIEW_TUTORIAL_LABEL_TOP;
    self.freshAppTutorialMiddleLabel.text = INBOX_VIEW_TUTORIAL_LABEL_MIDDLE;
}

#pragma mark - Viewed / Unviewed calls

- (void)markMissedCallsAsViewed {
    BOOL needsSave = NO;

    for (RecentCall* recent in self.inboxFeed) {
        if (!recent.userNotified) {
            recent.userNotified = true;
            needsSave = true;
        }
    }
    if (needsSave) {
        [Environment.getCurrent.recentCallManager saveContactsToDefaults];
        [(TabBarParentViewController*)self.mm_drawerController.centerViewController updateMissedCallCountLabel];
        [self.inboxFeedTableView reloadData];
    }
}

#pragma mark - Actions

- (void)showRecentCallViewControllerWithRecentCall:(RecentCall*)recent {
    [(TabBarParentViewController*)self.mm_drawerController.centerViewController showDialerViewControllerWithNumber:recent.phoneNumber];
}

- (void)showContactViewControllerWithContact:(Contact*)contact {
    ContactDetailViewController* vc = [[ContactDetailViewController alloc] initWithContact:contact];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)removeNewsFeedCell:(InboxFeedTableViewCell*)cell willDelete:(BOOL)delete {
    self.tableViewContentMutating = YES;
    NSIndexPath* indexPath = [self.inboxFeedTableView indexPathForCell:cell];

    [self.inboxFeedTableView beginUpdates];

    RecentCall* recent;

    if (self.isSearching) {
        recent = self.searchInboxFeed[(NSUInteger)indexPath.row];
    } else {
        recent = self.inboxFeed[(NSUInteger)indexPath.row];
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

    [self.inboxFeedTableView deleteRowsAtIndexPaths:@[indexPath]
                               withRowAnimation:animation];

    [self.inboxFeedTableView endUpdates];
    self.tableViewContentMutating = NO;
}

- (void)updateTutorialVisibility {
    self.freshInboxView.hidden = !Environment.preferences.getFreshInstallTutorialsEnabled;
    self.inboxFeedTableView.hidden = !self.freshInboxView.hidden;
}

#pragma mark - UITableViewDelegate

- (NSInteger)numberOfSectionsInTableView:(UITableView*)tableView {
    if (self.isSearching) {
        return TABLE_VIEW_NUM_SECTIONS_SEARCHING;
    } else {
        return TABLE_VIEW_NUM_SECTIONS_DEFAULT;
    }
}

- (NSString*)tableView:(UITableView*)tableView titleForHeaderInSection:(NSInteger)section {
	if (section == SEARCH_TABLE_SECTION_FEED) {
		return @"";
	} else if (section == SEARCH_TABLE_SECTION_REGISTERED) {
		return TABLE_SECTION_TITLE_REGISTERED;
	} else {
		return TABLE_SECTION_TITLE_UNREGISTERED;
	}
}

- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section {
    if (self.isSearching) {
        if (section == SEARCH_TABLE_SECTION_FEED) {
            return (NSInteger)self.searchInboxFeed.count;
        } else if (section == SEARCH_TABLE_SECTION_REGISTERED) {
            return (NSInteger)self.searchRegisteredContacts.count;
        } else {
            return (NSInteger)self.searchUnregisteredContacts.count;
        }
    } else {
        NSInteger inboxFeedAndInfoCellCount = (NSInteger)self.inboxFeed.count + 1;
        return inboxFeedAndInfoCellCount;
    }
}

- (UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath {
    if (self.isSearching) {
        return [self searchCellForIndexPath:indexPath];
    } else {
        return [self inboxFeedCellForIndexPath:indexPath];
    }
}

- (void)tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self.searchBarTitleView.searchTextField resignFirstResponder];

    if (self.isSearching) {
        if (indexPath.section == SEARCH_TABLE_SECTION_FEED) {
            [self showRecentCallViewControllerWithRecentCall:self.searchInboxFeed[(NSUInteger)indexPath.row]];
        } else if (indexPath.section == SEARCH_TABLE_SECTION_REGISTERED) {
            [self showContactViewControllerWithContact:self.searchRegisteredContacts[(NSUInteger)indexPath.row]];
        } else {
            [self showContactViewControllerWithContact:self.searchUnregisteredContacts[(NSUInteger)indexPath.row]];
        }
    } else {
        if (indexPath.row < (NSInteger)self.inboxFeed.count) {
            [self showRecentCallViewControllerWithRecentCall:self.inboxFeed[(NSUInteger)indexPath.row]];
        }
    }
}

- (CGFloat)tableView:(UITableView*)tableView heightForRowAtIndexPath:(NSIndexPath*)indexPath {
    if (indexPath.section == SEARCH_TABLE_SECTION_FEED) {
        if ((NSUInteger)indexPath.row == self.inboxFeed.count) {
            return FOOTER_CELL_HEIGHT;
        } else {
            return INBOX_TABLE_VIEW_CELL_HEIGHT;
        }
    } else {
        return CONTACT_TABLE_VIEW_CELL_HEIGHT;
    }
}

#pragma mark - Table cell creation

- (UITableViewCell*)searchCellForIndexPath:(NSIndexPath*)indexPath {
    if (indexPath.section == SEARCH_TABLE_SECTION_FEED) {
        return [self inboxCellForIndexPath:indexPath andIsSearching:YES];
    } else {
        return [self contactCellForIndexPath:indexPath];
    }
}

- (UITableViewCell*)inboxFeedCellForIndexPath:(NSIndexPath*)indexPath {
    if (!self.isSearching && (NSUInteger)[indexPath row] == self.inboxFeed.count) {
        return [self inboxFeedFooterCell];
    } else {
        return [self inboxCellForIndexPath:indexPath andIsSearching:NO];
    }
}

- (UITableViewCell*)inboxCellForIndexPath:(NSIndexPath*)indexPath andIsSearching:(BOOL)isSearching {
    InboxFeedTableViewCell* cell = [self.inboxFeedTableView dequeueReusableCellWithIdentifier:INBOX_FEED_TABLE_VIEW_CELL_IDENTIFIER];

    if (!cell) {
        cell = [[InboxFeedTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                             reuseIdentifier:INBOX_FEED_TABLE_VIEW_CELL_IDENTIFIER];
        cell.delegate = self;
    }

    RecentCall* recent = isSearching ? self.searchInboxFeed[(NSUInteger)indexPath.row] : self.inboxFeed[(NSUInteger)indexPath.row];
    [cell configureWithRecentCall:recent];
    return cell;
}
- (UITableViewCell*)contactCellForIndexPath:(NSIndexPath*)indexPath {
    ContactTableViewCell* cell = [self.inboxFeedTableView dequeueReusableCellWithIdentifier:CONTACT_TABLE_VIEW_CELL_IDENTIFIER];

    if (!cell) {
        cell = [[ContactTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                           reuseIdentifier:CONTACT_TABLE_VIEW_CELL_IDENTIFIER];
    }

    NSUInteger searchIndex = (NSUInteger)indexPath.row;
    Contact* contact;

    if (indexPath.section == SEARCH_TABLE_SECTION_REGISTERED) {
        contact = self.searchRegisteredContacts[searchIndex];
    } else {
        contact = self.searchUnregisteredContacts[searchIndex];
    }

    [cell configureWithContact:contact];

    return cell;
}

- (UITableViewCell*)inboxFeedFooterCell {
    InboxFeedFooterCell* cell = [self.inboxFeedTableView dequeueReusableCellWithIdentifier:FOOTER_TABLE_CELL_IDENTIFIER];

    if (!cell) {
        cell = [[InboxFeedFooterCell alloc] initWithStyle:UITableViewCellStyleDefault
                                          reuseIdentifier:FOOTER_TABLE_CELL_IDENTIFIER];
    }

    return cell;
}

#pragma mark - HomeFeedTableViewCellDelegate

- (void)inboxFeedTableViewCellTappedDelete:(InboxFeedTableViewCell*)cell {
    [self removeNewsFeedCell:cell willDelete:YES];
}

- (void)inboxFeedTableViewCellTappedArchive:(InboxFeedTableViewCell*)cell {
    [self removeNewsFeedCell:cell willDelete:NO];
}

#pragma mark - SearchBarTitleViewDelegate

- (void)searchBarTitleView:(SearchBarTitleView*)view didSearchForTerm:(NSString*)term {
    BOOL searching = term.length > 0;
    self.isSearching = searching;

    if (searching) {
        self.freshInboxView.hidden = YES;
        self.inboxFeedTableView.hidden = NO;
        self.searchInboxFeed = [Environment.getCurrent.recentCallManager recentsForSearchString:term
                                                                             andExcludeArchived:YES];
        
        [self reloadSearchContactsForTerm:term];
    } else {
        [self updateTutorialVisibility];
        self.searchInboxFeed = nil;
        self.searchRegisteredContacts = nil;
    }
    [self.inboxFeedTableView reloadData];
}

- (void)searchBarTitleViewDidTapMenu:(SearchBarTitleView*)view {
    [self.mm_drawerController openDrawerSide:MMDrawerSideLeft
                                    animated:YES
                                  completion:nil];
}

- (void)searchBarTitleViewDidEndSearching:(SearchBarTitleView*)view {
    self.isSearching = false;
    [self updateTutorialVisibility];
    [self.inboxFeedTableView reloadData];
}

- (void)reloadSearchContactsForTerm:(NSString*)term {
	
    NSArray* contacts = [Environment.getCurrent.contactsManager latestContactsWithSearchString:term];

    NSMutableArray* registeredContacts = [[NSMutableArray alloc] init];
    NSMutableArray* unregisteredContacts = [[NSMutableArray alloc] init];

    for (Contact* contact in contacts) {
        BOOL registeredContact = NO;

        for (PhoneNumber* phoneNumber in contact.parsedPhoneNumbers) {
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

    self.searchRegisteredContacts = [registeredContacts copy];
    self.searchUnregisteredContacts = [unregisteredContacts copy];
}

#pragma mark - Keyboard

- (void)keyboardWillShow:(NSNotification*)notification {
    double duration = [[notification userInfo][UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    [UIView animateWithDuration:duration animations:^{
        CGSize keyboardSize = [[notification userInfo][UIKeyboardFrameBeginUserInfoKey] CGRectValue].size;
        CGFloat height = CGRectGetHeight(self.inboxFeedTableView.frame) - (keyboardSize.height-BOTTOM_TAB_BAR_HEIGHT);
        self.inboxFeedTableView.frame = CGRectMake(CGRectGetMinX(self.inboxFeedTableView.frame),
                                                   CGRectGetMinY(self.inboxFeedTableView.frame),
                                                   CGRectGetWidth(self.inboxFeedTableView.frame),
                                                   height);
    }];
}

- (void)keyboardWillHide:(NSNotification*)notification {
    CGSize keyboardSize = [[notification userInfo][UIKeyboardFrameEndUserInfoKey] CGRectValue].size;
    CGFloat height = CGRectGetHeight(self.inboxFeedTableView.frame) + (keyboardSize.height-BOTTOM_TAB_BAR_HEIGHT);
    self.inboxFeedTableView.frame = CGRectMake(CGRectGetMinX(self.inboxFeedTableView.frame),
                                               CGRectGetMinY(self.inboxFeedTableView.frame),
                                               CGRectGetWidth(self.inboxFeedTableView.frame),
                                               height);
    if (!self.searchInboxFeed) {
        [self updateTutorialVisibility];
    }
}
@end
