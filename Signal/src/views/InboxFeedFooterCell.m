#import "InboxFeedFooterCell.h"
#import "RecentCallManager.h"
#import "LocalizableText.h"

@implementation InboxFeedFooterCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [[NSBundle mainBundle] loadNibNamed:NSStringFromClass([self class]) owner:self options:nil][0];
    if (self) {
        ObservableValue *recentCallObserver = [[[Environment getCurrent] recentCallManager] getObservableRecentCalls];
        [recentCallObserver watchLatestValue:^(id latestValue) {
            NSUInteger inboxCount = [[[[Environment getCurrent] recentCallManager] recentsForSearchString:nil andExcludeArchived:YES] count];
            if (inboxCount == 0) {
                _inboxCountLabel.text = @"";
                _inboxMessageLabelFirst.text = HOME_FOOTER_FIRST_MESSAGE_CALLS_NIL;
                _inboxMessageLabelSecond.text = HOME_FOOTER_SECOND_MESSAGE_CALLS_NIL;
            } else {
                _inboxCountLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)inboxCount];
                _inboxMessageLabelFirst.text = HOME_FOOTER_FIRST_MESSAGE_CALLS_UNSORTED;
                _inboxMessageLabelSecond.text = inboxCount == 1 ? HOME_FOOTER_SECOND_MESSAGE_CALL_UNSORTED : HOME_FOOTER_SECOND_MESSAGE_CALLS_UNSORTED;
            }
        } onThread:[NSThread mainThread] untilCancelled:nil];
    }
    return self;
}

- (NSString *)reuseIdentifier {
    return NSStringFromClass([self class]);
}

@end
