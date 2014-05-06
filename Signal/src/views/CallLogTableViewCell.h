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

- (void)recentCallTableViewCellTappedDelete:(CallLogTableViewCell *)cell;
- (void)recentCallTableViewCellTappedCall:(CallLogTableViewCell *)cell;

@end

@interface CallLogTableViewCell : UITableViewCell <UIScrollViewDelegate>

@property (nonatomic, strong) IBOutlet UILabel *contactNameLabel;
@property (nonatomic, strong) IBOutlet UILabel *contactNumberLabel;
@property (nonatomic, strong) IBOutlet UILabel *timeLabel;
@property (nonatomic, strong) IBOutlet UIImageView *callTypeImageView;
@property (nonatomic, strong) IBOutlet NextResponderScrollView *scrollView;
@property (nonatomic, strong) IBOutlet UIView *contentContainerView;
@property (nonatomic, strong) IBOutlet UIView *deleteView;
@property (nonatomic, strong) IBOutlet UIImageView *deleteImageView;
@property (nonatomic, assign) id<CallLogTableViewCellDelegate> delegate;

- (void)configureWithRecentCall:(RecentCall *)recentCall;
- (IBAction)phoneCallButtonTapped;

@end
