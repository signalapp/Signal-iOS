#import <UIKit/UIKit.h>
#import "ContactsManager.h"

/**
 *
 * ContactTableViewCell displays a contact from a Contact object.
 *
 */

@interface ContactTableViewCell : UITableViewCell

@property (nonatomic, strong) IBOutlet UILabel *nameLabel;
@property (nonatomic, strong) IBOutlet UIImageView *contactPictureView;
@property (nonatomic, strong) IBOutlet UIButton *callButton ;
@property (nonatomic, strong) IBOutlet UIButton *messageButton;

@property BOOL shouldShowContactButtons;

- (void)configureWithContact:(Contact *)contact;

@end
