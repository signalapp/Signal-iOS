#import <UIKit/UIKit.h>


@interface TodoCell : UITableViewCell

@property (nonatomic, weak) id <NSObject> delegate;

@property (nonatomic, weak) IBOutlet UIButton *checkmarkButton;
@property (nonatomic, weak) IBOutlet UILabel *titleLabel;

@end

@protocol TodoCellDelegate
@optional

- (void)didTapImageViewInCell:(TodoCell *)sender;

@end