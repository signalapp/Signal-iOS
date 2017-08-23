//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "ContactTableViewCell.h"
#import "Environment.h"
#import "OWSContactAvatarBuilder.h"
#import "OWSContactsManager.h"
#import "Signal-Swift.h"
#import "UIFont+OWS.h"
#import "UIUtil.h"
#import "UIView+OWS.h"
#import <SignalServiceKit/SignalAccount.h>
#import <SignalServiceKit/TSGroupThread.h>
#import <SignalServiceKit/TSThread.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const kContactsTable_CellReuseIdentifier = @"kContactsTable_CellReuseIdentifier";
const NSUInteger kContactTableViewCellAvatarSize = 40;

@interface ContactTableViewCell ()

@property (nonatomic) UILabel *nameLabel;
@property (nonatomic) UILabel *profileNameLabel;
@property (nonatomic) UIImageView *avatarView;
@property (nonatomic) UILabel *subtitle;
@property (nonatomic) UIView *nameContainerView;

@end

@implementation ContactTableViewCell

- (instancetype)init
{
    if (self = [super init]) {
        [self configureProgrammatically];
    }
    return self;
}

+ (nullable NSString *)reuseIdentifier
{
    return NSStringFromClass(self.class);
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
    self.preservesSuperviewLayoutMargins = YES;
    self.contentView.preservesSuperviewLayoutMargins = YES;

    _avatarView = [AvatarImageView new];
    [self.contentView addSubview:_avatarView];

    _nameContainerView = [UIView containerView];
    [self.contentView addSubview:_nameContainerView];

    _nameLabel = [UILabel new];
    _nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _nameLabel.font = [UIFont ows_dynamicTypeBodyFont];
    [_nameContainerView addSubview:_nameLabel];

    _profileNameLabel = [UILabel new];
    _profileNameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _profileNameLabel.font = [UIFont ows_footnoteFont];
    _profileNameLabel.textColor = [UIColor grayColor];
    [_nameContainerView addSubview:_profileNameLabel];

    _subtitle = [UILabel new];
    _subtitle.font = [UIFont ows_footnoteFont];
    _subtitle.textColor = [UIColor ows_darkGrayColor];
    [_nameContainerView addSubview:self.subtitle];

    [_avatarView autoVCenterInSuperview];
    [_avatarView autoPinLeadingToSuperView];
    [_avatarView autoSetDimension:ALDimensionWidth toSize:kContactTableViewCellAvatarSize];
    [_avatarView autoSetDimension:ALDimensionHeight toSize:kContactTableViewCellAvatarSize];

    [_nameLabel autoPinEdgeToSuperviewEdge:ALEdgeTop];
    [_nameLabel autoPinWidthToSuperview];

    // profileNameLabel can be zero sized, in which case nameLabel essentially occupies the totality of
    // nameContainerView's frame.
    [_profileNameLabel autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:_nameLabel];
    [_profileNameLabel autoPinWidthToSuperview];

    [_subtitle autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:_profileNameLabel];
    [_subtitle autoPinWidthToSuperview];
    [_subtitle autoPinEdgeToSuperviewEdge:ALEdgeBottom];

    [_nameContainerView autoVCenterInSuperview];
    [_nameContainerView autoPinLeadingToTrailingOfView:_avatarView margin:12.f];
    [_nameContainerView autoPinTrailingToSuperView];

    // Force layout, since imageView isn't being initally rendered on App Store optimized build.
    [self layoutSubviews];
}

- (void)configureWithSignalAccount:(SignalAccount *)signalAccount contactsManager:(OWSContactsManager *)contactsManager
{
    [self configureWithRecipientId:signalAccount.recipientId
                   contactsManager:contactsManager];
}

- (void)configureWithRecipientId:(NSString *)recipientId
                 contactsManager:(OWSContactsManager *)contactsManager
{
    self.nameLabel.attributedText =
        [contactsManager formattedFullNameForRecipientId:recipientId font:self.nameLabel.font];

    if ([contactsManager hasNameInSystemContactsForRecipientId:recipientId]) {
        // Don't display profile name when we have a veritas name in system Contacts
        self.profileNameLabel.text = nil;
    } else {
        // Use profile name, if any is available
        self.profileNameLabel.text = [contactsManager formattedProfileNameForRecipientId:recipientId];
    }

    if (self.accessoryMessage) {
        UILabel *blockedLabel = [[UILabel alloc] init];
        blockedLabel.textAlignment = NSTextAlignmentRight;
        blockedLabel.text = self.accessoryMessage;
        blockedLabel.font = [UIFont ows_mediumFontWithSize:13.f];
        blockedLabel.textColor = [UIColor colorWithWhite:0.5f alpha:1.f];
        [blockedLabel sizeToFit];

        self.accessoryView = blockedLabel;
    }

    self.avatarView.image = [[[OWSContactAvatarBuilder alloc] initWithSignalId:recipientId
                                                                      diameter:kContactTableViewCellAvatarSize
                                                               contactsManager:contactsManager] build];

    // Force layout, since imageView isn't being initally rendered on App Store optimized build.
    [self layoutSubviews];
}

- (void)configureWithThread:(TSThread *)thread contactsManager:(OWSContactsManager *)contactsManager
{
    OWSAssert(thread);

    NSString *threadName = thread.name;
    if (threadName.length == 0 && [thread isKindOfClass:[TSGroupThread class]]) {
        threadName = NSLocalizedString(@"NEW_GROUP_DEFAULT_TITLE", @"");
    }

    NSAttributedString *attributedText = [[NSAttributedString alloc]
                                          initWithString:threadName
                                          attributes:@{
                                                       NSForegroundColorAttributeName : [UIColor blackColor],
                                                       }];
    self.nameLabel.attributedText = attributedText;

    self.avatarView.image = [OWSAvatarBuilder buildImageForThread:thread
                                                         diameter:kContactTableViewCellAvatarSize
                                                  contactsManager:contactsManager];

    // Force layout, since imageView isn't being initally rendered on App Store optimized build.
    [self layoutSubviews];
}

- (NSAttributedString *)verifiedSubtitle
{
    NSMutableAttributedString *text = [NSMutableAttributedString new];
    // "checkmark"
    [text appendAttributedString:[[NSAttributedString alloc]
                                     initWithString:@"\uf00c "
                                         attributes:@{
                                             NSFontAttributeName :
                                                 [UIFont ows_fontAwesomeFont:self.subtitle.font.pointSize],
                                         }]];
    [text appendAttributedString:[[NSAttributedString alloc]
                                     initWithString:NSLocalizedString(@"PRIVACY_IDENTITY_IS_VERIFIED_BADGE",
                                                        @"Badge indicating that the user is verified.")]];
    return [text copy];
}

- (void)prepareForReuse
{
    self.accessoryMessage = nil;
    self.accessoryView = nil;
    self.accessoryType = UITableViewCellAccessoryNone;
    [self.subtitle removeFromSuperview];
    self.subtitle = nil;
}

@end

NS_ASSUME_NONNULL_END
