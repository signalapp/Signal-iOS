#import "InboxFeedTableViewCell.h"
#import "LocalizableText.h"
#import "Environment.h"
#import "Util.h"

#define ARCHIVE_IMAGE_VIEW_WIDTH 22.0f
#define DELETE_IMAGE_VIEW_WIDTH 19.0f
#define TIME_LABEL_SIZE 10
#define DATE_LABEL_SIZE 13

#define MISSED_CALL_VIEW_CORNER_RADIUS 6.0f

@implementation InboxFeedTableViewCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [[NSBundle mainBundle] loadNibNamed:NSStringFromClass([self class])
                                          owner:self
                                        options:nil][0];


    if (self) {
        _scrollView.contentSize = CGSizeMake(CGRectGetWidth(_contentContainerView.bounds),
                                             CGRectGetHeight(_scrollView.frame));

        [UIUtil applyRoundedBorderToImageView:&_contactPictureView];
        
        _scrollView.contentOffset				= CGPointMake(CGRectGetWidth(_archiveView.frame), 0);
        _missedCallView.layer.cornerRadius		= MISSED_CALL_VIEW_CORNER_RADIUS;
        _deleteImageView.image = [_deleteImageView.image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        _archiveImageView.image = [_archiveImageView.image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    }
    return self;
}

- (NSString *)reuseIdentifier {
    return NSStringFromClass([self class]);
}

- (void)configureWithRecentCall:(RecentCall *)recentCall {
    Contact *contact = [[[Environment getCurrent] contactsManager] latestContactWithRecordId:recentCall.contactRecordID];

    if (contact) {
        _nameLabel.text = contact.fullName;
        if (contact.image) {
            _contactPictureView.image = contact.image;
        } else {
            _contactPictureView.image = nil;
        }
    } else {
        _nameLabel.text = UNKNOWN_CONTACT_NAME;
        _contactPictureView.image = nil;
    }

    if (recentCall.callType == RPRecentCallTypeOutgoing) {
        _callTypeImageView.image = [UIImage imageNamed:CALL_TYPE_IMAGE_NAME_OUTGOING];
    } else {
        _callTypeImageView.image = [UIImage imageNamed:CALL_TYPE_IMAGE_NAME_INCOMING];
    }

    _missedCallView.hidden = recentCall.userNotified;
    _numberLabel.text = recentCall.phoneNumber.localizedDescriptionForUser;
    _timeLabel.attributedText = [self dateArrributedString:[recentCall date]];
}

#pragma mark - Date formatting

- (NSAttributedString *)dateArrributedString:(NSDate *)date {

    NSString *dateString;
    NSString *timeString = [[DateUtil timeFormatter] stringFromDate:date];

      
    if ([DateUtil dateIsOlderThanOneWeek:date]) {
        dateString = [[DateUtil dateFormatter] stringFromDate:date];
    } else {
        dateString = [[DateUtil weekdayFormatter] stringFromDate:date];
    }

    NSMutableAttributedString *attributedString = [[NSMutableAttributedString alloc] initWithString:[timeString stringByAppendingString:dateString]];

    [attributedString addAttribute:NSForegroundColorAttributeName
                             value:[UIColor darkGrayColor]
                             range:NSMakeRange(0, timeString.length)];

    [attributedString addAttribute:NSForegroundColorAttributeName
                             value:[UIUtil darkBackgroundColor]
                             range:NSMakeRange(timeString.length,dateString.length)];

    [attributedString addAttribute:NSFontAttributeName
                             value:[UIUtil helveticaLightWithSize:TIME_LABEL_SIZE]
                             range:NSMakeRange(0, timeString.length)];

    [attributedString addAttribute:NSFontAttributeName
                             value:[UIUtil helveticaRegularWithSize:DATE_LABEL_SIZE]
                             range:NSMakeRange(timeString.length,dateString.length)];

    return attributedString;
}

#pragma mark - UIScrollViewDelegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {

    if (_scrollView.contentOffset.x < 0) {
        _archiveImageView.tintColor = [UIUtil redColor];
        _archiveImageView.bounds = CGRectMake(_archiveImageView.bounds.origin.x,
                                              _archiveImageView.bounds.origin.y,
                                              ARCHIVE_IMAGE_VIEW_WIDTH,
                                              _archiveImageView.bounds.size.height);
    } else {

        double ratio = (_archiveView.frame.size.width/2.0f - _scrollView.contentOffset.x) / (_archiveView.frame.size.width/2.0f);
        double newWidth = ARCHIVE_IMAGE_VIEW_WIDTH/2 + (ARCHIVE_IMAGE_VIEW_WIDTH * ratio)/2.0f;
        _archiveImageView.bounds = CGRectMake(_archiveImageView.bounds.origin.x,
                                              _archiveImageView.bounds.origin.y,
                                              (CGFloat)newWidth,
                                              _archiveImageView.bounds.size.height);
        _archiveImageView.tintColor = [UIColor whiteColor];

    }

    if (scrollView.contentOffset.x > CGRectGetWidth(_archiveView.frame)*2) {
        _deleteImageView.tintColor = [UIUtil redColor];
        _deleteImageView.bounds = CGRectMake(_deleteImageView.bounds.origin.x,
                                             _deleteImageView.bounds.origin.y,
                                             DELETE_IMAGE_VIEW_WIDTH,
                                             _deleteImageView.bounds.size.height);
    } else {

        double ratio = _scrollView.contentOffset.x / (CGRectGetWidth(_deleteView.frame)*2);
        double newWidth = DELETE_IMAGE_VIEW_WIDTH/2 + (DELETE_IMAGE_VIEW_WIDTH * ratio)/2.0f;
        
        _deleteImageView.bounds = CGRectMake(_deleteImageView.bounds.origin.x,
                                             _deleteImageView.bounds.origin.y,
                                             (CGFloat)newWidth,
                                             _deleteImageView.bounds.size.height);
        _deleteImageView.tintColor = [UIColor whiteColor];
    }
}

- (void)scrollViewWillEndDragging:(UIScrollView *)scrollView
                     withVelocity:(CGPoint)velocity
              targetContentOffset:(inout CGPoint *)targetContentOffset {
	
    if (_scrollView.contentOffset.x < 0) {
        [_delegate inboxFeedTableViewCellTappedArchive:self];
    } else {
        *targetContentOffset = CGPointMake(CGRectGetWidth(_archiveView.frame), 0);
    }

    if (scrollView.contentOffset.x > CGRectGetWidth(_archiveView.frame)*2) {
        [_delegate inboxFeedTableViewCellTappedDelete:self];
    } else {
        *targetContentOffset = CGPointMake(CGRectGetWidth(_archiveView.frame), 0);
    }
}

@end
