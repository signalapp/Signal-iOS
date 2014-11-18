#import "FavouritesViewController.h"
#import "Environment.h"
#import "ContactDetailViewController.h"
#import "ContactsManager.h"
#import "LocalizableText.h"
#import "NSArray+FunctionalUtil.h"
#import "PropertyListPreferences+Util.h"
#import "TabBarParentViewController.h"

#import "UIViewController+MMDrawerController.h"

static NSString* const CONTACT_TABLE_VIEW_CELL_IDENTIFIER = @"ContactTableViewCell";

@interface FavouritesViewController ()

@property (strong, nonatomic) NSArray* favourites;
@property (strong, nonatomic) NSArray* searchFavourites;
@property (nonatomic) BOOL isSearching;

@end

@implementation FavouritesViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self observeLatestFavourites];
    [self observeKeyboardNotifications];
    self.favouriteTableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.navigationController.navigationBarHidden = YES;
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    self.navigationController.navigationBarHidden = NO;
}

- (void)observeLatestFavourites {
    ObservableValue* observableFavourites = Environment.getCurrent.contactsManager.getObservableFavourites;

    [observableFavourites watchLatestValue:^(NSArray* latestFavourites) {
        self.favourites = latestFavourites;
        [self.favouriteTableView reloadData];
        [self hideTableViewIfNoFavourites];
    } onThread:[NSThread mainThread] untilCancelled:nil];
}

- (void)hideTableViewIfNoFavourites {
    BOOL hideFavourites = self.favourites.count == 0;
    self.favouriteTableView.hidden = hideFavourites;
}

- (void)openLeftSideMenu {
    [self.mm_drawerController openDrawerSide:MMDrawerSideLeft animated:YES completion:nil];
}

- (void)pushContactDetailViewControllerWithContact:(Contact*)contact {
    ContactDetailViewController* vc = [[ContactDetailViewController alloc] initWithContact:contact];
    [self.navigationController pushViewController:vc animated:YES];
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

- (void)favouriteTapped:(Contact*)contact {

    PhoneNumberDirectoryFilter* filter = Environment.getCurrent.phoneDirectoryManager.getCurrentFilter;

    for (PhoneNumber* number in contact.parsedPhoneNumbers) {
        if ([filter containsPhoneNumber:number]) {
            [(TabBarParentViewController*)self.mm_drawerController.centerViewController showDialerViewControllerWithNumber:number];
            return;
        }
    }

    [[UIApplication sharedApplication] openURL:[contact.parsedPhoneNumbers[0] toSystemDialerURL]];
}

#pragma mark - UITableViewDelegate

- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section {
    return self.isSearching ? (NSInteger)self.searchFavourites.count : (NSInteger)self.favourites.count;
}

- (UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath {

    FavouriteTableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:CONTACT_TABLE_VIEW_CELL_IDENTIFIER];
    if (!cell) {
        cell = [[FavouriteTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                             reuseIdentifier:CONTACT_TABLE_VIEW_CELL_IDENTIFIER];
        cell.delegate = self;
    }

    Contact* contact = self.isSearching ? self.searchFavourites[(NSUInteger)indexPath.row] : self.favourites[(NSUInteger)indexPath.row];
    [cell configureWithContact:contact];

    return cell;
}

- (void)tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self.searchBarTitleView.searchTextField resignFirstResponder];
    Contact* contact = self.isSearching ? self.searchFavourites[(NSUInteger)indexPath.row] : self.favourites[(NSUInteger)indexPath.row];
    [self pushContactDetailViewControllerWithContact:contact];
}

#pragma mark - SearchBarTitleViewDelegate

- (void)searchBarTitleView:(SearchBarTitleView*)view didSearchForTerm:(NSString*)term {
    self.isSearching = YES;
    self.searchFavourites = [self favouritesForSearchTerm:term];
    [self.favouriteTableView reloadData];
}

- (void)searchBarTitleViewDidTapMenu:(SearchBarTitleView*)view {
    [self.mm_drawerController openDrawerSide:MMDrawerSideLeft
                                    animated:YES
                                  completion:nil];
}

- (void)searchBarTitleViewDidEndSearching:(SearchBarTitleView*)view {
    self.isSearching = NO;
    self.searchFavourites = nil;
    [self.favouriteTableView reloadData];
}

- (NSArray*)favouritesForSearchTerm:(NSString*)searchTerm {
    return [self.favourites filter:^int(Contact* contact) {
        return searchTerm.length == 0 || [ContactsManager name:contact.fullName matchesQuery:searchTerm];
    }];
}

#pragma mark - FavouriteTableViewCellDelegate

- (void)favouriteTableViewCellTappedCall:(FavouriteTableViewCell*)cell {
    NSIndexPath* indexPath = [self.favouriteTableView indexPathForCell:cell];
    Contact* contact = self.favourites[(NSUInteger)indexPath.row];
    [self favouriteTapped:contact];
}

#pragma mark - Keyboard

- (void)keyboardWillShow:(NSNotification*)notification {
    double duration = [[notification userInfo][UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    [UIView animateWithDuration:duration animations:^{
        CGSize keyboardSize = [[notification userInfo][UIKeyboardFrameBeginUserInfoKey] CGRectValue].size;
        CGFloat height = CGRectGetHeight(self.favouriteTableView.frame) - (keyboardSize.height-BOTTOM_TAB_BAR_HEIGHT);
        self.favouriteTableView.frame = CGRectMake(CGRectGetMinX(self.favouriteTableView.frame),
                                                   CGRectGetMinY(self.favouriteTableView.frame),
                                                   CGRectGetWidth(self.favouriteTableView.frame),
                                                   height);
    }];
}

- (void)keyboardWillHide:(NSNotification*)notification {
    CGSize keyboardSize = [[notification userInfo][UIKeyboardFrameEndUserInfoKey] CGRectValue].size;
    CGFloat height = CGRectGetHeight(self.favouriteTableView.frame) + (keyboardSize.height-BOTTOM_TAB_BAR_HEIGHT);
    self.favouriteTableView.frame = CGRectMake(CGRectGetMinX(self.favouriteTableView.frame),
                                               CGRectGetMinY(self.favouriteTableView.frame),
                                               CGRectGetWidth(self.favouriteTableView.frame),
                                               height);
}

@end
