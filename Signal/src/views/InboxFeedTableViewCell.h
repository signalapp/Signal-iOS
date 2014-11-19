#import <UIKit/UIKit.h>
#import "RecentCall.h"
#import "ContactsManager.h"
#import "NextResponderScrollView.h"

/**
 *
 * InboxFeedTableViewCell displays a non-archived Recent Call object and delegates deleting and archiving.
 * Archiving and deleting is started by the scroll view being scrolled past/below an offset greater than the respective button.
 *
 */

@class InboxFeedTableViewCell;

@protocol InboxFeedTableViewCellDelegate <NSObject>

- (void)inboxFeedTableViewCellTappedDelete:(InboxFeedTableViewCell*)cell;
- (void)inboxFeedTableViewCellTappedArchive:(InboxFeedTableViewCell*)cell;

@end

@interface InboxFeedTableViewCell : UITableViewCell <UIScrollViewDelegate>

@property (strong, nonatomic) IBOutlet UILabel* nameLabel;
@property (strong, nonatomic) IBOutlet UIImageView* contactPictureView;
@property (strong, nonatomic) IBOutlet UIImageView* callTypeImageView;
@property (strong, nonatomic) IBOutlet UILabel* numberLabel;
@property (strong, nonatomic) IBOutlet UILabel* timeLabel;
@property (strong, nonatomic) IBOutlet NextResponderScrollView* scrollView;
@property (strong, nonatomic) IBOutlet UIView* contentContainerView;
@property (strong, nonatomic) IBOutlet UIView* missedCallView;
@property (strong, nonatomic) IBOutlet UIView* deleteView;
@property (strong, nonatomic) IBOutlet UIView* archiveView;
@property (strong, nonatomic) IBOutlet UIImageView* deleteImageView;
@property (strong, nonatomic) IBOutlet UIImageView* archiveImageView;
@property (weak, nonatomic) id<InboxFeedTableViewCellDelegate> delegate;

- (void)configureWithRecentCall:(RecentCall*)recentCall;

@end
