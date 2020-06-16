//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "ContactCellView.h"
#import "OWSContactAvatarBuilder.h"
#import "OWSContactsManager.h"
#import "UIFont+OWS.h"
#import "UIView+OWS.h"
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/SignalAccount.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSContactThread.h>
#import <SignalServiceKit/TSGroupThread.h>
#import <SignalServiceKit/TSThread.h>

NS_ASSUME_NONNULL_BEGIN

const CGFloat kContactCellAvatarTextMargin = 8;

@interface ContactCellView ()

@property (nonatomic) UILabel *nameLabel;
@property (nonatomic) UIImageView *avatarView;
@property (nonatomic) UILabel *subtitleLabel;
@property (nonatomic) UILabel *accessoryLabel;
@property (nonatomic) UIStackView *nameContainerView;
@property (nonatomic) UIView *accessoryViewContainer;

@property (nonatomic, nullable) TSThread *thread;
@property (nonatomic) SignalServiceAddress *address;
@property (nonatomic, nullable) NSArray<NSLayoutConstraint *> *layoutConstraints;

@end

#pragma mark -

@implementation ContactCellView

- (instancetype)init
{
    if (self = [super init]) {
        [self configure];
    }
    return self;
}

#pragma mark - Dependencies

- (OWSContactsManager *)contactsManager
{
    OWSAssertDebug(Environment.shared.contactsManager);

    return Environment.shared.contactsManager;
}

- (SDSDatabaseStorage *)databaseStorage
{
    return SDSDatabaseStorage.shared;
}

- (TSAccountManager *)tsAccountManager
{
    OWSAssertDebug(SSKEnvironment.shared.tsAccountManager);

    return SSKEnvironment.shared.tsAccountManager;
}

- (OWSProfileManager *)profileManager
{
    return [OWSProfileManager sharedManager];
}

#pragma mark -

- (void)configure
{
    OWSAssertDebug(!self.nameLabel);

    self.layoutMargins = UIEdgeInsetsZero;

    _avatarView = [AvatarImageView new];

    self.nameLabel = [UILabel new];
    self.nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;

    self.subtitleLabel = [UILabel new];

    self.accessoryLabel = [[UILabel alloc] init];
    self.accessoryLabel.textAlignment = NSTextAlignmentRight;

    self.accessoryViewContainer = [UIView containerView];

    self.nameContainerView = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.nameLabel,
        self.subtitleLabel,
    ]];
    self.nameContainerView.axis = UILayoutConstraintAxisVertical;

    [self.avatarView setContentHuggingHorizontalHigh];
    [self.nameContainerView setContentHuggingHorizontalLow];
    [self.accessoryViewContainer setContentHuggingHorizontalHigh];

    self.axis = UILayoutConstraintAxisHorizontal;
    self.spacing = kContactCellAvatarTextMargin;
    self.alignment = UIStackViewAlignmentCenter;
    [self addArrangedSubview:self.avatarView];
    [self addArrangedSubview:self.nameContainerView];
    [self addArrangedSubview:self.accessoryViewContainer];

    [self configureFontsAndColors];
}

- (void)configureFontsAndColors
{
    self.nameLabel.font = OWSTableItem.primaryLabelFont;
    self.subtitleLabel.font = [UIFont ows_regularFontWithSize:11.f];
    self.accessoryLabel.font = [UIFont ows_semiboldFontWithSize:12.f];

    self.nameLabel.textColor = Theme.primaryTextColor;
    self.subtitleLabel.textColor = Theme.secondaryTextAndIconColor;
    self.accessoryLabel.textColor = Theme.middleGrayColor;
}

- (void)configureWithRecipientAddress:(SignalServiceAddress *)address
{
    OWSAssertDebug(address.isValid);

    // Update fonts to reflect changes to dynamic type.
    [self configureFontsAndColors];

    self.address = address;

    // TODO remove sneaky transaction.
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        self.thread = [TSContactThread getThreadWithContactAddress:address transaction:transaction];
    }];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(otherUsersProfileDidChange:)
                                                 name:kNSNotificationNameOtherUsersProfileDidChange
                                               object:nil];
    [self updateNameLabels];
    [self updateAvatar];

    if (self.accessoryMessage) {
        self.accessoryLabel.text = self.accessoryMessage;
        [self setAccessoryView:self.accessoryLabel];
    }

    // Force layout, since imageView isn't being initally rendered on App Store optimized build.
    [self layoutSubviews];
}

- (void)configureWithThread:(TSThread *)thread transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(thread);
    self.thread = thread;
    
    // Update fonts to reflect changes to dynamic type.
    [self configureFontsAndColors];

    TSContactThread *_Nullable contactThread;
    if ([self.thread isKindOfClass:[TSContactThread class]]) {
        contactThread = (TSContactThread *)self.thread;
    }

    if (contactThread != nil) {
        self.address = contactThread.contactAddress;

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(otherUsersProfileDidChange:)
                                                     name:kNSNotificationNameOtherUsersProfileDidChange
                                                   object:nil];
        [self updateNameLabels];
    } else {
        NSString *threadName = [self.contactsManager displayNameForThread:thread transaction:transaction];
        NSAttributedString *attributedText =
            [[NSAttributedString alloc] initWithString:threadName
                                            attributes:@{
                                                NSForegroundColorAttributeName : Theme.primaryTextColor,
                                            }];
        self.nameLabel.attributedText = attributedText;
    }

    self.layoutConstraints = [self.avatarView autoSetDimensionsToSize:CGSizeMake(self.avatarSize, self.avatarSize)];
    self.avatarView.image = [OWSAvatarBuilder buildImageForThread:thread diameter:self.avatarSize];

    if (self.accessoryMessage) {
        self.accessoryLabel.text = self.accessoryMessage;
        [self setAccessoryView:self.accessoryLabel];
    }

    // Force layout, since imageView isn't being initally rendered on App Store optimized build.
    [self layoutSubviews];
}

- (void)updateAvatar
{
    self.layoutConstraints = [self.avatarView autoSetDimensionsToSize:CGSizeMake(self.avatarSize, self.avatarSize)];

    if (self.customAvatar != nil) {
        self.avatarView.image = self.customAvatar;
        return;
    }

    SignalServiceAddress *address = self.address;
    if (!address.isValid) {
        OWSFailDebug(@"address should not be invalid");
        self.avatarView.image = nil;
        return;
    }

    ConversationColorName colorName = ^{
        if (self.thread) {
            return self.thread.conversationColorName;
        } else {
            return [TSThread stableColorNameForNewConversationWithString:address.stringForDisplay];
        }
    }();

    OWSContactAvatarBuilder *avatarBuilder = [[OWSContactAvatarBuilder alloc] initWithAddress:address
                                                                                    colorName:colorName
                                                                                     diameter:self.avatarSize];

    self.avatarView.image = [avatarBuilder build];
}

- (NSUInteger)avatarSize
{
    return self.useSmallAvatars ? kSmallAvatarSize : kStandardAvatarSize;
}

- (void)updateNameLabels
{
    BOOL hasCustomName = self.customName.length > 0;
    BOOL isNoteToSelf = IsNoteToSelfEnabled() && self.address.isLocalAddress;
    if (hasCustomName > 0) {
        self.nameLabel.attributedText = self.customName;
    } else if (isNoteToSelf) {
        self.nameLabel.text = MessageStrings.noteToSelf;
    } else {
        self.nameLabel.text = [self.contactsManager displayNameForAddress:self.address];
    }

    [self.nameLabel setNeedsLayout];
}

- (void)prepareForReuse
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];

    self.thread = nil;
    self.accessoryMessage = nil;
    self.nameLabel.text = nil;
    self.subtitleLabel.text = nil;
    self.accessoryLabel.text = nil;
    self.customName = nil;
    self.customAvatar = nil;
    for (UIView *subview in self.accessoryViewContainer.subviews) {
        [subview removeFromSuperview];
    }
    [NSLayoutConstraint deactivateConstraints:self.layoutConstraints];
    self.layoutConstraints = nil;
    self.useSmallAvatars = NO;
}

- (void)otherUsersProfileDidChange:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    SignalServiceAddress *address = notification.userInfo[kNSNotificationKey_ProfileAddress];
    OWSAssertDebug(address.isValid);

    if (address.isValid && [self.address isEqualToAddress:address]) {
        [self updateNameLabels];
        [self updateAvatar];
    }
}

- (NSAttributedString *)verifiedSubtitle
{
    NSMutableAttributedString *text = [NSMutableAttributedString new];
    // "checkmark"
    [text appendAttributedString:[[NSAttributedString alloc]
                                     initWithString:@"\uf00c "
                                         attributes:@{
                                             NSFontAttributeName :
                                                 [UIFont ows_fontAwesomeFont:self.subtitleLabel.font.pointSize],
                                         }]];
    [text appendAttributedString:[[NSAttributedString alloc]
                                     initWithString:NSLocalizedString(@"PRIVACY_IDENTITY_IS_VERIFIED_BADGE",
                                                        @"Badge indicating that the user is verified.")]];
    return [text copy];
}

- (void)setAttributedSubtitle:(nullable NSAttributedString *)attributedSubtitle
{
    self.subtitleLabel.attributedText = attributedSubtitle;
}

- (BOOL)hasAccessoryText
{
    return self.accessoryMessage.length > 0;
}

- (void)setAccessoryView:(UIView *)accessoryView
{
    OWSAssertDebug(accessoryView);
    OWSAssertDebug(self.accessoryViewContainer);
    OWSAssertDebug(self.accessoryViewContainer.subviews.count < 1);

    [self.accessoryViewContainer addSubview:accessoryView];

    // Trailing-align the accessory view.
    [accessoryView autoPinEdgeToSuperviewMargin:ALEdgeTop];
    [accessoryView autoPinEdgeToSuperviewMargin:ALEdgeBottom];
    [accessoryView autoPinEdgeToSuperviewMargin:ALEdgeTrailing];
    [accessoryView autoPinEdgeToSuperviewMargin:ALEdgeLeading relation:NSLayoutRelationGreaterThanOrEqual];
}

@end

NS_ASSUME_NONNULL_END
