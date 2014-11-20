#import "CallLogTableViewCell.h"
#import "Environment.h"
#import "ContactsManager.h"
#import "PropertyListPreferences+Util.h"
#import "LocalizableText.h"
#import "Util.h"

#define DELETE_IMAGE_VIEW_WIDTH 19.0f

@implementation CallLogTableViewCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString*)reuseIdentifier {

    self = [NSBundle.mainBundle loadNibNamed:NSStringFromClass([self class])
                                         owner:self
                                       options:nil][0];
    if (self) {
        self.scrollView.contentSize = CGSizeMake(CGRectGetWidth(self.contentContainerView.bounds),
                                                 CGRectGetHeight(self.scrollView.frame));
        self.deleteImageView.image = [self.deleteImageView.image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    }
    
    return self;
}

- (NSString*)reuseIdentifier {
    return NSStringFromClass([self class]);
}

- (void)prepareForReuse {
    self.scrollView.contentOffset = CGPointMake(0, 0);
    [super prepareForReuse];
}

- (void)configureWithRecentCall:(RecentCall*)recentCall {
    Contact* contact = [Environment.getCurrent.contactsManager latestContactWithRecordId:recentCall.contactRecordID];
    if (contact) {
        self.contactNameLabel.text = contact.fullName;
    } else {
        self.contactNameLabel.text = UNKNOWN_CONTACT_NAME;
    }

    if (recentCall.callType == RPRecentCallTypeOutgoing) {
        self.callTypeImageView.image = [UIImage imageNamed:CALL_TYPE_IMAGE_NAME_OUTGOING];
    } else {
        self.callTypeImageView.image = [UIImage imageNamed:CALL_TYPE_IMAGE_NAME_INCOMING];
    }

    self.contactNumberLabel.text = recentCall.phoneNumber.localizedDescriptionForUser;

    if ([DateUtil dateIsOlderThanOneWeek:[recentCall date]]) {
        self.timeLabel.text = [DateUtil.dateFormatter stringFromDate:[recentCall date]];
    } else {
        self.timeLabel.text = [DateUtil.weekdayFormatter stringFromDate:[recentCall date]];
    }
}

#pragma mark - UIScrollViewDelegate

- (void)scrollViewDidScroll:(UIScrollView*)scrollView {
	
    if (scrollView.contentOffset.x > CGRectGetWidth(_deleteView.frame)) {
        self.deleteImageView.tintColor = UIUtil.redColor;

        self.deleteImageView.bounds = CGRectMake(self.deleteImageView.bounds.origin.x,
                                                 self.deleteImageView.bounds.origin.y,
                                                 DELETE_IMAGE_VIEW_WIDTH,
                                                 self.deleteImageView.bounds.size.height);
    } else {
        
        double ratio = self.scrollView.contentOffset.x / CGRectGetWidth(_deleteView.frame);
        double newWidth = DELETE_IMAGE_VIEW_WIDTH/2 + (DELETE_IMAGE_VIEW_WIDTH * ratio)/2.0f;
        
        self.deleteImageView.bounds = CGRectMake(self.deleteImageView.bounds.origin.x,
                                                 self.deleteImageView.bounds.origin.y,
                                                 (CGFloat)newWidth,
                                                 self.deleteImageView.bounds.size.height);
        self.deleteImageView.tintColor = UIColor.whiteColor;
    }
}

- (void)scrollViewWillEndDragging:(UIScrollView*)scrollView
                     withVelocity:(CGPoint)velocity
              targetContentOffset:(inout CGPoint*)targetContentOffset {

    if (scrollView.contentOffset.x > CGRectGetWidth(self.deleteView.frame)) {
        // Prevents weak warning, see http://stackoverflow.com/a/11899135/3577738
        id delegate = self.delegate;
        [delegate recentCallTableViewCellTappedDelete:self];
    } else {
        *targetContentOffset = CGPointMake(0, 0);
    }
}

#pragma mark - Actions

- (IBAction)phoneCallButtonTapped {
    id delegate = self.delegate;
    [delegate recentCallTableViewCellTappedCall:self];
}

@end
