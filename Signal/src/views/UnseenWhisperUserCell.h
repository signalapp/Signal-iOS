#import <UIKit/UIKit.h>
#import "Contact.h"

@interface UnseenWhisperUserCell : UITableViewCell

@property (strong, nonatomic) IBOutlet UILabel* nameLabel;
@property (strong, nonatomic) IBOutlet UILabel* numberLabel;

- (void)configureWithContact:(Contact*)contact;

@end
