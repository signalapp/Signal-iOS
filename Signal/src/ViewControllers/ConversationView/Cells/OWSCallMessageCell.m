//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSCallMessageCell.h"
#import "ConversationViewItem.h"
#import "OWSBubbleView.h"
#import "OWSMessageFooterView.h"
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

@interface OWSCallMessageCell ()

@property (nonatomic, nullable) TSInteraction *interaction;

@property (nonatomic) OWSBubbleView *bubbleView;
@property (nonatomic) UIImageView *imageView;
@property (nonatomic) UIView *circleView;
@property (nonatomic) UILabel *titleLabel;
@property (nonatomic) OWSMessageFooterView *footerView;
@property (nonatomic) UIStackView *hStackView;
@property (nonatomic) UIStackView *vStackView;
@property (nonatomic) NSMutableArray<NSLayoutConstraint *> *layoutConstraints;

@end

#pragma mark -

@implementation OWSCallMessageCell

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

    self.layoutConstraints = [NSMutableArray new];

    self.bubbleView = [OWSBubbleView new];
    self.bubbleView.userInteractionEnabled = NO;
    [self.contentView addSubview:self.bubbleView];
    [self.bubbleView autoPinEdgeToSuperviewEdge:ALEdgeTop];
    [self.bubbleView autoPinEdgeToSuperviewEdge:ALEdgeBottom];

    self.imageView = [UIImageView new];
    [self.imageView setContentHuggingHigh];

    self.circleView = [UIView new];
    self.circleView.backgroundColor = [UIColor whiteColor];
    self.circleView.layer.cornerRadius = self.circleSize * 0.5f;
    [self.circleView addSubview:self.imageView];
    [self.imageView autoCenterInSuperview];
    [self.circleView autoSetDimension:ALDimensionWidth toSize:self.circleSize];
    [self.circleView autoSetDimension:ALDimensionHeight toSize:self.circleSize];
    [self.circleView setContentHuggingHigh];

    self.titleLabel = [UILabel new];
    self.titleLabel.numberOfLines = 0;
    self.titleLabel.lineBreakMode = NSLineBreakByWordWrapping;
    [self.titleLabel setContentHuggingLow];

    self.hStackView = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.circleView,
        self.titleLabel,
    ]];
    self.hStackView.axis = UILayoutConstraintAxisHorizontal;
    self.hStackView.spacing = self.hSpacing;
    self.hStackView.alignment = UIStackViewAlignmentCenter;

    self.footerView = [OWSMessageFooterView new];

    self.vStackView = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.hStackView,
        self.footerView,
    ]];
    self.vStackView.axis = UILayoutConstraintAxisVertical;
    self.vStackView.spacing = self.vSpacing;
    self.vStackView.userInteractionEnabled = NO;
    [self.bubbleView addSubview:self.vStackView];
    [self.vStackView autoPinToSuperviewEdges];

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
    OWSAssert([self.viewItem.interaction isKindOfClass:[TSCall class]]);

    TSCall *call = (TSCall *)self.viewItem.interaction;

    self.bubbleView.bubbleColor = [self bubbleColorForCall:call];

    UIImage *icon = [self iconForCall:call];
    self.imageView.image = [icon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    self.imageView.tintColor = [self iconColorForCall:call];
    self.titleLabel.textColor = [self textColorForCall:call];
    [self applyTitleForCall:call label:self.titleLabel];

    if (self.hasFooter) {
        [self.footerView configureWithConversationViewItem:self.viewItem isOverlayingMedia:NO];
        self.footerView.hidden = NO;
    } else {
        self.footerView.hidden = YES;
    }

    if (call.isIncoming) {
        [self.layoutConstraints addObjectsFromArray:@[
            [self.bubbleView autoPinEdgeToSuperviewEdge:ALEdgeLeading withInset:self.conversationStyle.gutterLeading],
            [self.bubbleView autoPinEdgeToSuperviewEdge:ALEdgeTrailing
                                              withInset:self.conversationStyle.gutterTrailing
                                               relation:NSLayoutRelationGreaterThanOrEqual],
        ]];
    } else {
        [self.layoutConstraints addObjectsFromArray:@[
            [self.bubbleView autoPinEdgeToSuperviewEdge:ALEdgeLeading
                                              withInset:self.conversationStyle.gutterLeading
                                               relation:NSLayoutRelationGreaterThanOrEqual],
            [self.bubbleView autoPinEdgeToSuperviewEdge:ALEdgeTrailing withInset:self.conversationStyle.gutterTrailing],
        ]];
    }

    CGSize cellSize = [self cellSizeWithTransaction:transaction];
    [self.layoutConstraints addObjectsFromArray:@[
        [self.bubbleView autoSetDimension:ALDimensionWidth toSize:cellSize.width],
        [self.bubbleView autoSetDimension:ALDimensionHeight toSize:cellSize.height],
    ]];

    self.vStackView.layoutMarginsRelativeArrangement = YES;
    self.vStackView.layoutMargins = UIEdgeInsetsMake(self.conversationStyle.textInsetTop,
        self.conversationStyle.textInsetHorizontal,
        self.conversationStyle.textInsetBottom,
        self.conversationStyle.textInsetHorizontal);
}

- (BOOL)hasFooter
{
    return !self.viewItem.shouldHideFooter;
}

- (CGFloat)circleSize
{
    return 48.f;
}

- (UIColor *)textColorForCall:(TSCall *)call
{
    return [self.conversationStyle bubbleTextColorWithCall:call];
}

- (UIColor *)bubbleColorForCall:(TSCall *)call
{
    return [self.conversationStyle bubbleColorWithCall:call];
}

- (UIColor *)iconColorForCall:(TSCall *)call
{
    switch (call.callType) {
        case RPRecentCallTypeIncoming:
        case RPRecentCallTypeOutgoing:
        case RPRecentCallTypeIncomingIncomplete:
        case RPRecentCallTypeOutgoingIncomplete:
            return [UIColor ows_greenColor];
        case RPRecentCallTypeIncomingMissed:
        case RPRecentCallTypeIncomingMissedBecauseOfChangedIdentity:
        case RPRecentCallTypeIncomingDeclined:
            return [UIColor ows_redColor];
    }
}

- (UIImage *)iconForCall:(TSCall *)call
{
    UIImage *result = nil;
    switch (call.callType) {
        case RPRecentCallTypeIncoming:
        case RPRecentCallTypeOutgoing:
        case RPRecentCallTypeIncomingIncomplete:
        case RPRecentCallTypeOutgoingIncomplete:
            result = [UIImage imageNamed:@"phone-up"];
            break;
        case RPRecentCallTypeIncomingMissed:
        case RPRecentCallTypeIncomingMissedBecauseOfChangedIdentity:
        case RPRecentCallTypeIncomingDeclined:
            result = [UIImage imageNamed:@"phone-down"];
            break;
    }
    OWSAssert(result);
    return result;
}

- (void)applyTitleForCall:(TSCall *)call label:(UILabel *)label
{
    OWSAssert(call);
    OWSAssert(label);

    [self configureFonts];

    label.text = [self titleForCall:call];
}

- (NSString *)titleForCall:(TSCall *)call
{
    // We don't actually use the `transaction` but other sibling classes do.
    switch (call.callType) {
        case RPRecentCallTypeIncoming:
        case RPRecentCallTypeOutgoing:
        case RPRecentCallTypeOutgoingIncomplete:
        case RPRecentCallTypeIncomingIncomplete:
            return NSLocalizedString(@"CALL_DEFAULT_STATUS",
                @"Message recorded in conversation history when local user is making or has completed a call.");
        case RPRecentCallTypeIncomingMissed:
        case RPRecentCallTypeIncomingMissedBecauseOfChangedIdentity:
            return NSLocalizedString(
                @"CALL_MISSED", @"Message recorded in conversation history when local user missed a call.");
        case RPRecentCallTypeIncomingDeclined:
            return NSLocalizedString(
                @"CALL_DECLINED", @"Message recorded in conversation history when local user declined a call.");
    }
}

- (CGFloat)hSpacing
{
    return 8.f;
}

- (CGFloat)vSpacing
{
    return 6.f;
}

- (CGSize)titleSize
{
    OWSAssert(self.conversationStyle);
    OWSAssert(self.viewItem);

    CGFloat maxTitleWidth = (CGFloat)ceil(self.conversationStyle.maxMessageWidth
        - (self.circleSize + self.hSpacing + self.conversationStyle.textInsetHorizontal * 2));
    DDLogVerbose(@"%@ maxTitleWidth %f", self.logTag, maxTitleWidth);
    return [self.titleLabel sizeThatFits:CGSizeMake(maxTitleWidth, CGFLOAT_MAX)];
}

- (CGSize)cellSizeWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    OWSAssert(self.conversationStyle);
    OWSAssert(self.viewItem);
    OWSAssert([self.viewItem.interaction isKindOfClass:[TSCall class]]);

    TSCall *call = (TSCall *)self.viewItem.interaction;

    [self applyTitleForCall:call label:self.titleLabel];
    CGSize titleSize = [self titleSize];

    CGSize hStackSize = titleSize;
    hStackSize.width += (self.hSpacing + self.circleSize);
    hStackSize.height = MAX(hStackSize.height, self.circleSize);

    CGSize vStackSize = hStackSize;
    if (self.hasFooter) {
        CGSize footerSize = [self.footerView measureWithConversationViewItem:self.viewItem];
        vStackSize.height += (self.vSpacing + footerSize.height);
        vStackSize.width = MAX(vStackSize.width, footerSize.width);
    }

    CGSize result = CGSizeCeil(CGSizeMake(
        MIN(self.conversationStyle.viewWidth, vStackSize.width + self.conversationStyle.textInsetHorizontal * 2),
        vStackSize.height + self.conversationStyle.textInsetTop + self.conversationStyle.textInsetBottom));
    return result;
}

#pragma mark - UIMenuController

- (void)showMenuController
{
    OWSAssertIsOnMainThread();

    DDLogDebug(@"%@ long pressed call cell: %@", self.logTag, self.viewItem.interaction.debugDescription);

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

- (void) delete:(nullable id)sender
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

- (void)prepareForReuse
{
    [NSLayoutConstraint deactivateConstraints:self.layoutConstraints];
    [self.layoutConstraints removeAllObjects];

    [self.footerView prepareForReuse];
}

#pragma mark - Gesture recognizers

- (void)handleTapGesture:(UITapGestureRecognizer *)sender
{
    OWSAssert(self.delegate);
    OWSAssert([self.viewItem.interaction isKindOfClass:[TSCall class]]);

    if (sender.state == UIGestureRecognizerStateRecognized) {
        TSCall *call = (TSCall *)self.viewItem.interaction;
        [self.delegate didTapCall:call];
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
