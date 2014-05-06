#import <UIKit/UIKit.h>
#import "Contact.h"

@interface UnseenWhisperUserCell : UITableViewCell

@property (nonatomic, strong) IBOutlet UILabel *nameLabel;
@property (nonatomic, strong) IBOutlet UILabel *numberLabel;

- (void)configureWithContact:(Contact *)contact;

@end
