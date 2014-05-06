#import <UIKit/UIKit.h>

#import "ContactBrowseViewController.h"
#import "ContactsManager.h"
#import "FutureSource.h"
#import "TabBarParentViewController.h"

/**
 *
 * LeftSideMenuViewController is the nav bin view controller which can be swiped in from the left and/or tapped open from a button
 *
 */

@interface LeftSideMenuViewController : UIViewController <UITableViewDelegate, UITableViewDataSource>

@property (nonatomic, strong) TabBarParentViewController *centerTabBarViewController;
@property (nonatomic, strong) IBOutlet UITableView *menuOptionTableView;
@property (nonatomic, strong) IBOutlet UIView *firstSectionHeaderView;
@property (nonatomic, strong) IBOutlet UIView *secondSectionHeaderView;

- (void)showDialerViewController;
- (void)showContactsViewController;
- (void)showRecentsViewController;
- (void)showFavouritesViewController;

@end
