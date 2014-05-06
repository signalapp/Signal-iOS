#import <UIKit/UIKit.h>

#import "ContactsManager.h"
#import "CallLogTableViewCell.h"
#import "SearchBarTitleView.h"

@interface CallLogViewController : UIViewController <UITableViewDataSource, UITableViewDelegate, CallLogTableViewCellDelegate, SearchBarTitleViewDelegate>

@property (nonatomic, strong) IBOutlet SearchBarTitleView *searchBarTitleView;
@property (nonatomic, strong) IBOutlet UITableView *recentCallsTableView;

@end
