#import "FavouritesViewController.h"
#import "Environment.h"
#import "ContactDetailViewController.h"
#import "ContactsManager.h"
#import "LocalizableText.h"
#import "FunctionalUtil.h"
#import "PreferencesUtil.h"
#import "TabBarParentViewController.h"

#import "UIViewController+MMDrawerController.h"

static NSString *const CONTACT_TABLE_VIEW_CELL_IDENTIFIER = @"ContactTableViewCell";

@interface FavouritesViewController () {
    NSArray *_favourites;
    NSArray *_searchFavourites;
    BOOL _isSearching;
}

@end

@implementation FavouritesViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self observeLatestFavourites];
    [self observeKeyboardNotifications];
    _favouriteTableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
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
    ObservableValue *observableFavourites = [[[Environment getCurrent] contactsManager] getObservableFavourites];

    [observableFavourites watchLatestValue:^(NSArray *latestFavourites) {
        _favourites = latestFavourites;
        [_favouriteTableView reloadData];
        [self hideTableViewIfNoFavourites];
    } onThread:[NSThread mainThread] untilCancelled:nil];
}

- (void)hideTableViewIfNoFavourites {
    BOOL hideFavourites = _favourites.count == 0;
    _favouriteTableView.hidden = hideFavourites;
}

- (void)openLeftSideMenu {
    [self.mm_drawerController openDrawerSide:MMDrawerSideLeft animated:YES completion:nil];
}

- (void)pushContactDetailViewControllerWithContact:(Contact *)contact {
    ContactDetailViewController *vc = [ContactDetailViewController contactDetailViewControllerWithContact:contact];
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

- (void)favouriteTapped:(Contact *)contact {

    PhoneNumberDirectoryFilter *filter = [[[Environment getCurrent] phoneDirectoryManager] getCurrentFilter];

    for (PhoneNumber *number in contact.parsedPhoneNumbers) {
        if ([filter containsPhoneNumber:number]) {
            [(TabBarParentViewController *)self.mm_drawerController.centerViewController showDialerViewControllerWithNumber:number];
            return;
        }
    }

    [UIApplication.sharedApplication openURL:[contact.parsedPhoneNumbers[0] toSystemDialerURL]];
}

#pragma mark - UITableViewDelegate

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return _isSearching ? (NSInteger)_searchFavourites.count : (NSInteger)_favourites.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {

    FavouriteTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CONTACT_TABLE_VIEW_CELL_IDENTIFIER];
    if (!cell) {
        cell = [[FavouriteTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                           reuseIdentifier:CONTACT_TABLE_VIEW_CELL_IDENTIFIER];
        cell.delegate = self;
    }

    Contact *contact = _isSearching ? _searchFavourites[(NSUInteger)indexPath.row] : _favourites[(NSUInteger)indexPath.row];
    [cell configureWithContact:contact];

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [_searchBarTitleView.searchTextField resignFirstResponder];
    Contact *contact = _isSearching ? _searchFavourites[(NSUInteger)indexPath.row] : _favourites[(NSUInteger)indexPath.row];
    [self pushContactDetailViewControllerWithContact:contact];
}

#pragma mark - SearchBarTitleViewDelegate

- (void)searchBarTitleView:(SearchBarTitleView *)view didSearchForTerm:(NSString *)term {
    _isSearching = YES;
    _searchFavourites = [self favouritesForSearchTerm:term];
    [_favouriteTableView reloadData];
}

- (void)searchBarTitleViewDidTapMenu:(SearchBarTitleView *)view {
    [self.mm_drawerController openDrawerSide:MMDrawerSideLeft
                                    animated:YES
                                  completion:nil];
}

- (void)searchBarTitleViewDidEndSearching:(SearchBarTitleView *)view {
    _isSearching = NO;
    _searchFavourites = nil;
    [_favouriteTableView reloadData];
}

- (NSArray *)favouritesForSearchTerm:(NSString *)searchTerm {
    return [_favourites filter:^int(Contact *contact) {
        return searchTerm.length == 0 || [ContactsManager name:[contact fullName] matchesQuery:searchTerm];
    }];
}

#pragma mark - FavouriteTableViewCellDelegate

- (void)favouriteTableViewCellTappedCall:(FavouriteTableViewCell *)cell {
    NSIndexPath *indexPath = [_favouriteTableView indexPathForCell:cell];
    Contact *contact = _favourites[(NSUInteger)indexPath.row];
    [self favouriteTapped:contact];
}

#pragma mark - Keyboard

- (void)keyboardWillShow:(NSNotification *)notification {
    double duration = [[notification userInfo][UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    [UIView animateWithDuration:duration animations:^{
        CGSize keyboardSize = [[notification userInfo][UIKeyboardFrameBeginUserInfoKey] CGRectValue].size;
        CGFloat height = CGRectGetHeight(_favouriteTableView.frame) - (keyboardSize.height-BOTTOM_TAB_BAR_HEIGHT);
        _favouriteTableView.frame = CGRectMake(CGRectGetMinX(_favouriteTableView.frame),
                                               CGRectGetMinY(_favouriteTableView.frame),
                                               CGRectGetWidth(_favouriteTableView.frame),
                                               height);
    }];
}

- (void)keyboardWillHide:(NSNotification *)notification {
    CGSize keyboardSize = [[notification userInfo][UIKeyboardFrameEndUserInfoKey] CGRectValue].size;
    CGFloat height = CGRectGetHeight(_favouriteTableView.frame) + (keyboardSize.height-BOTTOM_TAB_BAR_HEIGHT);
    _favouriteTableView.frame = CGRectMake(CGRectGetMinX(_favouriteTableView.frame),
                                           CGRectGetMinY(_favouriteTableView.frame),
                                           CGRectGetWidth(_favouriteTableView.frame),
                                           height);
}

@end
