#import <UIKit/UIKit.h>
#import "SearchBarTitleView.h"
#import "FavouriteTableViewCell.h"

/**
 *
 * FavouritesViewController displays a table view of favourites obtained through the ContactsManager
 * 
 */

@interface FavouritesViewController : UIViewController <UITableViewDataSource, UITableViewDelegate, SearchBarTitleViewDelegate, FavouriteTableViewCellDelegate>

@property (strong, nonatomic) IBOutlet SearchBarTitleView* searchBarTitleView;
@property (strong, nonatomic) IBOutlet UITableView* favouriteTableView;

@end
