#import <UIKit/UIKit.h>
#import "ContactsManager.h"

/**
 *
 * FavouriteTableViewCell displays a contact from a Contact object.
 *
 */

@class FavouriteTableViewCell;

@protocol FavouriteTableViewCellDelegate <NSObject>
- (void)favouriteTableViewCellTappedCall:(FavouriteTableViewCell*)cell;
@end


@interface FavouriteTableViewCell : UITableViewCell

@property (strong, nonatomic) IBOutlet UILabel* nameLabel;
@property (strong, nonatomic) IBOutlet UIImageView* contactPictureView;
@property (weak, nonatomic) id<FavouriteTableViewCellDelegate> delegate;

- (void)configureWithContact:(Contact*)contact;
- (IBAction)callTapped;

@end
