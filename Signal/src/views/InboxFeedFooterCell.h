#import <UIKit/UIKit.h>

/**
 *
 * The last cell of Inbox feed that displays an active count of the items left to be archived/deleted
 *
 */

@interface InboxFeedFooterCell : UITableViewCell

@property (nonatomic, strong) IBOutlet UILabel *inboxCountLabel;
@property (nonatomic, strong) IBOutlet UILabel *inboxMessageLabelFirst;
@property (nonatomic, strong) IBOutlet UILabel *inboxMessageLabelSecond;

@end
