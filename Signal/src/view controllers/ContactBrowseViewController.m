#import "Contact.h"
#import "ContactBrowseViewController.h"
#import "ContactDetailViewController.h"
#import "ContactsManager.h"
#import "ContactTableViewCell.h"
#import "InCallViewController.h"
#import "LocalizableText.h"
#import "PropertyListPreferences+Util.h"
#import "TabBarParentViewController.h"
#import "NotificationManifest.h"
#import "PhoneNumberDirectoryFilterManager.h"

#import <AddressBook/AddressBook.h>
#import <UIViewController+MMDrawerController.h>

#define NOTIFICATION_VIEW_ANIMATION_DURATION 0.5f
#define REFRESH_TIMEOUT 20

static NSString* const CONTACT_BROWSE_TABLE_CELL_IDENTIFIER = @"ContactTableViewCell";

@interface ContactBrowseViewController ()

@property (strong, nonatomic) NSDictionary* latestAlphabeticalContacts;
@property (strong, nonatomic) NSArray* latestSortedAlphabeticalContactKeys;
@property (strong, nonatomic) NSArray* latestContacts;
@property (strong, nonatomic) NSArray* arrayOfNewWhisperUsers;
@property (nonatomic) CGRect originalTableViewFrame;
@property (nonatomic) BOOL showingNotificationView;

@end

@implementation ContactBrowseViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(contactsDidRefresh)
                                                 name:NOTIFICATION_DIRECTORY_WAS_UPDATED
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(contactRefreshFailed)
                                                 name:NOTIFICATION_DIRECTORY_FAILED
                                               object:nil];

    self.refreshControl = [[UIRefreshControl alloc] init];
    [self.refreshControl addTarget:self action:@selector(refreshContacts) forControlEvents:UIControlEventValueChanged];
    [self.contactTableView addSubview:self.refreshControl];
    
    [self setupContacts];
    [self observeKeyboardNotifications];
    self.originalTableViewFrame = self.contactTableView.frame;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:YES animated:NO];
    [self.contactTableView reloadData];
    [self.searchBarTitleView updateAutoCorrectionType];
    [Environment.getCurrent.contactsManager enableNewUserNotifications];
    
    BOOL showNotificationView = self.arrayOfNewWhisperUsers != nil;
    if (showNotificationView) {
        [self showNotificationViewAnimated:NO];
    } else {
        [self hideNotificationView];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    self.navigationController.navigationBarHidden = NO;
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)onSearchOrContactChange:(NSString*)searchTerm {
    if (self.latestContacts) {
        self.latestAlphabeticalContacts = [ContactsManager groupContactsByFirstLetter:self.latestContacts
                                                                 matchingSearchString:searchTerm];
        
        NSArray* contactKeys = [self.latestAlphabeticalContacts allKeys];
        self.latestSortedAlphabeticalContactKeys = [contactKeys sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
        [self.contactTableView reloadData];
    }
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

- (void)notificationViewTapped:(id)sender {
    [(TabBarParentViewController*)self.mm_drawerController.centerViewController presentInviteContactsViewController];
}

- (void)showNotificationForNewWhisperUsers:(NSArray*)users {
    
    self.arrayOfNewWhisperUsers = users;

    BOOL isViewVisible = self.isViewLoaded && self.view.window;
    
    if (isViewVisible) {
        [self showNotificationViewAnimated:YES];
    }
}

- (void)showNotificationViewAnimated:(BOOL)animated {
    
    if (self.showingNotificationView) {
        return;
    }
    
    CGFloat animationTime = animated ? NOTIFICATION_VIEW_ANIMATION_DURATION : 0.0f;
    
    [UIView animateWithDuration:animationTime animations:^{
        self.notificationView.frame = CGRectMake(CGRectGetMinX(self.notificationView.frame),
                                                 CGRectGetHeight(self.searchBarTitleView.frame),
                                                 CGRectGetWidth(self.notificationView.frame),
                                                 CGRectGetHeight(self.notificationView.frame));
    
        CGFloat tableViewYOrigin = CGRectGetMinY(self.originalTableViewFrame) + CGRectGetHeight(self.notificationView.frame);
        self.contactTableView.frame = CGRectMake(CGRectGetMinX(self.contactTableView.frame),
                                                 tableViewYOrigin,
                                                 CGRectGetWidth(self.contactTableView.frame),
                                                 CGRectGetHeight(self.contactTableView.frame));
        
    }];
    
    self.showingNotificationView = YES;
}

- (void)hideNotificationView {
    if (!self.showingNotificationView) {
        return;
    }
    
    self.notificationView.frame = CGRectMake(CGRectGetMinX(self.notificationView.frame),
                                             0,
                                             CGRectGetWidth(self.notificationView.frame),
                                             CGRectGetHeight(self.notificationView.frame));
    self.contactTableView.frame = self.originalTableViewFrame;
    self.showingNotificationView = NO;
}

#pragma mark - Contact functions

- (void)setupContacts {
    ObservableValue* observableContacts = Environment.getCurrent.contactsManager.getObservableWhisperUsers;

    [observableContacts watchLatestValue:^(NSArray* latestContacts) {
        self.latestContacts = latestContacts;
        [self onSearchOrContactChange:nil];
    } onThread:[NSThread mainThread] untilCancelled:nil];
}

- (NSArray*)contactsForSectionIndex:(NSUInteger)index {
    return [self.latestAlphabeticalContacts valueForKey:self.latestSortedAlphabeticalContactKeys[index]];
}

- (void)pushContactViewControllerForContactIndexPath:(NSIndexPath*)indexPath {
    NSArray* contactSection = [self contactsForSectionIndex:(NSUInteger)indexPath.section];
    Contact* contact = contactSection[(NSUInteger)indexPath.row];
    ContactDetailViewController* vc = [[ContactDetailViewController alloc] initWithContact:contact];
    [self.navigationController pushViewController:vc animated:YES];
}

#pragma mark - UITableViewDelegate

- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)[[self contactsForSectionIndex:(NSUInteger)section] count];
}

- (NSString*)tableView:(UITableView*)tableView titleForHeaderInSection:(NSInteger)section {
    return self.latestSortedAlphabeticalContactKeys[(NSUInteger)section];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView*)tableView {
    return (NSInteger)[[self.latestAlphabeticalContacts allKeys] count];
}

- (UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath {
	
    ContactTableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:CONTACT_BROWSE_TABLE_CELL_IDENTIFIER];

    if (!cell) {
        cell = [[ContactTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                           reuseIdentifier:CONTACT_BROWSE_TABLE_CELL_IDENTIFIER];
    }

    NSArray* contactSection = [self contactsForSectionIndex:(NSUInteger)indexPath.section];
    Contact* contact = contactSection[(NSUInteger)indexPath.row];
    [cell configureWithContact:contact];

    return cell;
}

- (void)tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)indexPath {
    [self.searchBarTitleView.searchTextField resignFirstResponder];
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self pushContactViewControllerForContactIndexPath:indexPath];
}

- (NSArray*)sectionIndexTitlesForTableView:(UITableView*)tableView {
    return self.latestSortedAlphabeticalContactKeys;
}

#pragma mark - SearchBarTitleViewDelegate

- (void)searchBarTitleView:(SearchBarTitleView*)view didSearchForTerm:(NSString*)term {
    [self onSearchOrContactChange:term];
}

- (void)searchBarTitleViewDidTapMenu:(SearchBarTitleView*)view {
    [self.mm_drawerController openDrawerSide:MMDrawerSideLeft
                                    animated:YES
                                  completion:nil];
}

- (void)searchBarTitleViewDidEndSearching:(SearchBarTitleView*)view {
    [self onSearchOrContactChange:nil];
}

#pragma mark - Keyboard

- (void)keyboardWillShow:(NSNotification*)notification {
    double duration = [[notification userInfo][UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    [UIView animateWithDuration:duration animations:^{
        CGSize keyboardSize = [[notification userInfo][UIKeyboardFrameBeginUserInfoKey] CGRectValue].size;
        self.contactTableView.frame = CGRectMake(CGRectGetMinX(self.contactTableView.frame),
                                                 CGRectGetMinY(self.contactTableView.frame),
                                                 CGRectGetWidth(self.contactTableView.frame),
                                                 CGRectGetHeight(self.contactTableView.frame) - (keyboardSize.height-BOTTOM_TAB_BAR_HEIGHT));
    }];
}

- (void)keyboardWillHide:(NSNotification*)notification {
    CGSize keyboardSize = [[notification userInfo][UIKeyboardFrameEndUserInfoKey] CGRectValue].size;
    self.contactTableView.frame = CGRectMake(CGRectGetMinX(self.contactTableView.frame),
                                             CGRectGetMinY(self.contactTableView.frame),
                                             CGRectGetWidth(self.contactTableView.frame),
                                             CGRectGetHeight(self.contactTableView.frame) + (keyboardSize.height-BOTTOM_TAB_BAR_HEIGHT));
}

#pragma mark - Refresh controls

- (void)refreshContacts {
    [Environment.getCurrent.phoneDirectoryManager forceUpdate];
}

- (void)contactRefreshFailed {
#warning Deprecated method
    UIAlertView* alert = [[UIAlertView alloc] initWithTitle:TIMEOUT
                                                    message:TIMEOUT_CONTACTS_DETAIL
                                                   delegate:nil
                                          cancelButtonTitle:NSLocalizedString(@"OK", @"")
                                          otherButtonTitles:nil];
    [alert show];
    [self.refreshControl endRefreshing];
}

- (void)contactsDidRefresh {
    [self.refreshControl endRefreshing];
}

@end
