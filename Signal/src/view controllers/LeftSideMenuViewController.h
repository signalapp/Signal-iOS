#import <UIKit/UIKit.h>

#import "ContactBrowseViewController.h"
#import "ContactsManager.h"
#import "TabBarParentViewController.h"

/**
 *
 * LeftSideMenuViewController is the nav bin view controller which can be swiped in from the left and/or tapped open from a button
 *
 */

@interface LeftSideMenuViewController : UIViewController <UITableViewDelegate, UITableViewDataSource>

@property (strong, nonatomic) TabBarParentViewController* centerTabBarViewController;
@property (strong, nonatomic) IBOutlet UITableView* menuOptionTableView;
@property (strong, nonatomic) IBOutlet UIView* firstSectionHeaderView;
@property (strong, nonatomic) IBOutlet UIView* secondSectionHeaderView;

- (void)showDialerViewController;
- (void)showContactsViewController;
- (void)showRecentsViewController;
- (void)showFavouritesViewController;

@end
