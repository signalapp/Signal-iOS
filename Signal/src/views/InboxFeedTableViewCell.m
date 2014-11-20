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

@synthesize contactPictureView = _contactPictureView;

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString*)reuseIdentifier {
    self = [NSBundle.mainBundle loadNibNamed:NSStringFromClass([self class])
                                          owner:self
                                        options:nil][0];


    if (self) {
        self.scrollView.contentSize = CGSizeMake(CGRectGetWidth(self.contentContainerView.bounds),
                                                 CGRectGetHeight(self.scrollView.frame));

        [UIUtil applyRoundedBorderToImageView:&_contactPictureView];
        
        self.scrollView.contentOffset          = CGPointMake(CGRectGetWidth(self.archiveView.frame), 0);
        self.missedCallView.layer.cornerRadius = MISSED_CALL_VIEW_CORNER_RADIUS;
        self.deleteImageView.image             = [self.deleteImageView.image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        self.archiveImageView.image            = [self.archiveImageView.image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    }
    
    return self;
}

- (NSString*)reuseIdentifier {
    return NSStringFromClass([self class]);
}

- (void)configureWithRecentCall:(RecentCall*)recentCall {
    Contact* contact = [Environment.getCurrent.contactsManager latestContactWithRecordId:recentCall.contactRecordID];

    if (contact) {
        self.nameLabel.text = contact.fullName;
        if (contact.image) {
            self.contactPictureView.image = contact.image;
        } else {
            self.contactPictureView.image = nil;
        }
    } else {
        self.nameLabel.text = UNKNOWN_CONTACT_NAME;
        self.contactPictureView.image = nil;
    }

    if (recentCall.callType == RPRecentCallTypeOutgoing) {
        self.callTypeImageView.image = [UIImage imageNamed:CALL_TYPE_IMAGE_NAME_OUTGOING];
    } else {
        self.callTypeImageView.image = [UIImage imageNamed:CALL_TYPE_IMAGE_NAME_INCOMING];
    }

    self.missedCallView.hidden    = recentCall.userNotified;
    self.numberLabel.text         = recentCall.phoneNumber.localizedDescriptionForUser;
    self.timeLabel.attributedText = [self dateArrributedString:[recentCall date]];
}

#pragma mark - Date formatting

- (NSAttributedString*)dateArrributedString:(NSDate*)date {

    NSString* dateString;
    NSString* timeString = [DateUtil.timeFormatter stringFromDate:date];

      
    if ([DateUtil dateIsOlderThanOneWeek:date]) {
        dateString = [DateUtil.dateFormatter stringFromDate:date];
    } else {
        dateString = [DateUtil.weekdayFormatter stringFromDate:date];
    }

    NSMutableAttributedString *attributedString = [[NSMutableAttributedString alloc] initWithString:[timeString stringByAppendingString:dateString]];

    [attributedString addAttribute:NSForegroundColorAttributeName
                             value:UIColor.darkGrayColor
                             range:NSMakeRange(0, timeString.length)];

    [attributedString addAttribute:NSForegroundColorAttributeName
                             value:UIUtil.darkBackgroundColor
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

- (void)scrollViewDidScroll:(UIScrollView*)scrollView {

    if (self.scrollView.contentOffset.x < 0) {
        self.archiveImageView.tintColor = UIUtil.redColor;
        self.archiveImageView.bounds = CGRectMake(self.archiveImageView.bounds.origin.x,
                                                  self.archiveImageView.bounds.origin.y,
                                                  ARCHIVE_IMAGE_VIEW_WIDTH,
                                                  self.archiveImageView.bounds.size.height);
    } else {

        double ratio = (self.archiveView.frame.size.width/2.0f - self.scrollView.contentOffset.x) / (self.archiveView.frame.size.width/2.0f);
        double newWidth = ARCHIVE_IMAGE_VIEW_WIDTH/2 + (ARCHIVE_IMAGE_VIEW_WIDTH * ratio)/2.0f;
        self.archiveImageView.bounds = CGRectMake(self.archiveImageView.bounds.origin.x,
                                                  self.archiveImageView.bounds.origin.y,
                                                  (CGFloat)newWidth,
                                                  self.archiveImageView.bounds.size.height);
        self.archiveImageView.tintColor = UIColor.whiteColor;

    }

    if (scrollView.contentOffset.x > CGRectGetWidth(self.archiveView.frame)*2) {
        self.deleteImageView.tintColor = UIUtil.redColor;
        self.deleteImageView.bounds = CGRectMake(self.deleteImageView.bounds.origin.x,
                                                 self.deleteImageView.bounds.origin.y,
                                                 DELETE_IMAGE_VIEW_WIDTH,
                                                 self.deleteImageView.bounds.size.height);
    } else {

        double ratio = self.scrollView.contentOffset.x / (CGRectGetWidth(self.deleteView.frame)*2);
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
    id delegate = self.delegate;
    
    if (self.scrollView.contentOffset.x < 0) {
        [delegate inboxFeedTableViewCellTappedArchive:self];
    } else {
        *targetContentOffset = CGPointMake(CGRectGetWidth(self.archiveView.frame), 0);
    }

    if (scrollView.contentOffset.x > CGRectGetWidth(self.archiveView.frame)*2) {
        [delegate inboxFeedTableViewCellTappedDelete:self];
    } else {
        *targetContentOffset = CGPointMake(CGRectGetWidth(self.archiveView.frame), 0);
    }
}

@end
