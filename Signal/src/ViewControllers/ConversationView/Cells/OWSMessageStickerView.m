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

    self.senderNameLabel = [OWSLabel new];
    self.senderNameContainer = [UIView new];
    self.senderNameContainer.layoutMargins = UIEdgeInsetsMake(0, 0, self.senderNameBottomSpacing, 0);
    [self.senderNameContainer addSubview:self.senderNameLabel];
    [self.senderNameLabel ows_autoPinToSuperviewMargins];

    self.footerView = [OWSMessageFooterView new];
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
    OWSAssertDebug(self.viewItem.stickerAttachment != nil);

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

    [self.stackView addArrangedSubview:bodyMediaView];

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
        self.conversationStyle.textInsetHorizontal,
        self.conversationStyle.textInsetBottom,
        self.conversationStyle.textInsetHorizontal);
    [self.stackView addArrangedSubview:textStackView];
    return YES;
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
    self.senderNameLabel.font = OWSMessageStickerView.senderNameFont;
    self.senderNameLabel.attributedText = self.viewItem.senderName;
    self.senderNameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
}

+ (UIFont *)senderNameFont
{
    return OWSMessageBubbleView.senderNameFont;
}

+ (NSDictionary *)senderNamePrimaryAttributes
{
    return OWSMessageBubbleView.senderNamePrimaryAttributes;
}

+ (NSDictionary *)senderNameSecondaryAttributes
{
    return OWSMessageBubbleView.senderNameSecondaryAttributes;
}

- (UIView *)loadStickerView
{
    OWSAssertDebug(self.viewItem.stickerAttachment);

    TSAttachmentStream *stickerAttachment = self.viewItem.stickerAttachment;
    YYAnimatedImageView *stickerView = [YYAnimatedImageView new];

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

#pragma mark - Measurement

- (CGSize)bodyMediaSize
{
    OWSAssertDebug(self.viewItem.stickerAttachment);

    const CGFloat kStickerSize = 128;
    return CGSizeMake(kStickerSize, kStickerSize);
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
    OWSAssertDebug(self.viewItem.stickerAttachment);

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

- (void)addTapGestureHandler
{
    UITapGestureRecognizer *tap =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTapGesture:)];
    [self addGestureRecognizer:tap];
}

- (void)handleTapGesture:(UITapGestureRecognizer *)sender
{
    OWSAssertDebug(self.delegate);

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

    // TODO:
}

- (void)handleMediaTapGesture:(CGPoint)locationInMessageBubble
{
    OWSAssertDebug(self.delegate);

    // TODO:
}

- (OWSMessageGestureLocation)gestureLocationForLocation:(CGPoint)locationInMessageBubble
{
    return OWSMessageGestureLocation_Media;
}

@end

NS_ASSUME_NONNULL_END
