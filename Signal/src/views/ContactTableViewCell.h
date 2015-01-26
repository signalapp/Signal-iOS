#import <UIKit/UIKit.h>
#import "ContactsManager.h"

/**
 *
 * ContactTableViewCell displays a contact from a Contact object.
 *
 */

@interface ContactTableViewCell : UITableViewCell

@property (nonatomic, strong) IBOutlet UILabel *nameLabel;
@property (nonatomic, strong) IBOutlet UIButton *callButton ;

@property BOOL shouldShowContactButtons;

- (void)configureWithContact:(Contact *)contact;
-(IBAction)callContact:(id)sender;
@end
