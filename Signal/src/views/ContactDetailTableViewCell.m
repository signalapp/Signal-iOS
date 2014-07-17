#import "ContactDetailTableViewCell.h"
#import "LocalizableText.h"
#import "PhoneNumber.h"
#import "Environment.h"
#import "PhoneNumberDirectoryFilter.h"
#import "PhoneNumberDirectoryFilterManager.h"

#define INFO_DISPLAY_LABEL_DEFAULT_WIDTH 202
@implementation ContactDetailTableViewCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [[NSBundle mainBundle] loadNibNamed:NSStringFromClass([self class]) owner:self options:nil][0];
    return self;
}

- (NSString *)reuseIdentifier {
    return NSStringFromClass([self class]);
}

- (void)configureWithPhoneNumber:(PhoneNumber *)phoneNumber isSecure:(BOOL)isSecure {
    _infoDisplayLabel.frame = CGRectMake(_infoDisplayLabel.frame.origin.x,
                                         _infoDisplayLabel.frame.origin.y,
                                         INFO_DISPLAY_LABEL_DEFAULT_WIDTH,
                                         CGRectGetHeight(_infoDisplayLabel.frame));

    _infoDisplayLabel.text = [phoneNumber localizedDescriptionForUser];
        
    if (isSecure) {
        _infoTypeLabel.text = CONTACT_DETAIL_COMM_TYPE_SECURE;
    } else {
        _infoTypeLabel.text = CONTACT_DETAIL_COMM_TYPE_INSECURE;
    }
}

- (void)configureWithEmailString:(NSString *)emailString {
    _infoTypeLabel.text = CONTACT_DETAIL_COMM_TYPE_EMAIL;
    _infoDisplayLabel.text = emailString;
}

- (void)configureWithNotes:(NSString *)notes {
    _infoDisplayLabel.frame = CGRectMake(_infoDisplayLabel.frame.origin.x,
                                         _infoDisplayLabel.frame.origin.y,
                                         (CGFloat)(fabs(_infoDisplayLabel.frame.origin.x - CGRectGetWidth(self.frame))),
                                         CGRectGetHeight(_infoDisplayLabel.frame));
    _infoDisplayLabel.text = notes;
    _infoTypeLabel.text = CONTACT_DETAIL_COMM_TYPE_NOTES;
}

@end
