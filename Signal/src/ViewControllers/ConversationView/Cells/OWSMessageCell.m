//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageCell.h"
#import "OWSContactAvatarBuilder.h"
#import "OWSMessageBubbleView.h"
#import "OWSMessageHeaderView.h"
#import "OWSMessageHiddenView.h"
#import "OWSMessageStickerView.h"
#import "Signal-Swift.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSMessageCell () <UIGestureRecognizerDelegate>

// The nullable properties are created as needed.
// The non-nullable properties are so frequently used that it's easier
// to always keep one around.

@property (nonatomic) OWSMessageHeaderView *headerView;
@property (nonatomic) OWSMessageBubbleView *messageBubbleView;
@property (nonatomic) OWSMessageStickerView *messageStickerView;
@property (nonatomic) OWSMessageHiddenView *messageHiddenView;
@property (nonatomic) AvatarImageView *avatarView;
@property (nonatomic, nullable) UIImageView *sendFailureBadgeView;

@property (nonatomic, nullable) NSMutableArray<NSLayoutConstraint *> *viewConstraints;

@property (nonatomic) UIPanGestureRecognizer *panGestureRecognizer;
@property (nonatomic) UIView *swipeableContentView;
@property (nonatomic) UIImageView *swipeToReplyImageView;
@property (nonatomic) CGFloat swipeableContentViewInitialX;
@property (nonatomic) CGFloat messageViewInitialX;
@property (nonatomic) BOOL isReplyActive;

@property (nonatomic) BOOL isPresentingMenuController;

@end

#pragma mark -

@implementation OWSMessageCell

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
    // Ensure only called once.
    OWSAssertDebug(!self.messageBubbleView);

    self.layoutMargins = UIEdgeInsetsZero;
    self.contentView.layoutMargins = UIEdgeInsetsZero;

    _viewConstraints = [NSMutableArray new];

    self.messageBubbleView = [OWSMessageBubbleView new];
    self.messageStickerView = [OWSMessageStickerView new];
    self.messageHiddenView = [OWSMessageHiddenView new];

    self.headerView = [OWSMessageHeaderView new];

    self.avatarView = [[AvatarImageView alloc] init];
    [self.avatarView autoSetDimension:ALDimensionWidth toSize:self.avatarSize];
    [self.avatarView autoSetDimension:ALDimensionHeight toSize:self.avatarSize];

    self.contentView.userInteractionEnabled = YES;

    UITapGestureRecognizer *tap =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTapGesture:)];
    [self addGestureRecognizer:tap];

    UILongPressGestureRecognizer *longPress =
        [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPressGesture:)];
    [self.contentView addGestureRecognizer:longPress];

    self.panGestureRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self
                                                                          action:@selector(handlePanGesture:)];
    self.panGestureRecognizer.delegate = self;
    [self.contentView addGestureRecognizer:self.panGestureRecognizer];
    [tap requireGestureRecognizerToFail:self.panGestureRecognizer];

    [self setupSwipeContainer];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setConversationStyle:(nullable ConversationStyle *)conversationStyle
{
    [super setConversationStyle:conversationStyle];

    self.messageBubbleView.conversationStyle = conversationStyle;
    self.messageStickerView.conversationStyle = conversationStyle;
    self.messageHiddenView.conversationStyle = conversationStyle;
}

+ (NSString *)cellReuseIdentifier
{
    return NSStringFromClass([self class]);
}

#pragma mark - Convenience Accessors

- (OWSMessageCellType)cellType
{
    return self.viewItem.messageCellType;
}

- (TSMessage *)message
{
    OWSAssertDebug([self.viewItem.interaction isKindOfClass:[TSMessage class]]);

    return (TSMessage *)self.viewItem.interaction;
}

- (BOOL)isIncoming
{
    return self.viewItem.interaction.interactionType == OWSInteractionType_IncomingMessage;
}

- (BOOL)isOutgoing
{
    return self.viewItem.interaction.interactionType == OWSInteractionType_OutgoingMessage;
}

- (BOOL)shouldHaveSendFailureBadge
{
    if (![self.viewItem.interaction isKindOfClass:[TSOutgoingMessage class]]) {
        return NO;
    }
    TSOutgoingMessage *outgoingMessage = (TSOutgoingMessage *)self.viewItem.interaction;
    return outgoingMessage.messageState == TSOutgoingMessageStateFailed;
}

- (OWSMessageView *)messageView
{
    if (self.cellType == OWSMessageCellType_StickerMessage) {
        return self.messageStickerView;
    } else if (self.cellType == OWSMessageCellType_PerMessageExpiration) {
        return self.messageHiddenView;
    } else {
        return self.messageBubbleView;
    }
}

#pragma mark - Load

- (void)loadForDisplay
{
    OWSAssertDebug(self.conversationStyle);
    OWSAssertDebug(self.viewItem);
    OWSAssertDebug(self.viewItem.interaction);
    OWSAssertDebug([self.viewItem.interaction isKindOfClass:[TSMessage class]]);
    OWSAssertDebug(self.messageBubbleView);
    OWSAssertDebug(self.messageStickerView);
    OWSAssertDebug(self.messageHiddenView);

    OWSMessageView *messageView = self.messageView;
    messageView.viewItem = self.viewItem;
    messageView.cellMediaCache = self.delegate.cellMediaCache;
    [messageView configureViews];
    [messageView loadContent];
    [self.contentView addSubview:messageView];
    [messageView autoPinBottomToSuperviewMarginWithInset:0];

    if (self.viewItem.hasCellHeader) {
        CGFloat headerHeight =
            [self.headerView measureWithConversationViewItem:self.viewItem conversationStyle:self.conversationStyle]
                .height;
        [self.headerView loadForDisplayWithViewItem:self.viewItem conversationStyle:self.conversationStyle];
        [self.contentView addSubview:self.headerView];
        [self.viewConstraints addObjectsFromArray:@[
            [self.headerView autoSetDimension:ALDimensionHeight toSize:headerHeight],
            [self.headerView autoPinEdgeToSuperviewEdge:ALEdgeLeading],
            [self.headerView autoPinEdgeToSuperviewEdge:ALEdgeTrailing],
            [self.headerView autoPinEdgeToSuperviewEdge:ALEdgeTop],
            [messageView autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:self.headerView],
        ]];
    } else {
        [self.viewConstraints addObjectsFromArray:@[
            [messageView autoPinEdgeToSuperviewEdge:ALEdgeTop],
        ]];
    }

    if (self.isIncoming) {
        [self.viewConstraints addObjectsFromArray:@[
            [messageView autoPinEdgeToSuperviewEdge:ALEdgeLeading withInset:self.conversationStyle.gutterLeading],
            [messageView autoPinEdgeToSuperviewEdge:ALEdgeTrailing
                                          withInset:self.conversationStyle.gutterTrailing
                                           relation:NSLayoutRelationGreaterThanOrEqual],
        ]];
    } else {
        if (self.shouldHaveSendFailureBadge) {
            self.sendFailureBadgeView = [UIImageView new];
            self.sendFailureBadgeView.image =
                [self.sendFailureBadge imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            self.sendFailureBadgeView.tintColor = [UIColor ows_destructiveRedColor];
            [self.contentView addSubview:self.sendFailureBadgeView];

            CGFloat sendFailureBadgeBottomMargin
                = round(self.conversationStyle.lastTextLineAxis - self.sendFailureBadgeSize * 0.5f);
            [self.viewConstraints addObjectsFromArray:@[
                [messageView autoPinEdgeToSuperviewEdge:ALEdgeLeading
                                              withInset:self.conversationStyle.gutterLeading
                                               relation:NSLayoutRelationGreaterThanOrEqual],
                [self.sendFailureBadgeView autoPinLeadingToTrailingEdgeOfView:messageView
                                                                       offset:self.sendFailureBadgeSpacing],
                // V-align the "send failure" badge with the
                // last line of the text (if any, or where it
                // would be).
                [messageView autoPinEdge:ALEdgeBottom
                                  toEdge:ALEdgeBottom
                                  ofView:self.sendFailureBadgeView
                              withOffset:sendFailureBadgeBottomMargin],
                [self.sendFailureBadgeView autoPinEdgeToSuperviewEdge:ALEdgeTrailing
                                                            withInset:self.conversationStyle.errorGutterTrailing],
                [self.sendFailureBadgeView autoSetDimension:ALDimensionWidth toSize:self.sendFailureBadgeSize],
                [self.sendFailureBadgeView autoSetDimension:ALDimensionHeight toSize:self.sendFailureBadgeSize],
            ]];
        } else {
            [self.viewConstraints addObjectsFromArray:@[
                [messageView autoPinEdgeToSuperviewEdge:ALEdgeLeading
                                              withInset:self.conversationStyle.gutterLeading
                                               relation:NSLayoutRelationGreaterThanOrEqual],
                [messageView autoPinEdgeToSuperviewEdge:ALEdgeTrailing withInset:self.conversationStyle.gutterTrailing],
            ]];
        }
    }

    if ([self updateAvatarView]) {
        [self.viewConstraints addObjectsFromArray:@[
            // V-align the "group sender" avatar with the
            // last line of the text (if any, or where it
            // would be).
            [messageView autoPinLeadingToTrailingEdgeOfView:self.avatarView offset:8],
            [messageView autoPinEdge:ALEdgeBottom toEdge:ALEdgeBottom ofView:self.avatarView],
        ]];
    }

    // Swipe-to-reply
    [self.viewConstraints addObjectsFromArray:@[
        [self.swipeToReplyImageView autoPinEdge:ALEdgeLeading toEdge:ALEdgeLeading ofView:messageView withOffset:8],
        [self.swipeToReplyImageView autoAlignAxis:ALAxisHorizontal toSameAxisOfView:messageView],
    ]];
}

- (UIImage *)sendFailureBadge
{
    UIImage *image = [UIImage imageNamed:@"message_status_failed_large"];
    OWSAssertDebug(image);
    OWSAssertDebug(image.size.width == self.sendFailureBadgeSize && image.size.height == self.sendFailureBadgeSize);
    return image;
}

- (CGFloat)sendFailureBadgeSize
{
    return 20.f;
}

- (CGFloat)sendFailureBadgeSpacing
{
    return 8.f;
}

// * If cell is visible, lazy-load (expensive) view contents.
// * If cell is not visible, eagerly unload view contents.
- (void)ensureMediaLoadState
{
    OWSAssertDebug(self.messageView);

    if (!self.isCellVisible) {
        [self.messageView unloadContent];
    } else {
        [self.messageView loadContent];
    }
}

#pragma mark - Avatar

// Returns YES IFF the avatar view is appropriate and configured.
- (BOOL)updateAvatarView
{
    if (!self.viewItem.shouldShowSenderAvatar) {
        return NO;
    }
    if (!self.viewItem.isGroupThread) {
        OWSFailDebug(@"not a group thread.");
        return NO;
    }
    if (self.viewItem.interaction.interactionType != OWSInteractionType_IncomingMessage) {
        OWSFailDebug(@"not an incoming message.");
        return NO;
    }
    OWSAssertDebug(self.viewItem.authorConversationColorName != nil);

    TSIncomingMessage *incomingMessage = (TSIncomingMessage *)self.viewItem.interaction;
    UIImage *_Nullable authorAvatarImage =
        [[[OWSContactAvatarBuilder alloc] initWithAddress:incomingMessage.authorAddress
                                                colorName:self.viewItem.authorConversationColorName
                                                 diameter:self.avatarSize] build];
    self.avatarView.image = authorAvatarImage;
    [self.swipeableContentView addSubview:self.avatarView];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(otherUsersProfileDidChange:)
                                                 name:kNSNotificationName_OtherUsersProfileDidChange
                                               object:nil];

    return YES;
}

- (NSUInteger)avatarSize
{
    return 36.f;
}

- (void)otherUsersProfileDidChange:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    if (!self.viewItem.shouldShowSenderAvatar) {
        return;
    }
    if (!self.viewItem.isGroupThread) {
        OWSFailDebug(@"not a group thread.");
        return;
    }
    if (self.viewItem.interaction.interactionType != OWSInteractionType_IncomingMessage) {
        OWSFailDebug(@"not an incoming message.");
        return;
    }

    SignalServiceAddress *address = notification.userInfo[kNSNotificationKey_ProfileAddress];
    if (!address.isValid) {
        return;
    }
    TSIncomingMessage *incomingMessage = (TSIncomingMessage *)self.viewItem.interaction;

    if (![incomingMessage.authorAddress matchesAddress:address]) {
        return;
    }

    [self updateAvatarView];
}

#pragma mark - Measurement

- (CGSize)cellSize
{
    OWSAssertDebug(self.conversationStyle);
    OWSAssertDebug(self.conversationStyle.viewWidth > 0);
    OWSAssertDebug(self.viewItem);
    OWSAssertDebug([self.viewItem.interaction isKindOfClass:[TSMessage class]]);
    OWSAssertDebug(self.messageView);

    self.messageView.viewItem = self.viewItem;
    self.messageView.cellMediaCache = self.delegate.cellMediaCache;
    CGSize messageSize = [self.messageView measureSize];

    CGSize cellSize = messageSize;

    OWSAssertDebug(cellSize.width > 0 && cellSize.height > 0);

    if (self.viewItem.hasCellHeader) {
        cellSize.height +=
            [self.headerView measureWithConversationViewItem:self.viewItem conversationStyle:self.conversationStyle]
                .height;
    }

    if (self.shouldHaveSendFailureBadge) {
        cellSize.width += self.sendFailureBadgeSize + self.sendFailureBadgeSpacing;
    }

    cellSize = CGSizeCeil(cellSize);

    return cellSize;
}

#pragma mark - Reuse

- (void)prepareForReuse
{
    [super prepareForReuse];

    [NSLayoutConstraint deactivateConstraints:self.viewConstraints];
    self.viewConstraints = [NSMutableArray new];

    [self.messageBubbleView prepareForReuse];
    [self.messageBubbleView unloadContent];
    [self.messageBubbleView removeFromSuperview];
    [self.messageStickerView prepareForReuse];
    [self.messageStickerView unloadContent];
    [self.messageStickerView removeFromSuperview];
    [self.messageHiddenView prepareForReuse];
    [self.messageHiddenView unloadContent];
    [self.messageHiddenView removeFromSuperview];

    [self.headerView removeFromSuperview];

    self.avatarView.image = nil;
    [self.avatarView removeFromSuperview];

    [self.sendFailureBadgeView removeFromSuperview];
    self.sendFailureBadgeView = nil;

    [[NSNotificationCenter defaultCenter] removeObserver:self];

    [self resetSwipePositionAnimated:NO];
    self.swipeToReplyImageView.alpha = 0;
}

#pragma mark - Notifications

- (void)setIsCellVisible:(BOOL)isCellVisible {
    BOOL didChange = self.isCellVisible != isCellVisible;

    [super setIsCellVisible:isCellVisible];

    if (!didChange) {
        return;
    }

    [self ensureMediaLoadState];
}

#pragma mark - Gesture recognizers

- (void)handleTapGesture:(UITapGestureRecognizer *)sender
{
    OWSAssertDebug(self.delegate);

    if (sender.state != UIGestureRecognizerStateRecognized) {
        OWSLogVerbose(@"Ignoring tap on message: %@", self.viewItem.interaction.debugDescription);
        return;
    }

    if ([self isGestureInCellHeader:sender]) {
        return;
    }

    if (self.viewItem.interaction.interactionType == OWSInteractionType_OutgoingMessage) {
        TSOutgoingMessage *outgoingMessage = (TSOutgoingMessage *)self.viewItem.interaction;
        if (outgoingMessage.messageState == TSOutgoingMessageStateFailed) {
            [self.delegate didTapFailedOutgoingMessage:outgoingMessage];
            return;
        } else if (outgoingMessage.messageState == TSOutgoingMessageStateSending) {
            // Ignore taps on outgoing messages being sent.
            return;
        }
    }

    [self.messageView handleTapGesture:sender];
}

- (void)handleLongPressGesture:(UILongPressGestureRecognizer *)sender
{
    OWSAssertDebug(self.delegate);

    if (sender.state != UIGestureRecognizerStateBegan) {
        return;
    }

    if ([self isGestureInCellHeader:sender]) {
        return;
    }

    BOOL shouldAllowReply = [self shouldAllowReply];
    CGPoint locationInMessageBubble = [sender locationInView:self.messageView];
    switch ([self.messageView gestureLocationForLocation:locationInMessageBubble]) {
        case OWSMessageGestureLocation_Default:
        case OWSMessageGestureLocation_OversizeText:
        case OWSMessageGestureLocation_LinkPreview: {
            [self.delegate conversationCell:self
                           shouldAllowReply:shouldAllowReply
                   didLongpressTextViewItem:self.viewItem];
            break;
        }
        case OWSMessageGestureLocation_Media: {
            [self.delegate conversationCell:self
                           shouldAllowReply:shouldAllowReply
                  didLongpressMediaViewItem:self.viewItem];
            break;
        }
        case OWSMessageGestureLocation_QuotedReply: {
            [self.delegate conversationCell:self
                           shouldAllowReply:shouldAllowReply
                  didLongpressQuoteViewItem:self.viewItem];
            break;
        }
        case OWSMessageGestureLocation_Sticker:
            OWSAssertDebug(self.viewItem.stickerInfo != nil);
            [self.delegate conversationCell:self didLongpressSticker:self.viewItem];
            break;
    }
}

- (void)handlePanGesture:(UIPanGestureRecognizer *)sender
{
    if ([self.messageView handlePanGesture:sender]) {
        return;
    }

    [self handleSwipeToReplyGesture:sender];
}

- (BOOL)isGestureInCellHeader:(UIGestureRecognizer *)sender
{
    OWSAssertDebug(self.viewItem);

    if (!self.viewItem.hasCellHeader) {
        return NO;
    }

    CGPoint location = [sender locationInView:self];
    CGPoint headerBottom = [self convertPoint:CGPointMake(0, self.headerView.height) fromView:self.headerView];
    return location.y <= headerBottom.y;
}

# pragma mark - UIGestureRecognizerDelegate

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer
{
    if (gestureRecognizer == self.panGestureRecognizer) {
        // Only allow the pan gesture to recognize horizontal panning,
        // to avoid conflicts with the conversation view scroll view.
        CGPoint velocity = [self.panGestureRecognizer velocityInView:self];
        return fabs(velocity.x) > fabs(velocity.y);
    }

    return YES;
}

#pragma mark - Swipe To Reply

- (BOOL)shouldAllowReply
{
    if (self.viewItem.messageCellType == OWSMessageCellType_PerMessageExpiration) {
        // Don't allow "reply" messages with per-message expiration.
        return NO;
    } else if (self.viewItem.interaction.interactionType == OWSInteractionType_OutgoingMessage) {
        TSOutgoingMessage *outgoingMessage = (TSOutgoingMessage *)self.viewItem.interaction;
        if (outgoingMessage.messageState == TSOutgoingMessageStateFailed) {
            // Don't allow "delete" or "reply" on "failed" outgoing messages.
            return NO;
        } else if (outgoingMessage.messageState == TSOutgoingMessageStateSending) {
            // Don't allow "delete" or "reply" on "sending" outgoing messages.
            return NO;
        }
    }
    return YES;
}

- (CGFloat)swipeToReplyThreshold
{
    return 55.f;
}

- (BOOL)useSwipeFadeTransition
{
    // Right now, only stickers need the reply button to fade in.
    // If we add other message types that don't have bubbles,
    // we should add them here.
    return self.cellType == OWSMessageCellType_StickerMessage;
}

- (void)setIsReplyActive:(BOOL)isReplyActive
{
    if (isReplyActive == _isReplyActive) {
        return;
    }

    _isReplyActive = isReplyActive;

    // Update the reply image styling to reflect active state
    CGAffineTransform transform = CGAffineTransformIdentity;
    UIColor *tintColor = [UIColor ows_gray45Color];

    if (isReplyActive) {
        transform = CGAffineTransformMakeScale(1.16, 1.16);
        tintColor = Theme.isDarkThemeEnabled ? [UIColor ows_gray25Color] : [UIColor ows_gray75Color];

        // If we're transitioning to the active state, play haptic feedback
        [[ImpactHapticFeedback new] impactOccurred];
    }

    self.swipeToReplyImageView.tintColor = tintColor;

    [UIView animateWithDuration:0.2
                          delay:0
         usingSpringWithDamping:0.06
          initialSpringVelocity:0.8
                        options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
                         self.swipeToReplyImageView.transform = transform;
                     }
                     completion:nil];
}

- (void)setupSwipeContainer
{
    self.swipeableContentView = [UIView new];
    [self.contentView addSubview:self.swipeableContentView];
    [self.swipeableContentView autoPinEdgeToSuperviewEdge:ALEdgeLeading];

    self.swipeToReplyImageView = [UIImageView new];
    [self.swipeToReplyImageView
        setTemplateImage:[UIImage imageNamed:@"reply-outline-24"]
               tintColor:Theme.isDarkThemeEnabled ? [UIColor ows_gray45Color] : [UIColor ows_gray45Color]];
    self.swipeToReplyImageView.contentMode = UIViewContentModeScaleAspectFit;
    self.swipeToReplyImageView.alpha = 0;
    [self.swipeableContentView addSubview:self.swipeToReplyImageView];
}

- (void)handleSwipeToReplyGesture:(UIPanGestureRecognizer *)sender
{
    OWSAssert(self.delegate);

    BOOL hasFailed = NO;
    BOOL hasFinished = NO;

    switch (sender.state) {
        case UIGestureRecognizerStateBegan: {
            self.messageViewInitialX = self.messageView.frame.origin.x;
            self.swipeableContentViewInitialX = self.swipeableContentView.frame.origin.x;

            // If this message doesn't allow reply, end the gesture
            if (![self shouldAllowReply]) {
                sender.enabled = NO;
                sender.enabled = YES;
                return;
            }
            break;
        }
        case UIGestureRecognizerStateEnded:
            hasFinished = YES;
            break;
        case UIGestureRecognizerStateFailed:
        case UIGestureRecognizerStateCancelled:
            hasFailed = YES;
            break;
        case UIGestureRecognizerStateChanged:
        case UIGestureRecognizerStatePossible:
            break;
    }

    CGFloat translationX = [sender translationInView:self].x;
    // Invert positions for RTL logic, since the user is swiping in the opposite direction.
    if (CurrentAppContext().isRTL) {
        translationX = -translationX;
    }

    self.isReplyActive = translationX >= self.swipeToReplyThreshold;

    if (self.isReplyActive && hasFinished) {
        [self.delegate conversationCell:self didReplyToItem:self.viewItem];
    }

    if (hasFailed || hasFinished) {
        [self resetSwipePositionAnimated:YES];
    } else {
        [self setSwipePosition:translationX animated:hasFinished];
    }
}

- (void)setSwipePosition:(CGFloat)position animated:(BOOL)animated
{
    // Scale the translation above or below the desired range,
    // to produce an elastic feeling when you overscroll.
    if (position < 0) {
        position = position / 4;
    } else if (position > self.swipeToReplyThreshold) {
        CGFloat overflow = position - self.swipeToReplyThreshold;
        position = self.swipeToReplyThreshold + overflow / 4;
    }

    CGRect newMessageViewFrame = self.messageView.frame;
    newMessageViewFrame.origin.x = self.messageViewInitialX + (CurrentAppContext().isRTL ? -position : position);

    // The swipe content moves at 1/8th the speed of the message bubble,
    // so that it reveals itself from underneath with an elastic feel.
    CGRect newSwipeContentFrame = self.swipeableContentView.frame;
    newSwipeContentFrame.origin.x
        = self.swipeableContentViewInitialX + (CurrentAppContext().isRTL ? -position : position) / 8;

    CGFloat alpha = 1;
    if ([self useSwipeFadeTransition]) {
        alpha = CGFloatClamp01(CGFloatInverseLerp(position, 0, self.swipeToReplyThreshold));
    }

    void (^viewUpdates)(void) = ^() {
        self.swipeToReplyImageView.alpha = alpha;
        self.messageView.frame = newMessageViewFrame;
        self.swipeableContentView.frame = newSwipeContentFrame;
    };

    if (animated) {
        [UIView animateWithDuration:0.1 animations:viewUpdates];
    } else {
        viewUpdates();
    }
}

- (void)resetSwipePositionAnimated:(BOOL)animated
{
    [self setSwipePosition:0 animated:animated];
    self.isReplyActive = NO;
}

@end

NS_ASSUME_NONNULL_END
