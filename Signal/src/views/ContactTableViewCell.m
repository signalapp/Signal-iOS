//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "ContactTableViewCell.h"
#import "Environment.h"
#import "OWSContactAvatarBuilder.h"
#import "OWSContactsManager.h"
#import "UIFont+OWS.h"
#import "UIUtil.h"
#import "UIView+OWS.h"

NS_ASSUME_NONNULL_BEGIN

@interface ContactTableViewCell ()

@property (nonatomic) IBOutlet UILabel *nameLabel;
@property (nonatomic) IBOutlet UIImageView *avatarView;

@end

@implementation ContactTableViewCell

- (instancetype)init
{
    if (self = [super init]) {
        [self configureProgrammatically];
    }
    return self;
}

- (nullable NSString *)reuseIdentifier
{
    return NSStringFromClass(self.class);
}

+ (CGFloat)rowHeight
{
    return 59.f;
}

- (void)configureProgrammatically
{
    _avatarView = [UIImageView new];
    _avatarView.contentMode = UIViewContentModeScaleToFill;
    _avatarView.image = [UIImage imageNamed:@"empty-group-avatar"];
    [self.contentView addSubview:_avatarView];

    _nameLabel = [UILabel new];
    _nameLabel.contentMode = UIViewContentModeLeft;
    _nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _nameLabel.font = [UIFont ows_dynamicTypeBodyFont];
    [self.contentView addSubview:_nameLabel];

    [_avatarView autoVCenterInSuperview];
    [_avatarView autoPinEdgeToSuperviewEdge:ALEdgeLeft withInset:8.f];
    [_avatarView autoSetDimension:ALDimensionWidth toSize:40.f];
    [_avatarView autoSetDimension:ALDimensionHeight toSize:40.f];

    [_nameLabel autoPinEdgeToSuperviewEdge:ALEdgeRight];
    [_nameLabel autoPinEdgeToSuperviewEdge:ALEdgeTop];
    [_nameLabel autoPinEdgeToSuperviewEdge:ALEdgeBottom];
    [_nameLabel autoPinEdge:ALEdgeLeft toEdge:ALEdgeRight ofView:_avatarView withOffset:12.f];

    // Force layout, since imageView isn't being initally rendered on App Store optimized build.
    [self layoutSubviews];
}

- (void)configureWithContact:(Contact *)contact contactsManager:(OWSContactsManager *)contactsManager
{
    NSMutableAttributedString *attributedText =
        [[contactsManager formattedFullNameForContact:contact font:self.nameLabel.font] mutableCopy];
    if (self.isBlocked) {
        // Add whitespace between the contact name and the blocked indicator.
        [attributedText appendAttributedString:[[NSAttributedString alloc] initWithString:@" " attributes:nil]];
        [attributedText appendAttributedString:[[NSAttributedString alloc]
                                                   initWithString:NSLocalizedString(@"CONTACT_BLOCKED_INDICATOR",
                                                                      @"An indicator that a contact has been blocked.")
                                                       attributes:@{
                                                           NSFontAttributeName : [UIFont
                                                               ows_mediumFontWithSize:self.nameLabel.font.pointSize],
                                                           NSForegroundColorAttributeName : [UIColor blackColor],
                                                       }]];
    }
    self.nameLabel.attributedText = attributedText;
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
