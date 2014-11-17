#import "Environment.h"
#import "LocalizableText.h"
#import "PropertyListPreferences+Util.h"
#import "CallLogViewController.h"
#import "RecentCall.h"
#import "TabBarParentViewController.h"
#import "RecentCallManager.h"

#import <UIViewController+MMDrawerController.h>

#define RECENT_CALL_TABLE_CELL_HEIGHT 43

static NSString *const RECENT_CALL_TABLE_CELL_IDENTIFIER = @"CallLogTableViewCell";

typedef NSComparisonResult (^CallComparator)(RecentCall*, RecentCall*);

@interface CallLogViewController () {
    NSArray *_recents;
    BOOL _tableViewContentMutating;
    NSString *_searchTerm;
}

@end

@implementation CallLogViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self observeRecentCalls];
    [self observeKeyboardNotifications];
    _searchBarTitleView.titleLabel.text = RECENT_NAV_BAR_TITLE;
    _recentCallsTableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
}

- (void)viewWillAppear:(BOOL)animated {
    [self.navigationController setNavigationBarHidden:YES animated:NO];
    [super viewWillAppear:animated];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.navigationController setNavigationBarHidden:NO animated:YES];
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

- (void)observeRecentCalls {
    ObservableValue *observableRecents = Environment.getCurrent.recentCallManager.getObservableRecentCalls;

    [observableRecents watchLatestValue:^(NSArray *latestRecents) {
        if (_searchTerm) {
            _recents = [Environment.getCurrent.recentCallManager recentsForSearchString:_searchTerm
                                                                         andExcludeArchived:NO];
        } else {
            _recents = latestRecents;
        }
        
        if (!_tableViewContentMutating) {
            [_recentCallsTableView reloadData];
        }
    } onThread:NSThread.mainThread untilCancelled:nil];
}

- (void)deleteRecentCallAtIndexPath:(NSIndexPath *)indexPath {
    [_recentCallsTableView beginUpdates];
    [_recentCallsTableView deleteRowsAtIndexPaths:@[indexPath]
                                 withRowAnimation:UITableViewRowAnimationLeft];

    RecentCall *recent;


    [Environment.getCurrent.recentCallManager removeRecentCall:recent];

    [_recentCallsTableView endUpdates];
}

#pragma mark - UITableViewDelegate

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)_recents.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    CallLogTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:RECENT_CALL_TABLE_CELL_IDENTIFIER];
    if (!cell) {
        cell = [[CallLogTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                           reuseIdentifier:RECENT_CALL_TABLE_CELL_IDENTIFIER];
        cell.delegate = self;
    }
    RecentCall *recent = _recents[(NSUInteger)indexPath.row];
    [cell configureWithRecentCall:recent];

    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return RECENT_CALL_TABLE_CELL_HEIGHT;
}

#pragma mark - RecentCallTableViewCellDelegate

- (void)recentCallTableViewCellTappedDelete:(CallLogTableViewCell *)cell {
    _tableViewContentMutating = YES;
    NSIndexPath *indexPath = [_recentCallsTableView indexPathForCell:cell];

    [_recentCallsTableView beginUpdates];
    [_recentCallsTableView deleteRowsAtIndexPaths:@[indexPath]
                                 withRowAnimation:UITableViewRowAnimationLeft];

    RecentCall *recent = _recents[(NSUInteger)indexPath.row];
    [Environment.getCurrent.recentCallManager removeRecentCall:recent];

    [_recentCallsTableView endUpdates];
    _tableViewContentMutating = NO;
}

- (void)recentCallTableViewCellTappedCall:(CallLogTableViewCell *)cell {
    NSIndexPath *indexPath = [_recentCallsTableView indexPathForCell:cell];
    RecentCall *recent = _recents[(NSUInteger)indexPath.row];
    [(TabBarParentViewController *)self.mm_drawerController.centerViewController showDialerViewControllerWithNumber:recent.phoneNumber];
}

#pragma mark - SearchBarTitleViewDelegate

- (void)searchBarTitleView:(SearchBarTitleView *)view didSearchForTerm:(NSString *)term {
    _searchTerm = term;
    _recents = [Environment.getCurrent.recentCallManager recentsForSearchString:term
                                                                 andExcludeArchived:NO];
    [_recentCallsTableView reloadData];
}

- (void)searchBarTitleViewDidTapMenu:(SearchBarTitleView *)view {
    [self.mm_drawerController openDrawerSide:MMDrawerSideLeft
                                    animated:YES
                                  completion:nil];
}

- (void)searchBarTitleViewDidEndSearching:(SearchBarTitleView *)view {
    _searchTerm = nil;
    _recents = [Environment.getCurrent.recentCallManager recentsForSearchString:nil
                                                                 andExcludeArchived:NO];
    [_recentCallsTableView reloadData];
}

#pragma mark - Keyboard

- (void)keyboardWillShow:(NSNotification *)notification {
    double duration = [[notification userInfo][UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    [UIView animateWithDuration:duration animations:^{
        CGSize keyboardSize = [[notification userInfo][UIKeyboardFrameBeginUserInfoKey] CGRectValue].size;
        CGFloat height = CGRectGetHeight(_recentCallsTableView.frame) - (keyboardSize.height-BOTTOM_TAB_BAR_HEIGHT);
        _recentCallsTableView.frame = CGRectMake(CGRectGetMinX(_recentCallsTableView.frame),
                                                 CGRectGetMinY(_recentCallsTableView.frame),
                                                 CGRectGetWidth(_recentCallsTableView.frame),
                                                 height);
    }];
}

- (void)keyboardWillHide:(NSNotification *)notification {
    CGSize keyboardSize = [[notification userInfo][UIKeyboardFrameEndUserInfoKey] CGRectValue].size;
    CGFloat height = CGRectGetHeight(_recentCallsTableView.frame) + (keyboardSize.height-BOTTOM_TAB_BAR_HEIGHT);
    _recentCallsTableView.frame = CGRectMake(CGRectGetMinX(_recentCallsTableView.frame),
                                             CGRectGetMinY(_recentCallsTableView.frame),
                                             CGRectGetWidth(_recentCallsTableView.frame),
                                             height);
}

@end
