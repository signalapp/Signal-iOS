#import "ContactDetailTableViewCell.h"
#import "LocalizableText.h"
#import "PhoneNumber.h"
#import "Environment.h"
#import "PhoneNumberDirectoryFilter.h"
#import "PhoneNumberDirectoryFilterManager.h"

#define INFO_DISPLAY_LABEL_DEFAULT_WIDTH 202

@implementation ContactDetailTableViewCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString*)reuseIdentifier {
    self = [[NSBundle.mainBundle loadNibNamed:NSStringFromClass([self class]) owner:self options:nil] firstObject];
    return self;
}

- (NSString*)reuseIdentifier {
    return NSStringFromClass([self class]);
}

- (void)configureWithPhoneNumber:(PhoneNumber*)phoneNumber isSecure:(BOOL)isSecure {
    self.infoDisplayLabel.frame = CGRectMake(self.infoDisplayLabel.frame.origin.x,
                                             self.infoDisplayLabel.frame.origin.y,
                                             INFO_DISPLAY_LABEL_DEFAULT_WIDTH,
                                             CGRectGetHeight(self.infoDisplayLabel.frame));

    self.infoDisplayLabel.text = phoneNumber.localizedDescriptionForUser;
        
    if (isSecure) {
        self.infoTypeLabel.text = CONTACT_DETAIL_COMM_TYPE_SECURE;
    } else {
        self.infoTypeLabel.text = CONTACT_DETAIL_COMM_TYPE_INSECURE;
    }
}

- (void)configureWithEmailString:(NSString*)emailString {
    self.infoTypeLabel.text = CONTACT_DETAIL_COMM_TYPE_EMAIL;
    self.infoDisplayLabel.text = emailString;
}

- (void)configureWithNotes:(NSString*)notes {
    self.infoDisplayLabel.frame = CGRectMake(self.infoDisplayLabel.frame.origin.x,
                                             self.infoDisplayLabel.frame.origin.y,
                                             (CGFloat)(fabs(self.infoDisplayLabel.frame.origin.x - CGRectGetWidth(self.frame))),
                                             CGRectGetHeight(self.infoDisplayLabel.frame));
    self.infoDisplayLabel.text = notes;
    self.infoTypeLabel.text = CONTACT_DETAIL_COMM_TYPE_NOTES;
}

@end
