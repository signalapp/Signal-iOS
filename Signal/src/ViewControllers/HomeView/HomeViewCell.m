//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "HomeViewCell.h"
#import "OWSAvatarBuilder.h"
#import "Signal-Swift.h"
#import <SignalMessaging/OWSFormat.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/OWSMath.h>
#import <SignalServiceKit/OWSMessageManager.h>
#import <SignalServiceKit/OWSUserProfile.h>
#import <SignalServiceKit/TSContactThread.h>
#import <SignalServiceKit/TSGroupThread.h>

NS_ASSUME_NONNULL_BEGIN

@interface HomeViewCell ()

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

@implementation HomeViewCell

#pragma mark - Dependencies

- (OWSContactsManager *)contactsManager
{
    OWSAssertDebug(Environment.shared.contactsManager);

    return Environment.shared.contactsManager;
}

- (id<OWSTypingIndicators>)typingIndicators
{
    return SSKEnvironment.shared.typingIndicators;
}

- (TSAccountManager *)tsAccountManager
{
    OWSAssertDebug(SSKEnvironment.shared.tsAccountManager);

    return SSKEnvironment.shared.tsAccountManager;
}

#pragma mark -

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(nullable NSString *)reuseIdentifier
{
    if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]) {
        [self commontInit];
    }
    return self;
}

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
    OWSAssertDebug(!self.avatarView);

    self.backgroundColor = Theme.backgroundColor;

    _viewConstraints = [NSMutableArray new];

    self.avatarView = [[AvatarImageView alloc] init];
    [self.contentView addSubview:self.avatarView];
    [self.avatarView autoSetDimension:ALDimensionWidth toSize:self.avatarSize];
    [self.avatarView autoSetDimension:ALDimensionHeight toSize:self.avatarSize];
    [self.avatarView autoPinLeadingToSuperviewMargin];
    [self.avatarView autoVCenterInSuperview];
    [self.avatarView setContentHuggingHigh];
    [self.avatarView setCompressionResistanceHigh];
    // Ensure that the cell's contents never overflow the cell bounds.
    [self.avatarView autoPinEdgeToSuperviewMargin:ALEdgeTop relation:NSLayoutRelationGreaterThanOrEqual];
    [self.avatarView autoPinEdgeToSuperviewMargin:ALEdgeBottom relation:NSLayoutRelationGreaterThanOrEqual];

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
    self.snippetLabel.numberOfLines = 1;
    self.snippetLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.snippetLabel setContentHuggingHorizontalLow];
    [self.snippetLabel setCompressionResistanceHorizontalLow];

    self.typingIndicatorView = [TypingIndicatorView new];
    [self.contentView addSubview:self.typingIndicatorView];

    UIStackView *bottomRowView = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.snippetLabel,
        self.messageStatusView,
    ]];

    bottomRowView.axis = UILayoutConstraintAxisHorizontal;
    bottomRowView.alignment = UIStackViewAlignmentLastBaseline;
    bottomRowView.spacing = 6.f;

    UIStackView *vStackView = [[UIStackView alloc] initWithArrangedSubviews:@[
        topRowView,
        bottomRowView,
    ]];
    vStackView.axis = UILayoutConstraintAxisVertical;

    [self.contentView addSubview:vStackView];
    [vStackView autoPinLeadingToTrailingEdgeOfView:self.avatarView offset:self.avatarHSpacing];
    [vStackView autoVCenterInSuperview];
    // Ensure that the cell's contents never overflow the cell bounds.
    [vStackView autoPinEdgeToSuperviewMargin:ALEdgeTop relation:NSLayoutRelationGreaterThanOrEqual];
    [vStackView autoPinEdgeToSuperviewMargin:ALEdgeBottom relation:NSLayoutRelationGreaterThanOrEqual];
    [vStackView autoPinTrailingToSuperviewMargin];

    vStackView.userInteractionEnabled = NO;

    self.unreadLabel = [UILabel new];
    self.unreadLabel.textColor = [UIColor ows_whiteColor];
    self.unreadLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.unreadLabel.textAlignment = NSTextAlignmentCenter;
    [self.unreadLabel setContentHuggingHigh];
    [self.unreadLabel setCompressionResistanceHigh];

    self.unreadBadge = [NeverClearView new];
    self.unreadBadge.backgroundColor = [UIColor ows_materialBlueColor];
    [self.unreadBadge addSubview:self.unreadLabel];
    [self.unreadLabel autoCenterInSuperview];
    [self.unreadBadge setContentHuggingHigh];
    [self.unreadBadge setCompressionResistanceHigh];

    [self.contentView addSubview:self.unreadBadge];
    [self.unreadBadge autoAlignAxis:ALAxisHorizontal toSameAxisOfView:self.nameLabel];

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

- (void)configureWithThread:(ThreadViewModel *)thread
                  isBlocked:(BOOL)isBlocked
{
    [self configureWithThread:thread
                    isBlocked:isBlocked
              overrideSnippet:nil
                 overrideDate:nil];
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
                                                 name:kNSNotificationName_OtherUsersProfileDidChange
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

    [self updatePreview];

    NSDate *_Nullable labelDate = overrideDate ?: thread.lastMessageDate;
    if (labelDate != nil) {
        self.dateTimeLabel.text = [DateUtil formatDateShort:labelDate];
    } else {
        self.dateTimeLabel.text = nil;
    }

    UIColor *textColor = [Theme secondaryColor];
    if (hasUnreadMessages && overrideSnippet == nil) {
        textColor = [Theme primaryColor];
        self.dateTimeLabel.font = self.dateTimeFont.ows_mediumWeight;
    } else {
        self.dateTimeLabel.font = self.dateTimeFont;
    }
    self.dateTimeLabel.textColor = textColor;

    NSUInteger unreadCount = thread.unreadCount;
    if (overrideSnippet) {
        // If we're using the home view cell to render search results,
        // don't show "unread badge" or "message status" indicator.
        self.unreadBadge.hidden = YES;
        self.messageStatusView.hidden = YES;
    } else if (unreadCount > 0) {
        // If there are unread messages, show the "unread badge."
        // The "message status" indicators is redundant.
        self.unreadBadge.hidden = NO;
        self.messageStatusView.hidden = YES;

        self.unreadLabel.text = [OWSFormat formatInt:(int)unreadCount];
        self.unreadLabel.font = self.unreadFont;
        const int unreadBadgeHeight = (int)ceil(self.unreadLabel.font.lineHeight * 1.5f);
        self.unreadBadge.layer.cornerRadius = unreadBadgeHeight / 2;
        self.unreadBadge.layer.borderColor = Theme.backgroundColor.CGColor;
        self.unreadBadge.layer.borderWidth = 1.f;

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
                                 ]];
                             }];
    } else {
        UIImage *_Nullable statusIndicatorImage = nil;
        // TODO: Theme, Review with design.
        UIColor *messageStatusViewTintColor
            = (Theme.isDarkThemeEnabled ? [UIColor ows_gray25Color] : [UIColor ows_gray45Color]);
        BOOL shouldAnimateStatusIcon = NO;
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
                    break;
                case MessageReceiptStatusDelivered:
                    statusIndicatorImage = [UIImage imageNamed:@"message_status_delivered"];
                    break;
                case MessageReceiptStatusRead:
                    statusIndicatorImage = [UIImage imageNamed:@"message_status_read"];
                    break;
                case MessageReceiptStatusFailed:
                    statusIndicatorImage = [UIImage imageNamed:@"message_status_failed"];
                    messageStatusViewTintColor = [UIColor ows_destructiveRedColor];
                    break;
            }
        }
        self.messageStatusView.image = [statusIndicatorImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        self.messageStatusView.tintColor = messageStatusViewTintColor;
        self.messageStatusView.hidden = statusIndicatorImage == nil;
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
        [snippetText appendAttributedString:
                         [[NSAttributedString alloc]
                             initWithString:NSLocalizedString(@"HOME_VIEW_BLOCKED_CONVERSATION",
                                                @"Table cell subtitle label for a conversation the user has blocked.")
                                 attributes:@{
                                     NSFontAttributeName : self.snippetFont.ows_mediumWeight,
                                     NSForegroundColorAttributeName : [Theme primaryColor],
                                 }]];
    } else {
        if ([thread isMuted]) {
            [snippetText appendAttributedString:[[NSAttributedString alloc]
                                                    initWithString:LocalizationNotNeeded(@"\ue067  ")
                                                        attributes:@{
                                                            NSFontAttributeName : [UIFont ows_elegantIconsFont:9.f],
                                                            NSForegroundColorAttributeName :
                                                                (hasUnreadMessages ? [Theme primaryColor]
                                                                                   : [Theme secondaryColor]),
                                                        }]];
        }
        NSString *displayableText = thread.lastMessageText;
        if (displayableText) {
            [snippetText appendAttributedString:[[NSAttributedString alloc]
                                                    initWithString:displayableText
                                                        attributes:@{
                                                            NSFontAttributeName :
                                                                (hasUnreadMessages ? self.snippetFont.ows_mediumWeight
                                                                                   : self.snippetFont),
                                                            NSForegroundColorAttributeName :
                                                                (hasUnreadMessages ? [Theme primaryColor]
                                                                                   : [Theme secondaryColor]),
                                                        }]];
        }
    }

    return snippetText;
}

#pragma mark - Constants

- (UIFont *)unreadFont
{
    return [UIFont ows_dynamicTypeCaption1Font].ows_mediumWeight;
}

- (UIFont *)dateTimeFont
{
    return [UIFont ows_dynamicTypeCaption1Font];
}

- (UIFont *)snippetFont
{
    return [UIFont ows_dynamicTypeSubheadlineFont];
}

- (UIFont *)nameFont
{
    return [UIFont ows_dynamicTypeBodyFont].ows_mediumWeight;
}

// Used for profile names.
- (UIFont *)nameSecondaryFont
{
    return [UIFont ows_dynamicTypeBodyFont].ows_italic;
}

- (NSUInteger)avatarSize
{
    return kStandardAvatarSize;
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

    if (![self.thread.contactAddress matchesAddress:address]) {
        return;
    }

    [self updateNameLabel];
    [self updateAvatarView];
}

- (void)updateNameLabel
{
    OWSAssertIsOnMainThread();

    self.nameLabel.font = self.nameFont;
    self.nameLabel.textColor = [Theme primaryColor];

    ThreadViewModel *thread = self.thread;
    if (thread == nil) {
        OWSFailDebug(@"thread should not be nil");
        self.nameLabel.attributedText = nil;
        return;
    }

    NSAttributedString *name;
    if (thread.isGroupThread) {
        if (thread.name.length == 0) {
            name = [[NSAttributedString alloc] initWithString:[MessageStrings newGroupDefaultTitle]];
        } else {
            name = [[NSAttributedString alloc] initWithString:thread.name];
        }
    } else {
        if (self.thread.threadRecord.isNoteToSelf) {
            name = [[NSAttributedString alloc]
                initWithString:NSLocalizedString(@"NOTE_TO_SELF", @"Label for 1:1 conversation with yourself.")
                    attributes:@{
                        NSFontAttributeName : self.nameFont,
                    }];
        } else {
            name = [self.contactsManager attributedContactOrProfileNameForAddress:thread.contactAddress
                                                                      primaryFont:self.nameFont
                                                                    secondaryFont:self.nameSecondaryFont];
        }
    }

    self.nameLabel.attributedText = name;
}

#pragma mark - Typing Indicators

- (void)updatePreview
{
    if ([self.typingIndicators typingRecipientIdForThread:self.thread.threadRecord] != nil) {
        // If we hide snippetLabel, our layout will break since UIStackView will remove
        // it from the layout.  Wrapping the preview views (the snippet label and the
        // typing indicator) in a UIStackView proved non-trivial since we're using
        // UIStackViewAlignmentLastBaseline.  Therefore we hide the _contents_ of the
        // snippet label using an empty string.
        self.snippetLabel.text = @" ";
        self.typingIndicatorView.hidden = NO;
        [self.typingIndicatorView startAnimation];
    } else {
        if (self.overrideSnippet) {
            self.snippetLabel.attributedText = self.overrideSnippet;
        } else {
            self.snippetLabel.attributedText = [self attributedSnippetForThread:self.thread isBlocked:self.isBlocked];
        }
        self.typingIndicatorView.hidden = YES;
        [self.typingIndicatorView stopAnimation];
    }
}

- (void)typingIndicatorStateDidChange:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(self.thread);

    if (notification.object && ![notification.object isEqual:self.thread.threadRecord.uniqueId]) {
        return;
    }

    [self updatePreview];
}

@end

NS_ASSUME_NONNULL_END
