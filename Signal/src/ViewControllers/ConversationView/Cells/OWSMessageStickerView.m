//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageStickerView.h"
#import "OWSLabel.h"
#import "OWSMessageBubbleView.h"
#import "OWSMessageFooterView.h"
#import "Signal-Swift.h"
#import "UIColor+OWS.h"
#import <SignalMessaging/UIView+OWS.h>
#import <YYImage/YYImage.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSMessageStickerView ()

@property (nonatomic) UIStackView *stackView;

@property (nonatomic) UILabel *senderNameLabel;

@property (nonatomic) UIView *senderNameContainer;

@property (nonatomic, nullable) UIView *bodyMediaView;

// Should lazy-load expensive view contents (images, etc.).
// Should do nothing if view is already loaded.
@property (nonatomic, nullable) dispatch_block_t loadCellContentBlock;
// Should unload all expensive view contents (images, etc.).
@property (nonatomic, nullable) dispatch_block_t unloadCellContentBlock;

@property (nonatomic, nullable) NSMutableArray<NSLayoutConstraint *> *viewConstraints;

@property (nonatomic) OWSMessageFooterView *footerView;

@end

#pragma mark -

@implementation OWSMessageStickerView

#pragma mark - Dependencies

- (OWSAttachmentDownloads *)attachmentDownloads
{
    return SSKEnvironment.shared.attachmentDownloads;
}

- (SDSDatabaseStorage *)databaseStorage
{
    return SDSDatabaseStorage.shared;
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
    OWSAssertDebug(!self.stackView);

    _viewConstraints = [NSMutableArray new];

    self.layoutMargins = UIEdgeInsetsZero;
    self.userInteractionEnabled = YES;

    self.stackView = [UIStackView new];
    self.stackView.axis = UILayoutConstraintAxisVertical;
    self.stackView.alignment = UIStackViewAlignmentFill;
    // NOTE: we don't use bottom margin or spacing.
    CGFloat margin = OWSMessageStickerView.marginAndSpacing;
    self.stackView.layoutMargins = UIEdgeInsetsMake(margin, margin, 0, margin);
    self.stackView.layoutMarginsRelativeArrangement = YES;

    self.senderNameLabel = [OWSLabel new];
    self.senderNameContainer = [UIView new];
    self.senderNameContainer.layoutMargins = UIEdgeInsetsMake(0, 0, self.senderNameBottomSpacing, 0);
    [self.senderNameContainer addSubview:self.senderNameLabel];
    [self.senderNameLabel ows_autoPinToSuperviewMargins];

    self.footerView = [OWSMessageFooterView new];
}

+ (CGFloat)marginAndSpacing
{
    return 8;
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

#pragma mark - Load

- (void)configureViews
{
    OWSAssertDebug(self.conversationStyle);
    OWSAssertDebug(self.viewItem);
    OWSAssertDebug(self.viewItem.interaction);
    OWSAssertDebug([self.viewItem.interaction isKindOfClass:[TSMessage class]]);
    OWSAssertDebug(self.viewItem.stickerAttachment != nil || self.viewItem.isFailedSticker);

    CGSize bodyMediaSize = [self bodyMediaSize];

    [self addSubview:self.stackView];
    [self.viewConstraints addObjectsFromArray:[self.stackView autoPinEdgesToSuperviewEdges]];

    if (self.shouldShowSenderName) {
        [self configureSenderNameLabel];
        [self insertAnyTextViewsIntoStackView:@[
            self.senderNameContainer,
        ]];
    }

    UIView *bodyMediaView = [self loadStickerView];
    OWSAssertDebug(self.loadCellContentBlock);
    OWSAssertDebug(self.unloadCellContentBlock);
    bodyMediaView.clipsToBounds = YES;
    self.bodyMediaView = bodyMediaView;
    bodyMediaView.userInteractionEnabled = NO;

    // Wrap the sticker view - otherwise, a long header or footer
    // will horizontally stretch the sticker content.
    UIStackView *bodyViewWrapper = [[UIStackView alloc] initWithArrangedSubviews:@[ bodyMediaView ]];
    bodyViewWrapper.axis = UILayoutConstraintAxisVertical;
    bodyViewWrapper.alignment = UIStackViewAlignmentLeading;

    [self.stackView addArrangedSubview:bodyViewWrapper];

    [self.footerView configureWithConversationViewItem:self.viewItem
                                     conversationStyle:self.conversationStyle
                                            isIncoming:self.isIncoming
                                     isOverlayingMedia:NO
                                       isOutsideBubble:YES];
    [self insertAnyTextViewsIntoStackView:@[
        self.footerView,
    ]];

    CGSize bubbleSize = [self measureSize];
    [self.viewConstraints addObjectsFromArray:@[
        [self autoSetDimension:ALDimensionWidth toSize:bubbleSize.width],
        [bodyMediaView autoSetDimension:ALDimensionWidth toSize:bodyMediaSize.width],
        [bodyMediaView autoSetDimension:ALDimensionHeight toSize:bodyMediaSize.height],
        [bodyViewWrapper autoSetDimension:ALDimensionHeight toSize:bodyMediaSize.height],
    ]];
}

- (CGFloat)senderNameBottomSpacing
{
    return 2.f;
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
        OWSMessageStickerView.textInsetHorizontal,
        self.conversationStyle.textInsetBottom,
        OWSMessageStickerView.textInsetHorizontal);
    [self.stackView addArrangedSubview:textStackView];
    return YES;
}

+ (CGFloat)textInsetHorizontal
{
    return 0.f;
}

- (CGFloat)textViewVSpacing
{
    return 2.f;
}

#pragma mark - Load / Unload

- (void)loadContent
{
    if (self.loadCellContentBlock) {
        self.loadCellContentBlock();
    }
}

- (void)unloadContent
{
    if (self.unloadCellContentBlock) {
        self.unloadCellContentBlock();
    }
}

#pragma mark - Subviews

- (BOOL)shouldShowSenderName
{
    return self.viewItem.senderName.length > 0;
}

- (void)configureSenderNameLabel
{
    OWSAssertDebug(self.senderNameLabel);
    OWSAssertDebug(self.shouldShowSenderName);

    self.senderNameLabel.textColor = self.bodyTextColor;
    self.senderNameLabel.font = OWSMessageView.senderNameFont;
    self.senderNameLabel.attributedText = self.viewItem.senderName;
    self.senderNameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
}

- (UIView *)loadStickerView
{
    if (self.viewItem.isFailedSticker) {
        return [self loadFailedStickerView];
    }

    OWSAssertDebug(self.viewItem.stickerAttachment != nil);

    TSAttachmentStream *stickerAttachment = self.viewItem.stickerAttachment;
    YYAnimatedImageView *stickerView = [YYAnimatedImageView new];

    stickerView.accessibilityLabel =
        [OWSMessageView accessibilityLabelWithDescription:NSLocalizedString(@"ACCESSIBILITY_LABEL_STICKER",
                                                              @"Accessibility label for stickers.")
                                               authorName:self.viewItem.accessibilityAuthorName];

    self.loadCellContentBlock = ^{
        NSString *_Nullable filePath = stickerAttachment.originalFilePath;
        OWSCAssertDebug(filePath);
        YYImage *_Nullable image = [[YYImage alloc] initWithContentsOfFile:filePath];
        OWSCAssertDebug(image);
        stickerView.image = image;
    };
    self.unloadCellContentBlock = ^{
        stickerView.image = nil;
    };

    return stickerView;
}

- (UIView *)loadFailedStickerView
{
    OWSAssertDebug(self.viewItem.isFailedSticker);

    UIView *roundedRectView = [UIView new];
    roundedRectView.backgroundColor = UIColor.ows_gray45Color;
    roundedRectView.layer.cornerRadius = 8;

    UIView *pillboxView = [[OWSLayerView alloc] initWithFrame:CGRectZero
                                               layoutCallback:^(UIView *view) {
                                                   view.layer.cornerRadius = MIN(view.width, view.height) * 0.5f;
                                               }];
    pillboxView.backgroundColor = Theme.offBackgroundColor;
    [roundedRectView addSubview:pillboxView];
    [pillboxView autoCenterInSuperview];

    UIImageView *iconView =
        [UIImageView withTemplateImageName:@"download-filled-2-24" tintColor:Theme.offBackgroundColor];
    UIView *circleView = [UIView new];
    circleView.backgroundColor = UIColor.ows_gray45Color;
    circleView.layer.cornerRadius = 12.f;
    [circleView addSubview:iconView];
    [iconView autoPinEdgesToSuperviewEdges];

    UILabel *label = [UILabel new];
    label.text = NSLocalizedString(@"STICKERS_FAILED_DOWNLOAD", @"Label for a sticker that failed to download.");
    label.font = UIFont.ows_dynamicTypeCaption1Font.ows_mediumWeight;
    label.textColor = UIColor.ows_gray45Color;

    UIStackView *stackView = [[UIStackView alloc] initWithArrangedSubviews:@[
        circleView,
        label,
    ]];
    stackView.axis = UILayoutConstraintAxisHorizontal;
    stackView.spacing = 4;
    stackView.alignment = UIStackViewAlignmentCenter;
    stackView.layoutMargins = UIEdgeInsetsMake(4, 4, 4, 4);
    stackView.layoutMarginsRelativeArrangement = YES;
    [pillboxView addSubview:stackView];
    [stackView autoPinEdgesToSuperviewEdges];

    CGFloat minMargin = 10;
    CGFloat maxWidth = self.stickerSize
        - (minMargin * 2 + stackView.spacing + stackView.layoutMargins.left + stackView.layoutMargins.right);
    [stackView autoSetDimension:ALDimensionWidth toSize:maxWidth relation:NSLayoutRelationLessThanOrEqual];

    self.loadCellContentBlock = ^{
        // Do nothing.
    };
    self.unloadCellContentBlock = ^{
        // Do nothing.
    };

    return roundedRectView;
}

#pragma mark - Measurement

- (CGFloat)stickerSize
{
    return 128;
}

- (CGSize)bodyMediaSize
{
    OWSAssertDebug(self.viewItem.stickerAttachment != nil || self.viewItem.isFailedSticker);

    return CGSizeMake(self.stickerSize, self.stickerSize);
}

- (nullable NSValue *)senderNameSize
{
    OWSAssertDebug(self.conversationStyle);
    OWSAssertDebug(self.conversationStyle.maxMessageWidth > 0);

    if (!self.shouldShowSenderName) {
        return nil;
    }

    CGFloat hMargins = OWSMessageStickerView.textInsetHorizontal * 2;
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
    OWSAssertDebug(self.viewItem.stickerAttachment != nil || self.viewItem.isFailedSticker);

    CGSize cellSize = CGSizeZero;

    NSMutableArray<NSValue *> *textViewSizes = [NSMutableArray new];

    NSValue *_Nullable senderNameSize = [self senderNameSize];
    if (senderNameSize) {
        [textViewSizes addObject:senderNameSize];
    }

    CGSize bodyMediaSize = [self bodyMediaSize];
    cellSize.width = MAX(cellSize.width, bodyMediaSize.width);
    cellSize.height += bodyMediaSize.height;

    if (textViewSizes.count > 0) {
        CGSize groupSize = [self sizeForTextViewGroup:textViewSizes];
        cellSize.width = MAX(cellSize.width, groupSize.width);
        cellSize.height += groupSize.height;
        [textViewSizes removeAllObjects];
    }

    CGSize footerSize = [self.footerView measureWithConversationViewItem:self.viewItem];
    footerSize.width = MIN(footerSize.width, self.conversationStyle.maxMessageWidth);
    [textViewSizes addObject:[NSValue valueWithCGSize:footerSize]];

    if (textViewSizes.count > 0) {
        CGSize groupSize = [self sizeForTextViewGroup:textViewSizes];
        cellSize.width = MAX(cellSize.width, groupSize.width);
        cellSize.height += groupSize.height;
    }

    OWSAssertDebug(cellSize.width > 0 && cellSize.height > 0);

    CGFloat margin = OWSMessageStickerView.marginAndSpacing;
    cellSize.width += margin * 2;
    cellSize.height += margin;

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
    result.width += OWSMessageStickerView.textInsetHorizontal * 2;

    return result;
}

#pragma mark -

- (UIColor *)bodyTextColor
{
    OWSAssertDebug([self.viewItem.interaction isKindOfClass:[TSMessage class]]);

    TSMessage *message = (TSMessage *)self.viewItem.interaction;
    return [self.conversationStyle bubbleTextColorWithMessage:message];
}

- (void)prepareForReuse
{
    [NSLayoutConstraint deactivateConstraints:self.viewConstraints];
    self.viewConstraints = [NSMutableArray new];

    self.delegate = nil;

    for (UIView *subview in self.subviews) {
        [subview removeFromSuperview];
    }

    if (self.unloadCellContentBlock) {
        self.unloadCellContentBlock();
    }
    self.loadCellContentBlock = nil;
    self.unloadCellContentBlock = nil;

    for (UIView *subview in self.bodyMediaView.subviews) {
        [subview removeFromSuperview];
    }
    [self.bodyMediaView removeFromSuperview];
    self.bodyMediaView = nil;

    [self.footerView removeFromSuperview];
    [self.footerView prepareForReuse];

    for (UIView *subview in self.stackView.subviews) {
        [subview removeFromSuperview];
    }
}

#pragma mark - Gestures

- (void)addGestureHandlers
{
    UITapGestureRecognizer *tap =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTapGesture:)];
    [self addGestureRecognizer:tap];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self
                                                                          action:@selector(handlePanGesture:)];
    [self addGestureRecognizer:pan];
    [tap requireGestureRecognizerToFail:pan];
}

- (BOOL)willHandleTapGesture:(UITapGestureRecognizer *)sender
{
    return YES;
}

- (void)handleTapGesture:(UITapGestureRecognizer *)sender
{
    if (sender.state != UIGestureRecognizerStateRecognized) {
        OWSLogVerbose(@"Ignoring tap on message: %@", self.viewItem.interaction.debugDescription);
        return;
    }

    if (self.viewItem.interaction.interactionType == OWSInteractionType_OutgoingMessage) {
        TSOutgoingMessage *outgoingMessage = (TSOutgoingMessage *)self.viewItem.interaction;
        if (outgoingMessage.messageState == TSOutgoingMessageStateFailed) {
            return;
        } else if (outgoingMessage.messageState == TSOutgoingMessageStateSending) {
            // Ignore taps on outgoing messages being sent.
            return;
        }
    }

    if (self.viewItem.isFailedSticker) {
        TSMessage *message = (TSMessage *)self.viewItem.interaction;
        [self.databaseStorage uiReadWithBlock:^(SDSAnyReadTransaction *transaction) {
            [self.attachmentDownloads
                downloadAllAttachmentsForMessage:message
                                     transaction:transaction
                                         success:^(NSArray<TSAttachmentStream *> *_Nonnull attachmentStreams) {
                                             // Do nothing.
                                         }
                                         failure:^(NSError *_Nonnull error){
                                             // Do nothing.
                                         }];
        }];
        return;
    }

    StickerPackInfo *_Nullable stickerPackInfo = self.viewItem.stickerInfo.packInfo;
    if (!stickerPackInfo) {
        OWSFailDebug(@"Missing stickerPackInfo.");
        return;
    }

    [self.delegate showStickerPack:stickerPackInfo];
}

- (BOOL)handlePanGesture:(UIPanGestureRecognizer *)sender
{
    return NO;
}

- (void)handleMediaTapGesture:(CGPoint)locationInMessageBubble
{
    OWSFailDebug(@"This method should never be called.");
}

- (OWSMessageGestureLocation)gestureLocationForLocation:(CGPoint)locationInMessageBubble
{
    return OWSMessageGestureLocation_Sticker;
}

@end

NS_ASSUME_NONNULL_END
