#import "InboxFeedFooterCell.h"
#import "RecentCallManager.h"
#import "LocalizableText.h"

@implementation InboxFeedFooterCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString*)reuseIdentifier {
    self = [[NSBundle.mainBundle loadNibNamed:NSStringFromClass([self class]) owner:self options:nil] firstObject];
    
    if (self) {
        ObservableValue* recentCallObserver = Environment.getCurrent.recentCallManager.getObservableRecentCalls;
        [recentCallObserver watchLatestValue:^(id latestValue) {
            NSUInteger inboxCount = [[Environment.getCurrent.recentCallManager recentsForSearchString:nil andExcludeArchived:YES] count];
            if (inboxCount == 0) {
                self.inboxCountLabel.text = @"";
                self.inboxMessageLabelFirst.text = HOME_FOOTER_FIRST_MESSAGE_CALLS_NIL;
                self.inboxMessageLabelSecond.text = HOME_FOOTER_SECOND_MESSAGE_CALLS_NIL;
            } else {
                self.inboxCountLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)inboxCount];
                self.inboxMessageLabelFirst.text = HOME_FOOTER_FIRST_MESSAGE_CALLS_UNSORTED;
                self.inboxMessageLabelSecond.text = inboxCount == 1 ? HOME_FOOTER_SECOND_MESSAGE_CALL_UNSORTED : HOME_FOOTER_SECOND_MESSAGE_CALLS_UNSORTED;
            }
        } onThread:NSThread.mainThread untilCancelled:nil];
    }
    return self;
}

- (NSString*)reuseIdentifier {
    return NSStringFromClass([self class]);
}

@end
