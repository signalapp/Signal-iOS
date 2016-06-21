#import <UIKit/UIKit.h>

@interface MYTableViewCell : UITableViewCell

@property (nonatomic, weak) IBOutlet UIView *customHighlightView;
@property (nonatomic, weak) IBOutlet UILabel *nameLabel;

- (void)flash;

@end
