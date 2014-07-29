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

- (void)inboxFeedTableViewCellTappedDelete:(InboxFeedTableViewCell *)cell;
- (void)inboxFeedTableViewCellTappedArchive:(InboxFeedTableViewCell *)cell;

@end

@interface InboxFeedTableViewCell : UITableViewCell <UIScrollViewDelegate>

@property (nonatomic, strong) IBOutlet UILabel *nameLabel;
@property (nonatomic, strong) IBOutlet UIImageView *contactPictureView;
@property (nonatomic, strong) IBOutlet UIImageView *callTypeImageView;
@property (nonatomic, strong) IBOutlet UILabel *numberLabel;
@property (nonatomic, strong) IBOutlet UILabel *dateTimeLabel;
@property (nonatomic, strong) IBOutlet NextResponderScrollView *scrollView;
@property (nonatomic, strong) IBOutlet UIView *contentContainerView;
@property (nonatomic, strong) IBOutlet UIView *missedCallView;
@property (nonatomic, strong) IBOutlet UIView *deleteView;
@property (nonatomic, strong) IBOutlet UIView *archiveView;
@property (nonatomic, strong) IBOutlet UIImageView *deleteImageView;
@property (nonatomic, strong) IBOutlet UIImageView *archiveImageView;
@property (nonatomic, assign) id<InboxFeedTableViewCellDelegate> delegate;

- (void)configureWithRecentCall:(RecentCall *)recentCall;

@end
