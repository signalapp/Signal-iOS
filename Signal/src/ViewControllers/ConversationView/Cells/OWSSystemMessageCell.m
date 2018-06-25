//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSSystemMessageCell.h"
#import "ConversationViewItem.h"
#import "Signal-Swift.h"
#import "UIColor+OWS.h"
#import "UIFont+OWS.h"
#import "UIView+OWS.h"
#import <SignalMessaging/Environment.h>
#import <SignalMessaging/OWSContactsManager.h>
#import <SignalServiceKit/OWSVerificationStateChangeMessage.h>
#import <SignalServiceKit/TSCall.h>
#import <SignalServiceKit/TSErrorMessage.h>
#import <SignalServiceKit/TSInfoMessage.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSSystemMessageCell ()

@property (nonatomic, nullable) TSInteraction *interaction;

@property (nonatomic) UIImageView *imageView;
@property (nonatomic) UILabel *titleLabel;
@property (nonatomic) UIStackView *stackView;
@property (nonatomic) NSArray<NSLayoutConstraint *> *layoutConstraints;

@end

#pragma mark -

@implementation OWSSystemMessageCell

// `[UIView init]` invokes `[self initWithFrame:...]`.
- (instancetype)initWithFrame:(CGRect)frame
{
    if (self = [super initWithFrame:frame]) {
        [self commontInit];
    }

    return self;
}

- (void)commontInit
{
    OWSAssert(!self.imageView);

    self.layoutMargins = UIEdgeInsetsZero;
    self.contentView.layoutMargins = UIEdgeInsetsZero;

    self.imageView = [UIImageView new];
    [self.imageView autoSetDimension:ALDimensionWidth toSize:self.iconSize];
    [self.imageView autoSetDimension:ALDimensionHeight toSize:self.iconSize];
    [self.imageView setContentHuggingHigh];

    self.titleLabel = [UILabel new];
    self.titleLabel.textColor = [UIColor colorWithRGBHex:0x403e3b];
    self.titleLabel.numberOfLines = 0;
    self.titleLabel.lineBreakMode = NSLineBreakByWordWrapping;

    self.stackView = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.imageView,
        self.titleLabel,
    ]];
    self.stackView.axis = UILayoutConstraintAxisHorizontal;
    self.stackView.spacing = self.hSpacing;
    self.stackView.alignment = UIStackViewAlignmentCenter;
    [self.contentView addSubview:self.stackView];

    UITapGestureRecognizer *tap =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTapGesture:)];
    [self addGestureRecognizer:tap];

    UILongPressGestureRecognizer *longPress =
        [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPressGesture:)];
    [self addGestureRecognizer:longPress];
}

- (void)configureFonts
{
    // Update cell to reflect changes in dynamic text.
    self.titleLabel.font = UIFont.ows_dynamicTypeFootnoteFont;
}

+ (NSString *)cellReuseIdentifier
{
    return NSStringFromClass([self class]);
}

- (void)loadForDisplayWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    OWSAssert(self.layoutInfo);
    OWSAssert(self.viewItem);

    TSInteraction *interaction = self.viewItem.interaction;

    UIImage *icon = [self iconForInteraction:interaction];
    self.imageView.image = [icon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    self.imageView.tintColor = [self iconColorForInteraction:interaction];
    self.titleLabel.textColor = [self textColor];
    [self applyTitleForInteraction:interaction label:self.titleLabel];

    CGSize titleSize = [self titleSize];

    [NSLayoutConstraint deactivateConstraints:self.layoutConstraints];
    self.layoutConstraints = @[
        [self.titleLabel autoSetDimension:ALDimensionWidth toSize:titleSize.width],
        [self.stackView autoPinEdgeToSuperviewEdge:ALEdgeTop withInset:self.topVMargin],
        [self.stackView autoPinEdgeToSuperviewEdge:ALEdgeBottom withInset:self.bottomVMargin],
        // H-center the stack.
        [self.stackView autoHCenterInSuperview],
        [self.stackView autoPinEdgeToSuperviewEdge:ALEdgeLeading
                                         withInset:self.layoutInfo.fullWidthGutterLeading
                                          relation:NSLayoutRelationGreaterThanOrEqual],
        [self.stackView autoPinEdgeToSuperviewEdge:ALEdgeTrailing
                                         withInset:self.layoutInfo.fullWidthGutterTrailing
                                          relation:NSLayoutRelationGreaterThanOrEqual],
    ];
}

- (UIColor *)textColor
{
    return [UIColor colorWithRGBHex:0x303030];
}

- (UIColor *)iconColorForInteraction:(TSInteraction *)interaction
{
    // "Phone", "Shield" and "Hourglass" icons have a lot of "ink" so they
    // are less dark for balance.
    return [UIColor colorWithRGBHex:0x404040];
}

- (UIImage *)iconForInteraction:(TSInteraction *)interaction
{
    UIImage *result = nil;

    // TODO: Don't cast.
    if ([interaction isKindOfClass:[TSErrorMessage class]]) {
        switch (((TSErrorMessage *)interaction).errorType) {
            case TSErrorMessageNonBlockingIdentityChange:
            case TSErrorMessageWrongTrustedIdentityKey:
                result = [UIImage imageNamed:@"system_message_security"];
                break;
            case TSErrorMessageInvalidKeyException:
            case TSErrorMessageMissingKeyId:
            case TSErrorMessageNoSession:
            case TSErrorMessageInvalidMessage:
            case TSErrorMessageDuplicateMessage:
            case TSErrorMessageInvalidVersion:
            case TSErrorMessageUnknownContactBlockOffer:
            case TSErrorMessageGroupCreationFailed:
                result = [UIImage imageNamed:@"system_message_info"];
                break;
        }
    } else if ([interaction isKindOfClass:[TSInfoMessage class]]) {
        switch (((TSInfoMessage *)interaction).messageType) {
            case TSInfoMessageUserNotRegistered:
            case TSInfoMessageTypeSessionDidEnd:
            case TSInfoMessageTypeUnsupportedMessage:
            case TSInfoMessageAddToContactsOffer:
            case TSInfoMessageAddUserToProfileWhitelistOffer:
            case TSInfoMessageAddGroupToProfileWhitelistOffer:
                result = [UIImage imageNamed:@"system_message_info"];
                break;
            case TSInfoMessageTypeGroupUpdate:
            case TSInfoMessageTypeGroupQuit:
                result = [UIImage imageNamed:@"system_message_group"];
                break;
            case TSInfoMessageTypeDisappearingMessagesUpdate:
                result = [UIImage imageNamed:@"ic_timer"];
                break;
            case TSInfoMessageVerificationStateChange:
                result = [UIImage imageNamed:@"system_message_verified"];

                OWSAssert([interaction isKindOfClass:[OWSVerificationStateChangeMessage class]]);
                if ([interaction isKindOfClass:[OWSVerificationStateChangeMessage class]]) {
                    OWSVerificationStateChangeMessage *message = (OWSVerificationStateChangeMessage *)interaction;
                    BOOL isVerified = message.verificationState == OWSVerificationStateVerified;
                    if (!isVerified) {
                        result = [UIImage imageNamed:@"system_message_info"];
                    }
                }
                break;
        }
    } else if ([interaction isKindOfClass:[TSCall class]]) {
        result = [UIImage imageNamed:@"system_message_call"];
    } else {
        OWSFail(@"Unknown interaction type: %@", [interaction class]);
        return nil;
    }
    OWSAssert(result);
    return result;
}

- (void)applyTitleForInteraction:(TSInteraction *)interaction
                           label:(UILabel *)label
{
    OWSAssert(interaction);
    OWSAssert(label);

    [self configureFonts];

    // TODO: Should we move the copy generation into this view?

    if ([interaction isKindOfClass:[TSErrorMessage class]]) {
        TSErrorMessage *errorMessage = (TSErrorMessage *)interaction;
        label.text = [errorMessage previewText];
    } else if ([interaction isKindOfClass:[TSInfoMessage class]]) {
        TSInfoMessage *infoMessage = (TSInfoMessage *)interaction;
        if ([infoMessage isKindOfClass:[OWSVerificationStateChangeMessage class]]) {
            OWSVerificationStateChangeMessage *verificationMessage = (OWSVerificationStateChangeMessage *)infoMessage;
            BOOL isVerified = verificationMessage.verificationState == OWSVerificationStateVerified;
            NSString *displayName =
                [[Environment current].contactsManager displayNameForPhoneIdentifier:verificationMessage.recipientId];
            NSString *titleFormat = (isVerified
                    ? (verificationMessage.isLocalChange
                              ? NSLocalizedString(@"VERIFICATION_STATE_CHANGE_FORMAT_VERIFIED_LOCAL",
                                    @"Format for info message indicating that the verification state was verified on "
                                    @"this device. Embeds {{user's name or phone number}}.")
                              : NSLocalizedString(@"VERIFICATION_STATE_CHANGE_FORMAT_VERIFIED_OTHER_DEVICE",
                                    @"Format for info message indicating that the verification state was verified on "
                                    @"another device. Embeds {{user's name or phone number}}."))
                    : (verificationMessage.isLocalChange
                              ? NSLocalizedString(@"VERIFICATION_STATE_CHANGE_FORMAT_NOT_VERIFIED_LOCAL",
                                    @"Format for info message indicating that the verification state was unverified on "
                                    @"this device. Embeds {{user's name or phone number}}.")
                              : NSLocalizedString(@"VERIFICATION_STATE_CHANGE_FORMAT_NOT_VERIFIED_OTHER_DEVICE",
                                    @"Format for info message indicating that the verification state was unverified on "
                                    @"another device. Embeds {{user's name or phone number}}.")));
            label.text = [NSString stringWithFormat:titleFormat, displayName];
        } else {
            label.text = [infoMessage previewText];
        }
    } else if ([interaction isKindOfClass:[TSCall class]]) {
        TSCall *call = (TSCall *)interaction;
        label.text = [call previewText];
    } else {
        OWSFail(@"Unknown interaction type: %@", [interaction class]);
        label.text = nil;
    }
}

- (CGFloat)topVMargin
{
    return 5.f;
}

- (CGFloat)bottomVMargin
{
    return 5.f;
}

- (CGFloat)hSpacing
{
    return 8.f;
}

- (CGFloat)iconSize
{
    return 20.f;
}

- (CGSize)titleSize
{
    OWSAssert(self.layoutInfo);
    OWSAssert(self.viewItem);

    CGFloat hMargins = (self.layoutInfo.fullWidthGutterLeading + self.layoutInfo.fullWidthGutterTrailing);
    CGFloat maxTitleWidth
        = (CGFloat)floor(self.layoutInfo.fullWidthContentWidth - (hMargins + self.iconSize + self.hSpacing));
    return [self.titleLabel sizeThatFits:CGSizeMake(maxTitleWidth, CGFLOAT_MAX)];
}

- (CGSize)cellSize
{
    OWSAssert(self.layoutInfo);
    OWSAssert(self.viewItem);

    TSInteraction *interaction = self.viewItem.interaction;

    CGSize result = CGSizeMake(self.layoutInfo.viewWidth, 0);

    [self applyTitleForInteraction:interaction label:self.titleLabel];

    CGSize titleSize = [self titleSize];
    CGFloat contentHeight = ceil(MAX([self iconSize], titleSize.height));
    result.height = (contentHeight + self.topVMargin + self.bottomVMargin);

    return result;
}

#pragma mark - UIMenuController

- (void)showMenuController
{
    OWSAssertIsOnMainThread();

    DDLogDebug(@"%@ long pressed system message cell: %@", self.logTag, self.viewItem.interaction.debugDescription);

    [self becomeFirstResponder];

    if ([UIMenuController sharedMenuController].isMenuVisible) {
        [[UIMenuController sharedMenuController] setMenuVisible:NO animated:NO];
    }

    UIMenuController *menuController = [UIMenuController sharedMenuController];
    menuController.menuItems = @[];
    UIView *fromView = self.titleLabel;
    CGRect targetRect = [fromView.superview convertRect:fromView.frame toView:self];
    [menuController setTargetRect:targetRect inView:self];
    [menuController setMenuVisible:YES animated:YES];
}

- (BOOL)canPerformAction:(SEL)action withSender:(nullable id)sender
{
    return action == @selector(delete:);
}

- (void)delete:(nullable id)sender
{
    DDLogInfo(@"%@ chose delete", self.logTag);

    TSInteraction *interaction = self.viewItem.interaction;
    OWSAssert(interaction);

    [interaction remove];
}

- (BOOL)canBecomeFirstResponder
{
    return YES;
}

#pragma mark - Gesture recognizers

- (void)handleTapGesture:(UITapGestureRecognizer *)sender
{
    OWSAssert(self.delegate);

    if (sender.state == UIGestureRecognizerStateRecognized) {
        TSInteraction *interaction = self.viewItem.interaction;
        OWSAssert(interaction);
        [self.delegate didTapSystemMessageWithInteraction:interaction];
    }
}

- (void)handleLongPressGesture:(UILongPressGestureRecognizer *)longPress
{
    OWSAssert(self.delegate);

    TSInteraction *interaction = self.viewItem.interaction;
    OWSAssert(interaction);

    if (longPress.state == UIGestureRecognizerStateBegan) {
        [self showMenuController];
    }
}

@end

NS_ASSUME_NONNULL_END
