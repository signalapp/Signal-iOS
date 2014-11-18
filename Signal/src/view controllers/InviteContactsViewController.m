#import "InviteContactsViewController.h"
#import <UIViewController+MMDrawerController.h>
#import "ContactsManager.h"
#import "ContactTableViewCell.h"
#import "Environment.h"
#import "NSArray+FunctionalUtil.h"
#import "LocalizableText.h"
#import "ObservableValue.h"
#import "SMSInvite.h"
#import "TabBarParentViewController.h"
#import "UnseenWhisperUserCell.h"

#define FIRST_TABLE_SECTION 0
#define SECOND_TABLE_SECTION 1

static NSString* const NEW_USERS_TABLE_SECTION_IDENTIFIER = @"UnseenWhisperUserCell";
static NSString* const INVITE_CONTACTS_TABLE_CELL_IDENTIFIER = @"ContactTableViewCell";

@interface InviteContactsViewController ()

@property (strong, nonatomic) NSArray* latestContacts;
@property (strong, nonatomic) NSArray* displayedContacts;
@property (strong, nonatomic) NSArray* selectedContactNumbers;
@property (strong, nonatomic) NSArray* arrayOfNewWhisperUsers;
@property (strong, nonatomic) NSString* currentSearchTerm;
@property (strong, nonatomic) SMSInvite* smsInvite;
@property (nonatomic) BOOL isSearching;

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
    if (self.arrayOfNewWhisperUsers) {
        [(TabBarParentViewController*)self.mm_drawerController.centerViewController setNewWhisperUsersAsSeen:self.arrayOfNewWhisperUsers];
        [self.contactTableView reloadData];
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
    ObservableValue* observableContacts = Environment.getCurrent.contactsManager.getObservableContacts;
    
    [observableContacts watchLatestValue:^(NSArray* latestContacts) {
        self.latestContacts = [self getUnregisteredUsersFromAllUsers:latestContacts searchTerm:nil];
        self.displayedContacts = self.latestContacts;
        [self.contactTableView reloadData];
    } onThread:[NSThread mainThread] untilCancelled:nil];
}

- (NSArray*)getUnregisteredUsersFromAllUsers:(NSArray*)users searchTerm:(NSString*)searchTerm {
    ContactsManager* contactsManager = Environment.getCurrent.contactsManager;
    
    return [users filter:^int(Contact* contact) {
    
        BOOL matchesSearchQuery = YES;
     
        if (searchTerm != nil) {
            matchesSearchQuery = [ContactsManager name:contact.fullName matchesQuery:searchTerm];
        }
     
        return ![contactsManager isContactRegisteredWithWhisper:contact] && matchesSearchQuery;
    }];
}

- (void)presentActionSheetWithNumbersForContact:(Contact*)contact {
    
    self.selectedContactNumbers = contact.parsedPhoneNumbers;
    
    UIActionSheet* actionSheet = [[UIActionSheet alloc] init];
    actionSheet.delegate = self;
    actionSheet.title = INVITE_USERS_ACTION_SHEET_TITLE;
    
    for (PhoneNumber* number in self.selectedContactNumbers) {
        [actionSheet addButtonWithTitle:[number localizedDescriptionForUser]];
    }
    actionSheet.cancelButtonIndex = [actionSheet addButtonWithTitle:TXT_CANCEL_TITLE];
    
    [actionSheet showInView:self.mm_drawerController.centerViewController.view];
}

#pragma mark - Actions 

- (IBAction)dismissNewWhisperUsersTapped:(id)sender {
    [self.contactTableView beginUpdates];

    NSMutableArray *indexPaths = [[NSMutableArray alloc] init];
    
    for (int i = 0; i < (NSInteger)self.arrayOfNewWhisperUsers.count; i++) {
        [indexPaths addObject:[NSIndexPath indexPathForRow:i inSection:FIRST_TABLE_SECTION]];
    }
    [self.contactTableView deleteRowsAtIndexPaths:indexPaths withRowAnimation:UITableViewRowAnimationAutomatic];
    self.arrayOfNewWhisperUsers = nil;
    [self.contactTableView endUpdates];
    [self.contactTableView reloadData];
}

- (void)updateWithNewWhisperUsers:(NSArray*)users {
    self.arrayOfNewWhisperUsers = users;
}

#pragma mark - UITableViewDelegate

- (NSInteger)numberOfSectionsInTableView:(UITableView*)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == FIRST_TABLE_SECTION) {
        return self.isSearching ? 0 : (NSInteger)self.arrayOfNewWhisperUsers.count;
    } else {
        return (NSInteger)self.displayedContacts.count;
    }
}

- (UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath {
    if (indexPath.section == FIRST_TABLE_SECTION && !self.isSearching) {
        return [self cellForNewWhisperUserAtIndexPath:indexPath];
    } else {
        return [self cellForUnregisteredContactAtIndexPath:indexPath];
    }
}

- (UITableViewCell*)cellForNewWhisperUserAtIndexPath:(NSIndexPath*)indexPath {
    UnseenWhisperUserCell* cell = [self.contactTableView dequeueReusableCellWithIdentifier:NEW_USERS_TABLE_SECTION_IDENTIFIER];
    
    if (!cell) {
        cell = [[UnseenWhisperUserCell alloc] initWithStyle:UITableViewCellStyleDefault
                                            reuseIdentifier:NEW_USERS_TABLE_SECTION_IDENTIFIER];
    }
    
    [cell configureWithContact:self.arrayOfNewWhisperUsers[(NSUInteger)indexPath.row]];
    return cell;
}

- (UITableViewCell*)cellForUnregisteredContactAtIndexPath:(NSIndexPath*)indexPath {
    ContactTableViewCell* cell = [self.contactTableView dequeueReusableCellWithIdentifier:INVITE_CONTACTS_TABLE_CELL_IDENTIFIER];
    
    if (!cell) {
        cell = [[ContactTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                           reuseIdentifier:INVITE_CONTACTS_TABLE_CELL_IDENTIFIER];
    }
    
    [cell configureWithContact:self.displayedContacts[(NSUInteger)indexPath.row]];
    return cell;
}

- (void)tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    if (indexPath.section == SECOND_TABLE_SECTION) {
        Contact* contact = self.displayedContacts[(NSUInteger)indexPath.row];
        [self presentActionSheetWithNumbersForContact:contact];
    }
}

- (UIView*)tableView:(UITableView*)tableView viewForHeaderInSection:(NSInteger)section {
    if (section == FIRST_TABLE_SECTION  && !self.isSearching && self.arrayOfNewWhisperUsers.count > 0) {
        return self.unseenWhisperUsersHeaderView;
    } else if (section == SECOND_TABLE_SECTION) {
        return self.regularContactsHeaderView;
    } else {
        return nil;
    }
}

- (CGFloat)tableView:(UITableView*)tableView heightForHeaderInSection:(NSInteger)section {
    if (self.isSearching || (self.arrayOfNewWhisperUsers.count == 0 && section == FIRST_TABLE_SECTION)) {
        return 0.0f;
    } else {
        CGFloat newUsersViewHeight = CGRectGetHeight(self.unseenWhisperUsersHeaderView.frame);
        CGFloat regularContactsViewHeight = CGRectGetHeight(self.regularContactsHeaderView.frame);
        
        return section == FIRST_TABLE_SECTION ? newUsersViewHeight : regularContactsViewHeight;
    }
}

#pragma mark - UIActionSheetDelegate

- (void)actionSheet:(UIActionSheet*)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex != actionSheet.cancelButtonIndex) {
        self.smsInvite = [[SMSInvite alloc] initWithParent:self];
        [self.smsInvite sendSMSInviteToNumber:self.selectedContactNumbers[(NSUInteger)buttonIndex]];
    }
}

#pragma mark - SearchBarTitleViewDelegate

- (void)searchBarTitleView:(SearchBarTitleView*)view didSearchForTerm:(NSString*)term {
    self.isSearching = YES;
    self.currentSearchTerm = term;
    self.displayedContacts = [self getUnregisteredUsersFromAllUsers:self.latestContacts searchTerm:term];
    [self.contactTableView reloadData];
}

- (void)searchBarTitleViewDidEndSearching:(SearchBarTitleView*)view {
    self.isSearching = NO;
    self.currentSearchTerm = nil;
    self.displayedContacts = [self getUnregisteredUsersFromAllUsers:self.latestContacts searchTerm:self.currentSearchTerm];
    [self.contactTableView reloadData];
}

- (void)searchBarTitleViewDidTapMenu:(SearchBarTitleView*)view {
    [self.mm_drawerController openDrawerSide:MMDrawerSideLeft
                                    animated:YES
                                  completion:nil];
}

#pragma mark - Keyboard

- (void)keyboardWillShow:(NSNotification*)notification {
    double duration = [[notification userInfo][UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    [UIView animateWithDuration:duration animations:^{
        CGSize keyboardSize = [[notification userInfo][UIKeyboardFrameBeginUserInfoKey] CGRectValue].size;
        CGFloat height = CGRectGetHeight(self.contactTableView.frame) - (keyboardSize.height-BOTTOM_TAB_BAR_HEIGHT);
        self.contactTableView.frame = CGRectMake(CGRectGetMinX(self.contactTableView.frame),
                                                 CGRectGetMinY(self.contactTableView.frame),
                                                 CGRectGetWidth(self.contactTableView.frame),
                                                 height);
    }];
}

- (void)keyboardWillHide:(NSNotification*)notification {
    CGSize keyboardSize = [[notification userInfo][UIKeyboardFrameEndUserInfoKey] CGRectValue].size;
    CGFloat height = CGRectGetHeight(self.contactTableView.frame) + (keyboardSize.height-BOTTOM_TAB_BAR_HEIGHT);
    self.contactTableView.frame = CGRectMake(CGRectGetMinX(self.contactTableView.frame),
                                             CGRectGetMinY(self.contactTableView.frame),
                                             CGRectGetWidth(self.contactTableView.frame),
                                             height);
}

@end
