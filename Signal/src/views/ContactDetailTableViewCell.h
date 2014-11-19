#import <UIKit/UIKit.h>
#import "PhoneNumber.h"

/**
 *
 * ContactDetailTableViewCell displays a contact communication item (Phone number, email, notes)
 * This will hide/show SMS/Phone buttons when needed, depending on the item type.
 * The color side view is blue if Whisper number or notes, and green otherwise.
 *
 */

@interface ContactDetailTableViewCell : UITableViewCell

@property (strong, nonatomic) IBOutlet UILabel* infoTypeLabel;
@property (strong, nonatomic) IBOutlet UILabel* infoDisplayLabel;

- (void)configureWithPhoneNumber:(PhoneNumber*)numberString isSecure:(BOOL)isSecure;
- (void)configureWithEmailString:(NSString*)emailString;
- (void)configureWithNotes:(NSString*)notes;

@end
