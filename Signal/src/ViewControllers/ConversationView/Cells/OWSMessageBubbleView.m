//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
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

@interface OWSMessageBubbleView () <OWSQuotedMessageViewDelegate,
    OWSContactShareButtonsViewDelegate,
    UITextViewDelegate>

@property (nonatomic) OWSBubbleView *bubbleView;

@property (nonatomic) UIStackView *stackView;

@property (nonatomic) UILabel *senderNameLabel;

@property (nonatomic) UIView *senderNameContainer;

@property (nonatomic) OWSMessageTextView *bodyTextView;

@property (nonatomic, nullable) UIView *quotedMessageView;

@property (nonatomic, nullable) UIView *bodyMediaView;

@property (nonatomic) LinkPreviewView *linkPreviewView;

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

#pragma mark - Dependencies

- (OWSAttachmentDownloads *)attachmentDownloads
{
    return SSKEnvironment.shared.attachmentDownloads;
}

- (TSAccountManager *)tsAccountManager
{
    OWSAssertDebug(SSKEnvironment.shared.tsAccountManager);

    return SSKEnvironment.shared.tsAccountManager;
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
    OWSAssertDebug(!self.bodyTextView);

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
    self.bodyTextView.hidden = YES;

    self.linkPreviewView = [[LinkPreviewView alloc] initWithDraftDelegate:nil];

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
    textView.delegate = self;
    return textView;
}

- (UIFont *)textMessageFont
{
    OWSAssertDebug(DisplayableText.kMaxJumbomojiCount == 5);

    CGFloat basePointSize = UIFont.ows_dynamicTypeBodyFont.pointSize;
    switch (self.displayableBodyText.jumbomojiCount) {
        case 0:
            break;
        case 1:
            return [UIFont ows_regularFontWithSize:basePointSize + 30.f];
        case 2:
            return [UIFont ows_regularFontWithSize:basePointSize + 24.f];
        case 3:
        case 4:
        case 5:
            return [UIFont ows_regularFontWithSize:basePointSize + 18.f];
        default:
            OWSFailDebug(@"Unexpected jumbomoji count: %zd", self.displayableBodyText.jumbomojiCount);
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
    OWSAssertDebug(self.viewItem);

    return self.viewItem.hasBodyText;
}

- (nullable DisplayableText *)displayableBodyText
{
    // This should always be valid for the appropriate cell types.
    OWSAssertDebug(self.viewItem.displayableBodyText);

    return self.viewItem.displayableBodyText;
}

- (TSMessage *)message
{
    OWSAssertDebug([self.viewItem.interaction isKindOfClass:[TSMessage class]]);

    return (TSMessage *)self.viewItem.interaction;
}

- (BOOL)isQuotedReply
{
    // This should always be valid for the appropriate cell types.
    OWSAssertDebug(self.viewItem);

    return self.viewItem.isQuotedReply;
}

- (BOOL)hasQuotedText
{
    // This should always be valid for the appropriate cell types.
    OWSAssertDebug(self.viewItem);

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

#pragma mark - Load

- (void)configureViews
{
    OWSAssertDebug(self.conversationStyle);
    OWSAssertDebug(self.viewItem);
    OWSAssertDebug(self.viewItem.interaction);
    OWSAssertDebug([self.viewItem.interaction isKindOfClass:[TSMessage class]]);

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
        OWSAssertDebug(quotedMessageSize);
        [self.viewConstraints addObject:[quotedMessageView autoSetDimension:ALDimensionHeight
                                                                     toSize:quotedMessageSize.CGSizeValue.height]];
    }

    UIView *_Nullable bodyMediaView = nil;
    switch (self.cellType) {
        case OWSMessageCellType_Unknown:
        case OWSMessageCellType_TextOnlyMessage:
            break;
        case OWSMessageCellType_Audio:
            bodyMediaView = [self loadViewForAudio];
            break;
        case OWSMessageCellType_GenericAttachment:
            bodyMediaView = [self loadViewForGenericAttachment];
            break;
        case OWSMessageCellType_ContactShare:
            bodyMediaView = [self loadViewForContactShare];
            break;
        case OWSMessageCellType_MediaMessage:
            bodyMediaView = [self loadViewForMediaAlbum];
            break;
        case OWSMessageCellType_OversizeTextDownloading:
            bodyMediaView = [self loadViewForOversizeTextDownload];
            break;
        case OWSMessageCellType_StickerMessage:
            OWSFailDebug(@"Stickers should not be rendered with this view.");
            break;
    }

    if (bodyMediaView) {
        OWSAssertDebug(self.loadCellContentBlock);
        OWSAssertDebug(self.unloadCellContentBlock);

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
            } else {
                OWSAssertDebug(self.cellType == OWSMessageCellType_ContactShare);

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

    if (self.viewItem.linkPreview) {
        if (self.isQuotedReply) {
            UIView *spacerView = [UIView containerView];
            [spacerView autoSetDimension:ALDimensionHeight toSize:self.bodyMediaQuotedReplyVSpacing];
            [spacerView setCompressionResistanceHigh];
            [self.stackView addArrangedSubview:spacerView];
        }

        self.linkPreviewView.state = self.linkPreviewState;
        [self.stackView addArrangedSubview:self.linkPreviewView];
        [self.linkPreviewView addBorderViewsWithBubbleView:self.bubbleView];
    }

    // We render malformed messages as "empty text" messages,
    // so create a text view if there is no body media view.
    if (self.hasBodyText || !bodyMediaView) {
        [self configureBodyTextView];
        [textViews addObject:self.bodyTextView];

        OWSAssertDebug(bodyTextSize);
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
        OWSAssertDebug(bodyMediaView);

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
                                         conversationStyle:self.conversationStyle
                                                isIncoming:self.isIncoming
                                         isOverlayingMedia:YES
                                           isOutsideBubble:NO];
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
    if (bodyMediaView) {
        OWSAssertDebug(bodyMediaSize);
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

    OWSAssertDebug(self.viewItem.contactShare);

    OWSContactShareButtonsView *buttonsView =
        [[OWSContactShareButtonsView alloc] initWithContactShare:self.viewItem.contactShare delegate:self];

    NSValue *_Nullable actionButtonsSize = [self actionButtonsSize];
    OWSAssertDebug(actionButtonsSize);
    [self.viewConstraints addObjectsFromArray:@[
        [buttonsView autoSetDimension:ALDimensionHeight toSize:actionButtonsSize.CGSizeValue.height],
    ]];

    // The "contact share" view casts a shadow "downward" onto adjacent views,
    // so we use a "proxy" view to take its place within the v-stack
    // view and then insert the "contact share" view above its proxy so that
    // it floats above the other content of the bubble view.

    UIView *proxyView = [UIView new];
    [self.stackView addArrangedSubview:proxyView];

    OWSBubbleShapeView *shadowView = [[OWSBubbleShapeView alloc] initShadow];
    OWSBubbleShapeView *clipView = [[OWSBubbleShapeView alloc] initClip];

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

    OWSAssertDebug(buttonsView.backgroundColor);
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
    OWSAssertDebug([self.viewItem.interaction isKindOfClass:[TSMessage class]]);

    TSMessage *message = (TSMessage *)self.viewItem.interaction;
    return [self.conversationStyle bubbleColorWithMessage:message];
}

- (BOOL)hasBodyMediaWithThumbnail
{
    switch (self.cellType) {
        case OWSMessageCellType_Unknown:
        case OWSMessageCellType_TextOnlyMessage:
        case OWSMessageCellType_Audio:
        case OWSMessageCellType_GenericAttachment:
        case OWSMessageCellType_ContactShare:
        case OWSMessageCellType_OversizeTextDownloading:
            return NO;
        case OWSMessageCellType_MediaMessage:
            return YES;
        case OWSMessageCellType_StickerMessage:
            OWSFailDebug(@"Stickers should not be rendered with this view.");
            return NO;
    }
}

- (BOOL)hasBodyMediaView {
    switch (self.cellType) {
        case OWSMessageCellType_Unknown:
        case OWSMessageCellType_TextOnlyMessage:
            return NO;
        case OWSMessageCellType_Audio:
        case OWSMessageCellType_GenericAttachment:
        case OWSMessageCellType_ContactShare:
        case OWSMessageCellType_MediaMessage:
        case OWSMessageCellType_OversizeTextDownloading:
            return YES;
        case OWSMessageCellType_StickerMessage:
            OWSFailDebug(@"Stickers should not be rendered with this view.");
            return NO;
    }
}

- (BOOL)hasFullWidthMediaView
{
    return (self.hasBodyMediaWithThumbnail || self.cellType == OWSMessageCellType_ContactShare
        || self.cellType == OWSMessageCellType_MediaMessage);
}

- (BOOL)canFooterOverlayMedia
{
    return self.hasBodyMediaWithThumbnail;
}

- (BOOL)hasBottomFooter
{
    BOOL shouldFooterOverlayMedia = (self.canFooterOverlayMedia && self.hasBodyMediaView && !self.hasBodyText);
    if (self.viewItem.shouldHideFooter) {
        return NO;
    } else if (shouldFooterOverlayMedia) {
        return NO;
    } else {
        return YES;
    }
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

- (CGFloat)bodyMediaQuotedReplyVSpacing
{
    return 6.f;
}

- (CGFloat)quotedReplyTopMargin
{
    return 6.f;
}

- (nullable LinkPreviewSent *)linkPreviewState
{
    if (!self.viewItem.linkPreview) {
        return nil;
    }
    return [[LinkPreviewSent alloc] initWithLinkPreview:self.viewItem.linkPreview
                                        imageAttachment:self.viewItem.linkPreviewAttachment
                                      conversationStyle:self.conversationStyle];
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
    OWSAssertDebug(self.hasBodyText);

    BOOL shouldIgnoreEvents = NO;
    if (self.viewItem.interaction.interactionType == OWSInteractionType_OutgoingMessage) {
        // Ignore taps on links in outgoing messages that haven't been sent yet, as
        // this interferes with "tap to retry".
        TSOutgoingMessage *outgoingMessage = (TSOutgoingMessage *)self.viewItem.interaction;
        shouldIgnoreEvents = outgoingMessage.messageState != TSOutgoingMessageStateSent;
    }
    [self.class loadForTextDisplay:self.bodyTextView
                   displayableText:self.displayableBodyText
                        searchText:self.delegate.lastSearchedText
                         textColor:self.bodyTextColor
                              font:self.textMessageFont
                shouldIgnoreEvents:shouldIgnoreEvents];
}

+ (void)loadForTextDisplay:(OWSMessageTextView *)textView
           displayableText:(DisplayableText *)displayableText
                searchText:(nullable NSString *)searchText
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

    NSString *text = displayableText.displayText;

    NSMutableAttributedString *attributedText = [[NSMutableAttributedString alloc]
        initWithString:text
            attributes:@{ NSFontAttributeName : font, NSForegroundColorAttributeName : textColor }];
    if (searchText.length >= ConversationSearchController.kMinimumSearchTextLength) {
        NSString *searchableText = [FullTextSearchFinder normalizeWithText:searchText];
        NSError *error;
        NSRegularExpression *regex =
            [[NSRegularExpression alloc] initWithPattern:[NSRegularExpression escapedPatternForString:searchableText]
                                                 options:NSRegularExpressionCaseInsensitive
                                                   error:&error];
        OWSAssertDebug(error == nil);
        for (NSTextCheckingResult *match in
            [regex matchesInString:text options:NSMatchingWithoutAnchoringBounds range:NSMakeRange(0, text.length)]) {

            OWSAssertDebug(match.range.length >= ConversationSearchController.kMinimumSearchTextLength);
            [attributedText addAttribute:NSBackgroundColorAttributeName value:UIColor.yellowColor range:match.range];
            [attributedText addAttribute:NSForegroundColorAttributeName value:UIColor.ows_blackColor range:match.range];
        }
    }

    [textView ensureShouldLinkifyText:displayableText.shouldAllowLinkification];

    // For perf, set text last. Otherwise changing font/color is more expensive.

    // We use attributedText even when we're not highlighting searched text to esnure any lingering
    // attributes are reset.
    textView.attributedText = attributedText;
}

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

- (UIView *)loadViewForMediaAlbum
{
    OWSAssertDebug(self.viewItem.mediaAlbumItems);

    OWSMediaAlbumCellView *albumView =
        [[OWSMediaAlbumCellView alloc] initWithMediaCache:self.cellMediaCache
                                                    items:self.viewItem.mediaAlbumItems
                                               isOutgoing:self.isOutgoing
                                          maxMessageWidth:self.conversationStyle.maxMessageWidth];
    self.loadCellContentBlock = ^{
        [albumView loadMedia];
    };
    self.unloadCellContentBlock = ^{
        [albumView unloadMedia];
    };

    // Only apply "inner shadow" for single media, not albums.
    if (albumView.itemViews.count == 1) {
        UIView *itemView = albumView.itemViews.firstObject;
        OWSBubbleShapeView *innerShadowView = [[OWSBubbleShapeView alloc]
            initInnerShadowWithColor:(Theme.isDarkThemeEnabled ? UIColor.ows_whiteColor : UIColor.ows_blackColor)
                              radius:0.5f
                             opacity:0.15f];
        [itemView addSubview:innerShadowView];
        [self.bubbleView addPartnerView:innerShadowView];
        [self.viewConstraints addObjectsFromArray:[innerShadowView ows_autoPinToSuperviewEdges]];
    }

    return albumView;
}

- (UIView *)loadViewForAudio
{
    TSAttachment *attachment = (self.viewItem.attachmentStream ?: self.viewItem.attachmentPointer);
    OWSAssertDebug(attachment);
    OWSAssertDebug([attachment isAudio]);

    OWSAudioMessageView *audioMessageView = [[OWSAudioMessageView alloc] initWithAttachment:attachment
                                                                                 isIncoming:self.isIncoming
                                                                                   viewItem:self.viewItem
                                                                          conversationStyle:self.conversationStyle];
    self.viewItem.lastAudioMessageView = audioMessageView;
    [audioMessageView createContents];
    [self addProgressViewsIfNecessary:audioMessageView shouldShowDownloadProgress:NO];

    self.loadCellContentBlock = ^{
        // Do nothing.
    };
    self.unloadCellContentBlock = ^{
        // Do nothing.
    };

    return audioMessageView;
}

- (UIView *)loadViewForGenericAttachment
{
    TSAttachment *attachment = (self.viewItem.attachmentStream ?: self.viewItem.attachmentPointer);
    OWSAssertDebug(attachment);
    OWSGenericAttachmentView *attachmentView = [[OWSGenericAttachmentView alloc] initWithAttachment:attachment
                                                                                         isIncoming:self.isIncoming
                                                                                           viewItem:self.viewItem];
    [attachmentView createContentsWithConversationStyle:self.conversationStyle];
    [self addProgressViewsIfNecessary:attachmentView shouldShowDownloadProgress:NO];

    self.loadCellContentBlock = ^{
        // Do nothing.
    };
    self.unloadCellContentBlock = ^{
        // Do nothing.
    };

    return attachmentView;
}

- (UIView *)loadViewForContactShare
{
    OWSAssertDebug(self.viewItem.contactShare);

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

- (UIView *)loadViewForOversizeTextDownload
{
    // We can use an empty view.  The progress views will display download
    // progress or tap-to-retry UI.
    UIView *attachmentView = [UIView new];

    [self addProgressViewsIfNecessary:attachmentView shouldShowDownloadProgress:YES];

    self.loadCellContentBlock = ^{
        // Do nothing.
    };
    self.unloadCellContentBlock = ^{
        // Do nothing.
    };

    return attachmentView;
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
            [self addTapToRetryView:bodyMediaView];
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
    overlayView.backgroundColor = [self.bubbleColor colorWithAlphaComponent:0.5];
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
    label.backgroundColor = self.bubbleColor;
    [bodyMediaView addSubview:label];
    [label autoPinEdgesToSuperviewMargins];
    [label setContentHuggingLow];
    [label setCompressionResistanceLow];
}

- (void)showAttachmentErrorViewWithMediaView:(UIView *)mediaView
{
    OWSAssertDebug(mediaView);

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
    OWSAssertDebug(self.conversationStyle);
    OWSAssertDebug(self.conversationStyle.maxMessageWidth > 0);

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
    OWSAssertDebug(self.conversationStyle);
    OWSAssertDebug(self.conversationStyle.maxMessageWidth > 0);

    // This upper bound should have no effect in portrait orientation.
    // It limits body media size in landscape.
    const CGFloat kMaxBodyMediaSize = 350;
    CGFloat maxMessageWidth = MIN(kMaxBodyMediaSize, self.conversationStyle.maxMessageWidth);
    if (!self.hasFullWidthMediaView) {
        CGFloat hMargins = self.conversationStyle.textInsetHorizontal * 2;
        maxMessageWidth -= hMargins;
    }

    CGSize result = CGSizeZero;
    switch (self.cellType) {
        case OWSMessageCellType_Unknown:
        case OWSMessageCellType_TextOnlyMessage: {
            return nil;
        }
        case OWSMessageCellType_Audio:
            result = CGSizeMake(maxMessageWidth, OWSAudioMessageView.bubbleHeight);
            break;
        case OWSMessageCellType_GenericAttachment: {
            TSAttachment *attachment = (self.viewItem.attachmentStream ?: self.viewItem.attachmentPointer);
            OWSAssertDebug(attachment);
            OWSGenericAttachmentView *attachmentView =
                [[OWSGenericAttachmentView alloc] initWithAttachment:attachment
                                                          isIncoming:self.isIncoming
                                                            viewItem:self.viewItem];
            [attachmentView createContentsWithConversationStyle:self.conversationStyle];
            result = [attachmentView measureSizeWithMaxMessageWidth:maxMessageWidth];
            break;
        }
        case OWSMessageCellType_ContactShare:
            OWSAssertDebug(self.viewItem.contactShare);

            result = CGSizeMake(maxMessageWidth, [OWSContactShareView bubbleHeight]);
            break;
        case OWSMessageCellType_MediaMessage:
            result = [OWSMediaAlbumCellView layoutSizeForMaxMessageWidth:maxMessageWidth
                                                                   items:self.viewItem.mediaAlbumItems];

            if (self.viewItem.mediaAlbumItems.count == 1) {
                // Honor the content aspect ratio for single media.
                ConversationMediaAlbumItem *mediaAlbumItem = self.viewItem.mediaAlbumItems.firstObject;
                if (mediaAlbumItem.mediaSize.width > 0 && mediaAlbumItem.mediaSize.height > 0) {
                    CGSize mediaSize = mediaAlbumItem.mediaSize;
                    CGFloat contentAspectRatio = mediaSize.width / mediaSize.height;
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
                    CGFloat shortSrcDimension = MIN(mediaSize.width, mediaSize.height);
                    CGFloat shortDstDimension = MIN(mediaWidth, mediaHeight);
                    if (shortDstDimension > kMinimumSize && shortDstDimension > shortSrcDimension) {
                        CGFloat factor = kMinimumSize / shortDstDimension;
                        mediaWidth *= factor;
                        mediaHeight *= factor;
                    }

                    result = CGSizeRound(CGSizeMake(mediaWidth, mediaHeight));
                }
            }
            break;
        case OWSMessageCellType_OversizeTextDownloading:
            // There's no way to predict the size of the oversize text,
            // so we just use a square bubble.
            result = CGSizeMake(maxMessageWidth, maxMessageWidth);
            break;
        case OWSMessageCellType_StickerMessage:
            OWSFailDebug(@"Stickers should not be rendered with this view.");
            result = CGSizeZero;
            break;
    }

    OWSAssertDebug(result.width <= maxMessageWidth);
    result.width = MIN(result.width, maxMessageWidth);

    return [NSValue valueWithCGSize:CGSizeCeil(result)];
}

- (nullable NSValue *)quotedMessageSize
{
    OWSAssertDebug(self.conversationStyle);
    OWSAssertDebug(self.conversationStyle.maxMessageWidth > 0);
    OWSAssertDebug(self.viewItem);
    OWSAssertDebug([self.viewItem.interaction isKindOfClass:[TSMessage class]]);

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

- (nullable NSValue *)actionButtonsSize
{
    OWSAssertDebug(self.conversationStyle);
    OWSAssertDebug(self.conversationStyle.maxMessageWidth > 0);

    if (self.cellType == OWSMessageCellType_ContactShare) {
        OWSAssertDebug(self.viewItem.contactShare);

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
        } else if (quotedMessageSize && self.viewItem.linkPreview) {
            cellSize.height += self.bodyMediaQuotedReplyVSpacing;
        }
    }

    if (self.viewItem.linkPreview) {
        CGSize linkPreviewSize = [self.linkPreviewView measureWithSentState:self.linkPreviewState];
        linkPreviewSize.width = MIN(linkPreviewSize.width, self.conversationStyle.maxMessageWidth);
        cellSize.width = MAX(cellSize.width, linkPreviewSize.width);
        cellSize.height += linkPreviewSize.height;
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

    OWSAssertDebug(cellSize.width > 0 && cellSize.height > 0);

    if (self.hasTapForMore) {
        cellSize.height += self.tapForMoreHeight + self.textViewVSpacing;
    }

    NSValue *_Nullable actionButtonsSize = [self actionButtonsSize];
    if (actionButtonsSize) {
        cellSize.width = MAX(cellSize.width, actionButtonsSize.CGSizeValue.width);
        cellSize.height += actionButtonsSize.CGSizeValue.height;
    }

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
    OWSAssertDebug([self.viewItem.interaction isKindOfClass:[TSMessage class]]);

    TSMessage *message = (TSMessage *)self.viewItem.interaction;
    return [self.conversationStyle bubbleTextColorWithMessage:message];
}

- (void)prepareForReuse
{
    [NSLayoutConstraint deactivateConstraints:self.viewConstraints];
    self.viewConstraints = [NSMutableArray new];

    self.delegate = nil;

    [self.bodyTextView removeFromSuperview];
    self.bodyTextView.text = nil;
    self.bodyTextView.attributedText = nil;
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

    [self.linkPreviewView removeFromSuperview];
    self.linkPreviewView.state = nil;
}

#pragma mark - Gestures

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
            [self handleMediaTapGesture:locationInMessageBubble];
            break;
        case OWSMessageGestureLocation_QuotedReply:
            if (self.viewItem.quotedReply) {
                [self.delegate didTapConversationItem:self.viewItem quotedReply:self.viewItem.quotedReply];
            } else {
                OWSFailDebug(@"Missing quoted message.");
            }
            break;
        case OWSMessageGestureLocation_LinkPreview:
            if (self.viewItem.linkPreview) {
                [self.delegate didTapConversationItem:self.viewItem linkPreview:self.viewItem.linkPreview];
            } else {
                OWSFailDebug(@"Missing link preview.");
            }
            break;
        case OWSMessageGestureLocation_Sticker:
            OWSFailDebug(@"Unexpected value.");
            break;
    }
}

- (void)handleMediaTapGesture:(CGPoint)locationInMessageBubble
{
    OWSAssertDebug(self.delegate);

    if (self.viewItem.attachmentPointer && self.viewItem.attachmentPointer.state == TSAttachmentPointerStateFailed) {
        [self.delegate didTapFailedIncomingAttachment:self.viewItem];
        return;
    }

    switch (self.cellType) {
        case OWSMessageCellType_Unknown:
        case OWSMessageCellType_TextOnlyMessage:
        case OWSMessageCellType_OversizeTextDownloading:
            break;
        case OWSMessageCellType_Audio:
            if (self.viewItem.attachmentStream) {
                [self.delegate didTapAudioViewItem:self.viewItem attachmentStream:self.viewItem.attachmentStream];
            }
            return;
        case OWSMessageCellType_GenericAttachment:
            if (self.viewItem.attachmentStream) {
                [AttachmentSharing showShareUIForAttachment:self.viewItem.attachmentStream];
            }
            break;
        case OWSMessageCellType_ContactShare:
            [self.delegate didTapContactShareViewItem:self.viewItem];
            break;
        case OWSMessageCellType_MediaMessage: {
            OWSAssertDebug(self.bodyMediaView);
            OWSAssertDebug(self.viewItem.mediaAlbumItems.count > 0);

            if (![self.bodyMediaView isKindOfClass:[OWSMediaAlbumCellView class]]) {
                OWSFailDebug(@"Unexpected body media view: %@", self.bodyMediaView.class);
                return;
            }
            OWSMediaAlbumCellView *_Nullable mediaAlbumCellView = (OWSMediaAlbumCellView *)self.bodyMediaView;
            CGPoint location = [self convertPoint:locationInMessageBubble toView:self.bodyMediaView];
            OWSConversationMediaView *_Nullable mediaView = [mediaAlbumCellView mediaViewForLocation:location];
            if (!mediaView) {
                OWSFailDebug(@"Missing media view.");
                return;
            }

            if ([mediaAlbumCellView isMoreItemsViewWithMediaView:mediaView]
                && self.viewItem.mediaAlbumHasFailedAttachment) {
                [self.delegate didTapFailedIncomingAttachment:self.viewItem];
                return;
            }

            TSAttachment *attachment = mediaView.attachment;
            if ([attachment isKindOfClass:[TSAttachmentPointer class]]) {
                TSAttachmentPointer *attachmentPointer = (TSAttachmentPointer *)attachment;
                if (attachmentPointer.state == TSAttachmentPointerStateFailed) {
                    // Treat the tap as a "retry" tap if the user taps on a failed download.
                    [self.delegate didTapFailedIncomingAttachment:self.viewItem];
                    return;
                }
            } else if (![attachment isKindOfClass:[TSAttachmentStream class]]) {
                OWSLogWarn(@"Media attachment not yet downloaded.");
                return;
            }
            TSAttachmentStream *attachmentStream = (TSAttachmentStream *)attachment;
            [self.delegate didTapImageViewItem:self.viewItem attachmentStream:attachmentStream imageView:mediaView];
            break;
        }
        case OWSMessageCellType_StickerMessage:
            OWSFailDebug(@"Stickers should not be rendered with this view.");
            break;
    }
}

- (void)handlePanGesture:(UIPanGestureRecognizer *)sender
{
    if (sender.state != UIGestureRecognizerStateChanged) {
        return;
    }

    CGPoint locationInMessageBubble = [sender locationInView:self];
    if ([self gestureLocationForLocation:locationInMessageBubble] == OWSMessageGestureLocation_Media) {
        [self handleMediaPanGesture:sender];
    }
}

- (void)handleMediaPanGesture:(UIPanGestureRecognizer *)sender
{
    OWSAssertDebug(self.delegate);

    if (self.cellType == OWSMessageCellType_Audio && self.viewItem.attachmentStream) {
        if ([self.bodyMediaView isKindOfClass:[OWSAudioMessageView class]]) {
            OWSAudioMessageView *_Nullable audioMessageView = (OWSAudioMessageView *)self.bodyMediaView;

            CGPoint locationInAudioView = [sender locationInView:audioMessageView];

            if ([audioMessageView canScrubToLocation:locationInAudioView]) {
                NSTimeInterval scrubbedTime = [audioMessageView scrubToLocation:locationInAudioView];
                [self.delegate didScrubAudioViewItem:self.viewItem
                                              toTime:scrubbedTime
                                    attachmentStream:self.viewItem.attachmentStream];
            }
        }
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

    if (self.viewItem.linkPreview) {
        CGPoint location = [self convertPoint:locationInMessageBubble toView:self.linkPreviewView];
        if (CGRectContainsPoint(self.linkPreviewView.bounds, location)) {
            return OWSMessageGestureLocation_LinkPreview;
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

- (void)didCancelQuotedReply
{
    OWSFailDebug(@"Sent quoted replies should not be cancellable.");
}

#pragma mark - OWSContactShareButtonsViewDelegate

- (void)didTapSendMessageToContactShare:(ContactShareViewModel *)contactShare
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(contactShare);

    [self.delegate didTapSendMessageToContactShare:contactShare];
}

- (void)didTapSendInviteToContactShare:(ContactShareViewModel *)contactShare
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(contactShare);

    [self.delegate didTapSendInviteToContactShare:contactShare];
}

- (void)didTapShowAddToContactUIForContactShare:(ContactShareViewModel *)contactShare
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(contactShare);

    [self.delegate didTapShowAddToContactUIForContactShare:contactShare];
}

#pragma mark - UITextViewDelegate

- (BOOL)textView:(UITextView *)textView
    shouldInteractWithURL:(NSURL *)url
                  inRange:(NSRange)characterRange
              interaction:(UITextItemInteraction)interaction
{
    return [self shouldInteractWithURL:url];
}

- (BOOL)textView:(UITextView *)textView shouldInteractWithURL:(NSURL *)url inRange:(NSRange)characterRange
{
    return [self shouldInteractWithURL:url];
}

- (BOOL)shouldInteractWithURL:(NSURL *)url
{
    if (![self.tsAccountManager isRegistered]) {
        return YES;
    }
    if (![StickerPackInfo isStickerPackShareUrl:url]) {
        return YES;
    }
    StickerPackInfo *_Nullable stickerPackInfo = [StickerPackInfo parseStickerPackShareUrl:url];
    if (stickerPackInfo == nil) {
        OWSFailDebug(@"Invalid URL: %@", url);
        return YES;
    }

    [self.delegate didTapStickerPack:stickerPackInfo];

    return NO;
}

@end

NS_ASSUME_NONNULL_END
