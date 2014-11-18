#import <UIKit/UIKit.h>

#import "ContactsManager.h"
#import "CallLogTableViewCell.h"
#import "SearchBarTitleView.h"

@interface CallLogViewController : UIViewController <UITableViewDataSource, UITableViewDelegate, CallLogTableViewCellDelegate, SearchBarTitleViewDelegate>

@property (strong, nonatomic) IBOutlet SearchBarTitleView *searchBarTitleView;
@property (strong, nonatomic) IBOutlet UITableView *recentCallsTableView;

@end
