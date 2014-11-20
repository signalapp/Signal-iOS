#import <UIKit/UIKit.h>
#import "RecentCall.h"
#import "Contact.h"
#import "NextResponderScrollView.h"

/**
 *
 * RecentCallTableViewCell displays a Recent Call object and handles deleting by -
 * swiping past an offset greater than the delete button width
 *
 */

@class CallLogTableViewCell;

@protocol CallLogTableViewCellDelegate <NSObject>

- (void)recentCallTableViewCellTappedDelete:(CallLogTableViewCell*)cell;
- (void)recentCallTableViewCellTappedCall:(CallLogTableViewCell*)cell;

@end

@interface CallLogTableViewCell : UITableViewCell <UIScrollViewDelegate>

@property (strong, nonatomic) IBOutlet UILabel* contactNameLabel;
@property (strong, nonatomic) IBOutlet UILabel* contactNumberLabel;
@property (strong, nonatomic) IBOutlet UILabel* timeLabel;
@property (strong, nonatomic) IBOutlet UIImageView* callTypeImageView;
@property (strong, nonatomic) IBOutlet NextResponderScrollView* scrollView;
@property (strong, nonatomic) IBOutlet UIView* contentContainerView;
@property (strong, nonatomic) IBOutlet UIView* deleteView;
@property (strong, nonatomic) IBOutlet UIImageView* deleteImageView;
@property (weak, nonatomic) id<CallLogTableViewCellDelegate> delegate;

- (void)configureWithRecentCall:(RecentCall*)recentCall;
- (IBAction)phoneCallButtonTapped;

@end
