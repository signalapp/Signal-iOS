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
@property (nonatomic) MessageStatusView *messageStatusView;
@property (nonatomic) TypingIndicatorView *typingIndicatorView;

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
    [self.avatarView autoPinEdgeToSuperviewEdge:ALEdgeTop withInset:8 relation:NSLayoutRelationGreaterThanOrEqual];
    [self.avatarView autoPinEdgeToSuperviewEdge:ALEdgeBottom withInset:8 relation:NSLayoutRelationGreaterThanOrEqual];

    self.nameLabel = [UILabel new];
    self.nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.nameLabel.font = self.nameFont;
    [self.nameLabel setContentHuggingHorizontalLow];
    [self.nameLabel setCompressionResistanceHorizontalLow];

    self.dateTimeLabel = [UILabel new];
    [self.dateTimeLabel setContentHuggingHorizontalHigh];
    [self.dateTimeLabel setCompressionResistanceHorizontalHigh];

    self.messageStatusView = [MessageStatusView new];
    [self.messageStatusView setContentHuggingHorizontalHigh];
    [self.messageStatusView setCompressionResistanceHorizontalHigh];

    UIStackView *topRowView = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.nameLabel,
        self.dateTimeLabel,
    ]];
    topRowView.axis = UILayoutConstraintAxisHorizontal;
    topRowView.alignment = UIStackViewAlignmentLastBaseline;
    topRowView.spacing = 6.f;

    self.snippetLabel = [UILabel new];
    self.snippetLabel.font = [self snippetFont];
    self.snippetLabel.numberOfLines = 2;
    self.snippetLabel.lineBreakMode = NSLineBreakByWordWrapping;
    [self.snippetLabel setContentHuggingHorizontalLow];
    [self.snippetLabel setCompressionResistanceHorizontalLow];

    self.typingIndicatorView = [TypingIndicatorView new];
    [self.contentView addSubview:self.typingIndicatorView];

    UIStackView *bottomRowView = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.snippetLabel,
        self.messageStatusView,
    ]];
    // snippetLabel is two lines.
    // The message status should be vertically aligned with the
    // center of the _first line_ of the snippet label.
    // Therefore we:
    //
    // * Top align everything in the bottom row.
    // * Ensure messageStatusView has _half_ the height of the
    //   bottom row.
    // * Internally the messageStatusView will v-center its icon.
    [[NSLayoutConstraint constraintWithItem:self.messageStatusView
                                  attribute:NSLayoutAttributeHeight
                                  relatedBy:NSLayoutRelationEqual
                                     toItem:bottomRowView
                                  attribute:NSLayoutAttributeHeight
                                 multiplier:0.5
                                   constant:0] autoInstall];
    bottomRowView.axis = UILayoutConstraintAxisHorizontal;
    bottomRowView.alignment = UIStackViewAlignmentTop;
    bottomRowView.spacing = 6.f;

    UIStackView *vStackView = [[UIStackView alloc] initWithArrangedSubviews:@[ topRowView, bottomRowView ]];
    vStackView.axis = UILayoutConstraintAxisVertical;

    [self.contentView addSubview:vStackView];
    [vStackView autoPinLeadingToTrailingEdgeOfView:self.avatarView offset:self.avatarHSpacing];
    [vStackView autoVCenterInSuperview];
    // Ensure that the cell's contents never overflow the cell bounds.
    [vStackView autoPinEdgeToSuperviewEdge:ALEdgeTop withInset:8 relation:NSLayoutRelationGreaterThanOrEqual];
    [vStackView autoPinEdgeToSuperviewEdge:ALEdgeBottom withInset:8 relation:NSLayoutRelationGreaterThanOrEqual];
    [vStackView autoPinTrailingToSuperviewMargin];

    vStackView.userInteractionEnabled = NO;

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

    [self.typingIndicatorView autoPinEdge:ALEdgeLeading toEdge:ALEdgeLeading ofView:self.snippetLabel];
    [self.typingIndicatorView autoAlignAxis:ALAxisHorizontal toSameAxisOfView:self.snippetLabel];
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

    BOOL hasUnreadMessages = thread.hasUnreadMessages;

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
    self.snippetLabel.font = [self snippetFont];
    self.snippetLabel.textColor = UIColor.ows_gray45Color;

    [self updatePreview];

    NSDate *_Nullable labelDate = overrideDate ?: thread.lastMessageDate;
    if (labelDate != nil) {
        self.dateTimeLabel.text = [DateUtil formatDateShort:labelDate];
    } else {
        self.dateTimeLabel.text = nil;
    }

    UIColor *textColor = Theme.secondaryTextAndIconColor;
    if (hasUnreadMessages && overrideSnippet == nil) {
        textColor = Theme.primaryTextColor;
        self.dateTimeLabel.font = self.dateTimeFont.ows_semibold;
    } else {
        self.dateTimeLabel.font = self.dateTimeFont;
    }
    self.dateTimeLabel.textColor = textColor;

    if (overrideSnippet) {
        // If we're using the conversation list cell to render search results,
        // don't show "unread badge" or "message status" indicator.
        self.unreadBadge.hidden = YES;
        self.messageStatusView.hidden = YES;
    } else if (thread.hasUnreadMessages) {
        // If there are unread messages, show the "unread badge."
        // The "message status" indicators is redundant.
        self.unreadBadge.hidden = NO;
        self.messageStatusView.hidden = YES;

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
        UIImage *_Nullable statusIndicatorImage = nil;
        UIColor *messageStatusViewTintColor = [UIColor ows_gray45Color];
        BOOL shouldAnimateStatusIcon = NO;
        BOOL shouldHideStatusIndicator = NO;

        if ([self.thread.lastMessageForInbox isKindOfClass:[TSOutgoingMessage class]]) {
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
        }
        self.messageStatusView.image = [statusIndicatorImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        self.messageStatusView.tintColor = messageStatusViewTintColor;
        self.messageStatusView.hidden = shouldHideStatusIndicator || statusIndicatorImage == nil;
        self.unreadBadge.hidden = YES;
        if (shouldAnimateStatusIcon) {
            CABasicAnimation *animation;
            animation = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
            animation.toValue = @(M_PI * 2.0);
            const CGFloat kPeriodSeconds = 1.f;
            animation.duration = kPeriodSeconds;
            animation.cumulative = YES;
            animation.repeatCount = HUGE_VALF;
            [self.messageStatusView.layer addAnimation:animation forKey:@"animation"];
        } else {
            [self.messageStatusView.layer removeAllAnimations];
        }
    }
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

    BOOL hasUnreadMessages = thread.hasUnreadMessages;

    NSMutableAttributedString *snippetText = [NSMutableAttributedString new];
    if (isBlocked) {
        // If thread is blocked, don't show a snippet or mute status.
        [snippetText append:NSLocalizedString(@"HOME_VIEW_BLOCKED_CONVERSATION",
                                @"Table cell subtitle label for a conversation the user has blocked.")
                 attributes:@{
                     NSFontAttributeName : self.snippetFont.ows_semibold,
                     NSForegroundColorAttributeName : Theme.primaryTextColor,
                 }];
    } else if (thread.hasPendingMessageRequest) {
        // If you haven't accepted the message request for this thread, don't show the latest message

        // For group threads, show who we think added you (if we know)
        if (thread.addedToGroupByName != nil) {
            NSString *addedToGroupFormat = NSLocalizedString(@"HOME_VIEW_MESSAGE_REQUEST_ADDED_TO_GROUP_FORMAT",
                @"Table cell subtitle label for a group the user has been added to. {Embeds inviter name}");
            [snippetText append:[NSString stringWithFormat:addedToGroupFormat, thread.addedToGroupByName]
                     attributes:@{
                         NSFontAttributeName : self.snippetFont.ows_semibold,
                         NSForegroundColorAttributeName : Theme.primaryTextColor,
                     }];

            // Otherwise just show a generic "message request" message
        } else {
            [snippetText append:NSLocalizedString(@"HOME_VIEW_MESSAGE_REQUEST_CONVERSATION",
                                    @"Table cell subtitle label for a conversation the user has not accepted.")
                     attributes:@{
                         NSFontAttributeName : self.snippetFont.ows_semibold,
                         NSForegroundColorAttributeName : Theme.primaryTextColor,
                     }];
        }
    } else {
        if ([thread isMuted]) {
            [snippetText
                appendTemplatedImageNamed:@"bell-disabled-outline-24"
                                     font:self.snippetFont
                               attributes:@{
                                   NSForegroundColorAttributeName :
                                       (hasUnreadMessages ? Theme.primaryTextColor : Theme.secondaryTextAndIconColor),
                               }];
            [snippetText append:@" "
                     attributes:@{
                         NSFontAttributeName : self.snippetFont.ows_semibold,
                     }];
        }

        UIFont *snippetFont = (hasUnreadMessages ? self.snippetFont.ows_semibold : self.snippetFont);
        UIColor *snippetColor = (hasUnreadMessages ? Theme.primaryTextColor : Theme.secondaryTextAndIconColor);

        if (thread.draftText.length > 0 && !hasUnreadMessages) {
            [snippetText append:NSLocalizedString(
                                    @"HOME_VIEW_DRAFT_PREFIX", @"A prefix indicating that a message preview is a draft")
                     attributes:@{
                         NSFontAttributeName : self.snippetFont.ows_italic,
                         NSForegroundColorAttributeName : Theme.secondaryTextAndIconColor,
                     }];
            [snippetText append:thread.draftText
                     attributes:@{
                         NSFontAttributeName : snippetFont,
                         NSForegroundColorAttributeName : snippetColor,
                     }];
        } else {
            TSInteraction *_Nullable lastMessageForInbox = thread.lastMessageForInbox;
            NSString *displayableText = thread.lastMessageText.filterStringForDisplay;
            NSString *_Nullable senderName = nil;
            if (displayableText.length > 0 && thread.isGroupThread) {
                if ([lastMessageForInbox isKindOfClass:TSIncomingMessage.class]) {
                    senderName = @"Sender";
                } else if ([lastMessageForInbox isKindOfClass:TSOutgoingMessage.class]) {
                    senderName = NSLocalizedString(@"GROUP_MEMBER_LOCAL_USER", @"Label indicating the local user.");
                }
            }

            if (displayableText.length > 0) {
                if (senderName != nil) {
                    [snippetText append:senderName
                             attributes:@{
                                 NSFontAttributeName : snippetFont,
                                 NSForegroundColorAttributeName : snippetColor,
                             }];
                    [snippetText append:@":"
                             attributes:@{
                                 NSFontAttributeName : snippetFont,
                             }];
                    [snippetText append:@" "
                             attributes:@{
                                 NSFontAttributeName : snippetFont,
                             }];
                }

                [snippetText append:displayableText
                         attributes:@{
                             NSFontAttributeName : snippetFont,
                             NSForegroundColorAttributeName : snippetColor,
                         }];
            }
        }
    }

    return snippetText;
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
    self.messageStatusView.hidden = NO;

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

- (void)updatePreview
{
    OWSAssertIsOnMainThread();

    // We use "override snippets" to show "message" search results.
    // We don't want to show typing indicators in that case.
    BOOL isShowingOverrideSnippet = self.overrideSnippet != nil;
    if (!isShowingOverrideSnippet &&
        [self.typingIndicators typingAddressForThread:self.thread.threadRecord] != nil) {
        // If we hide snippetLabel, our layout will break since UIStackView will remove
        // it from the layout.  Wrapping the preview views (the snippet label and the
        // typing indicator) in a UIStackView proved non-trivial since we're using
        // UIStackViewAlignmentLastBaseline.  Therefore we hide the _contents_ of the
        // snippet label using an empty string.
        //
        // Ensure that the snippet is at least two lines so that it is top-aligned.
        self.snippetLabel.text = @"\n\n";
        self.typingIndicatorView.hidden = NO;
        [self.typingIndicatorView startAnimation];
    } else {
        NSAttributedString *attributedText;
        if (self.overrideSnippet) {
            attributedText = self.overrideSnippet;
        } else {
            attributedText = [self attributedSnippetForThread:self.thread isBlocked:self.isBlocked];
        }
        // Ensure that the snippet is at least two lines so that it is top-aligned.
        attributedText = [attributedText stringByAppendingString:@"\n\n" attributes:@{}];
        self.snippetLabel.attributedText = attributedText;

        self.typingIndicatorView.hidden = YES;
        [self.typingIndicatorView stopAnimation];
    }
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
