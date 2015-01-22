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

- (NSAttributedString *)attributedStringForContact:(Contact *)contact {
    NSMutableAttributedString *fullNameAttributedString = [[NSMutableAttributedString alloc] initWithString:contact.fullName];

    UIFont *firstNameFont;
    UIFont *lastNameFont;
    
    if (ABPersonGetSortOrdering() == kABPersonCompositeNameFormatFirstNameFirst) {
        firstNameFont = [UIFont ows_mediumFontWithSize:_nameLabel.font.pointSize];
        lastNameFont  = [UIFont ows_regularFontWithSize:_nameLabel.font.pointSize];
        firstNameFont = [UIFont ows_regularFontWithSize:_nameLabel.font.pointSize];
        lastNameFont  = [UIFont ows_mediumFontWithSize:_nameLabel.font.pointSize];
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
