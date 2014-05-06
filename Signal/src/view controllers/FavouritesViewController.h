#import <UIKit/UIKit.h>
#import "SearchBarTitleView.h"
#import "FavouriteTableViewCell.h"

/**
 *
 * FavouritesViewController displays a table view of favourites obtained through the ContactsManager
 * 
 */

@interface FavouritesViewController : UIViewController <UITableViewDataSource, UITableViewDelegate, SearchBarTitleViewDelegate, FavouriteTableViewCellDelegate>

@property (nonatomic, strong) IBOutlet SearchBarTitleView *searchBarTitleView;
@property (nonatomic, strong) IBOutlet UITableView *favouriteTableView;

@end
