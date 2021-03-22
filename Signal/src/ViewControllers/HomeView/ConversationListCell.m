//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import "ConversationListCell.h"
#import "OWSAvatarBuilder.h"
#import "Signal-Swift.h"
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/OWSFormat.h>
#import <SignalServiceKit/OWSMath.h>
#import <SignalServiceKit/OWSMessageManager.h>
#import <SignalServiceKit/TSContactThread.h>
#import <SignalServiceKit/TSGroupThread.h>

NS_ASSUME_NONNULL_BEGIN

@interface ConversationListCell ()

@property (nonatomic) AvatarImageView *avatarView;
@property (nonatomic) UILabel *nameLabel;
@property (nonatomic) UILabel *snippetLabel;
@property (nonatomic) UILabel *dateTimeLabel;
@property (nonatomic) UIImageView *messageStatusIconView;
@property (nonatomic) UIView *messageStatusWrapper;
@property (nonatomic) TypingIndicatorView *typingIndicatorView;
@property (nonatomic) UIView *typingIndicatorWrapper;
@property (nonatomic) UIImageView *muteIconView;
@property (nonatomic) UIView *muteIconWrapper;

@property (nonatomic) UIView *unreadBadge;
@property (nonatomic) UILabel *unreadLabel;

@property (nonatomic, nullable) ThreadViewModel *thread;
@property (nonatomic, nullable) NSAttributedString *overrideSnippet;
@property (nonatomic) BOOL isBlocked;

@property (nonatomic, readonly) NSMutableArray<NSLayoutConstraint *> *viewConstraints;

@end

#pragma mark -

@implementation ConversationListCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(nullable NSString *)reuseIdentifier
{
    if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]) {
        [self commonInit];
    }
    return self;
}

// `[UIView init]` invokes `[self initWithFrame:...]`.
- (instancetype)initWithFrame:(CGRect)frame
{
    if (self = [super initWithFrame:frame]) {
        [self commonInit];
    }

    return self;
}

- (void)commonInit
{
    OWSAssertDebug(!self.avatarView);

    self.backgroundColor = Theme.backgroundColor;

    _viewConstraints = [NSMutableArray new];

    self.avatarView = [[AvatarImageView alloc] init];
    [self.contentView addSubview:self.avatarView];
    [self.avatarView autoSetDimension:ALDimensionWidth toSize:self.avatarSize];
    [self.avatarView autoSetDimension:ALDimensionHeight toSize:self.avatarSize];
    [self.avatarView autoPinEdgeToSuperviewEdge:ALEdgeLeading withInset:16];
    [self.avatarView autoVCenterInSuperview];
    [self.avatarView setContentHuggingHigh];
    [self.avatarView setCompressionResistanceHigh];
    // Ensure that the cell's contents never overflow the cell bounds.
    [self.avatarView autoPinEdgeToSuperviewEdge:ALEdgeTop withInset:12 relation:NSLayoutRelationGreaterThanOrEqual];
    [self.avatarView autoPinEdgeToSuperviewEdge:ALEdgeBottom withInset:12 relation:NSLayoutRelationGreaterThanOrEqual];

    self.nameLabel = [UILabel new];
    self.nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.nameLabel.font = self.nameFont;
    [self.nameLabel setContentHuggingHorizontalLow];

    self.dateTimeLabel = [UILabel new];
    [self.dateTimeLabel setContentHuggingHorizontalHigh];
    [self.dateTimeLabel setCompressionResistanceHorizontalHigh];

    self.typingIndicatorWrapper = [UIView containerView];
    [self.typingIndicatorWrapper setContentHuggingHorizontalHigh];
    [self.typingIndicatorWrapper setCompressionResistanceHorizontalHigh];

    self.messageStatusWrapper = [UIView containerView];
    [self.messageStatusWrapper setContentHuggingHorizontalHigh];
    [self.messageStatusWrapper setCompressionResistanceHorizontalHigh];

    self.muteIconWrapper = [UIView containerView];
    [self.muteIconWrapper setContentHuggingHorizontalHigh];
    [self.muteIconWrapper setCompressionResistanceHorizontalHigh];

    self.muteIconView = [UIImageView withTemplateImageName:@"bell-disabled-outline-24"
                                                 tintColor:Theme.primaryTextColor];
    [self.muteIconView setContentHuggingHorizontalHigh];
    [self.muteIconView setCompressionResistanceHorizontalHigh];
    [self.muteIconWrapper addSubview:self.muteIconView];
    [self.muteIconView autoPinEdgesToSuperviewEdgesWithInsets:UIEdgeInsetsMake(0, 0, 2, 0)];

    UIView *topRowSpacer = UIView.hStretchingSpacer;

    UIStackView *topRowView = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.nameLabel,
        self.muteIconWrapper,
        topRowSpacer,
        self.dateTimeLabel,
    ]];
    topRowView.axis = UILayoutConstraintAxisHorizontal;
    topRowView.alignment = UIStackViewAlignmentLastBaseline;
    topRowView.spacing = 6.f;

    self.snippetLabel = [UILabel new];
    self.snippetLabel.numberOfLines = 2;
    self.snippetLabel.lineBreakMode = NSLineBreakByWordWrapping;
    [self.snippetLabel setContentHuggingHorizontalLow];
    [self.snippetLabel setCompressionResistanceHorizontalLow];

    UIStackView *bottomRowView = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.typingIndicatorWrapper,
        self.snippetLabel,
        self.messageStatusWrapper,
    ]];
    bottomRowView.axis = UILayoutConstraintAxisHorizontal;
    bottomRowView.alignment = UIStackViewAlignmentTop;
    bottomRowView.spacing = 6.f;

    UIStackView *vStackView = [[UIStackView alloc] initWithArrangedSubviews:@[ topRowView, bottomRowView ]];
    vStackView.axis = UILayoutConstraintAxisVertical;
    vStackView.spacing = 1.f;

    [self.contentView addSubview:vStackView];
    [vStackView autoPinLeadingToTrailingEdgeOfView:self.avatarView offset:self.avatarHSpacing];
    [vStackView autoVCenterInSuperview];
    // Ensure that the cell's contents never overflow the cell bounds.
    [vStackView autoPinEdgeToSuperviewEdge:ALEdgeTop withInset:7 relation:NSLayoutRelationGreaterThanOrEqual];
    [vStackView autoPinEdgeToSuperviewEdge:ALEdgeBottom withInset:9 relation:NSLayoutRelationGreaterThanOrEqual];
    [vStackView autoPinTrailingToSuperviewMargin];

    vStackView.userInteractionEnabled = NO;

    self.messageStatusIconView = [UIImageView new];
    [self.messageStatusIconView setContentHuggingHorizontalHigh];
    [self.messageStatusIconView setCompressionResistanceHorizontalHigh];
    [self.messageStatusWrapper addSubview:self.messageStatusIconView];
    [self.messageStatusIconView autoPinWidthToSuperview];
    [self.messageStatusIconView autoVCenterInSuperview];

    self.unreadLabel = [UILabel new];
    self.unreadLabel.textColor = [UIColor ows_whiteColor];
    self.unreadLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.unreadLabel.textAlignment = NSTextAlignmentCenter;
    [self.unreadLabel setContentHuggingHigh];
    [self.unreadLabel setCompressionResistanceHigh];

    self.unreadBadge = [NeverClearView new];
    self.unreadBadge.backgroundColor = UIColor.ows_accentBlueColor;
    [self.unreadBadge addSubview:self.unreadLabel];
    [self.unreadLabel autoCenterInSuperview];
    [self.unreadBadge setContentHuggingHigh];
    [self.unreadBadge setCompressionResistanceHigh];

    [self.contentView addSubview:self.unreadBadge];

    self.typingIndicatorView = [TypingIndicatorView new];
    [self.typingIndicatorView setContentHuggingHorizontalHigh];
    [self.typingIndicatorView setCompressionResistanceHorizontalHigh];
    [self.typingIndicatorWrapper addSubview:self.typingIndicatorView];
    [self.typingIndicatorView autoPinWidthToSuperview];
    [self.typingIndicatorView autoVCenterInSuperview];
}

- (UIColor *)snippetColor
{
    return Theme.isDarkThemeEnabled ? UIColor.ows_gray25Color : UIColor.ows_gray45Color;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

+ (NSString *)cellReuseIdentifier
{
    return NSStringFromClass([self class]);
}

- (void)initializeLayout
{
    self.selectionStyle = UITableViewCellSelectionStyleDefault;
}

- (nullable NSString *)reuseIdentifier
{
    return NSStringFromClass(self.class);
}

- (void)configureWithThread:(ThreadViewModel *)thread isBlocked:(BOOL)isBlocked
{
    [self configureWithThread:thread isBlocked:isBlocked overrideSnippet:nil overrideDate:nil];
}

- (void)configureWithThread:(ThreadViewModel *)thread
                  isBlocked:(BOOL)isBlocked
            overrideSnippet:(nullable NSAttributedString *)overrideSnippet
               overrideDate:(nullable NSDate *)overrideDate
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(thread);

    [OWSTableItem configureCell:self];

    self.thread = thread;
    self.overrideSnippet = overrideSnippet;
    self.isBlocked = isBlocked;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(otherUsersProfileDidChange:)
                                                 name:kNSNotificationNameOtherUsersProfileDidChange
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(typingIndicatorStateDidChange:)
                                                 name:[OWSTypingIndicatorsImpl typingIndicatorStateDidChange]
                                               object:nil];
    [self updateNameLabel];
    [self updateAvatarView];

    // We update the fonts every time this cell is configured to ensure that
    // changes to the dynamic type settings are reflected.
    self.snippetLabel.font = self.snippetFont;
    self.snippetLabel.textColor = self.snippetColor;

    CGFloat snippetLineHeight = ceil(1.1 * self.snippetFont.ows_semibold.lineHeight);

    CGFloat muteIconSize = 16;

    [self.viewConstraints addObjectsFromArray:@[
        [self.muteIconView autoSetDimension:ALDimensionWidth toSize:muteIconSize],
        [self.muteIconView autoSetDimension:ALDimensionHeight toSize:muteIconSize],

        // These views should align with the first (of two) of the snippet,
        // so their a v-center within wrappers with the height of a single
        // snippet line.
        [self.messageStatusWrapper autoSetDimension:ALDimensionHeight toSize:snippetLineHeight],
        [self.typingIndicatorWrapper autoSetDimension:ALDimensionHeight toSize:snippetLineHeight],
    ]];

    [self updatePreview];

    NSDate *_Nullable labelDate = overrideDate ?: thread.conversationListInfo.lastMessageDate;
    if (labelDate != nil) {
        self.dateTimeLabel.text = [DateUtil formatDateShort:labelDate];
    } else {
        self.dateTimeLabel.text = nil;
    }

    if (self.hasUnreadStyle) {
        self.dateTimeLabel.font = self.dateTimeFont.ows_semibold;
        self.dateTimeLabel.textColor = Theme.primaryTextColor;
    } else {
        self.dateTimeLabel.font = self.dateTimeFont;
        self.dateTimeLabel.textColor = self.snippetColor;
    }

    BOOL shouldHideStatusIndicator = NO;

    if (overrideSnippet) {
        // If we're using the conversation list cell to render search results,
        // don't show "unread badge" or "message status" indicator.
        self.unreadBadge.hidden = YES;
        shouldHideStatusIndicator = YES;
    } else if (self.hasUnreadStyle) {
        // If there are unread messages, show the "unread badge."
        self.unreadBadge.hidden = NO;

        NSUInteger unreadCount = thread.unreadCount;
        if (unreadCount > 0) {
            self.unreadLabel.text = [OWSFormat formatInt:(int)unreadCount];
        } else {
            self.unreadLabel.text = @"";
        }

        self.unreadLabel.font = self.unreadFont;
        const int unreadBadgeHeight = (int)ceil(self.unreadLabel.font.lineHeight * 1.5f);
        self.unreadBadge.layer.cornerRadius = unreadBadgeHeight / 2;
        self.unreadBadge.layer.borderColor = Theme.backgroundColor.CGColor;
        self.unreadBadge.layer.borderWidth = 2.f;

        [NSLayoutConstraint autoSetPriority:UILayoutPriorityDefaultHigh
                             forConstraints:^{
                                 // This is a bit arbitrary, but it should scale with the size of dynamic text
                                 CGFloat minMargin = CeilEven(unreadBadgeHeight * .5f);

                                 // Spec check. Should be 12pts (6pt on each side) when using default font size.
                                 OWSAssertDebug(UIFont.ows_dynamicTypeBodyFont.pointSize != 17 || minMargin == 12);

                                 [self.viewConstraints addObjectsFromArray:@[
                                     // badge sizing
                                     [self.unreadBadge autoMatchDimension:ALDimensionWidth
                                                              toDimension:ALDimensionWidth
                                                                   ofView:self.unreadLabel
                                                               withOffset:minMargin
                                                                 relation:NSLayoutRelationGreaterThanOrEqual],
                                     [self.unreadBadge autoSetDimension:ALDimensionWidth
                                                                 toSize:unreadBadgeHeight
                                                               relation:NSLayoutRelationGreaterThanOrEqual],
                                     [self.unreadBadge autoSetDimension:ALDimensionHeight toSize:unreadBadgeHeight],
                                     [self.unreadBadge autoPinEdge:ALEdgeTrailing
                                                            toEdge:ALEdgeTrailing
                                                            ofView:self.avatarView
                                                        withOffset:6.f],
                                     [self.unreadBadge autoPinEdge:ALEdgeTop toEdge:ALEdgeTop ofView:self.avatarView]
                                 ]];
                             }];
    } else {
        self.unreadBadge.hidden = YES;
    }

    if (!shouldHideStatusIndicator && [self.thread.lastMessageForInbox isKindOfClass:[TSOutgoingMessage class]]) {
        UIImage *_Nullable statusIndicatorImage = nil;
        UIColor *messageStatusViewTintColor = self.snippetColor;
        BOOL shouldAnimateStatusIcon = NO;

        TSOutgoingMessage *outgoingMessage = (TSOutgoingMessage *)self.thread.lastMessageForInbox;

        MessageReceiptStatus messageStatus =
            [MessageRecipientStatusUtils recipientStatusWithOutgoingMessage:outgoingMessage];
        switch (messageStatus) {
            case MessageReceiptStatusUploading:
            case MessageReceiptStatusSending:
                statusIndicatorImage = [UIImage imageNamed:@"message_status_sending"];
                shouldAnimateStatusIcon = YES;
                break;
            case MessageReceiptStatusSent:
            case MessageReceiptStatusSkipped:
                statusIndicatorImage = [UIImage imageNamed:@"message_status_sent"];
                shouldHideStatusIndicator = outgoingMessage.wasRemotelyDeleted;
                break;
            case MessageReceiptStatusDelivered:
                statusIndicatorImage = [UIImage imageNamed:@"message_status_delivered"];
                shouldHideStatusIndicator = outgoingMessage.wasRemotelyDeleted;
                break;
            case MessageReceiptStatusRead:
                statusIndicatorImage = [UIImage imageNamed:@"message_status_read"];
                shouldHideStatusIndicator = outgoingMessage.wasRemotelyDeleted;
                break;
            case MessageReceiptStatusFailed:
                statusIndicatorImage = [UIImage imageNamed:@"error-outline-12"];
                messageStatusViewTintColor = UIColor.ows_accentRedColor;
                break;
        }

        self.messageStatusIconView.image =
            [statusIndicatorImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        self.messageStatusIconView.tintColor = messageStatusViewTintColor;
        self.messageStatusWrapper.hidden = shouldHideStatusIndicator || statusIndicatorImage == nil;
        if (shouldAnimateStatusIcon) {
            CABasicAnimation *animation;
            animation = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
            animation.toValue = @(M_PI * 2.0);
            const CGFloat kPeriodSeconds = 1.f;
            animation.duration = kPeriodSeconds;
            animation.cumulative = YES;
            animation.repeatCount = HUGE_VALF;
            [self.messageStatusIconView.layer addAnimation:animation forKey:@"animation"];
        } else {
            [self.messageStatusIconView.layer removeAllAnimations];
        }
    } else {
        self.messageStatusWrapper.hidden = YES;
    }
}

- (BOOL)hasUnreadStyle
{
    return (self.thread.hasUnreadMessages && self.overrideSnippet == nil);
}

- (void)updateAvatarView
{
    ThreadViewModel *thread = self.thread;
    if (thread == nil) {
        OWSFailDebug(@"thread should not be nil");
        self.avatarView.image = nil;
        return;
    }

    self.avatarView.image = [OWSAvatarBuilder buildImageForThread:thread.threadRecord diameter:self.avatarSize];
}

- (NSAttributedString *)attributedSnippetForThread:(ThreadViewModel *)thread isBlocked:(BOOL)isBlocked
{
    OWSAssertDebug(thread);

    NSMutableAttributedString *snippetText = [NSMutableAttributedString new];
    if (isBlocked) {
        // If thread is blocked, don't show a snippet or mute status.
        [snippetText append:NSLocalizedString(@"HOME_VIEW_BLOCKED_CONVERSATION",
                                @"Table cell subtitle label for a conversation the user has blocked.")
                 attributes:@{
                     NSFontAttributeName : self.snippetFont,
                     NSForegroundColorAttributeName : self.snippetColor,
                 }];
    } else if (thread.hasPendingMessageRequest) {
        // If you haven't accepted the message request for this thread, don't show the latest message

        // For group threads, show who we think added you (if we know)
        NSString *_Nullable addedToGroupByName = thread.conversationListInfo.addedToGroupByName;
        if (addedToGroupByName != nil) {
            NSString *addedToGroupFormat = NSLocalizedString(@"HOME_VIEW_MESSAGE_REQUEST_ADDED_TO_GROUP_FORMAT",
                @"Table cell subtitle label for a group the user has been added to. {Embeds inviter name}");
            [snippetText append:[NSString stringWithFormat:addedToGroupFormat, addedToGroupByName]
                     attributes:@{
                         NSFontAttributeName : self.snippetFont,
                         NSForegroundColorAttributeName : self.snippetColor,
                     }];

            // Otherwise just show a generic "message request" message
        } else {
            [snippetText append:NSLocalizedString(@"HOME_VIEW_MESSAGE_REQUEST_CONVERSATION",
                                    @"Table cell subtitle label for a conversation the user has not accepted.")
                     attributes:@{
                         NSFontAttributeName : self.snippetFont,
                         NSForegroundColorAttributeName : self.snippetColor,
                     }];
        }
    } else {
        UIFont *snippetFont = self.snippetFont;
        UIColor *currentColor = self.snippetColor;
        NSString *_Nullable draftText = thread.conversationListInfo.draftText;

        if (draftText.length > 0 && !self.hasUnreadStyle) {
            [snippetText append:NSLocalizedString(
                                    @"HOME_VIEW_DRAFT_PREFIX", @"A prefix indicating that a message preview is a draft")
                     attributes:@{
                         NSFontAttributeName : self.snippetFont.ows_italic,
                         NSForegroundColorAttributeName : currentColor,
                     }];
            [snippetText append:draftText
                     attributes:@{
                         NSFontAttributeName : snippetFont,
                         NSForegroundColorAttributeName : currentColor,
                     }];
        } else {
            NSString *lastMessageText = thread.conversationListInfo.lastMessageText.filterStringForDisplay;
            if (lastMessageText.length > 0) {
                NSString *_Nullable senderName = thread.conversationListInfo.lastMessageSenderName;
                if (senderName != nil) {
                    [snippetText append:senderName
                             attributes:@{
                                 NSFontAttributeName : snippetFont.ows_medium,
                                 NSForegroundColorAttributeName : currentColor,
                             }];
                    [snippetText append:@":"
                             attributes:@{
                                 NSFontAttributeName : snippetFont.ows_medium,
                                 NSForegroundColorAttributeName : currentColor,
                             }];
                    [snippetText append:@" "
                             attributes:@{
                                 NSFontAttributeName : snippetFont,
                             }];
                }

                [snippetText append:lastMessageText
                         attributes:@{
                             NSFontAttributeName : snippetFont,
                             NSForegroundColorAttributeName : currentColor,
                         }];
            }
        }
    }

    return snippetText;
}

- (BOOL)shouldShowMuteIndicatorForThread:(ThreadViewModel *)thread isBlocked:(BOOL)isBlocked
{
    OWSAssertDebug(thread);

    return (!self.hasOverrideSnippet && !isBlocked && !thread.hasPendingMessageRequest && thread.isMuted);
}

#pragma mark - Constants

- (UIFont *)unreadFont
{
    return [UIFont ows_dynamicTypeCaption1ClampedFont].ows_semibold;
}

- (UIFont *)dateTimeFont
{
    return [UIFont ows_dynamicTypeCaption1ClampedFont];
}

- (UIFont *)snippetFont
{
    return [UIFont ows_dynamicTypeSubheadlineClampedFont];
}

- (UIFont *)nameFont
{
    return [UIFont ows_dynamicTypeBodyClampedFont].ows_semibold;
}

// Used for profile names.
- (UIFont *)nameSecondaryFont
{
    return [UIFont ows_dynamicTypeBodyClampedFont].ows_italic;
}

- (NSUInteger)avatarSize
{
    // This value is now larger than kStandardAvatarSize.
    return 56;
}

- (NSUInteger)avatarHSpacing
{
    return 12.f;
}

#pragma mark - Reuse

- (void)prepareForReuse
{
    [super prepareForReuse];

    [NSLayoutConstraint deactivateConstraints:self.viewConstraints];
    [self.viewConstraints removeAllObjects];

    self.thread = nil;
    self.overrideSnippet = nil;
    self.avatarView.image = nil;
    self.messageStatusWrapper.hidden = NO;

    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Name

- (void)otherUsersProfileDidChange:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    SignalServiceAddress *address = notification.userInfo[kNSNotificationKey_ProfileAddress];
    if (!address.isValid) {
        return;
    }

    if (![self.thread isKindOfClass:[TSContactThread class]]) {
        return;
    }

    if (![self.thread.contactAddress isEqualToAddress:address]) {
        return;
    }

    [self updateNameLabel];
    [self updateAvatarView];
}

- (void)updateNameLabel
{
    OWSAssertIsOnMainThread();

    self.nameLabel.font = self.nameFont;
    self.nameLabel.textColor = Theme.primaryTextColor;

    ThreadViewModel *thread = self.thread;
    if (thread == nil) {
        OWSFailDebug(@"thread should not be nil");
        self.nameLabel.attributedText = nil;
        return;
    }

    NSString *_Nullable name;
    if (thread.isGroupThread) {
        if (thread.name.length == 0) {
            name = [MessageStrings newGroupDefaultTitle];
        } else {
            name = thread.name;
        }
    } else {
        if (self.thread.threadRecord.isNoteToSelf) {
            name = MessageStrings.noteToSelf;
        } else {
            name = [self.contactsManager displayNameForAddress:thread.contactAddress];
        }
    }

    self.nameLabel.text = name;
}

#pragma mark - Typing Indicators

- (BOOL)hasOverrideSnippet
{
    return self.overrideSnippet != nil;
}

- (BOOL)shouldShowTypingIndicators
{
    return (
        !self.hasOverrideSnippet && [self.typingIndicatorsImpl typingAddressForThread:self.thread.threadRecord] != nil);
}

- (void)updatePreview
{
    OWSAssertIsOnMainThread();

    // We use "override snippets" to show "message" search results.
    // We don't want to show typing indicators in that case.
    if (self.shouldShowTypingIndicators) {
        // We want to be able to show/hide the typing indicators without
        // any "jitter" in the cell layout.
        //
        // Therefore we do not hide the snippet label, but use it to
        // display two lines of non-rendering text so that it retains its
        // full height.
        self.snippetLabel.attributedText = [@" \n " asAttributedStringWithAttributes:@{
            NSFontAttributeName : self.snippetFont,
        }];
        self.snippetLabel.textColor = Theme.backgroundColor;
        self.typingIndicatorWrapper.hidden = NO;
        [self.typingIndicatorView startAnimation];
    } else {
        NSAttributedString *attributedText;
        if (self.overrideSnippet) {
            attributedText = self.overrideSnippet;
        } else {
            attributedText = [self attributedSnippetForThread:self.thread isBlocked:self.isBlocked];
        }
        // Ensure that the snippet is at least two lines so that it is top-aligned.
        //
        // UILabel appears to have an issue where it's height is
        // too large if its text is just a series of empty lines,
        // so we include spaces to avoid that issue.
        attributedText = [attributedText stringByAppendingString:@" \n \n" attributes:@{
            NSFontAttributeName : self.snippetFont,
        }];
        self.snippetLabel.attributedText = attributedText;

        self.typingIndicatorWrapper.hidden = YES;
        [self.typingIndicatorView stopAnimation];
    }

    self.muteIconWrapper.hidden = ![self shouldShowMuteIndicatorForThread:self.thread isBlocked:self.isBlocked];
    self.muteIconView.tintColor = self.snippetColor;
}

- (void)typingIndicatorStateDidChange:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(self.thread);

    if (!notification.object || ![notification.object isEqual:self.thread.threadRecord.uniqueId]) {
        return;
    }

    [self updatePreview];
}

@end

NS_ASSUME_NONNULL_END
