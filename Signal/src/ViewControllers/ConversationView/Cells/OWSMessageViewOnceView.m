//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageViewOnceView.h"
#import "AttachmentUploadView.h"
#import "ConversationViewItem.h"
#import "OWSBubbleShapeView.h"
#import "OWSBubbleView.h"
#import "OWSLabel.h"
#import "OWSMessageFooterView.h"
#import "Signal-Swift.h"
#import "UIColor+OWS.h"
#import <SignalMessaging/UIView+OWS.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSMessageViewOnceView ()

@property (nonatomic) OWSBubbleView *bubbleView;

@property (nonatomic) UIStackView *vStackView;

@property (nonatomic) UILabel *senderNameLabel;

@property (nonatomic) UIView *senderNameContainer;

@property (nonatomic) UIStackView *hStackView;

@property (nonatomic) UIImageView *iconView;

@property (nonatomic) UILabel *label;

@property (nonatomic, nullable) NSMutableArray<NSLayoutConstraint *> *viewConstraints;

@property (nonatomic) OWSMessageFooterView *footerView;

@end

#pragma mark -

@implementation OWSMessageViewOnceView

#pragma mark - Dependencies

- (OWSAttachmentDownloads *)attachmentDownloads
{
    return SSKEnvironment.shared.attachmentDownloads;
}

#pragma mark -

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];

    if (!self) {
        return self;
    }

    [self commontInit];

    return self;
}

- (void)commontInit
{
    // Ensure only called once.
    OWSAssertDebug(!self.vStackView);

    _viewConstraints = [NSMutableArray new];

    self.layoutMargins = UIEdgeInsetsZero;
    self.userInteractionEnabled = YES;

    self.bubbleView = [OWSBubbleView new];
    self.bubbleView.layoutMargins = UIEdgeInsetsZero;
    [self addSubview:self.bubbleView];
    [self.bubbleView autoPinEdgesToSuperviewEdges];

    self.senderNameLabel = [OWSLabel new];
    self.senderNameContainer = [UIView new];
    self.senderNameContainer.layoutMargins = UIEdgeInsetsMake(0, 0, self.senderNameBottomSpacing, 0);
    [self.senderNameContainer addSubview:self.senderNameLabel];
    [self.senderNameLabel ows_autoPinToSuperviewMargins];

    self.iconView = [UIImageView new];
    [self.iconView setContentHuggingHigh];
    [self.iconView setCompressionResistanceHigh];
    [self.iconView autoSetDimension:ALDimensionWidth toSize:self.iconSize];
    [self.iconView autoSetDimension:ALDimensionHeight toSize:self.iconSize];

    self.label = [OWSLabel new];

    self.hStackView = [UIStackView new];
    self.hStackView.axis = UILayoutConstraintAxisHorizontal;
    self.hStackView.spacing = self.contentHSpacing;
    self.hStackView.alignment = UIStackViewAlignmentCenter;
    self.vStackView = [UIStackView new];
    self.vStackView.axis = UILayoutConstraintAxisVertical;

    self.footerView = [OWSMessageFooterView new];
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

#pragma mark - Load

- (void)configureViews
{
    OWSAssertDebug(self.conversationStyle);
    OWSAssertDebug(self.viewItem);
    OWSAssertDebug(self.viewItem.interaction);
    OWSAssertDebug([self.viewItem.interaction isKindOfClass:[TSMessage class]]);

    [self.bubbleView addSubview:self.vStackView];
    [self.viewConstraints addObjectsFromArray:[self.vStackView autoPinEdgesToSuperviewEdges]];
    NSMutableArray<UIView *> *textViews = [NSMutableArray new];

    if (self.shouldShowSenderName) {
        [self configureSenderNameLabel];
        [textViews addObject:self.senderNameContainer];
    }

    UIView *_Nullable downloadView = [self createDownloadViewIfNecessary];
    if (downloadView) {
        [self.hStackView addArrangedSubview:downloadView];
    }
    if (self.shouldShowIcon) {
        [self configureIconView];
        [self.hStackView addArrangedSubview:self.iconView];
    }
    [self configureLabel];
    [self.hStackView addArrangedSubview:self.label];
    [textViews addObject:self.hStackView];

    if (!self.viewItem.shouldHideFooter) {
        [self.footerView configureWithConversationViewItem:self.viewItem
                                         conversationStyle:self.conversationStyle
                                                isIncoming:self.isIncoming
                                         isOverlayingMedia:NO
                                           isOutsideBubble:self.isBubbleTransparent];
        [textViews addObject:self.footerView];
    }

    [self insertAnyTextViewsIntoStackView:textViews];

    CGSize bubbleSize = [self measureSize];
    [self.viewConstraints addObjectsFromArray:@[
        [self autoSetDimension:ALDimensionWidth toSize:bubbleSize.width],
    ]];

    [self updateBubbleColor];

    [self configureBubbleRounding];

    UIColor *_Nullable bubbleStrokeColor = self.bubbleStrokeColor;
    if (bubbleStrokeColor != nil) {
        self.bubbleView.strokeColor = bubbleStrokeColor;
        self.bubbleView.strokeThickness = 1.f;
    }
}

- (CGFloat)senderNameBottomSpacing
{
    return 2.f;
}

- (BOOL)shouldShowSenderName
{
    return self.viewItem.senderName.length > 0;
}

- (void)configureSenderNameLabel
{
    OWSAssertDebug(self.senderNameLabel);
    OWSAssertDebug(self.shouldShowSenderName);

    self.senderNameLabel.textColor = self.textColor;
    self.senderNameLabel.font = OWSMessageView.senderNameFont;
    self.senderNameLabel.attributedText = self.viewItem.senderName;
    self.senderNameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
}

- (CGFloat)iconSize
{
    return 24.f;
}

- (OWSDirectionalRectCorner)sharpCorners
{
    OWSDirectionalRectCorner sharpCorners = 0;

    if (!self.viewItem.isFirstInCluster) {
        sharpCorners = sharpCorners
            | (self.isIncoming ? OWSDirectionalRectCornerTopLeading : OWSDirectionalRectCornerTopTrailing);
    }

    if (!self.viewItem.isLastInCluster) {
        sharpCorners = sharpCorners
            | (self.isIncoming ? OWSDirectionalRectCornerBottomLeading : OWSDirectionalRectCornerBottomTrailing);
    }

    return sharpCorners;
}

- (OWSDirectionalRectCorner)sharpCornersForQuotedMessage
{
    if (self.viewItem.senderName) {
        return OWSDirectionalRectCornerAllCorners;
    } else {
        return self.sharpCorners | OWSDirectionalRectCornerBottomLeading | OWSDirectionalRectCornerBottomTrailing;
    }
}

- (void)configureBubbleRounding
{
    self.bubbleView.sharpCorners = self.sharpCorners;
}

- (void)updateBubbleColor
{
    self.bubbleView.fillColor = self.bubbleColor;
}

- (UIColor *)bubbleColor
{
    UIColor *pendingColor = (Theme.isDarkThemeEnabled ? UIColor.ows_gray85Color : UIColor.ows_gray15Color);

    switch (self.viewItem.viewOnceMessageState) {
        case ViewOnceMessageState_Unknown:
            OWSFailDebug(@"Invalid value.");
            // Fall through.
        case ViewOnceMessageState_IncomingExpired:
            return Theme.backgroundColor;
        case ViewOnceMessageState_IncomingDownloading:
            return pendingColor;
        case ViewOnceMessageState_IncomingFailed:
            return pendingColor;
        case ViewOnceMessageState_IncomingAvailable:
            return Theme.offBackgroundColor;
        case ViewOnceMessageState_OutgoingFailed:
            return pendingColor;
        case ViewOnceMessageState_OutgoingSending:
            return self.conversationStyle.bubbleColorOutgoingSending;
        case ViewOnceMessageState_OutgoingSentExpired:
            return self.conversationStyle.bubbleColorOutgoingSent;
        case ViewOnceMessageState_IncomingInvalidContent:
            return Theme.backgroundColor;
    }
}

- (BOOL)isBubbleTransparent
{
    switch (self.viewItem.viewOnceMessageState) {
        case ViewOnceMessageState_Unknown:
            OWSFailDebug(@"Invalid value.");
            // Fall through.
        case ViewOnceMessageState_IncomingExpired:
            return YES;
        case ViewOnceMessageState_IncomingDownloading:
        case ViewOnceMessageState_IncomingFailed:
        case ViewOnceMessageState_IncomingAvailable:
        case ViewOnceMessageState_OutgoingFailed:
        case ViewOnceMessageState_OutgoingSending:
        case ViewOnceMessageState_OutgoingSentExpired:
            return NO;
        case ViewOnceMessageState_IncomingInvalidContent:
            return YES;
    }
}

- (nullable UIColor *)bubbleStrokeColor
{
    switch (self.viewItem.viewOnceMessageState) {
        case ViewOnceMessageState_Unknown:
            OWSFailDebug(@"Invalid value.");
            // Fall through.
        case ViewOnceMessageState_IncomingExpired:
            return Theme.offBackgroundColor;
        case ViewOnceMessageState_IncomingDownloading:
            return nil;
        case ViewOnceMessageState_IncomingFailed:
            return nil;
        case ViewOnceMessageState_IncomingAvailable:
            return nil;
        case ViewOnceMessageState_OutgoingFailed:
            return nil;
        case ViewOnceMessageState_OutgoingSending:
        case ViewOnceMessageState_OutgoingSentExpired:
            return nil;
        case ViewOnceMessageState_IncomingInvalidContent:
            return UIColor.ows_destructiveRedColor;
    }
}

- (CGFloat)contentHSpacing
{
    return 8.f;
}

- (UIColor *)textColor
{
    switch (self.viewItem.viewOnceMessageState) {
        case ViewOnceMessageState_Unknown:
            OWSFailDebug(@"Invalid value.");
            // Fall through.
        case ViewOnceMessageState_IncomingExpired:
        case ViewOnceMessageState_IncomingDownloading:
        case ViewOnceMessageState_IncomingFailed:
        case ViewOnceMessageState_IncomingAvailable:
            return ConversationStyle.bubbleTextColorIncoming;
        case ViewOnceMessageState_OutgoingFailed:
        case ViewOnceMessageState_OutgoingSending:
        case ViewOnceMessageState_OutgoingSentExpired:
            return ConversationStyle.bubbleTextColorOutgoing;
        case ViewOnceMessageState_IncomingInvalidContent:
            return Theme.secondaryColor;
    }
}

- (UIColor *)iconColor
{
    UIColor *pendingColor = (Theme.isDarkThemeEnabled ? UIColor.ows_gray15Color : UIColor.ows_gray75Color);

    switch (self.viewItem.viewOnceMessageState) {
        case ViewOnceMessageState_Unknown:
            OWSFailDebug(@"Invalid value.");
            // Fall through.
        case ViewOnceMessageState_IncomingExpired:
            return ConversationStyle.bubbleTextColorIncoming;
        case ViewOnceMessageState_IncomingDownloading:
        case ViewOnceMessageState_IncomingFailed:
            return pendingColor;
        case ViewOnceMessageState_IncomingAvailable:
            return ConversationStyle.bubbleTextColorIncoming;
        case ViewOnceMessageState_OutgoingFailed:
            return pendingColor;
        case ViewOnceMessageState_OutgoingSending:
        case ViewOnceMessageState_OutgoingSentExpired:
            return ConversationStyle.bubbleTextColorOutgoing;
        case ViewOnceMessageState_IncomingInvalidContent:
            return Theme.secondaryColor;
    }
}

- (BOOL)hasBottomFooter
{
    return !self.viewItem.shouldHideFooter;
}

- (BOOL)insertAnyTextViewsIntoStackView:(NSArray<UIView *> *)textViews
{
    if (textViews.count < 1) {
        return NO;
    }

    UIStackView *textStackView = [[UIStackView alloc] initWithArrangedSubviews:textViews];
    textStackView.axis = UILayoutConstraintAxisVertical;
    textStackView.spacing = self.textViewVSpacing;
    textStackView.layoutMarginsRelativeArrangement = YES;
    textStackView.layoutMargins = UIEdgeInsetsMake(self.conversationStyle.textInsetTop,
        self.conversationStyle.textInsetHorizontal,
        self.conversationStyle.textInsetBottom,
        self.conversationStyle.textInsetHorizontal);
    [self.vStackView addArrangedSubview:textStackView];
    return YES;
}

- (CGFloat)textViewVSpacing
{
    return 2.f;
}

#pragma mark - Load / Unload

- (void)loadContent
{
    // Do nothing.
}

- (void)unloadContent
{
    // Do nothing.
}

#pragma mark - Subviews

- (void)configureLabel
{
    OWSAssertDebug(self.label);

    self.label.textColor = self.textColor;
    self.label.font = UIFont.ows_dynamicTypeSubheadlineFont.ows_mediumWeight;
    self.label.numberOfLines = 1;
    self.label.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.label setContentHuggingHorizontalLow];
    [self.label setCompressionResistanceHorizontalLow];

    switch (self.viewItem.viewOnceMessageState) {
        case ViewOnceMessageState_Unknown:
            OWSFailDebug(@"Invalid value.");
            // Fall through.
        case ViewOnceMessageState_IncomingExpired:
            self.label.text = NSLocalizedString(@"PER_MESSAGE_EXPIRATION_VIEWED",
                @"Label for view-once messages indicating that "
                @"the local user has viewed the message's contents.");
            break;
        case ViewOnceMessageState_IncomingDownloading:
            self.label.text
                = NSLocalizedString(@"MESSAGE_STATUS_DOWNLOADING", @"message status while message is downloading.");
            break;
        case ViewOnceMessageState_IncomingFailed:
            self.label.text = CommonStrings.retryButton;
            break;
        case ViewOnceMessageState_IncomingAvailable:
            self.label.text = NSLocalizedString(@"PER_MESSAGE_EXPIRATION_TAP_TO_VIEW",
                @"Label for view-once messages indicating that "
                @"user can tap to view the message's contents.");
            break;
        case ViewOnceMessageState_OutgoingFailed:
            self.label.text = CommonStrings.retryButton;
            break;
        case ViewOnceMessageState_OutgoingSending:
            self.label.text = NSLocalizedString(@"MESSAGE_STATUS_SENDING", @"message status while message is sending.");
            break;
        case ViewOnceMessageState_OutgoingSentExpired:
            self.label.text = NSLocalizedString(
                @"PER_MESSAGE_EXPIRATION_OUTGOING_MESSAGE", @"Label for outgoing view-once messages.");
            break;
        case ViewOnceMessageState_IncomingInvalidContent:
            self.label.text = NSLocalizedString(
                @"PER_MESSAGE_EXPIRATION_INVALID_CONTENT", @"Label for view-once messages that have invalid content.");
            // Reconfigure label for this state only.
            self.label.font = UIFont.ows_dynamicTypeSubheadlineFont;
            self.label.textColor = Theme.secondaryColor;
            self.label.numberOfLines = 0;
            self.label.lineBreakMode = NSLineBreakByWordWrapping;
            break;
    }
}

- (void)configureIconView
{
    OWSAssertDebug(self.iconView);

    NSString *_Nullable iconName = self.iconName;
    if (iconName != nil) {
        [self.iconView setTemplateImageName:iconName tintColor:self.iconColor];
    }
}

- (nullable NSString *)iconName
{
    switch (self.viewItem.viewOnceMessageState) {
        case ViewOnceMessageState_Unknown:
            OWSFailDebug(@"Invalid value.");
            // Fall through.
        case ViewOnceMessageState_IncomingExpired:
            return @"play-outline-24";
        case ViewOnceMessageState_IncomingDownloading:
            OWSFailDebug(@"Unexpected state.");
            return nil;
        case ViewOnceMessageState_IncomingFailed:
            return @"retry-24";
        case ViewOnceMessageState_IncomingAvailable:
            return @"play-filled-24";
        case ViewOnceMessageState_OutgoingFailed:
            return @"arrow-down-circle-outline-24";
        case ViewOnceMessageState_OutgoingSending:
        case ViewOnceMessageState_OutgoingSentExpired:
            return @"play-outline-24";
        case ViewOnceMessageState_IncomingInvalidContent:
            OWSFailDebug(@"Unexpected state.");
            return nil;
    }
}

- (nullable UIView *)createDownloadViewIfNecessary
{
    if (!self.isIncomingDownloading) {
        return nil;
    }

    NSString *_Nullable uniqueId = self.viewItem.attachmentPointer.uniqueId;
    if (uniqueId.length < 1) {
        OWSFailDebug(@"Missing uniqueId.");
        return nil;
    }

    MediaDownloadView *downloadView =
        [[MediaDownloadView alloc] initWithAttachmentId:uniqueId radius:self.downloadProgressRadius];
    [downloadView setProgressColor:self.textColor];
    [downloadView autoSetDimension:ALDimensionWidth toSize:self.iconSize];
    [downloadView autoSetDimension:ALDimensionHeight toSize:self.iconSize];
    [downloadView setContentHuggingHigh];
    [downloadView setCompressionResistanceHigh];
    return downloadView;
}

// We use this "min width" to reduce/avoid "flutter"
// in the bubble's size as the message changes states.
- (CGFloat)minContentWidth
{
    return round(self.conversationStyle.maxMessageWidth * 0.4f);
}

- (CGFloat)downloadProgressRadius
{
    return self.iconSize * 0.5f;
}

- (BOOL)shouldShowIcon
{
    return (self.viewItem.viewOnceMessageState != ViewOnceMessageState_IncomingInvalidContent
        && self.viewItem.viewOnceMessageState != ViewOnceMessageState_IncomingDownloading);
}

- (BOOL)shouldShowIconOrProgress
{
    return (self.viewItem.viewOnceMessageState != ViewOnceMessageState_IncomingInvalidContent);
}

- (BOOL)isIncomingDownloading
{
    return self.viewItem.viewOnceMessageState == ViewOnceMessageState_IncomingDownloading;
}

- (BOOL)isIncomingFailed
{
    return self.viewItem.viewOnceMessageState == ViewOnceMessageState_IncomingFailed;
}

- (BOOL)isAvailable
{
    return (self.viewItem.viewOnceMessageState == ViewOnceMessageState_IncomingAvailable);
}

#pragma mark - Measurement

- (CGSize)contentSize
{
    OWSAssertDebug(self.conversationStyle);
    OWSAssertDebug(self.conversationStyle.maxMessageWidth > 0);

    CGFloat hMargins = self.conversationStyle.textInsetHorizontal * 2;
    CGFloat maxTextWidth = self.conversationStyle.maxMessageWidth - hMargins;
    if (self.shouldShowIconOrProgress) {
        maxTextWidth -= self.contentHSpacing + self.iconSize;
    }
    maxTextWidth = floor(maxTextWidth);
    [self configureLabel];
    CGSize result = CGSizeCeil([self.label sizeThatFits:CGSizeMake(maxTextWidth, CGFLOAT_MAX)]);
    if (self.shouldShowIconOrProgress) {
        result.width += self.contentHSpacing + self.iconSize;
        result.height = MAX(result.height, self.iconSize);
    }
    result.width = MAX(result.width, self.minContentWidth);
    result.width = MIN(result.width, self.conversationStyle.maxMessageWidth);

    return result;
}

- (nullable NSValue *)senderNameSize
{
    OWSAssertDebug(self.conversationStyle);
    OWSAssertDebug(self.conversationStyle.maxMessageWidth > 0);

    if (!self.shouldShowSenderName) {
        return nil;
    }

    CGFloat hMargins = self.conversationStyle.textInsetHorizontal * 2;
    const int maxTextWidth = (int)floor(self.conversationStyle.maxMessageWidth - hMargins);
    [self configureSenderNameLabel];
    CGSize result = CGSizeCeil([self.senderNameLabel sizeThatFits:CGSizeMake(maxTextWidth, CGFLOAT_MAX)]);
    result.width = MIN(result.width, maxTextWidth);
    result.height += self.senderNameBottomSpacing;
    return [NSValue valueWithCGSize:result];
}

- (CGSize)measureSize
{
    OWSAssertDebug(self.conversationStyle);
    OWSAssertDebug(self.conversationStyle.viewWidth > 0);
    OWSAssertDebug(self.viewItem);
    OWSAssertDebug([self.viewItem.interaction isKindOfClass:[TSMessage class]]);

    CGSize cellSize = CGSizeZero;

    [self configureBubbleRounding];

    NSMutableArray<NSValue *> *textViewSizes = [NSMutableArray new];

    NSValue *_Nullable senderNameSize = [self senderNameSize];
    if (senderNameSize) {
        [textViewSizes addObject:senderNameSize];
    }

    CGSize contentSize = self.contentSize;
    [textViewSizes addObject:[NSValue valueWithCGSize:contentSize]];

    if (self.hasBottomFooter) {
        CGSize footerSize = [self.footerView measureWithConversationViewItem:self.viewItem];
        footerSize.width = MIN(footerSize.width, self.conversationStyle.maxMessageWidth);
        [textViewSizes addObject:[NSValue valueWithCGSize:footerSize]];
    }

    if (textViewSizes.count > 0) {
        CGSize groupSize = [self sizeForTextViewGroup:textViewSizes];
        cellSize.width = MAX(cellSize.width, groupSize.width);
        cellSize.height += groupSize.height;
    }

    // Make sure the bubble is always wide enough to complete it's bubble shape.
    cellSize.width = MAX(cellSize.width, self.bubbleView.minWidth);

    OWSAssertDebug(cellSize.width > 0 && cellSize.height > 0);

    cellSize = CGSizeCeil(cellSize);

    OWSAssertDebug(cellSize.width <= self.conversationStyle.maxMessageWidth);
    cellSize.width = MIN(cellSize.width, self.conversationStyle.maxMessageWidth);

    return cellSize;
}

- (CGSize)sizeForTextViewGroup:(NSArray<NSValue *> *)textViewSizes
{
    OWSAssertDebug(textViewSizes);
    OWSAssertDebug(textViewSizes.count > 0);
    OWSAssertDebug(self.conversationStyle);
    OWSAssertDebug(self.conversationStyle.maxMessageWidth > 0);

    CGSize result = CGSizeZero;
    for (NSValue *size in textViewSizes) {
        result.width = MAX(result.width, size.CGSizeValue.width);
        result.height += size.CGSizeValue.height;
    }
    result.height += self.textViewVSpacing * (textViewSizes.count - 1);
    result.height += (self.conversationStyle.textInsetTop + self.conversationStyle.textInsetBottom);
    result.width += self.conversationStyle.textInsetHorizontal * 2;

    return result;
}

#pragma mark -

- (void)prepareForReuse
{
    [NSLayoutConstraint deactivateConstraints:self.viewConstraints];
    self.viewConstraints = [NSMutableArray new];

    self.delegate = nil;

    self.label.text = nil;
    self.iconView.image = nil;

    self.bubbleView.fillColor = nil;
    self.bubbleView.strokeColor = nil;
    self.bubbleView.strokeThickness = 0.f;
    [self.bubbleView clearPartnerViews];

    for (UIView *subview in self.hStackView.subviews) {
        [subview removeFromSuperview];
    }
    for (UIView *subview in self.bubbleView.subviews) {
        [subview removeFromSuperview];
    }

    [self.footerView removeFromSuperview];
    [self.footerView prepareForReuse];

    for (UIView *subview in self.vStackView.subviews) {
        [subview removeFromSuperview];
    }
    for (UIView *subview in self.subviews) {
        if (subview != self.bubbleView) {
            [subview removeFromSuperview];
        }
    }
}

#pragma mark - Gestures

- (BOOL)willHandleTapGesture:(UITapGestureRecognizer *)sender
{
    return YES;
}

- (void)handleTapGesture:(UITapGestureRecognizer *)sender
{
    OWSAssertDebug(self.delegate);

    if (sender.state != UIGestureRecognizerStateRecognized) {
        OWSLogVerbose(@"Ignoring tap on message: %@", self.viewItem.interaction.debugDescription);
        return;
    }

    if (self.isIncomingFailed) {
        [self.delegate didTapFailedIncomingAttachment:self.viewItem];
    } else if (self.isAvailable) {
        if (!self.viewItem.attachmentStream) {
            OWSFailDebug(@"Missing attachment.");
            return;
        }
        [self.delegate didTapViewOnceAttachment:self.viewItem attachmentStream:self.viewItem.attachmentStream];
    }
}

- (OWSMessageGestureLocation)gestureLocationForLocation:(CGPoint)locationInMessageBubble
{
    return OWSMessageGestureLocation_Default;
}

- (BOOL)handlePanGesture:(UIPanGestureRecognizer *)sender
{
    return NO;
}

@end

NS_ASSUME_NONNULL_END
