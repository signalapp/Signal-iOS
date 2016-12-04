#import "ContactTableViewCell.h"
#import "Environment.h"
#import "OWSContactAvatarBuilder.h"
#import "OWSContactsManager.h"
#import "PhoneManager.h"
#import "Signal-Swift.h"
#import "UIUtil.h"

NS_ASSUME_NONNULL_BEGIN

@interface ContactTableViewCell ()

@property (nonatomic) IBOutlet UILabel *nameLabel;
@property (nonatomic) IBOutlet UIImageView *avatarView;

@end

@implementation ContactTableViewCell

- (nullable NSString *)reuseIdentifier
{
    return NSStringFromClass(self.class);
}

- (void)configureWithContact:(Contact *)contact contactsManager:(OWSContactsManager *)contactsManager
{
    OWSContactAdapter *contactAdapter = [[OWSContactAdapter alloc] initWithContact:contact];
    self.nameLabel.attributedText = [contactAdapter formattedFullNameWithFont:self.nameLabel.font];
    self.avatarView.image =
        [[[OWSContactAvatarBuilder alloc] initWithContactId:contact.textSecureIdentifiers.firstObject
                                                       name:contact.fullName
                                            contactsManager:contactsManager] build];

    // Force layout, since imageView isn't being initally rendered on App Store optimized build.
    [self layoutSubviews];
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    [UIUtil applyRoundedBorderToImageView:self.avatarView];
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
        firstNameFont = [UIFont ows_mediumFontWithSize:self.nameLabel.font.pointSize];
        firstNameFontColor = [UIColor blackColor];
        lastNameFont  = [UIFont ows_regularFontWithSize:self.nameLabel.font.pointSize];
        lastNameFontColor = [UIColor ows_darkGrayColor];
    } else {
        firstNameFont = [UIFont ows_regularFontWithSize:self.nameLabel.font.pointSize];
        firstNameFontColor = [UIColor ows_darkGrayColor];
        lastNameFont  = [UIFont ows_mediumFontWithSize:self.nameLabel.font.pointSize];
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

NS_ASSUME_NONNULL_END
