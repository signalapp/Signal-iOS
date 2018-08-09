//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageBubbleView.h"
#import "AttachmentUploadView.h"
#import "ConversationViewItem.h"
#import "OWSAudioMessageView.h"
#import "OWSBubbleShapeView.h"
#import "OWSBubbleView.h"
#import "OWSContactShareButtonsView.h"
#import "OWSContactShareView.h"
#import "OWSGenericAttachmentView.h"
#import "OWSLabel.h"
#import "OWSMessageFooterView.h"
#import "OWSMessageTextView.h"
#import "OWSQuotedMessageView.h"
#import "Signal-Swift.h"
#import "UIColor+OWS.h"
#import <SignalMessaging/UIView+OWS.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSMessageBubbleView () <OWSQuotedMessageViewDelegate, OWSContactShareButtonsViewDelegate>

@property (nonatomic) OWSBubbleView *bubbleView;

@property (nonatomic) UIStackView *stackView;

@property (nonatomic) UILabel *senderNameLabel;

@property (nonatomic) UIView *senderNameContainer;

@property (nonatomic) OWSMessageTextView *bodyTextView;

@property (nonatomic, nullable) UIView *quotedMessageView;

@property (nonatomic, nullable) UIView *bodyMediaView;

// Should lazy-load expensive view contents (images, etc.).
// Should do nothing if view is already loaded.
@property (nonatomic, nullable) dispatch_block_t loadCellContentBlock;
// Should unload all expensive view contents (images, etc.).
@property (nonatomic, nullable) dispatch_block_t unloadCellContentBlock;

@property (nonatomic, nullable) NSMutableArray<NSLayoutConstraint *> *viewConstraints;

@property (nonatomic) OWSMessageFooterView *footerView;

@property (nonatomic, nullable) OWSContactShareButtonsView *contactShareButtonsView;

@end

#pragma mark -

@implementation OWSMessageBubbleView

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
    OWSAssert(!self.bodyTextView);

    _viewConstraints = [NSMutableArray new];

    self.layoutMargins = UIEdgeInsetsZero;
    self.userInteractionEnabled = YES;

    self.bubbleView = [OWSBubbleView new];
    self.bubbleView.layoutMargins = UIEdgeInsetsZero;
    [self addSubview:self.bubbleView];
    [self.bubbleView autoPinEdgesToSuperviewEdges];

    self.stackView = [UIStackView new];
    self.stackView.axis = UILayoutConstraintAxisVertical;

    self.senderNameLabel = [OWSLabel new];
    self.senderNameContainer = [UIView new];
    self.senderNameContainer.layoutMargins = UIEdgeInsetsMake(0, 0, self.senderNameBottomSpacing, 0);
    [self.senderNameContainer addSubview:self.senderNameLabel];
    [self.senderNameLabel ows_autoPinToSuperviewMargins];

    self.bodyTextView = [self newTextView];
    // Setting dataDetectorTypes is expensive.  Do it just once.
    self.bodyTextView.dataDetectorTypes
        = (UIDataDetectorTypeLink | UIDataDetectorTypeAddress | UIDataDetectorTypeCalendarEvent);
    self.bodyTextView.hidden = YES;

    self.footerView = [OWSMessageFooterView new];
}

- (OWSMessageTextView *)newTextView
{
    OWSMessageTextView *textView = [OWSMessageTextView new];
    textView.backgroundColor = [UIColor clearColor];
    textView.opaque = NO;
    textView.editable = NO;
    textView.selectable = YES;
    textView.textContainerInset = UIEdgeInsetsZero;
    textView.contentInset = UIEdgeInsetsZero;
    textView.textContainer.lineFragmentPadding = 0;
    textView.scrollEnabled = NO;
    return textView;
}

- (UIFont *)textMessageFont
{
    OWSAssert(DisplayableText.kMaxJumbomojiCount == 5);

    CGFloat basePointSize = UIFont.ows_dynamicTypeBodyFont.pointSize;
    switch (self.displayableBodyText.jumbomojiCount) {
        case 0:
            break;
        case 1:
            return [UIFont ows_regularFontWithSize:basePointSize + 18.f];
        case 2:
            return [UIFont ows_regularFontWithSize:basePointSize + 12.f];
        case 3:
        case 4:
        case 5:
            return [UIFont ows_regularFontWithSize:basePointSize + 6.f];
        default:
            OWSFail(@"%@ Unexpected jumbomoji count: %zd", self.logTag, self.displayableBodyText.jumbomojiCount);
            break;
    }

    return UIFont.ows_dynamicTypeBodyFont;
}

#pragma mark - Convenience Accessors

- (OWSMessageCellType)cellType
{
    return self.viewItem.messageCellType;
}

- (BOOL)hasBodyText
{
    // This should always be valid for the appropriate cell types.
    OWSAssert(self.viewItem);

    return self.viewItem.hasBodyText;
}

- (nullable DisplayableText *)displayableBodyText
{
    // This should always be valid for the appropriate cell types.
    OWSAssert(self.viewItem.displayableBodyText);

    return self.viewItem.displayableBodyText;
}

- (nullable TSAttachmentStream *)attachmentStream
{
    // This should always be valid for the appropriate cell types.
    OWSAssert(self.viewItem.attachmentStream);

    return self.viewItem.attachmentStream;
}

- (nullable TSAttachmentPointer *)attachmentPointer
{
    // This should always be valid for the appropriate cell types.
    OWSAssert(self.viewItem.attachmentPointer);

    return self.viewItem.attachmentPointer;
}

- (TSMessage *)message
{
    OWSAssert([self.viewItem.interaction isKindOfClass:[TSMessage class]]);

    return (TSMessage *)self.viewItem.interaction;
}

- (CGSize)mediaSize
{
    // This should always be valid for the appropriate cell types.
    OWSAssert(self.viewItem.mediaSize.width > 0 && self.viewItem.mediaSize.height > 0);

    return self.viewItem.mediaSize;
}

- (BOOL)isQuotedReply
{
    // This should always be valid for the appropriate cell types.
    OWSAssert(self.viewItem);

    return self.viewItem.isQuotedReply;
}

- (BOOL)hasQuotedText
{
    // This should always be valid for the appropriate cell types.
    OWSAssert(self.viewItem);

    return self.viewItem.hasQuotedText;
}

- (BOOL)isIncoming
{
    return self.viewItem.interaction.interactionType == OWSInteractionType_IncomingMessage;
}

- (BOOL)isOutgoing
{
    return self.viewItem.interaction.interactionType == OWSInteractionType_OutgoingMessage;
}

#pragma mark -

- (BOOL)hasBodyTextContent
{
    switch (self.cellType) {
        case OWSMessageCellType_Unknown:
        case OWSMessageCellType_TextMessage:
        case OWSMessageCellType_OversizeTextMessage:
            return YES;
        case OWSMessageCellType_GenericAttachment:
        case OWSMessageCellType_DownloadingAttachment:
        case OWSMessageCellType_StillImage:
        case OWSMessageCellType_AnimatedImage:
        case OWSMessageCellType_Audio:
        case OWSMessageCellType_Video:
            // Is there a caption?
            return self.hasBodyText;
        case OWSMessageCellType_ContactShare:
            return NO;
    }
}

#pragma mark - Load

- (void)configureViews
{
    OWSAssert(self.conversationStyle);
    OWSAssert(self.viewItem);
    OWSAssert(self.viewItem.interaction);
    OWSAssert([self.viewItem.interaction isKindOfClass:[TSMessage class]]);

    NSValue *_Nullable quotedMessageSize = [self quotedMessageSize];
    NSValue *_Nullable bodyMediaSize = [self bodyMediaSize];
    NSValue *_Nullable bodyTextSize = [self bodyTextSize];

    [self.bubbleView addSubview:self.stackView];
    [self.viewConstraints addObjectsFromArray:[self.stackView autoPinEdgesToSuperviewEdges]];
    NSMutableArray<UIView *> *textViews = [NSMutableArray new];

    if (self.shouldShowSenderName) {
        [self configureSenderNameLabel];
        [textViews addObject:self.senderNameContainer];
    }

    if (self.isQuotedReply) {
        // Flush any pending "text" subviews.
        BOOL isFirstSubview = ![self insertAnyTextViewsIntoStackView:textViews];
        [textViews removeAllObjects];

        if (isFirstSubview) {
            UIView *spacerView = [UIView containerView];
            [spacerView autoSetDimension:ALDimensionHeight toSize:self.quotedReplyTopMargin];
            [spacerView setCompressionResistanceHigh];
            [self.stackView addArrangedSubview:spacerView];
        }

        DisplayableText *_Nullable displayableQuotedText
            = (self.viewItem.hasQuotedText ? self.viewItem.displayableQuotedText : nil);

        OWSQuotedMessageView *quotedMessageView =
            [OWSQuotedMessageView quotedMessageViewForConversation:self.viewItem.quotedReply
                                             displayableQuotedText:displayableQuotedText
                                                 conversationStyle:self.conversationStyle
                                                        isOutgoing:self.isOutgoing
                                                      sharpCorners:self.sharpCornersForQuotedMessage];
        quotedMessageView.delegate = self;

        self.quotedMessageView = quotedMessageView;
        [quotedMessageView createContents];
        [self.stackView addArrangedSubview:quotedMessageView];
        OWSAssert(quotedMessageSize);
        [self.viewConstraints addObject:[quotedMessageView autoSetDimension:ALDimensionHeight
                                                                     toSize:quotedMessageSize.CGSizeValue.height]];
    }

    UIView *_Nullable bodyMediaView = nil;
    switch (self.cellType) {
        case OWSMessageCellType_Unknown:
        case OWSMessageCellType_TextMessage:
        case OWSMessageCellType_OversizeTextMessage:
            break;
        case OWSMessageCellType_StillImage:
            OWSAssert(self.viewItem.attachmentStream);
            bodyMediaView = [self loadViewForStillImage];
            break;
        case OWSMessageCellType_AnimatedImage:
            OWSAssert(self.viewItem.attachmentStream);
            bodyMediaView = [self loadViewForAnimatedImage];
            break;
        case OWSMessageCellType_Video:
            OWSAssert(self.viewItem.attachmentStream);
            bodyMediaView = [self loadViewForVideo];
            break;
        case OWSMessageCellType_Audio:
            OWSAssert(self.viewItem.attachmentStream);
            bodyMediaView = [self loadViewForAudio];
            break;
        case OWSMessageCellType_GenericAttachment:
            bodyMediaView = [self loadViewForGenericAttachment];
            break;
        case OWSMessageCellType_DownloadingAttachment:
            bodyMediaView = [self loadViewForDownloadingAttachment];
            break;
        case OWSMessageCellType_ContactShare:
            bodyMediaView = [self loadViewForContactShare];
            break;
    }

    if (bodyMediaView) {
        OWSAssert(self.loadCellContentBlock);
        OWSAssert(self.unloadCellContentBlock);

        bodyMediaView.clipsToBounds = YES;

        self.bodyMediaView = bodyMediaView;
        bodyMediaView.userInteractionEnabled = NO;
        if (self.hasFullWidthMediaView) {
            // Flush any pending "text" subviews.
            [self insertAnyTextViewsIntoStackView:textViews];
            [textViews removeAllObjects];

            if (self.isQuotedReply) {
                UIView *spacerView = [UIView containerView];
                [spacerView autoSetDimension:ALDimensionHeight toSize:self.bodyMediaQuotedReplyVSpacing];
                [spacerView setCompressionResistanceHigh];
                [self.stackView addArrangedSubview:spacerView];
            }

            if (self.hasBodyMediaWithThumbnail) {
                [self.stackView addArrangedSubview:bodyMediaView];

                OWSBubbleShapeView *strokeView = [OWSBubbleShapeView bubbleDrawView];
                strokeView.strokeThickness = CGHairlineWidth();
                strokeView.strokeColor = (Theme.isDarkThemeEnabled ? [UIColor colorWithWhite:1.f alpha:0.2f]
                                                                   : [UIColor colorWithWhite:0.f alpha:0.2f]);
                [bodyMediaView addSubview:strokeView];
                [self.bubbleView addPartnerView:strokeView];
                [self.viewConstraints addObjectsFromArray:[strokeView ows_autoPinToSuperviewEdges]];
            } else {
                OWSAssert(self.cellType == OWSMessageCellType_ContactShare);

                if (self.contactShareHasSpacerTop) {
                    UIView *spacerView = [UIView containerView];
                    [spacerView autoSetDimension:ALDimensionHeight toSize:self.contactShareVSpacing];
                    [spacerView setCompressionResistanceHigh];
                    [self.stackView addArrangedSubview:spacerView];
                }

                [self.stackView addArrangedSubview:bodyMediaView];

                if (self.contactShareHasSpacerBottom) {
                    UIView *spacerView = [UIView containerView];
                    [spacerView autoSetDimension:ALDimensionHeight toSize:self.contactShareVSpacing];
                    [spacerView setCompressionResistanceHigh];
                    [self.stackView addArrangedSubview:spacerView];
                }
            }
        } else {
            [textViews addObject:bodyMediaView];
        }
    }

    // We render malformed messages as "empty text" messages,
    // so create a text view if there is no body media view.
    if (self.hasBodyText || !bodyMediaView) {
        [self configureBodyTextView];
        [textViews addObject:self.bodyTextView];

        OWSAssert(bodyTextSize);
        [self.viewConstraints addObjectsFromArray:@[
            [self.bodyTextView autoSetDimension:ALDimensionHeight toSize:bodyTextSize.CGSizeValue.height],
        ]];

        UIView *_Nullable tapForMoreLabel = [self createTapForMoreLabelIfNecessary];
        if (tapForMoreLabel) {
            [textViews addObject:tapForMoreLabel];
            [self.viewConstraints addObjectsFromArray:@[
                [tapForMoreLabel autoSetDimension:ALDimensionHeight toSize:self.tapForMoreHeight],
            ]];
        }
    }

    BOOL shouldFooterOverlayMedia = (self.canFooterOverlayMedia && bodyMediaView && !self.hasBodyText);
    if (self.viewItem.shouldHideFooter) {
        // Do nothing.
    } else if (shouldFooterOverlayMedia) {
        OWSAssert(bodyMediaView);

        CGFloat maxGradientHeight = 40.f;
        CAGradientLayer *gradientLayer = [CAGradientLayer new];
        gradientLayer.colors = @[
            (id)[UIColor colorWithWhite:0.f alpha:0.f].CGColor,
            (id)[UIColor colorWithWhite:0.f alpha:0.4f].CGColor,
        ];
        OWSLayerView *gradientView =
            [[OWSLayerView alloc] initWithFrame:CGRectZero
                                 layoutCallback:^(UIView *layerView) {
                                     CGRect layerFrame = layerView.bounds;
                                     layerFrame.size.height = MIN(maxGradientHeight, layerView.height);
                                     layerFrame.origin.y = layerView.height - layerFrame.size.height;
                                     gradientLayer.frame = layerFrame;
                                 }];
        [gradientView.layer addSublayer:gradientLayer];
        [bodyMediaView addSubview:gradientView];
        [self.viewConstraints addObjectsFromArray:[gradientView ows_autoPinToSuperviewEdges]];

        [self.footerView configureWithConversationViewItem:self.viewItem
                                         isOverlayingMedia:YES
                                         conversationStyle:self.conversationStyle
                                                isIncoming:self.isIncoming];
        [bodyMediaView addSubview:self.footerView];

        bodyMediaView.layoutMargins = UIEdgeInsetsZero;
        [self.viewConstraints addObjectsFromArray:@[
            [self.footerView autoPinLeadingToSuperviewMarginWithInset:self.conversationStyle.textInsetHorizontal],
            [self.footerView autoPinTrailingToSuperviewMarginWithInset:self.conversationStyle.textInsetHorizontal],
            [self.footerView autoPinEdgeToSuperviewMargin:ALEdgeTop relation:NSLayoutRelationGreaterThanOrEqual],
            [self.footerView autoPinBottomToSuperviewMarginWithInset:self.conversationStyle.textInsetBottom],
        ]];
    } else {
        [self.footerView configureWithConversationViewItem:self.viewItem
                                         isOverlayingMedia:NO
                                         conversationStyle:self.conversationStyle
                                                isIncoming:self.isIncoming];
        [textViews addObject:self.footerView];
    }

    [self insertAnyTextViewsIntoStackView:textViews];

    CGSize bubbleSize = [self measureSize];
    [self.viewConstraints addObjectsFromArray:@[
        [self autoSetDimension:ALDimensionWidth toSize:bubbleSize.width],
    ]];
    if (bodyMediaView) {
        OWSAssert(bodyMediaSize);
        [self.viewConstraints
            addObject:[bodyMediaView autoSetDimension:ALDimensionHeight toSize:bodyMediaSize.CGSizeValue.height]];
    }

    [self insertContactShareButtonsIfNecessary];

    [self updateBubbleColor];

    [self configureBubbleRounding];
}

- (void)insertContactShareButtonsIfNecessary
{
    if (self.cellType != OWSMessageCellType_ContactShare) {
        return;
    }

    if (![OWSContactShareButtonsView hasAnyButton:self.viewItem.contactShare]) {
        return;
    }

    OWSAssert(self.viewItem.contactShare);

    OWSContactShareButtonsView *buttonsView =
        [[OWSContactShareButtonsView alloc] initWithContactShare:self.viewItem.contactShare delegate:self];

    NSValue *_Nullable actionButtonsSize = [self actionButtonsSize];
    OWSAssert(actionButtonsSize);
    [self.viewConstraints addObjectsFromArray:@[
        [buttonsView autoSetDimension:ALDimensionHeight toSize:actionButtonsSize.CGSizeValue.height],
    ]];

    // The "contact share" view casts a shadow "downward" onto adjacent views,
    // so we use a "proxy" view to take its place within the v-stack
    // view and then insert the "contact share" view above its proxy so that
    // it floats above the other content of the bubble view.

    UIView *proxyView = [UIView new];
    [self.stackView addArrangedSubview:proxyView];

    OWSBubbleShapeView *shadowView = [OWSBubbleShapeView bubbleShadowView];
    OWSBubbleShapeView *clipView = [OWSBubbleShapeView bubbleClipView];

    [self addSubview:shadowView];
    [self addSubview:clipView];

    [self.viewConstraints addObjectsFromArray:[shadowView autoPinToEdgesOfView:proxyView]];
    [self.viewConstraints addObjectsFromArray:[clipView autoPinToEdgesOfView:proxyView]];

    [clipView addSubview:buttonsView];
    [self.viewConstraints addObjectsFromArray:[buttonsView ows_autoPinToSuperviewEdges]];

    [self.bubbleView addPartnerView:shadowView];
    [self.bubbleView addPartnerView:clipView];

    // Prevent the layer from animating changes.
    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    OWSAssert(buttonsView.backgroundColor);
    shadowView.fillColor = buttonsView.backgroundColor;
    shadowView.layer.shadowColor = Theme.boldColor.CGColor;
    shadowView.layer.shadowOpacity = 0.12f;
    shadowView.layer.shadowOffset = CGSizeZero;
    shadowView.layer.shadowRadius = 1.f;

    [CATransaction commit];
}

- (BOOL)contactShareHasSpacerTop
{
    return (self.cellType == OWSMessageCellType_ContactShare && (self.isQuotedReply || !self.shouldShowSenderName));
}

- (BOOL)contactShareHasSpacerBottom
{
    return (self.cellType == OWSMessageCellType_ContactShare && !self.hasBottomFooter);
}

- (CGFloat)contactShareVSpacing
{
    return 12.f;
}

- (CGFloat)senderNameBottomSpacing
{
    return 2.f;
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
    BOOL hasOnlyBodyMediaView = (self.hasBodyMediaWithThumbnail && self.stackView.subviews.count == 1);
    if (!hasOnlyBodyMediaView) {
        self.bubbleView.bubbleColor = self.bubbleColor;
    } else {
        // Media-only messages should have no background color; they will fill the bubble's bounds
        // and we don't want artifacts at the edges.
        self.bubbleView.bubbleColor = nil;
    }
}

- (UIColor *)bubbleColor
{
    OWSAssert([self.viewItem.interaction isKindOfClass:[TSMessage class]]);

    TSMessage *message = (TSMessage *)self.viewItem.interaction;
    return [self.conversationStyle bubbleColorWithMessage:message];
}

- (BOOL)hasBodyMediaWithThumbnail
{
    switch (self.cellType) {
        case OWSMessageCellType_Unknown:
        case OWSMessageCellType_TextMessage:
        case OWSMessageCellType_OversizeTextMessage:
            return NO;
        case OWSMessageCellType_StillImage:
        case OWSMessageCellType_AnimatedImage:
        case OWSMessageCellType_Video:
            return YES;
        case OWSMessageCellType_Audio:
        case OWSMessageCellType_GenericAttachment:
        case OWSMessageCellType_DownloadingAttachment:
        case OWSMessageCellType_ContactShare:
            return NO;
    }
}

- (BOOL)hasFullWidthMediaView
{
    return (self.hasBodyMediaWithThumbnail || self.cellType == OWSMessageCellType_ContactShare);
}

- (BOOL)canFooterOverlayMedia
{
    return self.hasBodyMediaWithThumbnail;
}

- (BOOL)hasBottomFooter
{
    BOOL shouldFooterOverlayMedia = (self.canFooterOverlayMedia && !self.hasBodyText);
    return !self.viewItem.shouldHideFooter && !shouldFooterOverlayMedia;
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

// We now eagerly create our view hierarchy (to do this exactly once per cell usage)
// but lazy-load any expensive media (photo, gif, etc.) used in those views. Note that
// this lazy-load can fail, in which case we modify the view hierarchy to use an "error"
// state. The didCellMediaFailToLoad reflects media load fails.
- (nullable id)tryToLoadCellMedia:(nullable id (^)(void))loadCellMediaBlock
                        mediaView:(UIView *)mediaView
                         cacheKey:(NSString *)cacheKey
                  shouldSkipCache:(BOOL)shouldSkipCache
{
    OWSAssert(self.attachmentStream);
    OWSAssert(mediaView);
    OWSAssert(cacheKey);
    OWSAssert(self.cellMediaCache);

    if (self.viewItem.didCellMediaFailToLoad) {
        return nil;
    }

    id _Nullable cellMedia = [self.cellMediaCache objectForKey:cacheKey];
    if (cellMedia) {
        DDLogVerbose(@"%@ cell media cache hit", self.logTag);
        return cellMedia;
    }
    cellMedia = loadCellMediaBlock();
    if (cellMedia) {
        DDLogVerbose(@"%@ cell media cache miss", self.logTag);
        if (!shouldSkipCache) {
            [self.cellMediaCache setObject:cellMedia forKey:cacheKey];
        }
    } else {
        DDLogError(@"%@ Failed to load cell media: %@", [self logTag], [self.attachmentStream mediaURL]);
        self.viewItem.didCellMediaFailToLoad = YES;
        [self showAttachmentErrorViewWithMediaView:mediaView];
    }
    return cellMedia;
}

- (CGFloat)textViewVSpacing
{
    return 2.f;
}

- (CGFloat)bodyMediaQuotedReplyVSpacing
{
    return 6.f;
}

- (CGFloat)quotedReplyTopMargin
{
    return 6.f;
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

- (void)configureBodyTextView
{
    OWSAssert(self.hasBodyText);

    BOOL shouldIgnoreEvents = NO;
    if (self.viewItem.interaction.interactionType == OWSInteractionType_OutgoingMessage) {
        // Ignore taps on links in outgoing messages that haven't been sent yet, as
        // this interferes with "tap to retry".
        TSOutgoingMessage *outgoingMessage = (TSOutgoingMessage *)self.viewItem.interaction;
        shouldIgnoreEvents = outgoingMessage.messageState != TSOutgoingMessageStateSent;
    }
    [self.class loadForTextDisplay:self.bodyTextView
                              text:self.displayableBodyText.displayText
                         textColor:self.bodyTextColor
                              font:self.textMessageFont
                shouldIgnoreEvents:shouldIgnoreEvents];
}

+ (void)loadForTextDisplay:(OWSMessageTextView *)textView
                      text:(NSString *)text
                 textColor:(UIColor *)textColor
                      font:(UIFont *)font
        shouldIgnoreEvents:(BOOL)shouldIgnoreEvents
{
    textView.hidden = NO;
    textView.textColor = textColor;

    // Honor dynamic type in the message bodies.
    textView.font = font;
    textView.linkTextAttributes = @{
        NSForegroundColorAttributeName : textColor,
        NSUnderlineStyleAttributeName : @(NSUnderlineStyleSingle | NSUnderlinePatternSolid)
    };
    textView.shouldIgnoreEvents = shouldIgnoreEvents;

    // For perf, set text last. Otherwise changing font/color is more expensive.
    textView.text = text;
}

- (BOOL)shouldShowSenderName
{
    return self.viewItem.senderName.length > 0;
}

- (void)configureSenderNameLabel
{
    OWSAssert(self.senderNameLabel);
    OWSAssert(self.shouldShowSenderName);

    self.senderNameLabel.textColor = self.bodyTextColor;
    self.senderNameLabel.font = OWSMessageBubbleView.senderNameFont;
    self.senderNameLabel.attributedText = self.viewItem.senderName;
    self.senderNameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
}

+ (UIFont *)senderNameFont
{
    return UIFont.ows_dynamicTypeSubheadlineFont.ows_mediumWeight;
}

+ (NSDictionary *)senderNamePrimaryAttributes
{
    return @{
        NSFontAttributeName : self.senderNameFont,
        NSForegroundColorAttributeName : ConversationStyle.bubbleTextColorIncoming,
    };
}

+ (NSDictionary *)senderNameSecondaryAttributes
{
    return @{
        NSFontAttributeName : self.senderNameFont.ows_italic,
        NSForegroundColorAttributeName : ConversationStyle.bubbleTextColorIncoming,
    };
}

- (BOOL)hasTapForMore
{
    if (!self.hasBodyText) {
        return NO;
    } else if (!self.displayableBodyText.isTextTruncated) {
        return NO;
    } else {
        return YES;
    }
}

- (nullable UIView *)createTapForMoreLabelIfNecessary
{
    if (!self.hasTapForMore) {
        return nil;
    }

    UILabel *tapForMoreLabel = [UILabel new];
    tapForMoreLabel.text = NSLocalizedString(@"CONVERSATION_VIEW_OVERSIZE_TEXT_TAP_FOR_MORE",
        @"Indicator on truncated text messages that they can be tapped to see the entire text message.");
    tapForMoreLabel.font = [self tapForMoreFont];
    tapForMoreLabel.textColor = [self.bodyTextColor colorWithAlphaComponent:0.85];
    tapForMoreLabel.textAlignment = [tapForMoreLabel textAlignmentUnnatural];

    return tapForMoreLabel;
}

- (UIView *)loadViewForStillImage
{
    OWSAssert(self.attachmentStream);
    OWSAssert([self.attachmentStream isImage]);

    UIImageView *stillImageView = [UIImageView new];
    // We need to specify a contentMode since the size of the image
    // might not match the aspect ratio of the view.
    stillImageView.contentMode = UIViewContentModeScaleAspectFill;
    // Use trilinear filters for better scaling quality at
    // some performance cost.
    stillImageView.layer.minificationFilter = kCAFilterTrilinear;
    stillImageView.layer.magnificationFilter = kCAFilterTrilinear;
    stillImageView.backgroundColor = [UIColor whiteColor];
    [self addAttachmentUploadViewIfNecessary];

    __weak OWSMessageBubbleView *weakSelf = self;
    self.loadCellContentBlock = ^{
        OWSMessageBubbleView *strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        OWSCAssert(strongSelf.bodyMediaView == stillImageView);
        if (stillImageView.image) {
            return;
        }
        // Don't cache large still images.
        //
        // TODO: Don't use full size images in the message cells.
        const NSUInteger kMaxCachableSize = 1024 * 1024;
        BOOL shouldSkipCache =
            [OWSFileSystem fileSizeOfPath:strongSelf.attachmentStream.filePath].unsignedIntegerValue < kMaxCachableSize;
        stillImageView.image = [strongSelf tryToLoadCellMedia:^{
            OWSCAssert([strongSelf.attachmentStream isImage]);
            return strongSelf.attachmentStream.image;
        }
                                                    mediaView:stillImageView
                                                     cacheKey:strongSelf.attachmentStream.uniqueId
                                              shouldSkipCache:shouldSkipCache];
    };
    self.unloadCellContentBlock = ^{
        OWSMessageBubbleView *strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        OWSCAssert(strongSelf.bodyMediaView == stillImageView);
        stillImageView.image = nil;
    };

    return stillImageView;
}

- (UIView *)loadViewForAnimatedImage
{
    OWSAssert(self.attachmentStream);
    OWSAssert([self.attachmentStream isAnimated]);

    YYAnimatedImageView *animatedImageView = [[YYAnimatedImageView alloc] init];
    // We need to specify a contentMode since the size of the image
    // might not match the aspect ratio of the view.
    animatedImageView.contentMode = UIViewContentModeScaleAspectFill;
    animatedImageView.backgroundColor = [UIColor whiteColor];
    [self addAttachmentUploadViewIfNecessary];

    __weak OWSMessageBubbleView *weakSelf = self;
    self.loadCellContentBlock = ^{
        OWSMessageBubbleView *strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        OWSCAssert(strongSelf.bodyMediaView == animatedImageView);
        if (animatedImageView.image) {
            return;
        }
        animatedImageView.image = [strongSelf tryToLoadCellMedia:^{
            OWSCAssert([strongSelf.attachmentStream isAnimated]);

            NSString *_Nullable filePath = [strongSelf.attachmentStream filePath];
            YYImage *_Nullable animatedImage = nil;
            if (strongSelf.attachmentStream.isValidImage && filePath) {
                animatedImage = [YYImage imageWithContentsOfFile:filePath];
            }
            return animatedImage;
        }
                                                       mediaView:animatedImageView
                                                        cacheKey:strongSelf.attachmentStream.uniqueId
                                                 shouldSkipCache:NO];
    };
    self.unloadCellContentBlock = ^{
        OWSMessageBubbleView *strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        OWSCAssert(strongSelf.bodyMediaView == animatedImageView);
        animatedImageView.image = nil;
    };

    return animatedImageView;
}

- (UIView *)loadViewForAudio
{
    OWSAssert(self.attachmentStream);
    OWSAssert([self.attachmentStream isAudio]);

    OWSAudioMessageView *audioMessageView = [[OWSAudioMessageView alloc] initWithAttachment:self.attachmentStream
                                                                                 isIncoming:self.isIncoming
                                                                                   viewItem:self.viewItem
                                                                          conversationStyle:self.conversationStyle];
    self.viewItem.lastAudioMessageView = audioMessageView;
    [audioMessageView createContents];
    [self addAttachmentUploadViewIfNecessary];

    self.loadCellContentBlock = ^{
        // Do nothing.
    };
    self.unloadCellContentBlock = ^{
        // Do nothing.
    };

    return audioMessageView;
}

- (UIView *)loadViewForVideo
{
    OWSAssert(self.attachmentStream);
    OWSAssert([self.attachmentStream isVideo]);

    UIImageView *stillImageView = [UIImageView new];
    // We need to specify a contentMode since the size of the image
    // might not match the aspect ratio of the view.
    stillImageView.contentMode = UIViewContentModeScaleAspectFill;
    // Use trilinear filters for better scaling quality at
    // some performance cost.
    stillImageView.layer.minificationFilter = kCAFilterTrilinear;
    stillImageView.layer.magnificationFilter = kCAFilterTrilinear;

    UIImage *videoPlayIcon = [UIImage imageNamed:@"play_button"];
    UIImageView *videoPlayButton = [[UIImageView alloc] initWithImage:videoPlayIcon];
    [stillImageView addSubview:videoPlayButton];
    [videoPlayButton autoCenterInSuperview];
    [self addAttachmentUploadViewIfNecessaryWithAttachmentStateCallback:^(BOOL isAttachmentReady) {
        videoPlayButton.hidden = !isAttachmentReady;
    }];

    __weak OWSMessageBubbleView *weakSelf = self;
    self.loadCellContentBlock = ^{
        OWSMessageBubbleView *strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        OWSCAssert(strongSelf.bodyMediaView == stillImageView);
        if (stillImageView.image) {
            return;
        }
        stillImageView.image = [strongSelf tryToLoadCellMedia:^{
            OWSCAssert([strongSelf.attachmentStream isVideo]);

            return strongSelf.attachmentStream.image;
        }
                                                    mediaView:stillImageView
                                                     cacheKey:strongSelf.attachmentStream.uniqueId
                                              shouldSkipCache:NO];
    };
    self.unloadCellContentBlock = ^{
        OWSMessageBubbleView *strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        OWSCAssert(strongSelf.bodyMediaView == stillImageView);
        stillImageView.image = nil;
    };

    return stillImageView;
}

- (UIView *)loadViewForGenericAttachment
{
    OWSAssert(self.viewItem.attachmentStream);
    OWSGenericAttachmentView *attachmentView =
        [[OWSGenericAttachmentView alloc] initWithAttachment:self.attachmentStream isIncoming:self.isIncoming];
    [attachmentView createContentsWithConversationStyle:self.conversationStyle];
    [self addAttachmentUploadViewIfNecessary];

    self.loadCellContentBlock = ^{
        // Do nothing.
    };
    self.unloadCellContentBlock = ^{
        // Do nothing.
    };

    return attachmentView;
}

- (UIView *)loadViewForDownloadingAttachment
{
    OWSAssert(self.attachmentPointer);

    AttachmentPointerView *downloadView =
        [[AttachmentPointerView alloc] initWithAttachmentPointer:self.attachmentPointer
                                                      isIncoming:self.isIncoming
                                               conversationStyle:self.conversationStyle];

    UIView *wrapper = [UIView new];
    [wrapper addSubview:downloadView];
    [downloadView autoPinEdgesToSuperviewEdges];

    self.loadCellContentBlock = ^{
        // Do nothing.
    };
    self.unloadCellContentBlock = ^{
        // Do nothing.
    };

    return wrapper;
}

- (UIView *)loadViewForContactShare
{
    OWSAssert(self.viewItem.contactShare);

    OWSContactShareView *contactShareView = [[OWSContactShareView alloc] initWithContactShare:self.viewItem.contactShare
                                                                                   isIncoming:self.isIncoming
                                                                            conversationStyle:self.conversationStyle];
    [contactShareView createContents];
    // TODO: Should we change appearance if contact avatar is uploading?

    self.loadCellContentBlock = ^{
        // Do nothing.
    };
    self.unloadCellContentBlock = ^{
        // Do nothing.
    };

    return contactShareView;
}

- (void)addAttachmentUploadViewIfNecessary
{
    [self addAttachmentUploadViewIfNecessaryWithAttachmentStateCallback:nil];
}

- (void)addAttachmentUploadViewIfNecessaryWithAttachmentStateCallback:
    (nullable AttachmentStateBlock)attachmentStateCallback
{
    OWSAssert(self.attachmentStream);

    if (!attachmentStateCallback) {
        attachmentStateCallback = ^(BOOL isAttachmentReady) {
        };
    }

    if (self.isOutgoing) {
        if (!self.attachmentStream.isUploaded) {
            AttachmentUploadView *attachmentUploadView =
                [[AttachmentUploadView alloc] initWithAttachment:self.attachmentStream
                                         attachmentStateCallback:attachmentStateCallback];
            [self.bubbleView addSubview:attachmentUploadView];
            [attachmentUploadView ows_autoPinToSuperviewEdges];
        }
    }
}

- (void)showAttachmentErrorViewWithMediaView:(UIView *)mediaView
{
    OWSAssert(mediaView);

    // TODO: We could do a better job of indicating that the media could not be loaded.
    UIView *errorView = [UIView new];
    errorView.backgroundColor = [UIColor colorWithWhite:0.85f alpha:1.f];
    errorView.userInteractionEnabled = NO;
    [mediaView addSubview:errorView];
    [errorView autoPinEdgesToSuperviewEdges];
}

#pragma mark - Measurement

// Size of "message body" text, not quoted reply text.
- (nullable NSValue *)bodyTextSize
{
    OWSAssert(self.conversationStyle);
    OWSAssert(self.conversationStyle.maxMessageWidth > 0);

    if (!self.hasBodyText) {
        return nil;
    }

    CGFloat hMargins = self.conversationStyle.textInsetHorizontal * 2;
    const int maxTextWidth = (int)floor(self.conversationStyle.maxMessageWidth - hMargins);

    [self configureBodyTextView];

    CGSize result = CGSizeCeil([self.bodyTextView sizeThatFits:CGSizeMake(maxTextWidth, CGFLOAT_MAX)]);

    return [NSValue valueWithCGSize:CGSizeCeil(result)];
}

- (nullable NSValue *)bodyMediaSize
{
    OWSAssert(self.conversationStyle);
    OWSAssert(self.conversationStyle.maxMessageWidth > 0);

    CGFloat maxMessageWidth = self.conversationStyle.maxMessageWidth;
    if (!self.hasFullWidthMediaView) {
        CGFloat hMargins = self.conversationStyle.textInsetHorizontal * 2;
        maxMessageWidth -= hMargins;
    }

    CGSize result = CGSizeZero;
    switch (self.cellType) {
        case OWSMessageCellType_Unknown:
        case OWSMessageCellType_TextMessage:
        case OWSMessageCellType_OversizeTextMessage: {
            return nil;
        }
        case OWSMessageCellType_StillImage:
        case OWSMessageCellType_AnimatedImage:
        case OWSMessageCellType_Video: {
            OWSAssert(self.mediaSize.width > 0);
            OWSAssert(self.mediaSize.height > 0);

            // TODO: Adjust this behavior.

            CGFloat contentAspectRatio = self.mediaSize.width / self.mediaSize.height;
            // Clamp the aspect ratio so that very thin/wide content is presented
            // in a reasonable way.
            const CGFloat minAspectRatio = 0.35f;
            const CGFloat maxAspectRatio = 1 / minAspectRatio;
            contentAspectRatio = MAX(minAspectRatio, MIN(maxAspectRatio, contentAspectRatio));

            const CGFloat maxMediaWidth = maxMessageWidth;
            const CGFloat maxMediaHeight = maxMessageWidth;
            CGFloat mediaWidth = maxMediaHeight * contentAspectRatio;
            CGFloat mediaHeight = maxMediaHeight;
            if (mediaWidth > maxMediaWidth) {
                mediaWidth = maxMediaWidth;
                mediaHeight = maxMediaWidth / contentAspectRatio;
            }

            // We don't want to blow up small images unnecessarily.
            const CGFloat kMinimumSize = 150.f;
            CGFloat shortSrcDimension = MIN(self.mediaSize.width, self.mediaSize.height);
            CGFloat shortDstDimension = MIN(mediaWidth, mediaHeight);
            if (shortDstDimension > kMinimumSize && shortDstDimension > shortSrcDimension) {
                CGFloat factor = kMinimumSize / shortDstDimension;
                mediaWidth *= factor;
                mediaHeight *= factor;
            }

            result = CGSizeRound(CGSizeMake(mediaWidth, mediaHeight));
            break;
        }
        case OWSMessageCellType_Audio:
            result = CGSizeMake(maxMessageWidth, OWSAudioMessageView.bubbleHeight);
            break;
        case OWSMessageCellType_GenericAttachment: {
            OWSAssert(self.viewItem.attachmentStream);
            OWSGenericAttachmentView *attachmentView =
                [[OWSGenericAttachmentView alloc] initWithAttachment:self.attachmentStream isIncoming:self.isIncoming];
            [attachmentView createContentsWithConversationStyle:self.conversationStyle];
            result = [attachmentView measureSizeWithMaxMessageWidth:maxMessageWidth];
            break;
        }
        case OWSMessageCellType_DownloadingAttachment:
            result = CGSizeMake(MIN(200, maxMessageWidth), [AttachmentPointerView measureHeight]);
            break;
        case OWSMessageCellType_ContactShare:
            OWSAssert(self.viewItem.contactShare);

            result = CGSizeMake(maxMessageWidth, [OWSContactShareView bubbleHeight]);
            break;
    }

    OWSAssert(result.width <= maxMessageWidth);
    result.width = MIN(result.width, maxMessageWidth);

    return [NSValue valueWithCGSize:CGSizeCeil(result)];
}

- (nullable NSValue *)quotedMessageSize
{
    OWSAssert(self.conversationStyle);
    OWSAssert(self.conversationStyle.maxMessageWidth > 0);
    OWSAssert(self.viewItem);
    OWSAssert([self.viewItem.interaction isKindOfClass:[TSMessage class]]);

    if (!self.isQuotedReply) {
        return nil;
    }

    DisplayableText *_Nullable displayableQuotedText
        = (self.viewItem.hasQuotedText ? self.viewItem.displayableQuotedText : nil);

    OWSQuotedMessageView *quotedMessageView =
        [OWSQuotedMessageView quotedMessageViewForConversation:self.viewItem.quotedReply
                                         displayableQuotedText:displayableQuotedText
                                             conversationStyle:self.conversationStyle
                                                    isOutgoing:self.isOutgoing
                                                  sharpCorners:self.sharpCornersForQuotedMessage];
    CGSize result = [quotedMessageView sizeForMaxWidth:self.conversationStyle.maxMessageWidth];
    return [NSValue valueWithCGSize:CGSizeCeil(result)];
}

- (nullable NSValue *)senderNameSize
{
    OWSAssert(self.conversationStyle);
    OWSAssert(self.conversationStyle.maxMessageWidth > 0);

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

- (nullable NSValue *)actionButtonsSize
{
    OWSAssert(self.conversationStyle);
    OWSAssert(self.conversationStyle.maxMessageWidth > 0);

    if (self.cellType == OWSMessageCellType_ContactShare) {
        OWSAssert(self.viewItem.contactShare);

        if ([OWSContactShareButtonsView hasAnyButton:self.viewItem.contactShare]) {
            CGSize buttonsSize = CGSizeCeil(
                CGSizeMake(self.conversationStyle.maxMessageWidth, [OWSContactShareButtonsView bubbleHeight]));
            return [NSValue valueWithCGSize:buttonsSize];
        }
    }
    return nil;
}

- (CGSize)measureSize
{
    OWSAssert(self.conversationStyle);
    OWSAssert(self.conversationStyle.viewWidth > 0);
    OWSAssert(self.viewItem);
    OWSAssert([self.viewItem.interaction isKindOfClass:[TSMessage class]]);

    CGSize cellSize = CGSizeZero;

    [self configureBubbleRounding];

    NSMutableArray<NSValue *> *textViewSizes = [NSMutableArray new];

    NSValue *_Nullable senderNameSize = [self senderNameSize];
    if (senderNameSize) {
        [textViewSizes addObject:senderNameSize];
    }

    NSValue *_Nullable quotedMessageSize = [self quotedMessageSize];
    if (quotedMessageSize) {
        if (!senderNameSize) {
            cellSize.height += self.quotedReplyTopMargin;
        }
        cellSize.width = MAX(cellSize.width, quotedMessageSize.CGSizeValue.width);
        cellSize.height += quotedMessageSize.CGSizeValue.height;
    }

    NSValue *_Nullable bodyMediaSize = [self bodyMediaSize];
    if (bodyMediaSize) {
        if (self.hasFullWidthMediaView) {
            cellSize.width = MAX(cellSize.width, bodyMediaSize.CGSizeValue.width);
            cellSize.height += bodyMediaSize.CGSizeValue.height;
        } else {
            [textViewSizes addObject:bodyMediaSize];
            bodyMediaSize = nil;
        }

        if (self.contactShareHasSpacerTop) {
            cellSize.height += self.contactShareVSpacing;
        }
        if (self.contactShareHasSpacerBottom) {
            cellSize.height += self.contactShareVSpacing;
        }
    }

    if (bodyMediaSize || quotedMessageSize) {
        if (textViewSizes.count > 0) {
            CGSize groupSize = [self sizeForTextViewGroup:textViewSizes];
            cellSize.width = MAX(cellSize.width, groupSize.width);
            cellSize.height += groupSize.height;
            [textViewSizes removeAllObjects];
        }

        if (bodyMediaSize && quotedMessageSize && self.hasFullWidthMediaView) {
            cellSize.height += self.bodyMediaQuotedReplyVSpacing;
        }
    }

    NSValue *_Nullable bodyTextSize = [self bodyTextSize];
    if (bodyTextSize) {
        [textViewSizes addObject:bodyTextSize];
    }

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

    OWSAssert(cellSize.width > 0 && cellSize.height > 0);

    if (self.hasTapForMore) {
        cellSize.height += self.tapForMoreHeight + self.textViewVSpacing;
    }

    NSValue *_Nullable actionButtonsSize = [self actionButtonsSize];
    if (actionButtonsSize) {
        cellSize.width = MAX(cellSize.width, actionButtonsSize.CGSizeValue.width);
        cellSize.height += actionButtonsSize.CGSizeValue.height;
    }

    cellSize = CGSizeCeil(cellSize);

    OWSAssert(cellSize.width <= self.conversationStyle.maxMessageWidth);
    cellSize.width = MIN(cellSize.width, self.conversationStyle.maxMessageWidth);

    return cellSize;
}

- (CGSize)sizeForTextViewGroup:(NSArray<NSValue *> *)textViewSizes
{
    OWSAssert(textViewSizes);
    OWSAssert(textViewSizes.count > 0);
    OWSAssert(self.conversationStyle);
    OWSAssert(self.conversationStyle.maxMessageWidth > 0);

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

- (UIFont *)tapForMoreFont
{
    return UIFont.ows_dynamicTypeCaption1Font;
}

- (CGFloat)tapForMoreHeight
{
    return (CGFloat)ceil([self tapForMoreFont].lineHeight * 1.25);
}

#pragma mark -

- (UIColor *)bodyTextColor
{
    OWSAssert([self.viewItem.interaction isKindOfClass:[TSMessage class]]);

    TSMessage *message = (TSMessage *)self.viewItem.interaction;
    return [self.conversationStyle bubbleTextColorWithMessage:message];
}

- (BOOL)isMediaBeingSent
{
    if (self.isIncoming) {
        return NO;
    }
    if (self.cellType == OWSMessageCellType_DownloadingAttachment) {
        return NO;
    }
    if (self.cellType == OWSMessageCellType_ContactShare) {
        // TODO: Handle this case.
        return NO;
    }
    if (!self.attachmentStream) {
        return NO;
    }
    TSOutgoingMessage *outgoingMessage = (TSOutgoingMessage *)self.viewItem.interaction;
    return outgoingMessage.messageState == TSOutgoingMessageStateSending;
}

- (void)prepareForReuse
{
    [NSLayoutConstraint deactivateConstraints:self.viewConstraints];
    self.viewConstraints = [NSMutableArray new];

    self.delegate = nil;

    [self.bodyTextView removeFromSuperview];
    self.bodyTextView.text = nil;
    self.bodyTextView.hidden = YES;

    self.bubbleView.bubbleColor = nil;
    [self.bubbleView clearPartnerViews];

    for (UIView *subview in self.bubbleView.subviews) {
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

    [self.quotedMessageView removeFromSuperview];
    self.quotedMessageView = nil;

    [self.footerView removeFromSuperview];
    [self.footerView prepareForReuse];

    for (UIView *subview in self.stackView.subviews) {
        [subview removeFromSuperview];
    }
    for (UIView *subview in self.subviews) {
        if (subview != self.bubbleView) {
            [subview removeFromSuperview];
        }
    }

    [self.contactShareButtonsView removeFromSuperview];
    self.contactShareButtonsView = nil;
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
    OWSAssert(self.delegate);

    if (sender.state != UIGestureRecognizerStateRecognized) {
        DDLogVerbose(@"%@ Ignoring tap on message: %@", self.logTag, self.viewItem.interaction.debugDescription);
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

    if (self.contactShareButtonsView) {
        if ([self.contactShareButtonsView handleTapGesture:sender]) {
            return;
        }
    }

    CGPoint locationInMessageBubble = [sender locationInView:self];
    switch ([self gestureLocationForLocation:locationInMessageBubble]) {
        case OWSMessageGestureLocation_Default:
            // Do nothing.
            return;
        case OWSMessageGestureLocation_OversizeText:
            [self.delegate didTapTruncatedTextMessage:self.viewItem];
            return;
        case OWSMessageGestureLocation_Media:
            [self handleMediaTapGesture];
            break;
        case OWSMessageGestureLocation_QuotedReply:
            if (self.viewItem.quotedReply) {
                [self.delegate didTapConversationItem:self.viewItem quotedReply:self.viewItem.quotedReply];
            } else {
                OWSFail(@"%@ Missing quoted message.", self.logTag);
            }
            break;
    }
}

- (void)handleMediaTapGesture
{
    OWSAssert(self.delegate);

    TSAttachmentStream *_Nullable attachmentStream = self.viewItem.attachmentStream;

    switch (self.cellType) {
        case OWSMessageCellType_Unknown:
        case OWSMessageCellType_TextMessage:
        case OWSMessageCellType_OversizeTextMessage:
            break;
        case OWSMessageCellType_StillImage:
            OWSAssert(self.bodyMediaView);
            OWSAssert(attachmentStream);

            [self.delegate didTapImageViewItem:self.viewItem
                              attachmentStream:attachmentStream
                                     imageView:self.bodyMediaView];
            break;
        case OWSMessageCellType_AnimatedImage:
            OWSAssert(self.bodyMediaView);
            OWSAssert(attachmentStream);

            [self.delegate didTapImageViewItem:self.viewItem
                              attachmentStream:attachmentStream
                                     imageView:self.bodyMediaView];
            break;
        case OWSMessageCellType_Audio:
            OWSAssert(attachmentStream);

            [self.delegate didTapAudioViewItem:self.viewItem attachmentStream:attachmentStream];
            return;
        case OWSMessageCellType_Video:
            OWSAssert(self.bodyMediaView);
            OWSAssert(attachmentStream);

            [self.delegate didTapVideoViewItem:self.viewItem
                              attachmentStream:attachmentStream
                                     imageView:self.bodyMediaView];
            return;
        case OWSMessageCellType_GenericAttachment:
            OWSAssert(attachmentStream);

            [AttachmentSharing showShareUIForAttachment:attachmentStream];
            break;
        case OWSMessageCellType_DownloadingAttachment: {
            TSAttachmentPointer *_Nullable attachmentPointer = self.viewItem.attachmentPointer;
            OWSAssert(attachmentPointer);

            if (attachmentPointer.state == TSAttachmentPointerStateFailed) {
                [self.delegate didTapFailedIncomingAttachment:self.viewItem attachmentPointer:attachmentPointer];
            }
            break;
        }
        case OWSMessageCellType_ContactShare:
            [self.delegate didTapContactShareViewItem:self.viewItem];
            break;
    }
}

- (OWSMessageGestureLocation)gestureLocationForLocation:(CGPoint)locationInMessageBubble
{
    if (self.quotedMessageView) {
        // Treat this as a "quoted reply" gesture if:
        //
        // * There is a "quoted reply" view.
        // * The gesture occured within or above the "quoted reply" view.
        CGPoint location = [self convertPoint:locationInMessageBubble toView:self.quotedMessageView];
        if (location.y <= self.quotedMessageView.height) {
            return OWSMessageGestureLocation_QuotedReply;
        }
    }

    if (self.bodyMediaView) {
        // Treat this as a "body media" gesture if:
        //
        // * There is a "body media" view.
        // * The gesture occured within or above the "body media" view...
        // * ...OR if the message doesn't have body text.
        CGPoint location = [self convertPoint:locationInMessageBubble toView:self.bodyMediaView];
        if (location.y <= self.bodyMediaView.height) {
            return OWSMessageGestureLocation_Media;
        }
        if (!self.viewItem.hasBodyText) {
            return OWSMessageGestureLocation_Media;
        }
    }

    if (self.hasTapForMore) {
        return OWSMessageGestureLocation_OversizeText;
    }

    return OWSMessageGestureLocation_Default;
}

- (void)didTapQuotedReply:(OWSQuotedReplyModel *)quotedReply
    failedThumbnailDownloadAttachmentPointer:(TSAttachmentPointer *)attachmentPointer
{
    [self.delegate didTapConversationItem:self.viewItem
                                     quotedReply:quotedReply
        failedThumbnailDownloadAttachmentPointer:attachmentPointer];
}

#pragma mark - OWSContactShareButtonsViewDelegate

- (void)didTapSendMessageToContactShare:(ContactShareViewModel *)contactShare
{
    OWSAssertIsOnMainThread();
    OWSAssert(contactShare);

    [self.delegate didTapSendMessageToContactShare:contactShare];
}

- (void)didTapSendInviteToContactShare:(ContactShareViewModel *)contactShare
{
    OWSAssertIsOnMainThread();
    OWSAssert(contactShare);

    [self.delegate didTapSendInviteToContactShare:contactShare];
}

- (void)didTapShowAddToContactUIForContactShare:(ContactShareViewModel *)contactShare
{
    OWSAssertIsOnMainThread();
    OWSAssert(contactShare);

    [self.delegate didTapShowAddToContactUIForContactShare:contactShare];
}

@end

NS_ASSUME_NONNULL_END
