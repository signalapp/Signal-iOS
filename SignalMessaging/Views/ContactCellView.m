//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
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

const CGFloat kContactCellAvatarTextMargin = 12;

@interface ContactCellView ()

@property (nonatomic) UILabel *nameLabel;
@property (nonatomic) ConversationAvatarView *avatarView;
@property (nonatomic) UILabel *subtitleLabel;
@property (nonatomic) UILabel *accessoryLabel;
@property (nonatomic) UIStackView *nameContainerView;
@property (nonatomic) UIView *accessoryViewContainer;

@property (nonatomic, nullable) TSThread *thread;
@property (nonatomic) SignalServiceAddress *address;

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

- (void)configure
{
    OWSAssertDebug(!self.nameLabel);

    self.layoutMargins = UIEdgeInsetsZero;

    self.avatarView = [[ConversationAvatarView alloc] initWithDiameter:self.avatarSize
                                                   localUserAvatarMode:LocalUserAvatarModeAsUser];

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
    self.subtitleLabel.font = [UIFont ows_dynamicTypeCaption1ClampedFont];
    self.accessoryLabel.font = [UIFont ows_dynamicTypeSubheadlineClampedFont];

    self.nameLabel.textColor = self.forceDarkAppearance ? Theme.darkThemePrimaryColor : Theme.primaryTextColor;
    self.subtitleLabel.textColor
        = self.forceDarkAppearance ? Theme.darkThemeSecondaryTextAndIconColor : Theme.secondaryTextAndIconColor;
    self.accessoryLabel.textColor = Theme.isDarkThemeEnabled ? UIColor.ows_gray25Color : UIColor.ows_gray45Color;

    if (self.nameLabel.attributedText.string.length > 0) {
        NSString *nameLabelText = self.nameLabel.attributedText.string;
        NSDictionary *updatedAttributes = @{ NSForegroundColorAttributeName : self.nameLabel.textColor };
        self.nameLabel.attributedText = [[NSAttributedString alloc] initWithString:nameLabelText
                                                                        attributes:updatedAttributes];
    }
}

- (void)configureWithSneakyTransactionWithRecipientAddress:(SignalServiceAddress *)address
                                       localUserAvatarMode:(LocalUserAvatarMode)localUserAvatarMode
{
    [self.databaseStorage uiReadWithBlock:^(SDSAnyReadTransaction *transaction) {
        [self configureWithRecipientAddress:address localUserAvatarMode:localUserAvatarMode transaction:transaction];
    }];
}

- (void)configureWithRecipientAddress:(SignalServiceAddress *)address
                  localUserAvatarMode:(LocalUserAvatarMode)localUserAvatarMode
                          transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(address.isValid);

    // Update fonts to reflect changes to dynamic type.
    [self configureFontsAndColors];

    self.address = address;
    self.thread = [TSContactThread getThreadWithContactAddress:address transaction:transaction];

    self.avatarView.localUserAvatarMode = localUserAvatarMode;
    [self.avatarView configureWithAddress:address transaction:transaction];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(otherUsersProfileDidChange:)
                                                 name:kNSNotificationNameOtherUsersProfileDidChange
                                               object:nil];
    [self updateNameLabels];

    if (self.accessoryMessage) {
        self.accessoryLabel.text = self.accessoryMessage;
        [self setAccessoryView:self.accessoryLabel];
    }

    // Force layout, since imageView isn't being initally rendered on App Store optimized build.
    [self layoutSubviews];
}

- (void)configureWithThread:(TSThread *)thread
        localUserAvatarMode:(LocalUserAvatarMode)localUserAvatarMode
                transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(thread);
    self.thread = thread;

    self.avatarView.localUserAvatarMode = localUserAvatarMode;
    [self.avatarView configureWithThread:self.thread transaction:transaction];

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
                                                NSForegroundColorAttributeName : self.nameLabel.textColor,
                                            }];
        self.nameLabel.attributedText = attributedText;
    }

    if (self.accessoryMessage) {
        self.accessoryLabel.text = self.accessoryMessage;
        [self setAccessoryView:self.accessoryLabel];
    }

    // Force layout, since imageView isn't being initally rendered on App Store optimized build.
    [self layoutSubviews];
}

- (NSUInteger)avatarSize
{
    return self.useLargeAvatars ? kStandardAvatarSize : kSmallAvatarSize;
}

- (void)setForceDarkAppearance:(BOOL)forceDarkAppearance
{
    if (_forceDarkAppearance != forceDarkAppearance) {
        _forceDarkAppearance = forceDarkAppearance;
        [self configureFontsAndColors];
    }
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

    [self.avatarView reset];

    self.forceDarkAppearance = NO;
    self.thread = nil;
    self.accessoryMessage = nil;
    self.nameLabel.text = nil;
    self.subtitleLabel.text = nil;
    self.accessoryLabel.text = nil;
    self.customName = nil;
    for (UIView *subview in self.accessoryViewContainer.subviews) {
        [subview removeFromSuperview];
    }
    self.useLargeAvatars = NO;
}

- (void)otherUsersProfileDidChange:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    SignalServiceAddress *address = notification.userInfo[kNSNotificationKey_ProfileAddress];
    OWSAssertDebug(address.isValid);

    if (address.isValid && [self.address isEqualToAddress:address]) {
        [self updateNameLabels];
    }
}

- (NSAttributedString *)verifiedSubtitle
{
    NSMutableAttributedString *text = [NSMutableAttributedString new];
    [text appendTemplatedImageNamed:@"check-12" font:self.subtitleLabel.font];
    [text append:@" " attributes:@{}];
    [text append:NSLocalizedString(
                     @"PRIVACY_IDENTITY_IS_VERIFIED_BADGE", @"Badge indicating that the user is verified.")
        attributes:@{}];
    return [text copy];
}

- (void)setAttributedSubtitle:(nullable NSAttributedString *)attributedSubtitle
{
    self.subtitleLabel.attributedText = attributedSubtitle;
}

- (void)setSubtitle:(nullable NSString *)subtitle
{
    [self setAttributedSubtitle:subtitle.asAttributedString];
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
