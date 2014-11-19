#import <UIKit/UIKit.h>

/**
 *
 * The last cell of Inbox feed that displays an active count of the items left to be archived/deleted
 *
 */

@interface InboxFeedFooterCell : UITableViewCell

@property (strong, nonatomic) IBOutlet UILabel* inboxCountLabel;
@property (strong, nonatomic) IBOutlet UILabel* inboxMessageLabelFirst;
@property (strong, nonatomic) IBOutlet UILabel* inboxMessageLabelSecond;

@end
