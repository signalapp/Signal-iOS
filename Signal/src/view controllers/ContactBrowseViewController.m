#import "Contact.h"
#import "ContactBrowseViewController.h"
#import "ContactDetailViewController.h"
#import "ContactsManager.h"
#import "ContactTableViewCell.h"
#import "InCallViewController.h"
#import "LocalizableText.h"
#import "PreferencesUtil.h"
#import "TabBarParentViewController.h"
#import "NotificationManifest.h"
#import "PhoneNumberDirectoryFilterManager.h"

#import <AddressBook/AddressBook.h>
#import <UIViewController+MMDrawerController.h>

#define NOTIFICATION_VIEW_ANIMATION_DURATION 0.5f
#define REFRESH_TIMEOUT 20

static NSString *const CONTACT_BROWSE_TABLE_CELL_IDENTIFIER = @"ContactTableViewCell";

@interface ContactBrowseViewController () {
    NSDictionary *_latestAlphabeticalContacts;
    NSArray *_latestSortedAlphabeticalContactKeys;
    NSArray *_latestContacts;
    NSArray *_newWhisperUsers;
    CGRect _originalTableViewFrame;
    BOOL _showingNotificationView;
}

@end

@implementation ContactBrowseViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(contactsDidRefresh) name:NOTIFICATION_DIRECTORY_WAS_UPDATED object:nil];
    UIRefreshControl *refreshControl = [[UIRefreshControl alloc]
                                        init];
    [refreshControl addTarget:self action:@selector(refreshContacts) forControlEvents:UIControlEventValueChanged];
    self.refreshControl = refreshControl;
    [self.contactTableView addSubview:self.refreshControl];
    
    [self setupContacts];
    [self observeKeyboardNotifications];
    _originalTableViewFrame = _contactTableView.frame;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:YES animated:NO];
    [_contactTableView reloadData];
    [_searchBarTitleView updateAutoCorrectionType];
    [[Environment getCurrent].contactsManager enableNewUserNotifications];
    
    BOOL showNotificationView = _newWhisperUsers != nil;
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

- (void)onSearchOrContactChange:(NSString *)searchTerm {
    if (_latestContacts) {
        _latestAlphabeticalContacts = [ContactsManager groupContactsByFirstLetter:_latestContacts
                                                             matchingSearchString:searchTerm];
        
        NSArray *contactKeys = [_latestAlphabeticalContacts allKeys];
        _latestSortedAlphabeticalContactKeys = [contactKeys sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
        [_contactTableView reloadData];
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
    [(TabBarParentViewController *)self.mm_drawerController.centerViewController presentInviteContactsViewController];
}

- (void)showNotificationForNewWhisperUsers:(NSArray *)users {
    
    _newWhisperUsers = users;

    BOOL isViewVisible = [self isViewLoaded] && self.view.window;
    
    if (isViewVisible) {
        [self showNotificationViewAnimated:YES];
    }
}

- (void)showNotificationViewAnimated:(BOOL)animated {
    
    if (_showingNotificationView) {
        return;
    }
    
    CGFloat animationTime = animated ? NOTIFICATION_VIEW_ANIMATION_DURATION : 0.0f;
    
    [UIView animateWithDuration:animationTime animations:^{
        _notificationView.frame = CGRectMake(CGRectGetMinX(_notificationView.frame),
                                             CGRectGetHeight(_searchBarTitleView.frame),
                                             CGRectGetWidth(_notificationView.frame),
                                             CGRectGetHeight(_notificationView.frame));
    
        CGFloat tableViewYOrigin = CGRectGetMinY(_originalTableViewFrame) + CGRectGetHeight(_notificationView.frame);
        _contactTableView.frame = CGRectMake(CGRectGetMinX(_contactTableView.frame),
                                             tableViewYOrigin,
                                             CGRectGetWidth(_contactTableView.frame),
                                             CGRectGetHeight(_contactTableView.frame));
        
    }];
    
    _showingNotificationView = YES;
}

- (void)hideNotificationView {
    if (!_showingNotificationView) {
        return;
    }
    
    _notificationView.frame = CGRectMake(CGRectGetMinX(_notificationView.frame),
                                         0,
                                         CGRectGetWidth(_notificationView.frame),
                                         CGRectGetHeight(_notificationView.frame));
    _contactTableView.frame = _originalTableViewFrame;
    _showingNotificationView = NO;
}

#pragma mark - Contact functions

- (void)setupContacts {
    ObservableValue *observableContacts = [[[Environment getCurrent] contactsManager] getObservableWhisperUsers];

    [observableContacts watchLatestValue:^(NSArray *latestContacts) {
        _latestContacts = latestContacts;
        [self onSearchOrContactChange:nil];
    } onThread:[NSThread mainThread] untilCancelled:nil];
}

- (NSArray *)contactsForSectionIndex:(NSUInteger)index {
    return [_latestAlphabeticalContacts valueForKey:_latestSortedAlphabeticalContactKeys[index]];
}

- (void)pushContactViewControllerForContactIndexPath:(NSIndexPath *)indexPath {
    NSArray *contactSection = [self contactsForSectionIndex:(NSUInteger)indexPath.section];
    Contact *contact = contactSection[(NSUInteger)indexPath.row];
    ContactDetailViewController *vc = [ContactDetailViewController contactDetailViewControllerWithContact:contact];
    [self.navigationController pushViewController:vc animated:YES];
}

#pragma mark - UITableViewDelegate

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)[[self contactsForSectionIndex:(NSUInteger)section] count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return _latestSortedAlphabeticalContactKeys[(NSUInteger)section];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return (NSInteger)[[_latestAlphabeticalContacts allKeys] count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	
    ContactTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CONTACT_BROWSE_TABLE_CELL_IDENTIFIER];

    if (!cell) {
        cell = [[ContactTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                           reuseIdentifier:CONTACT_BROWSE_TABLE_CELL_IDENTIFIER];
    }

    NSArray *contactSection = [self contactsForSectionIndex:(NSUInteger)indexPath.section];
    Contact *contact = contactSection[(NSUInteger)indexPath.row];
    [cell configureWithContact:contact];

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [_searchBarTitleView.searchTextField resignFirstResponder];
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self pushContactViewControllerForContactIndexPath:indexPath];
}

- (NSArray *)sectionIndexTitlesForTableView:(UITableView *)tableView {
    return _latestSortedAlphabeticalContactKeys;
}

#pragma mark - SearchBarTitleViewDelegate

- (void)searchBarTitleView:(SearchBarTitleView *)view didSearchForTerm:(NSString *)term {
    [self onSearchOrContactChange:term];
}

- (void)searchBarTitleViewDidTapMenu:(SearchBarTitleView *)view {
    [self.mm_drawerController openDrawerSide:MMDrawerSideLeft
                                    animated:YES
                                  completion:nil];
}

- (void)searchBarTitleViewDidEndSearching:(SearchBarTitleView *)view {
    [self onSearchOrContactChange:nil];
}

#pragma mark - Keyboard

- (void)keyboardWillShow:(NSNotification *)notification {
    double duration = [[notification userInfo][UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    [UIView animateWithDuration:duration animations:^{
        CGSize keyboardSize = [[notification userInfo][UIKeyboardFrameBeginUserInfoKey] CGRectValue].size;
        _contactTableView.frame = CGRectMake(CGRectGetMinX(_contactTableView.frame),
                                             CGRectGetMinY(_contactTableView.frame),
                                             CGRectGetWidth(_contactTableView.frame),
                                             CGRectGetHeight(_contactTableView.frame) - (keyboardSize.height-BOTTOM_TAB_BAR_HEIGHT));
    }];
}

- (void)keyboardWillHide:(NSNotification *)notification {
    CGSize keyboardSize = [[notification userInfo][UIKeyboardFrameEndUserInfoKey] CGRectValue].size;
    _contactTableView.frame = CGRectMake(CGRectGetMinX(_contactTableView.frame),
                                         CGRectGetMinY(_contactTableView.frame),
                                         CGRectGetWidth(_contactTableView.frame),
                                         CGRectGetHeight(_contactTableView.frame) + (keyboardSize.height-BOTTOM_TAB_BAR_HEIGHT));
}

#pragma mark - Refresh controls

- (void)refreshContacts{
    [[[Environment getCurrent] phoneDirectoryManager] forceUpdate];
    self.refreshTimer = [NSTimer scheduledTimerWithTimeInterval:REFRESH_TIMEOUT target:self selector:@selector(contactRefreshDidTimeout) userInfo:nil repeats:NO];
}

- (void)contactRefreshDidTimeout{
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:TIMEOUT message:TIMEOUT_CONTACTS_DETAIL delegate:nil cancelButtonTitle:NSLocalizedString(@"OK", @"") otherButtonTitles:nil];
    [alert show];
    [self.refreshControl endRefreshing];
}

- (void)contactsDidRefresh{
    [self.refreshTimer invalidate];
    [self.refreshControl endRefreshing];
}

@end
