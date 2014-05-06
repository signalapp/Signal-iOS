#import <UIKit/UIKit.h>
#import "ContactsManager.h"

/**
 *
 * FavouriteTableViewCell displays a contact from a Contact object.
 *
 */

@class FavouriteTableViewCell;

@protocol FavouriteTableViewCellDelegate <NSObject>
- (void)favouriteTableViewCellTappedCall:(FavouriteTableViewCell *)cell;
@end


@interface FavouriteTableViewCell : UITableViewCell

@property (nonatomic, strong) IBOutlet UILabel *nameLabel;
@property (nonatomic, strong) IBOutlet UIImageView *contactPictureView;
@property (nonatomic, strong) id<FavouriteTableViewCellDelegate> delegate;

- (void)configureWithContact:(Contact *)contact;
- (IBAction)callTapped;

@end
