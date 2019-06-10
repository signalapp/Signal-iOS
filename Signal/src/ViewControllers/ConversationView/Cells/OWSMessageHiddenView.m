//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageHiddenView.h"
#import "AttachmentUploadView.h"
#import "ConversationViewItem.h"

//#import "OWSAudioMessageView.h"
#import "OWSBubbleShapeView.h"
#import "OWSBubbleView.h"

//#import "OWSContactShareButtonsView.h"
//#import "OWSContactShareView.h"
//#import "OWSGenericAttachmentView.h"
#import "OWSLabel.h"
#import "OWSMessageFooterView.h"

//#import "OWSMessageTextView.h"
//#import "OWSQuotedMessageView.h"
#import "Signal-Swift.h"
#import "UIColor+OWS.h"
#import <SignalMessaging/UIView+OWS.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSMessageHiddenView ()

@property (nonatomic) OWSBubbleView *bubbleView;

@property (nonatomic) UIStackView *vStackView;

@property (nonatomic) UIStackView *hStackView;

@property (nonatomic) UIImageView *iconView;

@property (nonatomic) UILabel *label;

//@property (nonatomic) UIView *senderNameContainer;
//
//@property (nonatomic) OWSMessageTextView *bodyTextView;
//
//@property (nonatomic, nullable) UIView *quotedMessageView;
//
//@property (nonatomic, nullable) UIView *bodyMediaView;
//
//@property (nonatomic) LinkPreviewView *linkPreviewView;
//
//// Should lazy-load expensive view contents (images, etc.).
//// Should do nothing if view is already loaded.
//@property (nonatomic, nullable) dispatch_block_t loadCellContentBlock;
//// Should unload all expensive view contents (images, etc.).
//@property (nonatomic, nullable) dispatch_block_t unloadCellContentBlock;

@property (nonatomic, nullable) NSMutableArray<NSLayoutConstraint *> *viewConstraints;

@property (nonatomic) OWSMessageFooterView *footerView;

@end

#pragma mark -

@implementation OWSMessageHiddenView

#pragma mark - Dependencies

- (OWSAttachmentDownloads *)attachmentDownloads
{
    return SSKEnvironment.shared.attachmentDownloads;
}

//- (TSAccountManager *)tsAccountManager
//{
//    OWSAssertDebug(SSKEnvironment.shared.tsAccountManager);
//
//    return SSKEnvironment.shared.tsAccountManager;
//}

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

    self.iconView = [UIImageView new];
    [self.iconView setContentHuggingHorizontalHigh];
    [self.iconView setCompressionResistanceHorizontalHigh];
    [self.iconView autoSetDimension:ALDimensionWidth toSize:self.iconSize];
    [self.iconView autoSetDimension:ALDimensionHeight toSize:self.iconSize];

    self.label = [OWSLabel new];

    self.hStackView = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.iconView,
        self.label,
    ]];
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

- (BOOL)perMessageExpirationHasExpired
{
    return self.viewItem.perMessageExpirationHasExpired;
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
    // TODO:
    [self addProgressViewsIfNecessary:self.overlayHostView shouldShowDownloadProgress:NO];

    [self configureIconView];
    [self configureLabel];
    [textViews addObject:self.hStackView];

    if (self.viewItem.shouldHideFooter) {
        // Do nothing.
    } else {
        [self.footerView configureWithConversationViewItem:self.viewItem
                                         conversationStyle:self.conversationStyle
                                                isIncoming:self.isIncoming
                                         isOverlayingMedia:NO
                                           isOutsideBubble:NO];
        [textViews addObject:self.footerView];
    }

    [self insertAnyTextViewsIntoStackView:textViews];

    CGSize bubbleSize = [self measureSize];
    [self.viewConstraints addObjectsFromArray:@[
        [self autoSetDimension:ALDimensionWidth toSize:bubbleSize.width],
    ]];

    [self updateBubbleColor];

    [self configureBubbleRounding];
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
    if (self.perMessageExpirationHasExpired) {
        self.bubbleView.bubbleColor = UIColor.ows_gray15Color;
    } else if (self.isIncoming) {
        self.bubbleView.bubbleGradientColors = @[
            [UIColor.ows_gray05Color blendWithColor:UIColor.ows_blackColor alpha:0.15],
            UIColor.ows_gray05Color,
        ];
    } else {
        self.bubbleView.bubbleGradientColors = @[
            [UIColor.ows_signalBlueColor blendWithColor:UIColor.ows_blackColor alpha:0.15],
            UIColor.ows_signalBlueColor,
        ];
    }
}

- (CGFloat)contentHSpacing
{
    return 6.f;
}

- (UIColor *)contentForegroundColor
{
    if (self.perMessageExpirationHasExpired) {
        return UIColor.ows_gray60Color;
    } else if (self.isIncoming) {
        return UIColor.ows_gray90Color;
    } else {
        return UIColor.ows_whiteColor;
    }
}

- (UIView *)overlayHostView
{
    return self.hStackView;
}

- (UIColor *)overlayBackgroundColor
{
    if (self.perMessageExpirationHasExpired) {
        return UIColor.ows_gray15Color;
    } else if (self.isIncoming) {
        return UIColor.ows_gray05Color;
    } else {
        return UIColor.ows_signalBlueColor;
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

    self.label.textColor = self.contentForegroundColor;
    self.label.font = UIFont.ows_dynamicTypeSubheadlineFont.ows_mediumWeight;
    self.label.text
        = (self.perMessageExpirationHasExpired ? NSLocalizedString(@"PER_MESSAGE_EXPIRATION_VIEWED",
                                                     @"Label for messages with per-message expiration indicating that "
                                                     @"user has viewed the message's contents.")
                                               : NSLocalizedString(@"PER_MESSAGE_EXPIRATION_TAP_TO_VIEW",
                                                     @"Label for messages with per-message expiration indicating that "
                                                     @"user can tap to view the message's contents."));
    self.label.lineBreakMode = NSLineBreakByTruncatingTail;
}

- (void)configureIconView
{
    OWSAssertDebug(self.iconView);

    [self.iconView setTemplateImageName:(self.perMessageExpirationHasExpired ? @"play-outline-24" : @"play-filled-24")
                              tintColor:self.contentForegroundColor];
}

- (void)addProgressViewsIfNecessary:(UIView *)bodyMediaView shouldShowDownloadProgress:(BOOL)shouldShowDownloadProgress
{
    if (self.viewItem.attachmentStream) {
        [self addUploadViewIfNecessary:bodyMediaView];
    } else if (self.viewItem.attachmentPointer) {
        [self addDownloadViewIfNecessary:bodyMediaView shouldShowDownloadProgress:(BOOL)shouldShowDownloadProgress];
    }
}

- (void)addUploadViewIfNecessary:(UIView *)bodyMediaView
{
    OWSAssertDebug(self.viewItem.attachmentStream);

    if (!self.isOutgoing) {
        return;
    }
    if (self.viewItem.attachmentStream.isUploaded) {
        return;
    }

    AttachmentUploadView *uploadView = [[AttachmentUploadView alloc] initWithAttachment:self.viewItem.attachmentStream];
    [self.bubbleView addSubview:uploadView];
    [uploadView autoPinEdgesToSuperviewEdges];
    [uploadView setContentHuggingLow];
    [uploadView setCompressionResistanceLow];
}

- (void)addDownloadViewIfNecessary:(UIView *)bodyMediaView shouldShowDownloadProgress:(BOOL)shouldShowDownloadProgress
{
    OWSAssertDebug(self.viewItem.attachmentPointer);

    switch (self.viewItem.attachmentPointer.state) {
        case TSAttachmentPointerStateFailed:
            [self addTapToRetryView:self.overlayHostView];
            return;
        case TSAttachmentPointerStateEnqueued:
        case TSAttachmentPointerStateDownloading:
            break;
    }
    switch (self.viewItem.attachmentPointer.pointerType) {
        case TSAttachmentPointerTypeRestoring:
            // TODO: Show "restoring" indicator and possibly progress.
            return;
        case TSAttachmentPointerTypeUnknown:
        case TSAttachmentPointerTypeIncoming:
            break;
    }
    if (!shouldShowDownloadProgress) {
        return;
    }
    NSString *_Nullable uniqueId = self.viewItem.attachmentPointer.uniqueId;
    if (uniqueId.length < 1) {
        OWSFailDebug(@"Missing uniqueId.");
        return;
    }
    if ([self.attachmentDownloads downloadProgressForAttachmentId:uniqueId] == nil) {
        OWSFailDebug(@"Missing download progress.");
        return;
    }

    UIView *overlayView = [UIView new];
    overlayView.backgroundColor = [self.overlayBackgroundColor colorWithAlphaComponent:0.5];
    [bodyMediaView addSubview:overlayView];
    [overlayView autoPinEdgesToSuperviewEdges];
    [overlayView setContentHuggingLow];
    [overlayView setCompressionResistanceLow];

    MediaDownloadView *downloadView =
        [[MediaDownloadView alloc] initWithAttachmentId:uniqueId radius:self.conversationStyle.maxMessageWidth * 0.1f];
    bodyMediaView.layer.opacity = 0.5f;
    [self.bubbleView addSubview:downloadView];
    [downloadView autoPinEdgesToSuperviewEdges];
    [downloadView setContentHuggingLow];
    [downloadView setCompressionResistanceLow];
}

// TODO:
- (void)addTapToRetryView:(UIView *)bodyMediaView
{
    OWSAssertDebug(self.viewItem.attachmentPointer);

    // Hide the body media view, replace with "tap to retry" indicator.

    UILabel *label = [UILabel new];
    label.text = NSLocalizedString(
        @"ATTACHMENT_DOWNLOADING_STATUS_FAILED", @"Status label when an attachment download has failed.");
    label.font = UIFont.ows_dynamicTypeBodyFont;
    label.textColor = Theme.secondaryColor;
    label.numberOfLines = 0;
    label.lineBreakMode = NSLineBreakByWordWrapping;
    label.textAlignment = NSTextAlignmentCenter;
    label.backgroundColor = self.overlayBackgroundColor;
    [bodyMediaView addSubview:label];
    [label autoPinEdgesToSuperviewMargins];
    [label setContentHuggingLow];
    [label setCompressionResistanceLow];
}

#pragma mark - Measurement

- (CGSize)contentSize
{
    OWSAssertDebug(self.conversationStyle);
    OWSAssertDebug(self.conversationStyle.maxMessageWidth > 0);

    CGFloat hMargins = self.conversationStyle.textInsetHorizontal * 2;
    const int maxTextWidth
        = (int)floor(self.conversationStyle.maxMessageWidth - (hMargins + self.contentHSpacing + self.iconSize));
    [self configureLabel];
    CGSize result = CGSizeCeil([self.label sizeThatFits:CGSizeMake(maxTextWidth, CGFLOAT_MAX)]);
    result.width += self.contentHSpacing + self.iconSize;
    result.width = MIN(result.width, self.conversationStyle.maxMessageWidth);
    result.height = MAX(result.height, self.iconSize);
    return result;
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

    self.bubbleView.bubbleColor = nil;
    [self.bubbleView clearPartnerViews];

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

- (void)handleTapGesture:(UITapGestureRecognizer *)sender
{
    OWSAssertDebug(self.delegate);

    if (sender.state != UIGestureRecognizerStateRecognized) {
        OWSLogVerbose(@"Ignoring tap on message: %@", self.viewItem.interaction.debugDescription);
        return;
    }

    // TODO:
}

- (OWSMessageGestureLocation)gestureLocationForLocation:(CGPoint)locationInMessageBubble
{
    return OWSMessageGestureLocation_Default;
}

@end

NS_ASSUME_NONNULL_END
