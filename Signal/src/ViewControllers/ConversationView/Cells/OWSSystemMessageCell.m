//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSSystemMessageCell.h"
#import "ConversationViewItem.h"
#import "OWSMessageHeaderView.h"
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

typedef void (^SystemMessageActionBlock)(void);

@interface SystemMessageAction : NSObject

@property (nonatomic) NSString *title;
@property (nonatomic) SystemMessageActionBlock block;

@end

#pragma mark -

@implementation SystemMessageAction

+ (SystemMessageAction *)actionWithTitle:(NSString *)title block:(SystemMessageActionBlock)block
{
    SystemMessageAction *action = [SystemMessageAction new];
    action.title = title;
    action.block = block;
    return action;
}

@end

#pragma mark -

@interface OWSSystemMessageCell ()

@property (nonatomic) UIImageView *iconView;
@property (nonatomic) UILabel *titleLabel;
@property (nonatomic) UIButton *button;
@property (nonatomic) UIStackView *vStackView;
@property (nonatomic) OWSMessageHeaderView *headerView;
@property (nonatomic) NSLayoutConstraint *headerViewHeightConstraint;
@property (nonatomic) NSArray<NSLayoutConstraint *> *layoutConstraints;
@property (nonatomic, nullable) SystemMessageAction *action;

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
    OWSAssert(!self.iconView);

    self.layoutMargins = UIEdgeInsetsZero;
    self.contentView.layoutMargins = UIEdgeInsetsZero;
    self.layoutConstraints = @[];

    self.headerView = [OWSMessageHeaderView new];
    self.headerViewHeightConstraint = [self.headerView autoSetDimension:ALDimensionHeight toSize:0];

    self.iconView = [UIImageView new];
    [self.iconView autoSetDimension:ALDimensionWidth toSize:self.iconSize];
    [self.iconView autoSetDimension:ALDimensionHeight toSize:self.iconSize];
    [self.iconView setContentHuggingHigh];

    self.titleLabel = [UILabel new];
    self.titleLabel.numberOfLines = 0;
    self.titleLabel.lineBreakMode = NSLineBreakByWordWrapping;
    self.titleLabel.textAlignment = NSTextAlignmentCenter;

    UIStackView *contentStackView = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.iconView,
        self.titleLabel,
    ]];
    contentStackView.axis = UILayoutConstraintAxisVertical;
    contentStackView.spacing = self.iconVSpacing;
    contentStackView.alignment = UIStackViewAlignmentCenter;

    self.button = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.button setTitleColor:[UIColor ows_darkSkyBlueColor] forState:UIControlStateNormal];
    self.button.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.button.layer.cornerRadius = 4.f;
    [self.button addTarget:self action:@selector(buttonWasPressed:) forControlEvents:UIControlEventTouchUpInside];
    [self.button autoSetDimension:ALDimensionHeight toSize:self.buttonHeight];

    self.vStackView = [[UIStackView alloc] initWithArrangedSubviews:@[
        contentStackView,
        self.button,
    ]];
    self.vStackView.axis = UILayoutConstraintAxisVertical;
    self.vStackView.spacing = self.buttonVSpacing;
    self.vStackView.alignment = UIStackViewAlignmentCenter;
    self.vStackView.layoutMarginsRelativeArrangement = YES;

    UIStackView *cellStackView = [[UIStackView alloc] initWithArrangedSubviews:@[ self.headerView, self.vStackView ]];
    cellStackView.axis = UILayoutConstraintAxisVertical;
    [self.contentView addSubview:cellStackView];
    [cellStackView autoPinEdgesToSuperviewEdges];

    UILongPressGestureRecognizer *longPress =
        [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPressGesture:)];
    [self addGestureRecognizer:longPress];
}

- (CGFloat)buttonVSpacing
{
    return 7.f;
}

- (CGFloat)iconVSpacing
{
    return 9.f;
}

- (CGFloat)buttonHeight
{
    return 40.f;
}

- (CGFloat)buttonHPadding
{
    return 20.f;
}

- (void)configureFonts
{
    // Update cell to reflect changes in dynamic text.
    self.titleLabel.font = UIFont.ows_dynamicTypeSubheadlineFont;
}

+ (NSString *)cellReuseIdentifier
{
    return NSStringFromClass([self class]);
}

- (void)loadForDisplayWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    OWSAssert(self.conversationStyle);
    OWSAssert(self.viewItem);
    OWSAssert(transaction);

    [self.button setBackgroundColor:Theme.conversationButtonBackgroundColor];

    TSInteraction *interaction = self.viewItem.interaction;

    self.action = [self actionForInteraction:interaction];

    UIImage *_Nullable icon = [self iconForInteraction:interaction];
    if (icon) {
        self.iconView.image = [icon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        self.iconView.hidden = NO;
        self.iconView.tintColor = [self iconColorForInteraction:interaction];
    } else {
        self.iconView.hidden = YES;
    }

    self.titleLabel.textColor = [self textColor];
    [self applyTitleForInteraction:interaction label:self.titleLabel transaction:transaction];
    CGSize titleSize = [self titleSize];

    if (self.action) {
        [self.button setTitle:self.action.title forState:UIControlStateNormal];
        UIFont *buttonFont = UIFont.ows_dynamicTypeSubheadlineFont.ows_mediumWeight;
        self.button.titleLabel.font = buttonFont;
        self.button.hidden = NO;
    } else {
        self.button.hidden = YES;
    }
    CGSize buttonSize = [self.button sizeThatFits:CGSizeZero];

    [NSLayoutConstraint deactivateConstraints:self.layoutConstraints];

    if (self.viewItem.hasCellHeader) {
        self.headerView.hidden = NO;

        CGFloat headerHeight =
            [self.headerView measureWithConversationViewItem:self.viewItem conversationStyle:self.conversationStyle]
                .height;

        [self.headerView loadForDisplayWithViewItem:self.viewItem conversationStyle:self.conversationStyle];
        self.headerViewHeightConstraint.constant = headerHeight;
    } else {
        self.headerView.hidden = YES;
    }

    self.vStackView.layoutMargins = UIEdgeInsetsMake(self.topVMargin,
        self.conversationStyle.fullWidthGutterLeading,
        self.bottomVMargin,
        self.conversationStyle.fullWidthGutterLeading);

    self.layoutConstraints = @[
        [self.titleLabel autoSetDimension:ALDimensionWidth toSize:titleSize.width],
        [self.button autoSetDimension:ALDimensionWidth toSize:buttonSize.width + self.buttonHPadding * 2.f]
    ];
}

- (UIColor *)textColor
{
    return Theme.secondaryColor;
}

- (UIColor *)iconColorForInteraction:(TSInteraction *)interaction
{
    // "Phone", "Shield" and "Hourglass" icons have a lot of "ink" so they
    // are less dark for balance.
    return Theme.secondaryColor;
}

- (nullable UIImage *)iconForInteraction:(TSInteraction *)interaction
{
    UIImage *result = nil;

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
                return nil;
        }
    } else if ([interaction isKindOfClass:[TSInfoMessage class]]) {
        switch (((TSInfoMessage *)interaction).messageType) {
            case TSInfoMessageUserNotRegistered:
            case TSInfoMessageTypeSessionDidEnd:
            case TSInfoMessageTypeUnsupportedMessage:
            case TSInfoMessageAddToContactsOffer:
            case TSInfoMessageAddUserToProfileWhitelistOffer:
            case TSInfoMessageAddGroupToProfileWhitelistOffer:
            case TSInfoMessageTypeGroupUpdate:
            case TSInfoMessageTypeGroupQuit:
                return nil;
            case TSInfoMessageTypeDisappearingMessagesUpdate: {
                BOOL areDisappearingMessagesEnabled = YES;
                if ([interaction isKindOfClass:[OWSDisappearingConfigurationUpdateInfoMessage class]]) {
                    areDisappearingMessagesEnabled
                        = ((OWSDisappearingConfigurationUpdateInfoMessage *)interaction).configurationIsEnabled;
                } else {
                    OWSFail(@"%@ unexpected interaction type: %@", self.logTag, interaction.class);
                }
                result = (areDisappearingMessagesEnabled
                        ? [UIImage imageNamed:@"system_message_disappearing_messages"]
                        : [UIImage imageNamed:@"system_message_disappearing_messages_disabled"]);
                break;
            }
            case TSInfoMessageVerificationStateChange:
                OWSAssert([interaction isKindOfClass:[OWSVerificationStateChangeMessage class]]);
                if ([interaction isKindOfClass:[OWSVerificationStateChangeMessage class]]) {
                    OWSVerificationStateChangeMessage *message = (OWSVerificationStateChangeMessage *)interaction;
                    BOOL isVerified = message.verificationState == OWSVerificationStateVerified;
                    if (!isVerified) {
                        return nil;
                    }
                }
                result = [UIImage imageNamed:@"system_message_verified"];
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
                     transaction:(YapDatabaseReadTransaction *)transaction
{
    OWSAssert(interaction);
    OWSAssert(label);
    OWSAssert(transaction);

    [self configureFonts];

    // TODO: Should we move the copy generation into this view?

    if ([interaction isKindOfClass:[TSErrorMessage class]]) {
        TSErrorMessage *errorMessage = (TSErrorMessage *)interaction;
        label.text = [errorMessage previewTextWithTransaction:transaction];
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
            label.text = [infoMessage previewTextWithTransaction:transaction];
        }
    } else if ([interaction isKindOfClass:[TSCall class]]) {
        TSCall *call = (TSCall *)interaction;
        label.text = [call previewTextWithTransaction:transaction];
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
    OWSAssert(self.conversationStyle);
    OWSAssert(self.viewItem);

    CGFloat maxTitleWidth = (CGFloat)floor(self.conversationStyle.fullWidthContentWidth);
    return [self.titleLabel sizeThatFits:CGSizeMake(maxTitleWidth, CGFLOAT_MAX)];
}

- (CGSize)cellSizeWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    OWSAssert(self.conversationStyle);
    OWSAssert(self.viewItem);

    TSInteraction *interaction = self.viewItem.interaction;

    CGSize result = CGSizeMake(self.conversationStyle.viewWidth, 0);

    if (self.viewItem.hasCellHeader) {
        result.height +=
            [self.headerView measureWithConversationViewItem:self.viewItem conversationStyle:self.conversationStyle]
                .height;
    }

    UIImage *_Nullable icon = [self iconForInteraction:interaction];
    if (icon) {
        result.height += self.iconSize + self.iconVSpacing;
    }

    [self applyTitleForInteraction:interaction label:self.titleLabel transaction:transaction];
    CGSize titleSize = [self titleSize];
    result.height += titleSize.height;

    SystemMessageAction *_Nullable action = [self actionForInteraction:interaction];
    if (action) {
        result.height += self.buttonHeight + self.buttonVSpacing;
    }

    result.height += self.topVMargin + self.bottomVMargin;

    return result;
}

#pragma mark - Actions

- (nullable SystemMessageAction *)actionForInteraction:(TSInteraction *)interaction
{
    OWSAssertIsOnMainThread();
    OWSAssert(interaction);

    if ([interaction isKindOfClass:[TSErrorMessage class]]) {
        return [self actionForErrorMessage:(TSErrorMessage *)interaction];
    } else if ([interaction isKindOfClass:[TSInfoMessage class]]) {
        return [self actionForInfoMessage:(TSInfoMessage *)interaction];
    } else if ([interaction isKindOfClass:[TSCall class]]) {
        return [self actionForCall:(TSCall *)interaction];
    } else {
        OWSFail(@"Tap for system messages of unknown type: %@", [interaction class]);
        return nil;
    }
}

- (nullable SystemMessageAction *)actionForErrorMessage:(TSErrorMessage *)message
{
    OWSAssert(message);

    __weak OWSSystemMessageCell *weakSelf = self;
    switch (message.errorType) {
        case TSErrorMessageInvalidKeyException:
            return nil;
        case TSErrorMessageNonBlockingIdentityChange:
            return [SystemMessageAction
                actionWithTitle:NSLocalizedString(@"SYSTEM_MESSAGE_ACTION_VERIFY_SAFETY_NUMBER",
                                    @"Label for button to verify a user's safety number.")
                          block:^{
                              [weakSelf.delegate tappedNonBlockingIdentityChangeForRecipientId:message.recipientId];
                          }];
        case TSErrorMessageWrongTrustedIdentityKey:
            return [SystemMessageAction
                actionWithTitle:NSLocalizedString(@"SYSTEM_MESSAGE_ACTION_VERIFY_SAFETY_NUMBER",
                                    @"Label for button to verify a user's safety number.")
                          block:^{
                              [weakSelf.delegate
                                  tappedInvalidIdentityKeyErrorMessage:(TSInvalidIdentityKeyErrorMessage *)message];
                          }];
        case TSErrorMessageMissingKeyId:
        case TSErrorMessageNoSession:
            return nil;
        case TSErrorMessageInvalidMessage:
            return [SystemMessageAction actionWithTitle:NSLocalizedString(@"FINGERPRINT_SHRED_KEYMATERIAL_BUTTON", @"")
                                                  block:^{
                                                      [weakSelf.delegate tappedCorruptedMessage:message];
                                                  }];
        case TSErrorMessageDuplicateMessage:
        case TSErrorMessageInvalidVersion:
            return nil;
        case TSErrorMessageUnknownContactBlockOffer:
            OWSFail(@"TSErrorMessageUnknownContactBlockOffer");
            return nil;
        case TSErrorMessageGroupCreationFailed:
            return [SystemMessageAction actionWithTitle:CommonStrings.retryButton
                                                  block:^{
                                                      [weakSelf.delegate resendGroupUpdateForErrorMessage:message];
                                                  }];
    }

    DDLogWarn(@"%@ Unhandled tap for error message:%@", self.logTag, message);
    return nil;
}

- (nullable SystemMessageAction *)actionForInfoMessage:(TSInfoMessage *)message
{
    OWSAssert(message);

    __weak OWSSystemMessageCell *weakSelf = self;
    switch (message.messageType) {
        case TSInfoMessageUserNotRegistered:
        case TSInfoMessageTypeSessionDidEnd:
            return nil;
        case TSInfoMessageTypeUnsupportedMessage:
            // Unused.
            return nil;
        case TSInfoMessageAddToContactsOffer:
            // Unused.
            OWSFail(@"TSInfoMessageAddToContactsOffer");
            return nil;
        case TSInfoMessageAddUserToProfileWhitelistOffer:
            // Unused.
            OWSFail(@"TSInfoMessageAddUserToProfileWhitelistOffer");
            return nil;
        case TSInfoMessageAddGroupToProfileWhitelistOffer:
            // Unused.
            OWSFail(@"TSInfoMessageAddGroupToProfileWhitelistOffer");
            return nil;
        case TSInfoMessageTypeGroupUpdate:
            return nil;
        case TSInfoMessageTypeGroupQuit:
            return nil;
        case TSInfoMessageTypeDisappearingMessagesUpdate:
            return [SystemMessageAction actionWithTitle:NSLocalizedString(@"CONVERSATION_SETTINGS_TAP_TO_CHANGE",
                                                            @"Label for button that opens conversation settings.")
                                                  block:^{
                                                      [weakSelf.delegate showConversationSettings];
                                                  }];
        case TSInfoMessageVerificationStateChange:
            return [SystemMessageAction
                actionWithTitle:NSLocalizedString(@"SHOW_SAFETY_NUMBER_ACTION", @"Action sheet item")
                          block:^{
                              [weakSelf.delegate
                                  showFingerprintWithRecipientId:((OWSVerificationStateChangeMessage *)message)
                                                                     .recipientId];
                          }];
    }

    DDLogInfo(@"%@ Unhandled tap for info message: %@", self.logTag, message);
    return nil;
}

- (nullable SystemMessageAction *)actionForCall:(TSCall *)call
{
    OWSAssert(call);

    __weak OWSSystemMessageCell *weakSelf = self;
    switch (call.callType) {
        case RPRecentCallTypeIncoming:
        case RPRecentCallTypeIncomingMissed:
        case RPRecentCallTypeIncomingMissedBecauseOfChangedIdentity:
        case RPRecentCallTypeIncomingDeclined:
            return
                [SystemMessageAction actionWithTitle:NSLocalizedString(@"CALLBACK_BUTTON_TITLE", @"notification action")
                                               block:^{
                                                   [weakSelf.delegate handleCallTap:call];
                                               }];
        case RPRecentCallTypeOutgoing:
        case RPRecentCallTypeOutgoingMissed:
            return [SystemMessageAction actionWithTitle:NSLocalizedString(@"CALL_AGAIN_BUTTON_TITLE",
                                                            @"Label for button that lets users call a contact again.")
                                                  block:^{
                                                      [weakSelf.delegate handleCallTap:call];
                                                  }];
        case RPRecentCallTypeOutgoingIncomplete:
        case RPRecentCallTypeIncomingIncomplete:
            return nil;
    }
}

#pragma mark - Events

- (void)handleLongPressGesture:(UILongPressGestureRecognizer *)longPress
{
    OWSAssert(self.delegate);

    if ([self isGestureInCellHeader:longPress]) {
        return;
    }

    TSInteraction *interaction = self.viewItem.interaction;
    OWSAssert(interaction);

    if (longPress.state == UIGestureRecognizerStateBegan) {
        [self.delegate conversationCell:self didLongpressSystemMessageViewItem:self.viewItem];
    }
}

- (BOOL)isGestureInCellHeader:(UIGestureRecognizer *)sender
{
    OWSAssert(self.viewItem);

    if (!self.viewItem.hasCellHeader) {
        return NO;
    }

    CGPoint location = [sender locationInView:self];
    CGPoint headerBottom = [self convertPoint:CGPointMake(0, self.headerView.height) fromView:self.headerView];
    return location.y <= headerBottom.y;
}

- (void)buttonWasPressed:(id)sender
{
    if (!self.action.block) {
        OWSFail(@"%@ Missing action", self.logTag);
    } else {
        self.action.block();
    }
}

#pragma mark - Reuse

- (void)prepareForReuse
{
    [super prepareForReuse];

    self.action = nil;
}

@end

NS_ASSUME_NONNULL_END
