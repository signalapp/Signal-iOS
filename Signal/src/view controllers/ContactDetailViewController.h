#import <UIKit/UIKit.h>

#import "Contact.h"
#import "ContactDetailTableViewCell.h"
#import "PhoneNumberDirectoryFilterManager.h"

/**
 *
 * ContactDetailViewController displays information about a contact in a table view such as additional non-encryped communication methods.
 * Any additional non-encrypted information is opened in an external application (Email, SMS, Phone)
 *
 */

@interface ContactDetailViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>

@property (strong, nonatomic) IBOutlet UIButton* favouriteButton;
@property (strong, nonatomic) IBOutlet UIView* secureInfoHeaderView;
@property (strong, nonatomic) IBOutlet UILabel* contactNameLabel;
@property (strong, nonatomic) IBOutlet UIImageView* contactImageView;
@property (strong, nonatomic) IBOutlet UITableView* contactInfoTableView;

@property (strong, readonly, nonatomic) Contact* contact;

- (instancetype)initWithContact:(Contact*)contact;

- (IBAction)favouriteButtonTapped;

@end
