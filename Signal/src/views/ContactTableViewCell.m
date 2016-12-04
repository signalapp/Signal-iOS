#import "ContactTableViewCell.h"
#import "Environment.h"
#import "OWSContactAvatarBuilder.h"
#import "OWSContactsManager.h"
#import "PhoneManager.h"
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
    self.nameLabel.attributedText = [self attributedStringForContact:contact];
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

    NSDictionary<NSString *, id> *boldFontAttributes = @{
        NSFontAttributeName : [UIFont ows_mediumFontWithSize:self.nameLabel.font.pointSize],
        NSForegroundColorAttributeName : [UIColor blackColor]
    };

    NSDictionary<NSString *, id> *normalFontAttributes = @{
        NSFontAttributeName : [UIFont ows_regularFontWithSize:self.nameLabel.font.pointSize],
        NSForegroundColorAttributeName : [UIColor ows_darkGrayColor]
    };

    NSAttributedString *_Nullable firstName, *_Nullable lastName;
    if (ABPersonGetSortOrdering() == kABPersonSortByFirstName) {
        if (contact.firstName) {
            firstName = [[NSAttributedString alloc] initWithString:contact.firstName attributes:boldFontAttributes];
        }
        if (contact.lastName) {
            lastName = [[NSAttributedString alloc] initWithString:contact.lastName attributes:normalFontAttributes];
        }
    } else {
        if (contact.firstName) {
            firstName = [[NSAttributedString alloc] initWithString:contact.firstName attributes:normalFontAttributes];
        }
        if (contact.lastName) {
            lastName = [[NSAttributedString alloc] initWithString:contact.lastName attributes:boldFontAttributes];
        }
    }

    NSAttributedString *_Nullable leftName, *_Nullable rightName;
    if (ABPersonGetCompositeNameFormat() == kABPersonCompositeNameFormatFirstNameFirst) {
        leftName = firstName;
        rightName = lastName;
    } else {
        leftName = lastName;
        rightName = firstName;
    }

    NSMutableAttributedString *fullNameString = [NSMutableAttributedString new];
    if (leftName) {
        [fullNameString appendAttributedString:leftName];
    }
    if (leftName && rightName) {
        [fullNameString appendAttributedString:[[NSAttributedString alloc] initWithString:@" "]];
    }
    if (rightName) {
        [fullNameString appendAttributedString:rightName];
    }

    return fullNameString;
}

@end

NS_ASSUME_NONNULL_END
