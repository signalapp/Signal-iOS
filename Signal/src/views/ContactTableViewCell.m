#import "ContactTableViewCell.h"
#import "UIUtil.h"

#import "Environment.h"
#import "PhoneManager.h"

@interface ContactTableViewCell ()

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
    self.associatedContact = contact;
    self.nameLabel.attributedText = [self attributedStringForContact:contact];
}

- (NSAttributedString *)attributedStringForContact:(Contact *)contact {
    NSMutableAttributedString *fullNameAttributedString =
        [[NSMutableAttributedString alloc] initWithString:contact.fullName];

    BOOL firstNameDisplay = ABPersonGetCompositeNameFormat() == kABPersonCompositeNameFormatFirstNameFirst ? YES : NO;
    BOOL sortByFirstName = ABPersonGetSortOrdering() == kABPersonSortByFirstName ? YES : NO;

    UIFont *firstNameFont;
    UIColor *firstNameFontColor;
    NSRange firstNameRange;
    
    UIFont *lastNameFont;
    UIColor *lastNameFontColor;
    NSRange lastNameRange;

    if ((sortByFirstName && contact.firstName) || !contact.lastName) {
        firstNameFont = [UIFont ows_mediumFontWithSize:_nameLabel.font.pointSize];
        firstNameFontColor = [UIColor blackColor];
        lastNameFont  = [UIFont ows_regularFontWithSize:_nameLabel.font.pointSize];
        lastNameFontColor = [UIColor ows_darkGrayColor];
    } else {
        firstNameFont = [UIFont ows_regularFontWithSize:_nameLabel.font.pointSize];
        firstNameFontColor = [UIColor ows_darkGrayColor];
        lastNameFont  = [UIFont ows_mediumFontWithSize:_nameLabel.font.pointSize];
        lastNameFontColor = [UIColor blackColor];
    }
    
    if (firstNameDisplay) {
        unsigned skipFirstName = contact.firstName ? 1 : 0;
        firstNameRange = NSMakeRange(0, contact.firstName.length);
        lastNameRange = NSMakeRange(contact.firstName.length + skipFirstName, contact.lastName.length);
    } else {
        firstNameRange = NSMakeRange(contact.lastName.length, contact.firstName.length);
        lastNameRange = NSMakeRange(0, contact.lastName.length);
    }
    
    if (contact.firstName) {
        [fullNameAttributedString addAttribute:NSFontAttributeName
                                         value:firstNameFont
                                         range:firstNameRange];
        [fullNameAttributedString addAttribute:NSForegroundColorAttributeName
                                         value:firstNameFontColor
                                         range:firstNameRange];
    }
    if (contact.lastName) {
        [fullNameAttributedString addAttribute:NSFontAttributeName
                                         value:lastNameFont
                                         range:lastNameRange];
        [fullNameAttributedString addAttribute:NSForegroundColorAttributeName
                                         value:lastNameFontColor
                                         range:lastNameRange];
    }
    return fullNameAttributedString;
}

@end
