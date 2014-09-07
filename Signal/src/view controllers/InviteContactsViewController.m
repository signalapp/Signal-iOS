#import "InviteContactsViewController.h"

#import <UIViewController+MMDrawerController.h>

#import "ContactsManager.h"
#import "ContactTableViewCell.h"
#import "Environment.h"
#import "FunctionalUtil.h"
#import "LocalizableText.h"
#import "ObservableValue.h"
#import "SmsInvite.h"
#import "TabBarParentViewController.h"
#import "UnseenWhisperUserCell.h"



#define FIRST_TABLE_SECTION 0
#define SECOND_TABLE_SECTION 1

static NSString *const NEW_USERS_TABLE_SECTION_IDENTIFIER = @"UnseenWhisperUserCell";
static NSString *const INVITE_CONTACTS_TABLE_CELL_IDENTIFIER = @"ContactTableViewCell";

@interface InviteContactsViewController () {
    NSArray *_latestContacts;
    NSArray *_displayedContacts;
    NSArray *_selectedContactNumbers;
    NSArray *_newWhisperUsers;
    
    BOOL _isSearching;
    NSString *_currentSearchTerm;
    SmsInvite* smsInvite;
}

@end

@implementation InviteContactsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupContacts];
    [self observeKeyboardNotifications];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.navigationController.navigationBarHidden = YES;
    if (_newWhisperUsers) {
        [(TabBarParentViewController *)self.mm_drawerController.centerViewController setNewWhisperUsersAsSeen:_newWhisperUsers];
        [_contactTableView reloadData];
    }
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
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

- (void)setupContacts {
    ObservableValue *observableContacts = Environment.getCurrent.contactsManager.getObservableContacts;
    
    [observableContacts watchLatestValue:^(NSArray *latestContacts) {
        _latestContacts = [self getUnregisteredUsersFromAllUsers:latestContacts searchTerm:nil];
        _displayedContacts = _latestContacts;
        [_contactTableView reloadData];
    } onThread:NSThread.mainThread untilCancelled:nil];
}

- (NSArray *)getUnregisteredUsersFromAllUsers:(NSArray *)users searchTerm:(NSString *)searchTerm {
    ContactsManager *contactsManager = Environment.getCurrent.contactsManager;
    
    return [users filter:^int(Contact *contact) {
    
        BOOL matchesSearchQuery = YES;
     
        if (searchTerm != nil) {
            matchesSearchQuery = [ContactsManager name:contact.fullName matchesQuery:searchTerm];
        }
     
        return ![contactsManager isContactRegisteredWithWhisper:contact] && matchesSearchQuery;
    }];
}

- (void)presentActionSheetWithNumbersForContact:(Contact *)contact {
    
    _selectedContactNumbers = contact.parsedPhoneNumbers;
    
    UIActionSheet *actionSheet = [UIActionSheet new];
    actionSheet.delegate = self;
    actionSheet.title = INVITE_USERS_ACTION_SHEET_TITLE;
    
    for (PhoneNumber *number in _selectedContactNumbers) {
        [actionSheet addButtonWithTitle:number.localizedDescriptionForUser];
    }
    actionSheet.cancelButtonIndex = [actionSheet addButtonWithTitle:TXT_CANCEL_TITLE];
    
    [actionSheet showInView:self.mm_drawerController.centerViewController.view];
}

#pragma mark - Actions 

- (IBAction)dismissNewWhisperUsersTapped:(id)sender {
    [_contactTableView beginUpdates];

    NSMutableArray *indexPaths = [NSMutableArray array];
    
    for (int i = 0; i < (NSInteger)_newWhisperUsers.count; i++) {
        [indexPaths addObject:[NSIndexPath indexPathForRow:i inSection:FIRST_TABLE_SECTION]];
    }
    [_contactTableView deleteRowsAtIndexPaths:indexPaths withRowAnimation:UITableViewRowAnimationAutomatic];
    _newWhisperUsers = nil;
    [_contactTableView endUpdates];
    [_contactTableView reloadData];
}

- (void)updateWithNewWhisperUsers:(NSArray *)users {
    _newWhisperUsers = users;
}

#pragma mark - UITableViewDelegate

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == FIRST_TABLE_SECTION) {
        return _isSearching ? 0 : (NSInteger)_newWhisperUsers.count;
    } else {
        return (NSInteger)_displayedContacts.count;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == FIRST_TABLE_SECTION && !_isSearching) {
        return [self cellForNewWhisperUserAtIndexPath:indexPath];
    } else {
        return [self cellForUnregisteredContactAtIndexPath:indexPath];
    }
}

- (UITableViewCell *)cellForNewWhisperUserAtIndexPath:(NSIndexPath *)indexPath {
    UnseenWhisperUserCell *cell = [_contactTableView dequeueReusableCellWithIdentifier:NEW_USERS_TABLE_SECTION_IDENTIFIER];
    
    if (!cell) {
        cell = [[UnseenWhisperUserCell alloc] initWithStyle:UITableViewCellStyleDefault
                                            reuseIdentifier:NEW_USERS_TABLE_SECTION_IDENTIFIER];
    }
    
    [cell configureWithContact:_newWhisperUsers[(NSUInteger)indexPath.row]];
    return cell;
}

- (UITableViewCell *)cellForUnregisteredContactAtIndexPath:(NSIndexPath *)indexPath {
    ContactTableViewCell *cell = [_contactTableView dequeueReusableCellWithIdentifier:INVITE_CONTACTS_TABLE_CELL_IDENTIFIER];
    
    if (!cell) {
        cell = [[ContactTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                           reuseIdentifier:INVITE_CONTACTS_TABLE_CELL_IDENTIFIER];
    }
    
    [cell configureWithContact:_displayedContacts[(NSUInteger)indexPath.row]];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    if (indexPath.section == SECOND_TABLE_SECTION) {
        Contact *contact = _displayedContacts[(NSUInteger)indexPath.row];
        [self presentActionSheetWithNumbersForContact:contact];
    }
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    if (section == FIRST_TABLE_SECTION  && !_isSearching && _newWhisperUsers.count > 0) {
        return _unseenWhisperUsersHeaderView;
    } else if (section == SECOND_TABLE_SECTION) {
        return _regularContactsHeaderView;
    } else {
        return nil;
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    if (_isSearching || (_newWhisperUsers.count == 0 && section == FIRST_TABLE_SECTION)) {
        return 0.0f;
    } else {

        CGFloat newUsersViewHeight = CGRectGetHeight(_unseenWhisperUsersHeaderView.frame);
        CGFloat regularContactsViewHeight = CGRectGetHeight(_regularContactsHeaderView.frame);
        
        return section == FIRST_TABLE_SECTION ? newUsersViewHeight : regularContactsViewHeight;
    }
}

#pragma mark - UIActionSheetDelegate

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex != actionSheet.cancelButtonIndex) {
        smsInvite = [SmsInvite smsInviteWithParent:self];
        [smsInvite sendSMSInviteToNumber:_selectedContactNumbers[(NSUInteger)buttonIndex]];
    }
}

#pragma mark - SearchBarTitleViewDelegate

- (void)searchBarTitleView:(SearchBarTitleView *)view didSearchForTerm:(NSString *)term {
    _isSearching = YES;
    _currentSearchTerm = term;
    _displayedContacts = [self getUnregisteredUsersFromAllUsers:_latestContacts searchTerm:term];
    [_contactTableView reloadData];
}

- (void)searchBarTitleViewDidEndSearching:(SearchBarTitleView *)view {
    _isSearching = NO;
    _currentSearchTerm = nil;
    _displayedContacts = [self getUnregisteredUsersFromAllUsers:_latestContacts searchTerm:_currentSearchTerm];
    [_contactTableView reloadData];
}

- (void)searchBarTitleViewDidTapMenu:(SearchBarTitleView *)view {
    [self.mm_drawerController openDrawerSide:MMDrawerSideLeft
                                    animated:YES
                                  completion:nil];
}

#pragma mark - Keyboard

- (void)keyboardWillShow:(NSNotification *)notification {
    double duration = [[notification userInfo][UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    [UIView animateWithDuration:duration animations:^{
        CGSize keyboardSize = [[notification userInfo][UIKeyboardFrameBeginUserInfoKey] CGRectValue].size;
        CGFloat height = CGRectGetHeight(_contactTableView.frame) - (keyboardSize.height-BOTTOM_TAB_BAR_HEIGHT);
        _contactTableView.frame = CGRectMake(CGRectGetMinX(_contactTableView.frame),
                                               CGRectGetMinY(_contactTableView.frame),
                                               CGRectGetWidth(_contactTableView.frame),
                                               height);
    }];
}

- (void)keyboardWillHide:(NSNotification *)notification {
    CGSize keyboardSize = [[notification userInfo][UIKeyboardFrameEndUserInfoKey] CGRectValue].size;
    CGFloat height = CGRectGetHeight(_contactTableView.frame) + (keyboardSize.height-BOTTOM_TAB_BAR_HEIGHT);
    _contactTableView.frame = CGRectMake(CGRectGetMinX(_contactTableView.frame),
                                           CGRectGetMinY(_contactTableView.frame),
                                           CGRectGetWidth(_contactTableView.frame),
                                           height);
}

@end
