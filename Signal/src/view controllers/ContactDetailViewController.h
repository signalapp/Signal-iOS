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

@property (nonatomic, strong) IBOutlet UIButton *favouriteButton;
@property (nonatomic, strong) IBOutlet UIView *secureInfoHeaderView;
@property (nonatomic, strong) IBOutlet UILabel *contactNameLabel;
@property (nonatomic, strong) IBOutlet UIImageView *contactImageView;
@property (nonatomic, strong) IBOutlet UITableView *contactInfoTableView;

@property (nonatomic, readonly) Contact *contact;

+ (ContactDetailViewController *)contactDetailViewControllerWithContact:(Contact *)contact;

- (IBAction)favouriteButtonTapped;

@end
