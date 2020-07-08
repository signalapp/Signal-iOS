//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageCell.h"
#import "OWSContactAvatarBuilder.h"
#import "OWSMessageBubbleView.h"
#import "OWSMessageStickerView.h"
#import "OWSMessageViewOnceView.h"
#import "Signal-Swift.h"
#import <SignalMessaging/SignalMessaging-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSMessageCell () <UIGestureRecognizerDelegate>

// The nullable properties are created as needed.
// The non-nullable properties are so frequently used that it's easier
// to always keep one around.

@property (nonatomic) OWSMessageBubbleView *messageBubbleView;
@property (nonatomic) OWSMessageStickerView *messageStickerView;
@property (nonatomic) OWSMessageViewOnceView *messageViewOnceView;
@property (nonatomic) AvatarImageView *avatarView;
@property (nonatomic) UIView *avatarViewSpacer;
@property (nonatomic) MessageSelectionView *selectionView;
@property (nonatomic, nullable) UIView *sendFailureBadgeView;
@property (nonatomic) ReactionCountsView *reactionCountsView;
@property (nonatomic, nullable) NSLayoutConstraint *messageBottomConstraint;

@property (nonatomic) UITapGestureRecognizer *messageViewTapGestureRecognizer;
@property (nonatomic) UITapGestureRecognizer *contentViewTapGestureRecognizer;
@property (nonatomic) UIPanGestureRecognizer *panGestureRecognizer;
@property (nonatomic) UILongPressGestureRecognizer *longPressGestureRecognizer;
@property (nonatomic) UIView *swipeableContentView;
@property (nonatomic) UIImageView *swipeToReplyImageView;
@property (nonatomic) CGFloat swipeableContentViewInitialX;
@property (nonatomic, nullable) NSNumber *messageViewInitialX;
@property (nonatomic) CGFloat reactionCountsViewViewInitialX;
@property (nonatomic) BOOL isReplyActive;
@property (nonatomic) BOOL hasPreparedForDisplay;

@property (nonatomic) BOOL isPresentingMenuController;

@property (nonatomic, readonly) OWSMessageCellType messageCellType;

@end

#pragma mark -

@implementation OWSMessageCell

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
        [self commonInit];
    }

    return self;
}

- (void)commonInit
{
    // Ensure only called once.
    OWSAssertDebug(!self.messageBubbleView);

    _messageCellType = OWSMessageCellType_Unknown;

    self.layoutMargins = UIEdgeInsetsZero;
    self.contentView.layoutMargins = UIEdgeInsetsZero;

    self.messageBubbleView = [OWSMessageBubbleView new];
    self.messageStickerView = [OWSMessageStickerView new];
    self.messageViewOnceView = [OWSMessageViewOnceView new];
    self.selectionView = [MessageSelectionView new];

    self.avatarView = [[AvatarImageView alloc] init];
    [self.avatarView autoSetDimension:ALDimensionWidth toSize:ConversationStyle.groupMessageAvatarDiameter];
    [self.avatarView autoSetDimension:ALDimensionHeight toSize:ConversationStyle.groupMessageAvatarDiameter];

    self.avatarViewSpacer = [UIView new];
    [self.avatarViewSpacer autoSetDimension:ALDimensionWidth toSize:ConversationStyle.groupMessageAvatarDiameter];

    self.contentView.userInteractionEnabled = YES;

    self.messageViewTapGestureRecognizer =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleMessageViewTapGesture:)];
    self.messageViewTapGestureRecognizer.delegate = self;

    self.longPressGestureRecognizer =
        [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPressGesture:)];
    [self.contentView addGestureRecognizer:self.longPressGestureRecognizer];
    self.longPressGestureRecognizer.delegate = self;

    self.panGestureRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self
                                                                        action:@selector(handlePanGesture:)];
    self.panGestureRecognizer.delegate = self;
    [self.contentView addGestureRecognizer:self.panGestureRecognizer];
    [self.messageViewTapGestureRecognizer requireGestureRecognizerToFail:self.panGestureRecognizer];

    self.contentViewTapGestureRecognizer =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleContentViewTapGesture:)];
    self.contentViewTapGestureRecognizer.delegate = self;
    [self.contentView addGestureRecognizer:self.contentViewTapGestureRecognizer];
    [self.contentViewTapGestureRecognizer requireGestureRecognizerToFail:self.panGestureRecognizer];
    [self.contentViewTapGestureRecognizer requireGestureRecognizerToFail:self.messageViewTapGestureRecognizer];

    self.reactionCountsView = [ReactionCountsView new];

    [self setupSwipeContainer];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(otherUsersProfileDidChange:)
                                                 name:kNSNotificationNameOtherUsersProfileDidChange
                                               object:nil];
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
    self.messageViewOnceView.conversationStyle = conversationStyle;
}

#pragma mark - Convenience Accessors

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
    if (self.messageCellType == OWSMessageCellType_StickerMessage) {
        return self.messageStickerView;
    } else if (self.messageCellType == OWSMessageCellType_ViewOnce) {
        return self.messageViewOnceView;
    } else {
        return self.messageBubbleView;
    }
}

#pragma mark - Load

- (void)loadForDisplay
{
    if (!self.hasPreparedForDisplay) {
        [self prepareForDisplay];
    }

    OWSMessageView *messageView = self.messageView;
    messageView.cellMediaCache = self.delegate.cellMediaCache;
    messageView.viewItem = self.viewItem;
    [messageView configureViews];
    [messageView loadContent];

    // There is a bug with UIStackView where, on ocassion, hidden views
    // will be rendered (while not effecting layout). In order to work
    // around this, we also adjust the alpha of the views.

    self.selectionView.hidden = !self.delegate.isShowingSelectionUI;
    self.selectionView.alpha = self.selectionView.hidden ? 0 : 1;

    self.selected = [self.delegate isViewItemSelected:self.viewItem];

    self.avatarView.hidden = ![self updateAvatarView];
    self.avatarView.alpha = self.avatarView.hidden ? 0 : 1;

    self.reactionCountsView.hidden = ![self updateReactionsView];
    self.reactionCountsView.alpha = self.reactionCountsView.hidden ? 0 : 1;

    self.sendFailureBadgeView.hidden = !self.shouldHaveSendFailureBadge;
    self.sendFailureBadgeView.alpha = self.sendFailureBadgeView.hidden ? 0 : 1;
}

- (void)setSelected:(BOOL)selected
{
    [super setSelected:selected];
    self.selectionView.isSelected = selected;
}

- (void)setViewItem:(nullable id<ConversationViewItem>)viewItem
{
    OWSAssertIsOnMainThread();

    [super setViewItem:viewItem];

    if (viewItem) {
        if (!self.hasPreparedForDisplay) {
            _messageCellType = viewItem.messageCellType;
        } else {
            OWSAssertDebug(self.messageCellType == viewItem.messageCellType);
        }
    }
}

// This will only ever be called *once* and should prepare for displaying a specific
// type of message cell. Future reused cells will always use the same type.
- (void)prepareForDisplay
{
    OWSAssertDebug(self.conversationStyle);
    OWSAssertDebug(self.viewItem);
    OWSAssertDebug(self.viewItem.interaction);
    OWSAssertDebug([self.viewItem.interaction isKindOfClass:[TSMessage class]]);
    OWSAssertDebug(self.messageBubbleView);
    OWSAssertDebug(self.messageStickerView);
    OWSAssertDebug(self.messageViewOnceView);

    self.hasPreparedForDisplay = YES;

    UIStackView *messageStackView = [UIStackView new];
    messageStackView.axis = UILayoutConstraintAxisHorizontal;
    messageStackView.spacing = ConversationStyle.messageStackSpacing;
    [self.contentView addSubview:messageStackView];

    [messageStackView addGestureRecognizer:self.messageViewTapGestureRecognizer];

    [messageStackView autoPinEdgeToSuperviewEdge:ALEdgeLeading withInset:self.conversationStyle.gutterLeading];
    [messageStackView autoPinEdgeToSuperviewEdge:ALEdgeTrailing withInset:self.conversationStyle.gutterTrailing];
    [messageStackView autoPinEdgeToSuperviewEdge:ALEdgeTop];
    self.messageBottomConstraint = [messageStackView autoPinBottomToSuperviewMarginWithInset:0];

    // Selection
    [messageStackView addArrangedSubview:self.selectionView];
    [self.selectionView autoPinHeightToSuperview];

    if (self.isIncoming && self.viewItem.isGroupThread) {
        [messageStackView addArrangedSubview:self.avatarViewSpacer];
        [self.avatarViewSpacer autoPinHeightToSuperview];

        [self.swipeableContentView addSubview:self.avatarView];
        [self.avatarView autoPinEdge:ALEdgeLeading toEdge:ALEdgeLeading ofView:self.avatarViewSpacer];
        [self.avatarView autoPinEdge:ALEdgeBottom toEdge:ALEdgeBottom ofView:self.avatarViewSpacer];
    }

    NSArray<UIView *> *arrangedMessageViews;
    if (self.isIncoming) {
        arrangedMessageViews = @[ self.messageView, [UIView hStretchingSpacer] ];
    } else {
        arrangedMessageViews = @[ [UIView hStretchingSpacer], self.messageView ];
    }
    UIStackView *messageSubStack = [[UIStackView alloc] initWithArrangedSubviews:arrangedMessageViews];
    [messageStackView addArrangedSubview:messageSubStack];

    [messageStackView addSubview:self.reactionCountsView];

    if (self.isIncoming) {
        [self.reactionCountsView autoPinEdge:ALEdgeLeading
                                      toEdge:ALEdgeLeading
                                      ofView:self.messageView
                                  withOffset:6
                                    relation:NSLayoutRelationGreaterThanOrEqual];
    } else {
        [self.reactionCountsView autoPinEdge:ALEdgeTrailing
                                      toEdge:ALEdgeTrailing
                                      ofView:self.messageView
                                  withOffset:-6
                                    relation:NSLayoutRelationLessThanOrEqual];

        // Only outgoing messages ever show send failures, show setup accordingly.
        self.sendFailureBadgeView = [UIView new];
        [messageStackView addArrangedSubview:self.sendFailureBadgeView];

        UIImageView *sendFailureImageView = [UIImageView new];
        [sendFailureImageView setTemplateImage:self.sendFailureBadge tintColor:UIColor.ows_accentRedColor];
        [self.sendFailureBadgeView addSubview:sendFailureImageView];

        CGFloat sendFailureBadgeBottomMargin
            = round(self.conversationStyle.lastTextLineAxis - self.sendFailureBadgeSize * 0.5f);
        [sendFailureImageView autoPinWidthToSuperview];
        [sendFailureImageView autoPinEdgeToSuperviewEdge:ALEdgeBottom withInset:sendFailureBadgeBottomMargin];
        [sendFailureImageView autoSetDimension:ALDimensionWidth toSize:self.sendFailureBadgeSize];
        [sendFailureImageView autoSetDimension:ALDimensionHeight toSize:self.sendFailureBadgeSize];
    }

    // We want the reaction bubbles to stick to the middle of the screen inset from
    // the edge of the bubble with a small amount of padding unless the bubble is smaller
    // than the reactions view in which case it will break these constraints and extend
    // further into the middle of the screen than the message itself.
    [NSLayoutConstraint autoSetPriority:UILayoutPriorityDefaultLow
                         forConstraints:^{
                             if (self.isIncoming) {
                                 [self.reactionCountsView autoPinEdge:ALEdgeTrailing
                                                               toEdge:ALEdgeTrailing
                                                               ofView:self.messageView
                                                           withOffset:-6];
                             } else {
                                 [self.reactionCountsView autoPinEdge:ALEdgeLeading
                                                               toEdge:ALEdgeLeading
                                                               ofView:self.messageView
                                                           withOffset:6];
                             }
                         }];

    [self.reactionCountsView autoPinEdge:ALEdgeTop
                                  toEdge:ALEdgeBottom
                                  ofView:self.messageView
                              withOffset:-ReactionCountsView.inset];

    // Swipe-to-reply
    [self.swipeToReplyImageView autoPinEdge:ALEdgeLeading toEdge:ALEdgeLeading ofView:self.messageView withOffset:8];
    [self.swipeToReplyImageView autoAlignAxis:ALAxisHorizontal toSameAxisOfView:self.messageView];
}

- (UIImage *)sendFailureBadge
{
    UIImage *image = [UIImage imageNamed:@"error-outline-24"];
    OWSAssertDebug(image);
    OWSAssertDebug(image.size.width == self.sendFailureBadgeSize && image.size.height == self.sendFailureBadgeSize);
    return image;
}

- (CGFloat)sendFailureBadgeSize
{
    return 24.f;
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
    UIImage *_Nullable authorAvatarImage = [[[OWSContactAvatarBuilder alloc]
        initWithAddress:incomingMessage.authorAddress
              colorName:self.viewItem.authorConversationColorName
               diameter:(NSUInteger)ConversationStyle.groupMessageAvatarDiameter] build];
    self.avatarView.image = authorAvatarImage;

    return YES;
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

    if (![incomingMessage.authorAddress isEqualToAddress:address]) {
        return;
    }

    self.avatarView.hidden = ![self updateAvatarView];
}

#pragma mark - Reactions

// Returns true IFF we should display reactions bubbles
- (BOOL)updateReactionsView
{
    if (!self.viewItem.reactionState.hasReactions) {
        self.messageBottomConstraint.constant = 0;
        return NO;
    }

    self.messageBottomConstraint.constant = -(ReactionCountsView.height - ReactionCountsView.inset);
    [self.reactionCountsView configureWith:self.viewItem.reactionState];

    return YES;
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

    if (self.viewItem.reactionState.hasReactions) {
        cellSize.height += ReactionCountsView.height - ReactionCountsView.inset;
    }

    if (self.shouldHaveSendFailureBadge) {
        cellSize.width += self.sendFailureBadgeSize + ConversationStyle.messageStackSpacing;
    }

    cellSize = CGSizeCeil(cellSize);

    return cellSize;
}

#pragma mark - Reuse

- (void)prepareForReuse
{
    [super prepareForReuse];

    switch (self.messageCellType) {
        case OWSMessageCellType_StickerMessage:
            [self.messageStickerView prepareForReuse];
            [self.messageStickerView unloadContent];
            break;
        case OWSMessageCellType_ViewOnce:
            [self.messageViewOnceView prepareForReuse];
            [self.messageViewOnceView unloadContent];
            break;
        default:
            [self.messageBubbleView prepareForReuse];
            [self.messageBubbleView unloadContent];
            break;
    }

    self.avatarView.image = nil;
    self.avatarView.hidden = YES;

    self.reactionCountsView.hidden = YES;
    self.sendFailureBadgeView.hidden = YES;

    [self resetSwipePositionAnimated:NO];
    self.swipeToReplyImageView.alpha = 0;

    self.selectionView.alpha = 1.0;
    self.selected = NO;
}

#pragma mark - Notifications

- (void)setIsCellVisible:(BOOL)isCellVisible {
    BOOL didChange = self.isCellVisible != isCellVisible;

    [super setIsCellVisible:isCellVisible];

    if (!didChange) {
        return;
    }

    [self ensureMediaLoadState];
    if (isCellVisible) {
        self.selectionView.hidden = !self.delegate.isShowingSelectionUI;
    } else {
        self.selectionView.hidden = YES;
    }
}

#pragma mark - Gesture recognizers

- (void)handleMessageViewTapGesture:(UITapGestureRecognizer *)sender
{
    OWSAssertDebug(self.delegate);

    if (sender.state != UIGestureRecognizerStateRecognized) {
        OWSLogVerbose(@"Ignoring tap on message: %@", self.viewItem.interaction.debugDescription);
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

- (void)handleContentViewTapGesture:(UITapGestureRecognizer *)sender
{
    OWSAssertDebug(self.delegate);
    if (self.delegate.isShowingSelectionUI) {
        if (self.isSelected) {
            [self.delegate conversationCell:self didDeselectViewItem:self.viewItem];
        } else {
            [self.delegate conversationCell:self didSelectViewItem:self.viewItem];
        }
        return;
    } else if ([self isGestureInReactions:sender]) {
        [self.delegate conversationCell:self didTapReactions:self.viewItem];
        return;
    } else if ([self isGestureInAvatar:sender]) {
        [self.delegate conversationCell:self didTapAvatar:self.viewItem];
        return;
    }

    OWSFailDebug(@"Received unexpected gesture");
}

- (void)handleLongPressGesture:(UILongPressGestureRecognizer *)sender
{
    OWSAssertDebug(self.delegate);

    switch (sender.state) {
        case UIGestureRecognizerStateBegan: {
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
                    [self.delegate conversationCell:self
                                   shouldAllowReply:shouldAllowReply
                                didLongpressSticker:self.viewItem];
                    break;
            }
            break;
        }
        case UIGestureRecognizerStateEnded:
            [self.delegate conversationCell:self didEndLongpress:self.viewItem];
            break;
        case UIGestureRecognizerStateChanged:
            [self.delegate conversationCell:self didChangeLongpress:self.viewItem];
            break;
        case UIGestureRecognizerStateFailed:
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStatePossible:
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

- (BOOL)isGestureInAvatar:(UIGestureRecognizer *)sender
{
    OWSAssertDebug(self.viewItem);

    if (!self.viewItem.shouldShowSenderAvatar) {
        return NO;
    }

    if (!self.viewItem.isGroupThread) {
        OWSFailDebug(@"not a group thread.");
        return NO;
    }

    CGPoint tapPoint = [sender locationInView:self.avatarView.superview];
    return CGRectContainsPoint(self.avatarView.frame, tapPoint);
}

- (BOOL)isGestureInReactions:(UIGestureRecognizer *)sender
{
    OWSAssertDebug(self.viewItem);

    if (!self.viewItem.reactionState.hasReactions) {
        return NO;
    }

    // Increase reactions touch area height to make sure it's tappable.
    CGRect expandedReactionFrame = [self convertRect:self.reactionCountsView.frame
                                            fromView:self.reactionCountsView.superview];
    expandedReactionFrame = CGRectInset(expandedReactionFrame, 0, -11);

    CGPoint tapPoint = [sender locationInView:self];
    return CGRectContainsPoint(expandedReactionFrame, tapPoint);
}

# pragma mark - UIGestureRecognizerDelegate

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer
{
    if (self.delegate.isShowingSelectionUI) {
        return self.contentViewTapGestureRecognizer == gestureRecognizer;
    }

    if (gestureRecognizer == self.panGestureRecognizer) {
        // Only allow the pan gesture to recognize horizontal panning,
        // to avoid conflicts with the conversation view scroll view.
        CGPoint velocity = [self.panGestureRecognizer velocityInView:self];
        return fabs(velocity.x) > fabs(velocity.y);
    } else if (gestureRecognizer == self.messageViewTapGestureRecognizer) {
        return ![self isGestureInReactions:self.messageViewTapGestureRecognizer]
            && ![self isGestureInAvatar:self.contentViewTapGestureRecognizer] &&
            [self.messageView willHandleTapGesture:self.messageViewTapGestureRecognizer];
    } else if (gestureRecognizer == self.contentViewTapGestureRecognizer) {
        return [self isGestureInAvatar:self.contentViewTapGestureRecognizer] ||
            [self isGestureInReactions:self.contentViewTapGestureRecognizer];
    }

    return YES;
}

#pragma mark - Swipe To Reply

- (BOOL)shouldAllowReply
{
    if (self.delegate == nil) {
        return NO;
    }
    return [self.delegate conversationCell:self shouldAllowReplyForItem:self.viewItem];
}

- (CGFloat)swipeToReplyThreshold
{
    return 55.f;
}

- (BOOL)useSwipeFadeTransition
{
    return self.messageView.isBorderless;
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
        [ImpactHapticFeedback impactOccuredWithStyle:UIImpactFeedbackStyleLight];
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
            self.messageViewInitialX = @(self.messageView.frame.origin.x);
            self.reactionCountsViewViewInitialX = self.reactionCountsView.frame.origin.x;
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
        OWSAssertDebug(self.messageViewInitialX);
        [self setSwipePosition:translationX
            messageViewInitialX:self.messageViewInitialX.doubleValue
                       animated:hasFinished];
    }
}

- (void)setSwipePosition:(CGFloat)position messageViewInitialX:(CGFloat)messageViewInitialX animated:(BOOL)animated
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
    newMessageViewFrame.origin.x = messageViewInitialX + (CurrentAppContext().isRTL ? -position : position);

    // The swipe content moves at 1/8th the speed of the message bubble,
    // so that it reveals itself from underneath with an elastic feel.
    CGRect newSwipeContentFrame = self.swipeableContentView.frame;
    newSwipeContentFrame.origin.x
        = self.swipeableContentViewInitialX + (CurrentAppContext().isRTL ? -position : position) / 8;

    CGRect newReactionCountsViewFrame = self.reactionCountsView.frame;
    newReactionCountsViewFrame.origin.x
        = self.reactionCountsViewViewInitialX + (CurrentAppContext().isRTL ? -position : position);

    CGFloat alpha = 1;
    if ([self useSwipeFadeTransition]) {
        alpha = CGFloatClamp01(CGFloatInverseLerp(position, 0, self.swipeToReplyThreshold));
    }

    void (^viewUpdates)(void) = ^() {
        self.swipeToReplyImageView.alpha = alpha;
        self.messageView.frame = newMessageViewFrame;
        self.swipeableContentView.frame = newSwipeContentFrame;
        self.reactionCountsView.frame = newReactionCountsViewFrame;
    };

    if (animated) {
        [UIView animateWithDuration:0.1 animations:viewUpdates];
    } else {
        viewUpdates();
    }
}

- (void)resetSwipePositionAnimated:(BOOL)animated
{
    if (self.messageViewInitialX != nil) {
        [self setSwipePosition:0 messageViewInitialX:self.messageViewInitialX.doubleValue animated:animated];
        self.messageViewInitialX = nil;
    }
    self.isReplyActive = NO;
}

@end

NS_ASSUME_NONNULL_END
