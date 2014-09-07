#import "CallLogTableViewCell.h"
#import "Environment.h"
#import "ContactsManager.h"
#import "PreferencesUtil.h"
#import "LocalizableText.h"
#import "Util.h"

#define DELETE_IMAGE_VIEW_WIDTH 19.0f

@implementation CallLogTableViewCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {

    self = [NSBundle.mainBundle loadNibNamed:NSStringFromClass(self.class)
                                          owner:self
                                        options:nil][0];
    if (self) {
        _scrollView.contentSize = CGSizeMake(CGRectGetWidth(_contentContainerView.bounds),
                                             CGRectGetHeight(_scrollView.frame));
        _deleteImageView.image = [_deleteImageView.image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    }
    return self;
}

- (NSString *)reuseIdentifier {
    return NSStringFromClass(self.class);
}

- (void)prepareForReuse {
    _scrollView.contentOffset = CGPointMake(0, 0);
    [super prepareForReuse];
}

- (void)configureWithRecentCall:(RecentCall *)recentCall {
    Contact *contact = [Environment.getCurrent.contactsManager latestContactWithRecordId:recentCall.contactRecordID];
    if (contact) {
        _contactNameLabel.text = contact.fullName;
    } else {
        _contactNameLabel.text = UNKNOWN_CONTACT_NAME;
    }

    if (recentCall.callType == RPRecentCallTypeOutgoing) {
        _callTypeImageView.image = [UIImage imageNamed:CALL_TYPE_IMAGE_NAME_OUTGOING];
    } else {
        _callTypeImageView.image = [UIImage imageNamed:CALL_TYPE_IMAGE_NAME_INCOMING];
    }

    _contactNumberLabel.text = recentCall.phoneNumber.localizedDescriptionForUser;

    if ([DateUtil dateIsOlderThanOneWeek:[recentCall date]]) {
        _timeLabel.text = [[DateUtil dateFormatter] stringFromDate:[recentCall date]];
    } else {
        _timeLabel.text = [[DateUtil weekdayFormatter] stringFromDate:[recentCall date]];
    }
}

#pragma mark - UIScrollViewDelegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
	
    if (scrollView.contentOffset.x > CGRectGetWidth(_deleteView.frame)) {
        _deleteImageView.tintColor = [UIUtil redColor];

        _deleteImageView.bounds = CGRectMake(_deleteImageView.bounds.origin.x,
                                             _deleteImageView.bounds.origin.y,
                                             DELETE_IMAGE_VIEW_WIDTH,
                                             _deleteImageView.bounds.size.height);
    } else {
        
        double ratio = _scrollView.contentOffset.x / CGRectGetWidth(_deleteView.frame);
        double newWidth = DELETE_IMAGE_VIEW_WIDTH/2 + (DELETE_IMAGE_VIEW_WIDTH * ratio)/2.0f;
        
        _deleteImageView.bounds = CGRectMake(_deleteImageView.bounds.origin.x,
                                             _deleteImageView.bounds.origin.y,
                                             (CGFloat)newWidth,
                                             _deleteImageView.bounds.size.height);
        _deleteImageView.tintColor = UIColor.whiteColor;
    }
}

- (void)scrollViewWillEndDragging:(UIScrollView *)scrollView
                     withVelocity:(CGPoint)velocity
              targetContentOffset:(inout CGPoint *)targetContentOffset {

    if (scrollView.contentOffset.x > CGRectGetWidth(_deleteView.frame)) {
        [_delegate recentCallTableViewCellTappedDelete:self];
    } else {
        *targetContentOffset = CGPointMake(0, 0);
    }
}

#pragma mark - Actions

- (IBAction)phoneCallButtonTapped {
    [_delegate recentCallTableViewCellTappedCall:self];
}

@end
