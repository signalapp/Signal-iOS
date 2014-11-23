#import "ContactTableViewCell.h"

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
    
    if (!_shouldShowContactButtons)
    {
        _callButton.hidden = YES;
        _callButton.enabled = NO;
        _messageButton.hidden = YES;
        _callButton.enabled = NO;
    }
    
    return self;
}

- (NSString *)reuseIdentifier {
    return NSStringFromClass(self.class);
}

- (void)configureWithContact:(Contact *)contact {
    
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
        _callButton.imageView.image = [UIImage imageNamed:@"call_dark"];
    } else {
        [_callButton addConstraint:[NSLayoutConstraint constraintWithItem:_callButton attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual toItem:nil attribute:0 multiplier:1.0f constant:0]];
    }
    
    if (contact.isTextSecureContact && _shouldShowContactButtons)
    {
        _messageButton.imageView.image = [UIImage imageNamed:@"signal"];
    } else {
        [_messageButton addConstraint:[NSLayoutConstraint constraintWithItem:_messageButton attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationEqual toItem:nil attribute:0 multiplier:1.0f constant:0]];
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
        firstNameFont = [UIFont fontWithName:@"HelveticaNeue-Light" size:_nameLabel.font.pointSize];
        lastNameFont  = [UIFont systemFontOfSize:_nameLabel.font.pointSize];
    } else{
        firstNameFont = [UIFont fontWithName:@"HelveticaNeue-Light" size:_nameLabel.font.pointSize];
        lastNameFont  = [UIFont systemFontOfSize:_nameLabel.font.pointSize];
    }
    [fullNameAttributedString addAttribute:NSFontAttributeName value:firstNameFont range:NSMakeRange(0, contact.firstName.length)];
    [fullNameAttributedString addAttribute:NSFontAttributeName value:lastNameFont range:NSMakeRange(contact.firstName.length + 1, contact.lastName.length)];
    
    [fullNameAttributedString addAttribute:NSForegroundColorAttributeName value:[UIColor blackColor] range:NSMakeRange(0, contact.fullName.length)];
    return fullNameAttributedString;
}

-(IBAction)callContact:(id)sender
{
    //Initiate Call to _associatedContact
}

-(IBAction)messageContact:(id)sender
{
    //Load messages to _associatedContact
}

@end
