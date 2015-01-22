#import "ContactTableViewCell.h"
#import "UIUtil.h"

#import "Environment.h"
#import "PhoneManager.h"
#import "DJWActionSheet+OWS.h"

#define CONTACT_TABLE_CELL_BORDER_WIDTH 1.0f

@interface ContactTableViewCell() {
    
}
@property(strong,nonatomic) Contact* associatedContact;
@end

@implementation ContactTableViewCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [NSBundle.mainBundle loadNibNamed:NSStringFromClass(self.class) owner:self options:nil][0];
    _contactPictureView.layer.borderColor = [[UIColor lightGrayColor] CGColor];
    _contactPictureView.layer.masksToBounds = YES;
    self.selectionStyle = UITableViewCellSelectionStyleGray;
    _shouldShowContactButtons = YES;
    
    return self;
}

- (NSString *)reuseIdentifier {
    return NSStringFromClass(self.class);
}

-(void)showContactButtons:(BOOL)enabled
{
    _callButton.hidden = !enabled;
    _callButton.enabled = enabled;
    _messageButton.hidden = !enabled;
    _callButton.enabled = enabled;
}

- (void)configureWithContact:(Contact *)contact {
    [self showContactButtons:_shouldShowContactButtons];
    
    _associatedContact = contact;
    
    _nameLabel.attributedText = [self attributedStringForContact:contact];

    UIImage *image = contact.image;
    BOOL imageNotNil = image != nil;
    [self configureBorder:imageNotNil];

    if (imageNotNil) {
        _contactPictureView.image = image;
    } else {
        _contactPictureView.image = nil;
        [_contactPictureView addConstraint:[NSLayoutConstraint constraintWithItem:_contactPictureView attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual toItem:nil attribute:0 multiplier:1.0f constant:0]];
    }
    
    if (contact.isRedPhoneContact && _shouldShowContactButtons)
    {
        UIImage * callImage = [[UIImage imageNamed:@"call_dark"]imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        [_callButton setImage:callImage forState:UIControlStateNormal];
        _callButton.tintColor = [UIColor ows_materialBlueColor];
    } else {
        [_callButton setImage:[UIImage imageNamed:@"call_dotted"] forState:UIControlStateNormal];
    }
    
    if (contact.isTextSecureContact && _shouldShowContactButtons)
    {
        UIImage * messageImage = [[UIImage imageNamed:@"signal"]imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        [_messageButton setImage:messageImage forState:UIControlStateNormal];
        _messageButton.tintColor = [UIColor ows_materialBlueColor];
    } else {
        [_messageButton setImage:[UIImage imageNamed:@"signal_dotted"] forState:UIControlStateNormal];
    }
}

- (void)configureBorder:(BOOL)show {
    _contactPictureView.layer.borderWidth = show ? CONTACT_TABLE_CELL_BORDER_WIDTH : 0;
    _contactPictureView.layer.cornerRadius = show ? CGRectGetWidth(_contactPictureView.frame)/2 : 0;
}

- (NSAttributedString *)attributedStringForContact:(Contact *)contact {
    NSMutableAttributedString *fullNameAttributedString = [[NSMutableAttributedString alloc] initWithString:contact.fullName];

    UIFont *firstNameFont;
    UIFont *lastNameFont;
    
    if (ABPersonGetSortOrdering() == kABPersonCompositeNameFormatFirstNameFirst) {
        firstNameFont = [UIFont ows_mediumFontWithSize:_nameLabel.font.pointSize]; //TODOTYLERFONT
        lastNameFont  = [UIFont ows_regularFontWithSize:_nameLabel.font.pointSize]; //TODOTYLERFONT // TODOCHRISTINEFONT: color ows_lightgrey
    } else{
        firstNameFont = [UIFont ows_regularFontWithSize:_nameLabel.font.pointSize]; //TODOTYLERFONT // TODOCHRISTINEFONT: color ows_lightgrey
        lastNameFont  = [UIFont ows_mediumFontWithSize:_nameLabel.font.pointSize]; //TODOTYLERFONT
    }
    [fullNameAttributedString addAttribute:NSFontAttributeName value:firstNameFont range:NSMakeRange(0, contact.firstName.length)];
    [fullNameAttributedString addAttribute:NSFontAttributeName value:lastNameFont range:NSMakeRange(contact.firstName.length + 1, contact.lastName.length)];
    [fullNameAttributedString addAttribute:NSForegroundColorAttributeName value:[UIColor blackColor] range:NSMakeRange(0, contact.fullName.length)];
    
    if (ABPersonGetSortOrdering() == kABPersonCompositeNameFormatFirstNameFirst) {
        [fullNameAttributedString addAttribute:NSForegroundColorAttributeName value:[UIColor ows_darkGrayColor] range:NSMakeRange(contact.firstName.length + 1, contact.lastName.length)];
    }
    else {
        [fullNameAttributedString addAttribute:NSForegroundColorAttributeName value:[UIColor ows_darkGrayColor] range:NSMakeRange(0, contact.firstName.length)];
    }
    return fullNameAttributedString;
}

-(IBAction)callContact:(id)sender
{
    if (_associatedContact.isRedPhoneContact) {
        NSArray *redPhoneIdentifiers = [_associatedContact redPhoneIdentifiers];
        [Environment.phoneManager initiateOutgoingCallToContact:_associatedContact atRemoteNumber:[redPhoneIdentifiers firstObject]];
    } else{
        DDLogWarn(@"Tried to intiate a call but contact has no RedPhone identifier");
    }
}

-(IBAction)messageContact:(id)sender
{
    if (_associatedContact.isTextSecureContact) {
        NSArray *textSecureIdentifiers = [_associatedContact textSecureIdentifiers];
        [Environment messageIdentifier:[textSecureIdentifiers firstObject]];
    } else{
        DDLogWarn(@"Tried to intiate a call but contact has no RedPhone identifier");
    }

}

@end
