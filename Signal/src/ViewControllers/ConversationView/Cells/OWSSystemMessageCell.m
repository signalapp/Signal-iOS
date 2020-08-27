//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSSystemMessageCell.h"
#import "ConversationViewItem.h"
#import "Signal-Swift.h"
#import "UIFont+OWS.h"
#import "UIView+OWS.h"
#import <SignalMessaging/Environment.h>
#import <SignalMessaging/OWSContactsManager.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/OWSUnknownProtocolVersionMessage.h>
#import <SignalServiceKit/OWSVerificationStateChangeMessage.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSCall.h>
#import <SignalServiceKit/TSErrorMessage.h>
#import <SignalServiceKit/TSInfoMessage.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^SystemMessageActionBlock)(void);

@interface SystemMessageAction : NSObject

@property (nonatomic) NSString *title;
@property (nonatomic) SystemMessageActionBlock block;
@property (nonatomic) NSString *accessibilityIdentifier;

@end

#pragma mark -

@implementation SystemMessageAction

+ (SystemMessageAction *)actionWithTitle:(NSString *)title
                                   block:(SystemMessageActionBlock)block
                 accessibilityIdentifier:(NSString *)accessibilityIdentifier
{
    SystemMessageAction *action = [SystemMessageAction new];
    action.title = title;
    action.block = block;
    action.accessibilityIdentifier = accessibilityIdentifier;
    return action;
}

@end

#pragma mark -

@interface OWSSystemMessageCell () <UIGestureRecognizerDelegate, ConversationViewLongPressableCell>

@property (nonatomic) UILabel *titleLabel;
@property (nonatomic) UIButton *button;
@property (nonatomic) UIStackView *contentStackView;
@property (nonatomic) UIView *cellBackgroundView;
@property (nonatomic) NSArray<NSLayoutConstraint *> *layoutConstraints;
@property (nonatomic, nullable) SystemMessageAction *action;
@property (nonatomic) MessageSelectionView *selectionView;
@property (nonatomic, readonly) UITapGestureRecognizer *contentViewTapGestureRecognizer;

@end

#pragma mark -

@implementation OWSSystemMessageCell

- (instancetype)init
{
    return [self initWithFrame:CGRectZero];
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    return [self initWithFrame:CGRectZero];
}

// `[UIView init]` invokes `[self initWithFrame:...]`.
- (instancetype)initWithFrame:(CGRect)frame
{
    if (self = [super initWithFrame:frame]) {
        [self commontInit];
    }

    return self;
}

- (OWSContactsManager *)contactsManager
{
    return Environment.shared.contactsManager;
}

- (void)commontInit
{
    self.layoutMargins = UIEdgeInsetsZero;
    self.contentView.layoutMargins = UIEdgeInsetsZero;
    self.layoutConstraints = @[];

    self.selectionView = [MessageSelectionView new];
    _contentViewTapGestureRecognizer =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleContentViewTapGesture:)];
    self.contentViewTapGestureRecognizer.delegate = self;
    [self.contentView addGestureRecognizer:self.contentViewTapGestureRecognizer];

    self.titleLabel = [UILabel new];
    self.titleLabel.font = UIFont.ows_dynamicTypeFootnoteFont;
    self.titleLabel.numberOfLines = 0;
    self.titleLabel.lineBreakMode = NSLineBreakByWordWrapping;
    self.titleLabel.textAlignment = NSTextAlignmentCenter;

    self.button = [UIButton buttonWithType:UIButtonTypeCustom];
    self.button.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.button.contentEdgeInsets = UIEdgeInsetsMake(3, 12, 3, 12);
    self.button.layer.cornerRadius = self.buttonHeight / 2;
    [self.button addTarget:self action:@selector(buttonWasPressed:) forControlEvents:UIControlEventTouchUpInside];
    [self.button autoSetDimension:ALDimensionHeight toSize:self.buttonHeight];

    UIStackView *vStackView = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.titleLabel,
        self.button,
    ]];
    vStackView.axis = UILayoutConstraintAxisVertical;
    vStackView.spacing = self.vSpacing;
    vStackView.alignment = UIStackViewAlignmentCenter;

    UIStackView *contentStackView = [[UIStackView alloc] initWithArrangedSubviews:@[ self.selectionView, vStackView ]];

    contentStackView.axis = UILayoutConstraintAxisHorizontal;
    contentStackView.spacing = ConversationStyle.messageStackSpacing;
    contentStackView.layoutMarginsRelativeArrangement = YES;
    self.contentStackView = contentStackView;

    self.cellBackgroundView = [UIView new];
    self.cellBackgroundView.layer.cornerRadius = 5.f;
    [self.contentView addSubview:self.cellBackgroundView];

    [self.contentView addSubview:contentStackView];
    [contentStackView autoPinEdgesToSuperviewEdges];
}

- (CGFloat)vSpacing
{
    return 12.f;
}

- (CGFloat)buttonHeight
{
    return 28.f;
}

+ (NSString *)cellReuseIdentifier
{
    return NSStringFromClass([self class]);
}

- (void)loadForDisplay
{
    OWSAssertDebug(self.conversationStyle);
    OWSAssertDebug(self.viewItem);

    self.cellBackgroundView.backgroundColor = [Theme backgroundColor];

    [self.button setBackgroundColor:Theme.conversationButtonBackgroundColor];
    [self.button setTitleColor:Theme.conversationButtonTextColor forState:UIControlStateNormal];

    TSInteraction *interaction = self.viewItem.interaction;

    self.action = [self actionForInteraction:interaction];

    self.selectionView.hidden = !self.delegate.isShowingSelectionUI;

    [self applyTitleForInteraction:interaction label:self.titleLabel];
    CGSize titleSize = [self titleSize];

    if (self.action) {
        [self.button setTitle:self.action.title forState:UIControlStateNormal];
        UIFont *buttonFont = UIFont.ows_dynamicTypeFootnoteFont.ows_semibold;
        self.button.titleLabel.font = buttonFont;
        self.button.accessibilityIdentifier = self.action.accessibilityIdentifier;
        self.button.hidden = NO;
    } else {
        self.button.accessibilityIdentifier = nil;
        self.button.hidden = YES;
    }
    CGSize buttonSize = [self.button sizeThatFits:CGSizeZero];

    [NSLayoutConstraint deactivateConstraints:self.layoutConstraints];

    self.contentStackView.layoutMargins = UIEdgeInsetsMake(self.topVMargin,
        self.conversationStyle.fullWidthGutterLeading,
        self.bottomVMargin,
        self.conversationStyle.fullWidthGutterLeading);

    self.layoutConstraints = @[
        [self.titleLabel autoSetDimension:ALDimensionWidth toSize:titleSize.width],
        [self.cellBackgroundView autoPinEdge:ALEdgeTop toEdge:ALEdgeTop ofView:self.contentStackView],
        [self.cellBackgroundView autoPinEdge:ALEdgeBottom toEdge:ALEdgeBottom ofView:self.contentStackView],
        // Text in vStackView might flow right up to the edges, so only use half the gutter.
        [self.cellBackgroundView autoPinEdgeToSuperviewEdge:ALEdgeLeading
                                                  withInset:self.conversationStyle.fullWidthGutterLeading * 0.5f],
        [self.cellBackgroundView autoPinEdgeToSuperviewEdge:ALEdgeTrailing
                                                  withInset:self.conversationStyle.fullWidthGutterTrailing * 0.5f],
    ];
}

- (void)setIsCellVisible:(BOOL)isCellVisible
{
    BOOL didChange = self.isCellVisible != isCellVisible;

    [super setIsCellVisible:isCellVisible];

    if (!didChange) {
        return;
    }

    if (isCellVisible) {
        self.selectionView.hidden = !self.delegate.isShowingSelectionUI;
    } else {
        self.selectionView.hidden = YES;
    }
}

- (void)setSelected:(BOOL)selected
{
    [super setSelected:selected];

    // cellBackgroundView is helpful to focus on the interaction while message actions are
    // presented, but we don't want it to obscure the "selected" background tint.
    self.cellBackgroundView.hidden = selected;

    self.selectionView.isSelected = selected;
}

- (void)handleContentViewTapGesture:(UITapGestureRecognizer *)sender
{
    OWSAssertDebug(self.delegate);
    if (self.delegate.isShowingSelectionUI) {
        if (self.isSelected) {
            [self.delegate conversationCell:self didDeselectViewItem:self.viewItem];
        } else {
            [self.delegate conversationCell:self didSelectViewItem:self.viewItem];
        }
    }
}

#pragma mark - UIGestureRecognizerDelegate

- (UIColor *)textColorForInteraction:(TSInteraction *)interaction
{
    if ([interaction isKindOfClass:[TSCall class]]) {
        TSCall *call = (TSCall *)interaction;
        switch (call.callType) {
            case RPRecentCallTypeIncomingMissed:
            case RPRecentCallTypeIncomingMissedBecauseOfChangedIdentity:
            case RPRecentCallTypeIncomingBusyElsewhere:
            case RPRecentCallTypeIncomingDeclined:
            case RPRecentCallTypeIncomingDeclinedElsewhere:
                // We use a custom red here, as we consider changing
                // our red everywhere for better accessibility
                return [UIColor colorWithRGBHex:0xE51D0E];
            default:
                break;
        }
    }

    return Theme.secondaryTextAndIconColor;
}

- (nullable UIImage *)iconForInteraction:(TSInteraction *)interaction
{
    UIImage *result = nil;

    if ([interaction isKindOfClass:[TSErrorMessage class]]) {
        switch (((TSErrorMessage *)interaction).errorType) {
            case TSErrorMessageNonBlockingIdentityChange:
            case TSErrorMessageWrongTrustedIdentityKey:
                result = [Theme iconImage:ThemeIconSafetyNumber16];
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
                return nil;
            case TSInfoMessageTypeGroupUpdate:
            case TSInfoMessageTypeGroupQuit:
                return [Theme iconImage:ThemeIconGroup16];
            case TSInfoMessageUnknownProtocolVersion:
                OWSAssertDebug([interaction isKindOfClass:[OWSUnknownProtocolVersionMessage class]]);
                if ([interaction isKindOfClass:[OWSUnknownProtocolVersionMessage class]]) {
                    OWSUnknownProtocolVersionMessage *message = (OWSUnknownProtocolVersionMessage *)interaction;
                    result = [Theme iconImage:message.isProtocolVersionUnknown ? ThemeIconError16 : ThemeIconCheck16];
                }
                break;
            case TSInfoMessageTypeDisappearingMessagesUpdate: {
                BOOL areDisappearingMessagesEnabled = YES;
                if ([interaction isKindOfClass:[OWSDisappearingConfigurationUpdateInfoMessage class]]) {
                    areDisappearingMessagesEnabled
                        = ((OWSDisappearingConfigurationUpdateInfoMessage *)interaction).configurationIsEnabled;
                } else {
                    OWSFailDebug(@"unexpected interaction type: %@", interaction.class);
                }
                result = (areDisappearingMessagesEnabled ? [Theme iconImage:ThemeIconTimer16]
                                                         : [Theme iconImage:ThemeIconTimerDisabled16]);
                break;
            }
            case TSInfoMessageVerificationStateChange:
                OWSAssertDebug([interaction isKindOfClass:[OWSVerificationStateChangeMessage class]]);
                if ([interaction isKindOfClass:[OWSVerificationStateChangeMessage class]]) {
                    OWSVerificationStateChangeMessage *message = (OWSVerificationStateChangeMessage *)interaction;
                    BOOL isVerified = message.verificationState == OWSVerificationStateVerified;
                    if (!isVerified) {
                        return nil;
                    }
                }
                result = [Theme iconImage:ThemeIconCheck16];
                break;
            case TSInfoMessageUserJoinedSignal:
                result = [Theme iconImage:ThemeIconHeart16];
                break;
            case TSInfoMessageSyncedThread:
                result = [Theme iconImage:ThemeIconInfo16];
                break;
            case TSInfoMessageProfileUpdate:
                result = [Theme iconImage:ThemeIconProfile16];
                break;
        }
    } else if ([interaction isKindOfClass:[TSCall class]]) {
        TSCall *call = (TSCall *)interaction;

        NSString *offerTypeString;
        switch (call.offerType) {
            case TSRecentCallOfferTypeAudio:
                offerTypeString = @"phone";
                break;
            case TSRecentCallOfferTypeVideo:
                offerTypeString = @"video";
                break;
        }

        NSString *directionString;
        switch (call.callType) {
            case RPRecentCallTypeIncomingMissed:
            case RPRecentCallTypeIncomingMissedBecauseOfChangedIdentity:
            case RPRecentCallTypeIncomingBusyElsewhere:
            case RPRecentCallTypeIncomingDeclined:
            case RPRecentCallTypeIncomingDeclinedElsewhere:
                directionString = @"x";
                break;
            case RPRecentCallTypeIncoming:
            case RPRecentCallTypeIncomingIncomplete:
            case RPRecentCallTypeIncomingAnsweredElsewhere:
                directionString = @"incoming";
                break;
            case RPRecentCallTypeOutgoing:
            case RPRecentCallTypeOutgoingIncomplete:
            case RPRecentCallTypeOutgoingMissed:
                directionString = @"outgoing";
                break;
        }

        NSString *themeString = Theme.isDarkThemeEnabled ? @"solid" : @"outline";

        return [UIImage
            imageNamed:[NSString stringWithFormat:@"%@-%@-%@-16", offerTypeString, directionString, themeString]];
    } else {
        OWSFailDebug(@"Unknown interaction type: %@", [interaction class]);
        return nil;
    }
    OWSAssertDebug(result);
    return result;
}

- (NSString *)iconNameForGroupUpdate:(GroupUpdateType)type
{
    NSString *iconName;

    switch (type) {
        case GroupUpdateTypeUserMembershipState_left:
            iconName = [Theme iconName:ThemeIconLeave16];
            break;
        case GroupUpdateTypeUserMembershipState_removed:
            iconName = [Theme iconName:ThemeIconMemberRemove16];
            break;
        case GroupUpdateTypeUserMembershipState_invited:
        case GroupUpdateTypeUserMembershipState_added:
        case GroupUpdateTypeUserMembershipState_invitesNew:
            iconName = [Theme iconName:ThemeIconMemberAdded16];
            break;
        case GroupUpdateTypeGroupCreated:
        case GroupUpdateTypeGeneric:
        case GroupUpdateTypeDebug:
        case GroupUpdateTypeUserMembershipState:
        case GroupUpdateTypeUserMembershipState_invalidInvitesRemoved:
        case GroupUpdateTypeUserMembershipState_invalidInvitesAdded:
        case GroupUpdateTypeGroupInviteLink:
            iconName = [Theme iconName:ThemeIconGroup16];
            break;
        case GroupUpdateTypeUserMembershipState_invitesDeclined:
        case GroupUpdateTypeUserMembershipState_invitesRevoked:
            iconName = [Theme iconName:ThemeIconMemberDeclined16];
            break;
        case GroupUpdateTypeAccessAttributes:
        case GroupUpdateTypeAccessMembers:
        case GroupUpdateTypeUserRole:
            iconName = [Theme iconName:ThemeIconMegaphone16];
            break;
        case GroupUpdateTypeGroupName:
            iconName = [Theme iconName:ThemeIconCompose16];
            break;
        case GroupUpdateTypeGroupAvatar:
            iconName = [Theme iconName:ThemeIconPhoto16];
            break;
        case GroupUpdateTypeDisappearingMessagesState:
        case GroupUpdateTypeDisappearingMessagesState_enabled:
            iconName = [Theme iconName:ThemeIconTimer16];
            break;
        case GroupUpdateTypeDisappearingMessagesState_disabled:
            iconName = [Theme iconName:ThemeIconTimerDisabled16];
            break;
    }

    return iconName;
}

- (void)applyTitleForInteraction:(TSInteraction *)interaction
                           label:(UILabel *)label
{
    OWSAssertDebug(interaction);
    OWSAssertDebug(label);

    label.textColor = [self textColorForInteraction:interaction];
    NSMutableAttributedString *labelText = [NSMutableAttributedString new];

    if (self.viewItem.systemMessageGroupUpdates.count > 0) {
        for (GroupUpdateCopyItem *update in self.viewItem.systemMessageGroupUpdates) {
            NSString *iconName = [self iconNameForGroupUpdate:update.type];

            [labelText appendTemplatedImageNamed:iconName
                                            font:label.font
                                 heightReference:ImageAttachmentHeightReferenceLineHeight];
            [labelText append:@"  " attributes:@{}];
            [labelText append:update.text attributes:@{}];

            if (![update isEqual:self.viewItem.systemMessageGroupUpdates.lastObject]) {
                [labelText append:@"\n" attributes:@{}];
            }
        }

        if (self.viewItem.systemMessageGroupUpdates.count > 1) {
            NSMutableParagraphStyle *paragraphStyle = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
            paragraphStyle.paragraphSpacing = 12;
            paragraphStyle.alignment = NSTextAlignmentCenter;

            [labelText addAttribute:NSParagraphStyleAttributeName
                              value:paragraphStyle
                              range:NSMakeRange(0, labelText.length)];
        }
    } else {
        OWSAssertDebug(self.viewItem.systemMessageText.length > 0);

        UIImage *_Nullable icon = [self iconForInteraction:interaction];
        if (icon) {
            [labelText appendImage:[icon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]
                              font:label.font
                   heightReference:ImageAttachmentHeightReferenceLineHeight];
            [labelText appendAttributedString:[[NSAttributedString alloc] initWithString:@"  "]];
        }

        [labelText appendAttributedString:[[NSAttributedString alloc] initWithString:self.viewItem.systemMessageText]];

        if (self.shouldShowTimestamp) {
            [labelText
                appendAttributedString:[[NSAttributedString alloc] initWithString:LocalizationNotNeeded(@" · ")]];

            NSString *dateString = [DateUtil formatTimestampAsDate:interaction.timestamp];
            [labelText appendAttributedString:[[NSAttributedString alloc] initWithString:dateString]];

            [labelText appendAttributedString:[[NSAttributedString alloc] initWithString:LocalizationNotNeeded(@" ")]];

            NSString *timeString = [DateUtil formatTimestampAsTime:interaction.timestamp];
            [labelText appendAttributedString:[[NSAttributedString alloc] initWithString:timeString]];
        }
    }

    label.attributedText = labelText;
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

- (BOOL)shouldShowTimestamp
{
    return self.viewItem.interaction.interactionType == OWSInteractionType_Call;
}

- (CGSize)titleSize
{
    OWSAssertDebug(self.conversationStyle);
    OWSAssertDebug(self.viewItem);

    CGFloat maxTitleWidth = (CGFloat)floor(self.conversationStyle.selectableCenteredContentWidth);
    return [self.titleLabel sizeThatFits:CGSizeMake(maxTitleWidth, CGFLOAT_MAX)];
}

- (CGSize)cellSize
{
    OWSAssertDebug(self.conversationStyle);
    OWSAssertDebug(self.viewItem);

    TSInteraction *interaction = self.viewItem.interaction;

    CGSize result = CGSizeMake(self.conversationStyle.viewWidth, 0);

    [self applyTitleForInteraction:interaction label:self.titleLabel];
    CGSize titleSize = [self titleSize];
    result.height += titleSize.height;

    SystemMessageAction *_Nullable action = [self actionForInteraction:interaction];
    if (action) {
        result.height += self.buttonHeight + self.vSpacing;
    }

    result.height += self.topVMargin + self.bottomVMargin;

    return result;
}

#pragma mark - Actions

- (nullable SystemMessageAction *)actionForInteraction:(TSInteraction *)interaction
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(self.viewItem);
    OWSAssertDebug(interaction);

    if (self.viewItem.shouldCollapseSystemMessageAction) {
        return nil;
    }

    if ([interaction isKindOfClass:[TSErrorMessage class]]) {
        return [self actionForErrorMessage:(TSErrorMessage *)interaction];
    } else if ([interaction isKindOfClass:[TSInfoMessage class]]) {
        return [self actionForInfoMessage:(TSInfoMessage *)interaction];
    } else if ([interaction isKindOfClass:[TSCall class]]) {
        return [self actionForCall:(TSCall *)interaction];
    } else {
        OWSFailDebug(@"Tap for system messages of unknown type: %@", [interaction class]);
        return nil;
    }
}

- (nullable SystemMessageAction *)actionForErrorMessage:(TSErrorMessage *)message
{
    OWSAssertDebug(message);

    __weak OWSSystemMessageCell *weakSelf = self;
    switch (message.errorType) {
        case TSErrorMessageNonBlockingIdentityChange:
            return [SystemMessageAction
                        actionWithTitle:NSLocalizedString(@"SYSTEM_MESSAGE_ACTION_VERIFY_SAFETY_NUMBER",
                                            @"Label for button to verify a user's safety number.")
                                  block:^{
                                      [weakSelf.delegate
                                          tappedNonBlockingIdentityChangeForAddress:message.recipientAddress];
                                  }
                accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"verify_safety_number")];
        case TSErrorMessageWrongTrustedIdentityKey:
            return [SystemMessageAction
                        actionWithTitle:NSLocalizedString(@"SYSTEM_MESSAGE_ACTION_VERIFY_SAFETY_NUMBER",
                                            @"Label for button to verify a user's safety number.")
                                  block:^{
                                      [weakSelf.delegate
                                          tappedInvalidIdentityKeyErrorMessage:(TSInvalidIdentityKeyErrorMessage *)
                                                                                   message];
                                  }
                accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"verify_safety_number")];
        case TSErrorMessageInvalidKeyException:
        case TSErrorMessageMissingKeyId:
        case TSErrorMessageNoSession:
        case TSErrorMessageInvalidMessage:
            return [SystemMessageAction actionWithTitle:NSLocalizedString(@"FINGERPRINT_SHRED_KEYMATERIAL_BUTTON", @"")
                                                  block:^{
                                                      [weakSelf.delegate tappedCorruptedMessage:message];
                                                  }
                                accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"reset_session")];
        case TSErrorMessageDuplicateMessage:
        case TSErrorMessageInvalidVersion:
            return nil;
        case TSErrorMessageUnknownContactBlockOffer:
            OWSFailDebug(@"TSErrorMessageUnknownContactBlockOffer");
            return nil;
        case TSErrorMessageGroupCreationFailed:
            return [SystemMessageAction actionWithTitle:CommonStrings.retryButton
                                                  block:^{
                                                      [weakSelf.delegate resendGroupUpdateForErrorMessage:message];
                                                  }
                                accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"retry")];
    }

    OWSLogWarn(@"Unhandled tap for error message:%@", message);
    return nil;
}

- (nullable SystemMessageAction *)actionForInfoMessage:(TSInfoMessage *)infoMessage
{
    OWSAssertDebug(infoMessage);

    __weak OWSSystemMessageCell *weakSelf = self;
    switch (infoMessage.messageType) {
        case TSInfoMessageUserNotRegistered:
        case TSInfoMessageTypeSessionDidEnd:
            return nil;
        case TSInfoMessageTypeUnsupportedMessage:
            // Unused.
            return nil;
        case TSInfoMessageAddToContactsOffer:
            // Unused.
            OWSFailDebug(@"TSInfoMessageAddToContactsOffer");
            return nil;
        case TSInfoMessageAddUserToProfileWhitelistOffer:
            // Unused.
            OWSFailDebug(@"TSInfoMessageAddUserToProfileWhitelistOffer");
            return nil;
        case TSInfoMessageAddGroupToProfileWhitelistOffer:
            // Unused.
            OWSFailDebug(@"TSInfoMessageAddGroupToProfileWhitelistOffer");
            return nil;
        case TSInfoMessageTypeGroupUpdate:
            return nil;
        case TSInfoMessageTypeGroupQuit:
            return nil;
        case TSInfoMessageUnknownProtocolVersion: {
            if (![infoMessage isKindOfClass:[OWSUnknownProtocolVersionMessage class]]) {
                OWSFailDebug(@"Unexpected message type.");
                return nil;
            }
            OWSUnknownProtocolVersionMessage *message = (OWSUnknownProtocolVersionMessage *)infoMessage;
            if (message.isProtocolVersionUnknown) {
                return [SystemMessageAction
                            actionWithTitle:NSLocalizedString(@"UNKNOWN_PROTOCOL_VERSION_UPGRADE_BUTTON",
                                                @"Label for button that lets users upgrade the app.")
                                      block:^{
                                          [weakSelf showUpgradeAppUI];
                                      }
                    accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"show_upgrade_app_ui")];
            }
            return nil;
        }
        case TSInfoMessageTypeDisappearingMessagesUpdate:
            return nil;
        case TSInfoMessageVerificationStateChange:
            return nil;
        case TSInfoMessageUserJoinedSignal:
            return nil;
        case TSInfoMessageSyncedThread:
            return nil;
        case TSInfoMessageProfileUpdate:
            if ([self.contactsManager isSystemContactWithAddress:infoMessage.profileChangeAddress]
                && infoMessage.profileChangeNewNameComponents) {
                NSString *_Nullable systemContactName =
                    [self.contactsManager nameFromSystemContactsForAddress:infoMessage.profileChangeAddress];
                NSString *newProfileName = [NSPersonNameComponentsFormatter
                    localizedStringFromPersonNameComponents:infoMessage.profileChangeNewNameComponents
                                                      style:0
                                                    options:0];
                NSString *_Nullable currentProfileName = self.viewItem.senderProfileName;

                // Don't show the update contact button if the system contact name
                // is already equivalent to the new profile name.
                if ([NSObject isNullableObject:systemContactName equalTo:newProfileName]) {
                    return nil;
                }

                // If the new profile name is not the current profile name, it's no
                // longer relevant to ask you to update your contact.
                if (![NSObject isNullableObject:currentProfileName equalTo:newProfileName]) {
                    return nil;
                }

                return [SystemMessageAction
                            actionWithTitle:NSLocalizedString(@"UPDATE_CONTACT_ACTION", @"Action sheet item")
                                      block:^{
                                          [weakSelf.delegate
                                              updateSystemContactWithAddress:infoMessage.profileChangeAddress
                                                       withNewNameComponents:infoMessage
                                                                                 .profileChangeNewNameComponents];
                                      }
                    accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"update_contact")];
            } else {
                return nil;
            }
    }

    OWSLogInfo(@"Unhandled tap for info message: %@", infoMessage);
    return nil;
}

- (nullable SystemMessageAction *)actionForCall:(TSCall *)call
{
    OWSAssertDebug(call);

    __weak OWSSystemMessageCell *weakSelf = self;
    switch (call.callType) {
        case RPRecentCallTypeIncoming:
        case RPRecentCallTypeIncomingMissed:
        case RPRecentCallTypeIncomingMissedBecauseOfChangedIdentity:
        case RPRecentCallTypeIncomingDeclined:
        case RPRecentCallTypeIncomingAnsweredElsewhere:
        case RPRecentCallTypeIncomingDeclinedElsewhere:
        case RPRecentCallTypeIncomingBusyElsewhere:
            if ([self.delegate conversationCellHasPendingMessageRequest:self]) {
                return nil;
            }
            return
                [SystemMessageAction actionWithTitle:NSLocalizedString(@"CALLBACK_BUTTON_TITLE", @"notification action")
                                               block:^{
                                                   [weakSelf.delegate handleCallTap:call];
                                               }
                             accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"call_back")];
        case RPRecentCallTypeOutgoing:
        case RPRecentCallTypeOutgoingMissed:
            if ([self.delegate conversationCellHasPendingMessageRequest:self]) {
                return nil;
            }
            return [SystemMessageAction actionWithTitle:NSLocalizedString(@"CALL_AGAIN_BUTTON_TITLE",
                                                            @"Label for button that lets users call a contact again.")
                                                  block:^{
                                                      [weakSelf.delegate handleCallTap:call];
                                                  }
                                accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"call_again")];
        case RPRecentCallTypeOutgoingIncomplete:
        case RPRecentCallTypeIncomingIncomplete:
            return nil;
    }
}

#pragma mark - Events

- (void)handleLongPressGesture:(UILongPressGestureRecognizer *)longPress
{
    OWSAssertDebug(self.delegate);

    __unused TSInteraction *interaction = self.viewItem.interaction;
    OWSAssertDebug(interaction);

    if (longPress.state == UIGestureRecognizerStateBegan) {
        [self.delegate conversationCell:self didLongpressSystemMessageViewItem:self.viewItem];
    }
}

- (void)buttonWasPressed:(id)sender
{
    if (self.delegate.isShowingSelectionUI) {
        // While in select mode, any actions should be superseded by the tap gesture.
        // TODO - this is kind of a hack. A better approach might be to disable the button
        // when delegate.isShowingSelectionUI changes, but that requires some additional plumbing.
        if (self.isSelected) {
            [self.delegate conversationCell:self didDeselectViewItem:self.viewItem];
        } else {
            [self.delegate conversationCell:self didSelectViewItem:self.viewItem];
        }
    } else if (!self.action.block) {
        OWSFailDebug(@"Missing action");
    } else {
        self.action.block();
    }
}

- (void)showUpgradeAppUI
{
    NSString *url = @"https://itunes.apple.com/us/app/signal-private-messenger/id874139669?mt=8";
    [UIApplication.sharedApplication openURL:[NSURL URLWithString:url] options:@{} completionHandler:nil];
}

#pragma mark - Reuse

- (void)prepareForReuse
{
    [super prepareForReuse];

    self.action = nil;
    self.selectionView.alpha = 1.0;
    self.selected = NO;
}

@end

NS_ASSUME_NONNULL_END
