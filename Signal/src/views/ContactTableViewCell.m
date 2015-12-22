#import "ContactTableViewCell.h"
#import "UIUtil.h"

#import "Environment.h"
#import "PhoneManager.h"

#define CONTACT_TABLE_CELL_BORDER_WIDTH 1.0f

@interface ContactTableViewCell () {
}
@property (strong, nonatomic) Contact *associatedContact;
@end

@implementation ContactTableViewCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    return self;
}

- (NSString *)reuseIdentifier {
    return NSStringFromClass(self.class);
}


- (void)configureWithContact:(Contact *)contact {
    if (!contact.isTextSecureContact) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    _associatedContact = contact;

    _nameLabel.attributedText = [self attributedStringForContact:contact];
    if (!contact.isTextSecureContact) {
        _nameLabel.textColor = [UIColor lightGrayColor];
    }
}

- (NSAttributedString *)attributedStringForContact:(Contact *)contact {
    NSMutableAttributedString *fullNameAttributedString =
        [[NSMutableAttributedString alloc] initWithString:contact.fullName];

    UIFont *firstNameFont;
    UIFont *lastNameFont;

    if (ABPersonGetSortOrdering() == kABPersonCompositeNameFormatFirstNameFirst) {
        firstNameFont = [UIFont ows_mediumFontWithSize:_nameLabel.font.pointSize];
        lastNameFont  = [UIFont ows_regularFontWithSize:_nameLabel.font.pointSize];
    } else {
        firstNameFont = [UIFont ows_regularFontWithSize:_nameLabel.font.pointSize];
        lastNameFont  = [UIFont ows_mediumFontWithSize:_nameLabel.font.pointSize];
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

    if (ABPersonGetSortOrdering() == kABPersonCompositeNameFormatFirstNameFirst) {
        [fullNameAttributedString addAttribute:NSForegroundColorAttributeName
                                         value:[UIColor ows_darkGrayColor]
                                         range:NSMakeRange(contact.firstName.length + 1, contact.lastName.length)];
    } else {
        [fullNameAttributedString addAttribute:NSForegroundColorAttributeName
                                         value:[UIColor ows_darkGrayColor]
                                         range:NSMakeRange(0, contact.firstName.length)];
    }
    return fullNameAttributedString;
}

@end
