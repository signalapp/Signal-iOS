#import "ContactTableViewCell.h"

#define CONTACT_TABLE_CELL_BORDER_WIDTH 1.0f

@implementation ContactTableViewCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString*)reuseIdentifier {
    self = [[[NSBundle mainBundle] loadNibNamed:NSStringFromClass([self class]) owner:self options:nil] firstObject];
    
    if (self) {
        self.contactPictureView.layer.borderColor = [[UIColor lightGrayColor] CGColor];
        self.contactPictureView.layer.masksToBounds = YES;
    }
    
    return self;
}

- (NSString*)reuseIdentifier {
    return NSStringFromClass([self class]);
}

- (void)configureWithContact:(Contact*)contact {
	
    self.nameLabel.attributedText = [self attributedStringForContact:contact];

    UIImage* image = contact.image;
    BOOL imageNotNil = image != nil;
    [self configureBorder:imageNotNil];

    if (imageNotNil) {
        self.contactPictureView.image = image;
    } else {
        self.contactPictureView.image = nil;
    }
}

- (void)configureBorder:(BOOL)show {
    self.contactPictureView.layer.borderWidth = show ? CONTACT_TABLE_CELL_BORDER_WIDTH : 0;
    self.contactPictureView.layer.cornerRadius = show ? CGRectGetWidth(self.contactPictureView.frame)/2 : 0;
}

- (NSAttributedString*)attributedStringForContact:(Contact*)contact {
    NSMutableAttributedString *fullNameAttributedString = [[NSMutableAttributedString alloc] initWithString:contact.fullName];

    UIFont* firstNameFont;
    UIFont* lastNameFont;
    
    if (ABPersonGetSortOrdering() == kABPersonCompositeNameFormatFirstNameFirst) {
        firstNameFont = [UIFont boldSystemFontOfSize:self.nameLabel.font.pointSize];
        lastNameFont  = [UIFont systemFontOfSize:self.nameLabel.font.pointSize];
    } else{
        firstNameFont = [UIFont systemFontOfSize:self.nameLabel.font.pointSize];
        lastNameFont  = [UIFont boldSystemFontOfSize:self.nameLabel.font.pointSize];
    }
    [fullNameAttributedString addAttribute:NSFontAttributeName
                                     value:firstNameFont
                                     range:NSMakeRange(0, contact.firstName.length)];
    [fullNameAttributedString addAttribute:NSFontAttributeName
                                     value:lastNameFont
                                     range:NSMakeRange(contact.firstName.length + 1, contact.lastName.length)];
    
    [fullNameAttributedString addAttribute:NSForegroundColorAttributeName
                                     value:[UIColor blackColor]
                                     range:NSMakeRange(0, contact.fullName.length)];
    return fullNameAttributedString;
}

@end
