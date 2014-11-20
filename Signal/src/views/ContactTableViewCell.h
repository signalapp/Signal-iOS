#import <UIKit/UIKit.h>
#import "ContactsManager.h"

/**
 *
 * ContactTableViewCell displays a contact from a Contact object.
 *
 */

@interface ContactTableViewCell : UITableViewCell

@property (strong, nonatomic) IBOutlet UILabel* nameLabel;
@property (strong, nonatomic) IBOutlet UIImageView* contactPictureView;

- (void)configureWithContact:(Contact*)contact;

@end
