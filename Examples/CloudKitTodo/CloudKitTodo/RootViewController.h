#import <UIKit/UIKit.h>


@interface RootViewController : UIViewController

@property (nonatomic, weak) IBOutlet UITableView *tableView;

@property (nonatomic, weak) IBOutlet UIView *ckStatusView;
@property (nonatomic, weak) IBOutlet UILabel *ckTopStatusLabel;
@property (nonatomic, weak) IBOutlet UILabel *ckBottomStatusLabel;

- (IBAction)suspendButtonTapped:(id)sender;
- (IBAction)resumeButtonTapped:(id)sender;

@end
