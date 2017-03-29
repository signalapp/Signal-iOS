//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "ContactTableViewCell.h"
#import "Environment.h"
#import "OWSContactAvatarBuilder.h"
#import "OWSContactsManager.h"
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
    self.nameLabel.attributedText = [contactsManager formattedFullNameForContact:contact font:self.nameLabel.font];
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

@end

NS_ASSUME_NONNULL_END
