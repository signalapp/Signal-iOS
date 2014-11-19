#import "Environment.h"
#import "LocalizableText.h"
#import "PropertyListPreferences+Util.h"
#import "CallLogViewController.h"
#import "RecentCall.h"
#import "TabBarParentViewController.h"
#import "RecentCallManager.h"

#import <UIViewController+MMDrawerController.h>

#define RECENT_CALL_TABLE_CELL_HEIGHT 43

static NSString* const RECENT_CALL_TABLE_CELL_IDENTIFIER = @"CallLogTableViewCell";

typedef NSComparisonResult (^CallComparator)(RecentCall*, RecentCall*);

@interface CallLogViewController ()

@property (strong, nonatomic) NSArray* recents;
@property (strong, nonatomic) NSString* searchTerm;
@property (nonatomic) BOOL tableViewContentMutating;

@end

@implementation CallLogViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self observeRecentCalls];
    [self observeKeyboardNotifications];
    self.searchBarTitleView.titleLabel.text = RECENT_NAV_BAR_TITLE;
    self.recentCallsTableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
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

    [observableRecents watchLatestValue:^(NSArray* latestRecents) {
        if (self.searchTerm) {
            self.recents = [Environment.getCurrent.recentCallManager recentsForSearchString:self.searchTerm
                                                                         andExcludeArchived:NO];
        } else {
            self.recents = latestRecents;
        }
        
        if (!self.tableViewContentMutating) {
            [self.recentCallsTableView reloadData];
        }
    } onThread:[NSThread mainThread] untilCancelled:nil];
}

- (void)deleteRecentCallAtIndexPath:(NSIndexPath*)indexPath {
    [self.recentCallsTableView beginUpdates];
    [self.recentCallsTableView deleteRowsAtIndexPaths:@[indexPath]
                                     withRowAnimation:UITableViewRowAnimationLeft];

    RecentCall* recent;

    [Environment.getCurrent.recentCallManager removeRecentCall:recent];

    [self.recentCallsTableView endUpdates];
}

#pragma mark - UITableViewDelegate

- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.recents.count;
}

- (UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath {
    CallLogTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:RECENT_CALL_TABLE_CELL_IDENTIFIER];
    if (!cell) {
        cell = [[CallLogTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                           reuseIdentifier:RECENT_CALL_TABLE_CELL_IDENTIFIER];
        cell.delegate = self;
    }
    RecentCall* recent = self.recents[(NSUInteger)indexPath.row];
    [cell configureWithRecentCall:recent];

    return cell;
}

- (CGFloat)tableView:(UITableView*)tableView heightForRowAtIndexPath:(NSIndexPath*)indexPath {
    return RECENT_CALL_TABLE_CELL_HEIGHT;
}

#pragma mark - RecentCallTableViewCellDelegate

- (void)recentCallTableViewCellTappedDelete:(CallLogTableViewCell*)cell {
    self.tableViewContentMutating = YES;
    NSIndexPath* indexPath = [self.recentCallsTableView indexPathForCell:cell];

    [self.recentCallsTableView beginUpdates];
    [self.recentCallsTableView deleteRowsAtIndexPaths:@[indexPath]
                                  withRowAnimation:UITableViewRowAnimationLeft];

    RecentCall *recent = self.recents[(NSUInteger)indexPath.row];
    [Environment.getCurrent.recentCallManager removeRecentCall:recent];

    [self.recentCallsTableView endUpdates];
    self.tableViewContentMutating = NO;
}

- (void)recentCallTableViewCellTappedCall:(CallLogTableViewCell*)cell {
    NSIndexPath* indexPath = [self.recentCallsTableView indexPathForCell:cell];
    RecentCall* recent = self.recents[(NSUInteger)indexPath.row];
    [(TabBarParentViewController*)self.mm_drawerController.centerViewController showDialerViewControllerWithNumber:recent.phoneNumber];
}

#pragma mark - SearchBarTitleViewDelegate

- (void)searchBarTitleView:(SearchBarTitleView*)view didSearchForTerm:(NSString*)term {
    self.searchTerm = term;
    self.recents = [Environment.getCurrent.recentCallManager recentsForSearchString:term
                                                                 andExcludeArchived:NO];
    [self.recentCallsTableView reloadData];
}

- (void)searchBarTitleViewDidTapMenu:(SearchBarTitleView*)view {
    [self.mm_drawerController openDrawerSide:MMDrawerSideLeft
                                    animated:YES
                                  completion:nil];
}

- (void)searchBarTitleViewDidEndSearching:(SearchBarTitleView*)view {
    self.searchTerm = nil;
    self.recents = [Environment.getCurrent.recentCallManager recentsForSearchString:nil
                                                                 andExcludeArchived:NO];
    [self.recentCallsTableView reloadData];
}

#pragma mark - Keyboard

- (void)keyboardWillShow:(NSNotification*)notification {
    double duration = [[notification userInfo][UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    [UIView animateWithDuration:duration animations:^{
        CGSize keyboardSize = [[notification userInfo][UIKeyboardFrameBeginUserInfoKey] CGRectValue].size;
        CGFloat height = CGRectGetHeight(self.recentCallsTableView.frame) - (keyboardSize.height-BOTTOM_TAB_BAR_HEIGHT);
        self.recentCallsTableView.frame = CGRectMake(CGRectGetMinX(self.recentCallsTableView.frame),
                                                     CGRectGetMinY(self.recentCallsTableView.frame),
                                                     CGRectGetWidth(self.recentCallsTableView.frame),
                                                     height);
    }];
}

- (void)keyboardWillHide:(NSNotification*)notification {
    CGSize keyboardSize = [[notification userInfo][UIKeyboardFrameEndUserInfoKey] CGRectValue].size;
    CGFloat height = CGRectGetHeight(self.recentCallsTableView.frame) + (keyboardSize.height-BOTTOM_TAB_BAR_HEIGHT);
    self.recentCallsTableView.frame = CGRectMake(CGRectGetMinX(self.recentCallsTableView.frame),
                                                 CGRectGetMinY(self.recentCallsTableView.frame),
                                                 CGRectGetWidth(self.recentCallsTableView.frame),
                                                 height);
}

@end
