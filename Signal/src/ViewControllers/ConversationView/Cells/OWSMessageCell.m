//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageCell.h"
#import "AttachmentSharing.h"
#import "AttachmentUploadView.h"
#import "ConversationViewItem.h"
#import "NSAttributedString+OWS.h"
#import "OWSAudioMessageView.h"
#import "OWSBubbleStrokeView.h"
#import "OWSBubbleView.h"
#import "OWSExpirationTimerView.h"
#import "OWSGenericAttachmentView.h"
#import "OWSMessageTextView.h"
#import "Signal-Swift.h"
#import "UIColor+OWS.h"
#import <JSQMessagesViewController/JSQMessagesTimestampFormatter.h>
#import <JSQMessagesViewController/UIColor+JSQMessages.h>
#import <SignalMessaging/UIView+OWS.h>

NS_ASSUME_NONNULL_BEGIN

CG_INLINE CGSize CGSizeCeil(CGSize size)
{
    return CGSizeMake((CGFloat)ceil(size.width), (CGFloat)ceil(size.height));
}

@interface OWSMessageCell ()

// The nullable properties are created as needed.
// The non-nullable properties are so frequently used that it's easier
// to always keep one around.

// The cell's contentView contains:
//
// * MessageView (message)
// * dateHeaderLabel (above message)
// * footerView (below message)
// * failedSendBadgeView ("trailing" beside message)

@property (nonatomic) OWSBubbleView *bubbleView;

@property (nonatomic) UILabel *dateHeaderLabel;
@property (nonatomic) OWSMessageTextView *bodyTextView;
@property (nonatomic) UILabel *quotedTextView;
@property (nonatomic, nullable) UIImageView *failedSendBadgeView;
@property (nonatomic) UIView *footerView;
@property (nonatomic) UILabel *footerLabel;
@property (nonatomic, nullable) OWSExpirationTimerView *expirationTimerView;

@property (nonatomic, nullable) UIView *lastBodyMediaView;

// Should lazy-load expensive view contents (images, etc.).
// Should do nothing if view is already loaded.
@property (nonatomic, nullable) dispatch_block_t loadCellContentBlock;
// Should unload all expensive view contents (images, etc.).
@property (nonatomic, nullable) dispatch_block_t unloadCellContentBlock;

@property (nonatomic, nullable) NSMutableArray<NSLayoutConstraint *> *viewConstraints;
@property (nonatomic) BOOL isPresentingMenuController;

@end

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
    OWSAssert(!self.bodyTextView);

    _viewConstraints = [NSMutableArray new];

    self.layoutMargins = UIEdgeInsetsZero;
    self.contentView.layoutMargins = UIEdgeInsetsZero;

    self.bubbleView = [OWSBubbleView new];
    self.bubbleView.layoutMargins = UIEdgeInsetsZero;
    [self.contentView addSubview:self.bubbleView];

    self.footerView = [UIView containerView];
    [self.contentView addSubview:self.footerView];

    self.dateHeaderLabel = [UILabel new];
    self.dateHeaderLabel.font = [UIFont ows_regularFontWithSize:12.f];
    self.dateHeaderLabel.textAlignment = NSTextAlignmentCenter;
    self.dateHeaderLabel.textColor = [UIColor lightGrayColor];
    [self.contentView addSubview:self.dateHeaderLabel];

    self.bodyTextView = [self newTextView];
    // Setting dataDetectorTypes is expensive.  Do it just once.
    self.bodyTextView.dataDetectorTypes
        = (UIDataDetectorTypeLink | UIDataDetectorTypeAddress | UIDataDetectorTypeCalendarEvent);

    self.quotedTextView = [UILabel new];
    self.quotedTextView.numberOfLines = 3;
    self.quotedTextView.lineBreakMode = NSLineBreakByWordWrapping;

    self.footerLabel = [UILabel new];
    self.footerLabel.font = [UIFont ows_regularFontWithSize:12.f];
    self.footerLabel.textColor = [UIColor lightGrayColor];
    [self.footerView addSubview:self.footerLabel];

    // Hide these views by default.
    self.bodyTextView.hidden = YES;
    self.quotedTextView.hidden = YES;
    self.dateHeaderLabel.hidden = YES;
    self.footerLabel.hidden = YES;

    [self.bubbleView autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:self.dateHeaderLabel];
    [self.footerView autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:self.bubbleView];

    [self.footerView autoPinEdgeToSuperviewEdge:ALEdgeBottom];
    [self.footerView autoPinWidthToSuperview];

    self.contentView.userInteractionEnabled = YES;

    UITapGestureRecognizer *tap =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTapGesture:)];
    [self.contentView addGestureRecognizer:tap];

    UILongPressGestureRecognizer *longPress =
        [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPressGesture:)];
    [self.contentView addGestureRecognizer:longPress];

    PanDirectionGestureRecognizer *panGesture = [[PanDirectionGestureRecognizer alloc]
        initWithDirection:(self.isRTL ? PanDirectionLeft : PanDirectionRight)target:self
                   action:@selector(handlePanGesture:)];
    [self addGestureRecognizer:panGesture];
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

+ (NSString *)cellReuseIdentifier
{
    return NSStringFromClass([self class]);
}

- (UIFont *)textMessageFont
{
    OWSAssert(DisplayableText.kMaxJumbomojiCount == 5);

    CGFloat basePointSize = [UIFont ows_dynamicTypeBodyFont].pointSize;
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

    return [UIFont ows_dynamicTypeBodyFont];
}

- (BOOL)shouldHaveFailedSendBadge
{
    if (![self.viewItem.interaction isKindOfClass:[TSOutgoingMessage class]]) {
        return NO;
    }
    TSOutgoingMessage *outgoingMessage = (TSOutgoingMessage *)self.viewItem.interaction;
    return outgoingMessage.messageState == TSOutgoingMessageStateUnsent;
}

- (UIImage *)failedSendBadge
{
    UIImage *image = [UIImage imageNamed:@"message_send_failure"];
    OWSAssert(image);
    OWSAssert(image.size.width == self.failedSendBadgeSize && image.size.height == self.failedSendBadgeSize);
    return image;
}

- (CGFloat)failedSendBadgeSize
{
    return 20.f;
}

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

- (BOOL)hasQuotedAttachment
{
    // This should always be valid for the appropriate cell types.
    OWSAssert(self.viewItem);

    return self.viewItem.hasQuotedAttachment;
}

- (BOOL)hasQuotedAttachmentThumbnail
{
    // This should always be valid for the appropriate cell types.
    OWSAssert(self.viewItem);

    return (self.viewItem.hasQuotedAttachment &&
        [TSAttachmentStream hasThumbnailForMimeType:self.viewItem.quotedAttachmentMimetype]);
}

- (nullable DisplayableText *)displayableQuotedText
{
    // This should always be valid for the appropriate cell types.
    OWSAssert(self.viewItem.displayableQuotedText);

    return self.viewItem.displayableQuotedText;
}

- (TSMessage *)message
{
    OWSAssert([self.viewItem.interaction isKindOfClass:[TSMessage class]]);

    return (TSMessage *)self.viewItem.interaction;
}

- (BOOL)hasNonImageBodyContent
{
    switch (self.cellType) {
        case OWSMessageCellType_Unknown:
        case OWSMessageCellType_TextMessage:
        case OWSMessageCellType_OversizeTextMessage:
        case OWSMessageCellType_GenericAttachment:
        case OWSMessageCellType_DownloadingAttachment:
            return YES;
        case OWSMessageCellType_StillImage:
        case OWSMessageCellType_AnimatedImage:
        case OWSMessageCellType_Audio:
        case OWSMessageCellType_Video:
            return self.hasBodyText;
    }
}

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
    }
}

#pragma mark - Load

- (void)loadForDisplay
{
    OWSAssert(self.viewItem);
    OWSAssert(self.viewItem.interaction);
    OWSAssert([self.viewItem.interaction isKindOfClass:[TSMessage class]]);
    OWSAssert(self.contentWidth > 0);

    CGSize bodyMediaContentSize = [self bodyMediaSizeForContentWidth:self.contentWidth];
    CGSize bodyTextContentSize = [self bodyTextSizeForContentWidth:self.contentWidth includeMargins:NO];

    // TODO: We might not need to hide it.
    self.bubbleView.hidden = NO;
    self.bubbleView.isOutgoing = self.isOutgoing;
    self.bubbleView.hideTail = self.viewItem.shouldHideBubbleTail;

    if (self.shouldHaveFailedSendBadge) {
        self.failedSendBadgeView = [UIImageView new];
        self.failedSendBadgeView.image =
            [self.failedSendBadge imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        self.failedSendBadgeView.tintColor = [UIColor ows_destructiveRedColor];
        [self.contentView addSubview:self.failedSendBadgeView];

        [self.viewConstraints addObjectsFromArray:@[
            [self.bubbleView autoPinLeadingToSuperviewMargin],
            [self.failedSendBadgeView autoPinLeadingToTrailingEdgeOfView:self.bubbleView],
            [self.failedSendBadgeView autoAlignAxis:ALAxisHorizontal toSameAxisOfView:self.bubbleView],
            [self.failedSendBadgeView autoPinTrailingToSuperviewMargin],
            [self.failedSendBadgeView autoSetDimension:ALDimensionWidth toSize:self.failedSendBadgeSize],
            [self.failedSendBadgeView autoSetDimension:ALDimensionHeight toSize:self.failedSendBadgeSize],
        ]];
    } else {
        [self.viewConstraints addObjectsFromArray:@[
            [self.bubbleView autoPinLeadingToSuperviewMargin],
            [self.bubbleView autoPinTrailingToSuperviewMargin],
        ]];
    }

    if ([self.viewItem.interaction isKindOfClass:[TSMessage class]] && self.hasNonImageBodyContent) {
        TSMessage *message = (TSMessage *)self.viewItem.interaction;
        self.bubbleView.bubbleColor = [self.bubbleFactory bubbleColorWithMessage:message];
    } else {
        // Media-only messages should have no background color; they will fill the bubble's bounds
        // and we don't want artifacts at the edges.
        self.bubbleView.bubbleColor = nil;
    }

    [self updateDateHeader];
    [self updateFooter];

    UIView *_Nullable lastSubview = nil;
    CGFloat bottomMargin = 0;

    if (self.isQuotedReply) {
        OWSAssert(!lastSubview);

        UIView *quotedMessageView = [self createQuotedMessageView];

        [self.bubbleView addSubview:quotedMessageView];

        CGFloat leadingMargin = self.quotedBubbleLeadingMargin;
        CGFloat trailingMargin = self.quotedBubbleTrailingMargin;

        [self.viewConstraints addObjectsFromArray:@[
            [quotedMessageView autoPinLeadingToSuperviewMarginWithInset:leadingMargin],
            [quotedMessageView autoPinTrailingToSuperviewMarginWithInset:trailingMargin],
        ]];

        if (lastSubview) {
            [self.viewConstraints addObject:[quotedMessageView autoPinEdge:ALEdgeTop
                                                                    toEdge:ALEdgeBottom
                                                                    ofView:lastSubview
                                                                withOffset:self.quotedMessageTopInset]];
        } else {
            [self.viewConstraints addObject:[quotedMessageView autoPinEdgeToSuperviewEdge:ALEdgeTop
                                                                                withInset:self.quotedMessageTopInset]];
        }
        lastSubview = quotedMessageView;
        bottomMargin = 0;

        [self.bubbleView logFrameLaterWithLabel:@"bubbleView"];
        [quotedMessageView logFrameLaterWithLabel:@"quotedMessageView"];

        // TODO: Consider stroking the quoted thumbnail.
    }

    UIView *_Nullable bodyMediaView = nil;
    BOOL bodyMediaViewHasGreedyWidth = NO;
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
            bodyMediaViewHasGreedyWidth = YES;
            break;
        case OWSMessageCellType_GenericAttachment:
            bodyMediaView = [self loadViewForGenericAttachment];
            bodyMediaViewHasGreedyWidth = YES;
            break;
        case OWSMessageCellType_DownloadingAttachment:
            bodyMediaView = [self loadViewForDownloadingAttachment];
            bodyMediaViewHasGreedyWidth = YES;
            break;
    }

    if (bodyMediaView) {
        OWSAssert(self.loadCellContentBlock);
        OWSAssert(self.unloadCellContentBlock);
        OWSAssert(!lastSubview);

        bodyMediaView.clipsToBounds = YES;

        self.lastBodyMediaView = bodyMediaView;
        bodyMediaView.userInteractionEnabled = NO;
        if (self.isMediaBeingSent) {
            bodyMediaView.layer.opacity = 0.75f;
        }

        [self.bubbleView addSubview:bodyMediaView];
        // This layout can lead to extreme cropping of media content,
        // e.g. a very tall portrait image + long caption.  The media
        // view will have "max width", so the image will be cropped to
        // roughly a square.
        // TODO: Myles is considering alternatives.
        [self.viewConstraints addObjectsFromArray:@[
            [bodyMediaView autoPinLeadingToSuperviewMarginWithInset:0],
            [bodyMediaView autoPinTrailingToSuperviewMarginWithInset:0],
        ]];
        // We need constraints to control the vertical sizing of media and text views, but we use
        // lower priority so that when a message only contains media it uses the exact bounds of
        // the message view.
        [NSLayoutConstraint
            autoSetPriority:UILayoutPriorityDefaultLow
             forConstraints:^{
                 [self.viewConstraints
                     addObject:[bodyMediaView autoSetDimension:ALDimensionHeight toSize:bodyMediaContentSize.height]];
             }];

        if (lastSubview) {
            [self.viewConstraints
                addObject:[bodyMediaView autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:lastSubview withOffset:0]];
        } else {
            [self.viewConstraints addObject:[bodyMediaView autoPinEdgeToSuperviewEdge:ALEdgeTop withInset:0]];
        }
        lastSubview = bodyMediaView;
        bottomMargin = 0;

        BOOL shouldStrokeMediaView = [bodyMediaView isKindOfClass:[UIImageView class]];
        if (shouldStrokeMediaView) {
            OWSBubbleStrokeView *bubbleStrokeView = [OWSBubbleStrokeView new];
            bubbleStrokeView.strokeThickness = 1.f;
            bubbleStrokeView.strokeColor = [UIColor colorWithWhite:0.f alpha:0.1f];
            bubbleStrokeView.bubbleView = self.bubbleView;

            [self.bubbleView addSubview:bubbleStrokeView];
            [bubbleStrokeView autoPinEdge:ALEdgeTop toEdge:ALEdgeTop ofView:bodyMediaView];
            [bubbleStrokeView autoPinEdge:ALEdgeBottom toEdge:ALEdgeBottom ofView:bodyMediaView];
            [bubbleStrokeView autoPinEdge:ALEdgeLeft toEdge:ALEdgeLeft ofView:bodyMediaView];
            [bubbleStrokeView autoPinEdge:ALEdgeRight toEdge:ALEdgeRight ofView:bodyMediaView];
            self.bubbleView.bubbleStrokeView = bubbleStrokeView;
            OWSAssert(self.bubbleView.bubbleStrokeView);
        }
    }

    OWSMessageTextView *_Nullable bodyTextView = nil;
    // We render malformed messages as "empty text" messages,
    // so create a text view if there is no body media view.
    if (self.hasBodyText || !bodyMediaView) {
        bodyTextView = [self createBodyTextViewIfNecessary];
    }
    if (bodyTextView) {
        [self.bubbleView addSubview:bodyTextView];
        [self.viewConstraints addObjectsFromArray:@[
            [bodyTextView autoPinLeadingToSuperviewMarginWithInset:self.textLeadingMargin],
            [bodyTextView autoPinTrailingToSuperviewMarginWithInset:self.textTrailingMargin],
        ]];
        // We need constraints to control the vertical sizing of media and text views, but we use
        // lower priority so that when a message only contains media it uses the exact bounds of
        // the message view.
        [NSLayoutConstraint
            autoSetPriority:UILayoutPriorityDefaultLow
             forConstraints:^{
                 [self.viewConstraints
                     addObject:[bodyTextView autoSetDimension:ALDimensionHeight toSize:bodyTextContentSize.height]];
             }];
        if (lastSubview) {
            [self.viewConstraints addObject:[bodyTextView autoPinEdge:ALEdgeTop
                                                               toEdge:ALEdgeBottom
                                                               ofView:lastSubview
                                                           withOffset:self.textTopMargin]];
        } else {
            [self.viewConstraints
                addObject:[bodyTextView autoPinEdgeToSuperviewEdge:ALEdgeTop withInset:self.textTopMargin]];
        }
        lastSubview = bodyTextView;
        bottomMargin = self.textBottomMargin;
    }

    UIView *_Nullable tapForMoreLabel = [self createTapForMoreLabelIfNecessary];
    if (tapForMoreLabel) {
        OWSAssert(lastSubview);
        OWSAssert(lastSubview == bodyTextView);
        [self.bubbleView addSubview:tapForMoreLabel];
        [self.viewConstraints addObjectsFromArray:@[
            [tapForMoreLabel autoPinLeadingToSuperviewMarginWithInset:self.textLeadingMargin],
            [tapForMoreLabel autoPinTrailingToSuperviewMarginWithInset:self.textTrailingMargin],
            [tapForMoreLabel autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:lastSubview],
            [tapForMoreLabel autoSetDimension:ALDimensionHeight toSize:self.tapForMoreHeight],
        ]];
        lastSubview = tapForMoreLabel;
        bottomMargin = self.textBottomMargin;
    }

    OWSAssert(lastSubview);
    [self.viewConstraints addObjectsFromArray:@[
        [lastSubview autoPinEdgeToSuperviewEdge:ALEdgeBottom withInset:bottomMargin],
    ]];

    [self ensureMediaLoadState];
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

    if (self.viewItem.didCellMediaFailToLoad) {
        return nil;
    }

    NSCache *cellMediaCache = self.delegate.cellMediaCache;
    OWSAssert(cellMediaCache);

    id _Nullable cellMedia = [cellMediaCache objectForKey:cacheKey];
    if (cellMedia) {
        DDLogVerbose(@"%@ cell media cache hit", self.logTag);
        return cellMedia;
    }
    cellMedia = loadCellMediaBlock();
    if (cellMedia) {
        DDLogVerbose(@"%@ cell media cache miss", self.logTag);
        if (!shouldSkipCache) {
            [cellMediaCache setObject:cellMedia forKey:cacheKey];
        }
    } else {
        DDLogError(@"%@ Failed to load cell media: %@", [self logTag], [self.attachmentStream mediaURL]);
        self.viewItem.didCellMediaFailToLoad = YES;
        // TODO: Do we need to hide/remove the media view?
        [self showAttachmentErrorViewWithMediaView:mediaView];
    }
    return cellMedia;
}

// * If cell is visible, lazy-load (expensive) view contents.
// * If cell is not visible, eagerly unload view contents.
- (void)ensureMediaLoadState
{
    if (!self.isCellVisible) {
        // Eagerly unload.
        if (self.unloadCellContentBlock) {
            self.unloadCellContentBlock();
        }
        return;
    } else {
        // Lazy load.
        if (self.loadCellContentBlock) {
            self.loadCellContentBlock();
        }
    }
}

- (void)updateDateHeader
{
    OWSAssert(self.contentWidth > 0);

    static NSDateFormatter *dateHeaderDateFormatter = nil;
    static NSDateFormatter *dateHeaderTimeFormatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dateHeaderDateFormatter = [NSDateFormatter new];
        [dateHeaderDateFormatter setLocale:[NSLocale currentLocale]];
        [dateHeaderDateFormatter setDoesRelativeDateFormatting:YES];
        [dateHeaderDateFormatter setDateStyle:NSDateFormatterMediumStyle];
        [dateHeaderDateFormatter setTimeStyle:NSDateFormatterNoStyle];
        
        dateHeaderTimeFormatter = [NSDateFormatter new];
        [dateHeaderTimeFormatter setLocale:[NSLocale currentLocale]];
        [dateHeaderTimeFormatter setDoesRelativeDateFormatting:YES];
        [dateHeaderTimeFormatter setDateStyle:NSDateFormatterNoStyle];
        [dateHeaderTimeFormatter setTimeStyle:NSDateFormatterShortStyle];
    });

    if (self.viewItem.shouldShowDate) {
        NSDate *date = self.viewItem.interaction.dateForSorting;
        NSString *dateString = [dateHeaderDateFormatter stringFromDate:date];
        NSString *timeString = [dateHeaderTimeFormatter stringFromDate:date];

        NSAttributedString *attributedText = [NSAttributedString new];
        attributedText = [attributedText rtlSafeAppend:dateString
                                            attributes:@{
                                                NSFontAttributeName : self.dateHeaderDateFont,
                                                NSForegroundColorAttributeName : [UIColor lightGrayColor],
                                            }
                                         referenceView:self];
        attributedText = [attributedText rtlSafeAppend:@" "
                                            attributes:@{
                                                NSFontAttributeName : self.dateHeaderDateFont,
                                            }
                                         referenceView:self];
        attributedText = [attributedText rtlSafeAppend:timeString
                                            attributes:@{
                                                NSFontAttributeName : self.dateHeaderTimeFont,
                                                NSForegroundColorAttributeName : [UIColor lightGrayColor],
                                            }
                                         referenceView:self];

        self.dateHeaderLabel.attributedText = attributedText;
        self.dateHeaderLabel.hidden = NO;

        [self.viewConstraints addObjectsFromArray:@[
            // Date headers should be visually centered within the conversation view,
            // so they need to extend outside the cell's boundaries.
            [self.dateHeaderLabel autoSetDimension:ALDimensionWidth toSize:self.contentWidth],
            (self.isIncoming ? [self.dateHeaderLabel autoPinEdgeToSuperviewEdge:ALEdgeLeading]
                             : [self.dateHeaderLabel autoPinEdgeToSuperviewEdge:ALEdgeTrailing]),
            [self.dateHeaderLabel autoPinEdgeToSuperviewEdge:ALEdgeTop],
            [self.dateHeaderLabel autoSetDimension:ALDimensionHeight toSize:self.dateHeaderHeight],
        ]];
    } else {
        self.dateHeaderLabel.hidden = YES;
        [self.viewConstraints addObjectsFromArray:@[
            [self.dateHeaderLabel autoSetDimension:ALDimensionHeight toSize:0],
            [self.dateHeaderLabel autoPinEdgeToSuperviewEdge:ALEdgeTop],
        ]];
    }
}

- (CGFloat)footerHeight
{
    BOOL showFooter = NO;

    BOOL hasExpirationTimer = self.message.shouldStartExpireTimer;

    if (hasExpirationTimer) {
        showFooter = YES;
    } else if (self.isOutgoing) {
        showFooter = !self.viewItem.shouldHideRecipientStatus;
    } else if (self.viewItem.isGroupThread) {
        showFooter = YES;
    } else {
        showFooter = NO;
    }

    return (showFooter ? (CGFloat)ceil(MAX(kExpirationTimerViewSize, self.footerLabel.font.lineHeight)) : 0.f);
}

- (void)updateFooter
{
    OWSAssert(self.viewItem.interaction.interactionType == OWSInteractionType_IncomingMessage
        || self.viewItem.interaction.interactionType == OWSInteractionType_OutgoingMessage);

    TSMessage *message = self.message;
    BOOL hasExpirationTimer = message.shouldStartExpireTimer;
    NSAttributedString *attributedText = nil;
    if (self.isOutgoing) {
        if (!self.viewItem.shouldHideRecipientStatus || hasExpirationTimer) {
            TSOutgoingMessage *outgoingMessage = (TSOutgoingMessage *)message;
            NSString *statusMessage =
                [MessageRecipientStatusUtils statusMessageWithOutgoingMessage:outgoingMessage referenceView:self];
            attributedText = [[NSAttributedString alloc] initWithString:statusMessage attributes:@{}];
        }
    } else if (self.viewItem.isGroupThread) {
        TSIncomingMessage *incomingMessage = (TSIncomingMessage *)self.viewItem.interaction;
        attributedText = [self.delegate attributedContactOrProfileNameForPhoneIdentifier:incomingMessage.authorId];
    }
    
    if (!hasExpirationTimer &&
        !attributedText) {
        self.footerLabel.hidden = YES;
        [self.viewConstraints addObjectsFromArray:@[
            [self.footerView autoSetDimension:ALDimensionHeight toSize:0],
        ]];
        return;
    }

    if (hasExpirationTimer) {
        uint64_t expirationTimestamp = message.expiresAt;
        uint32_t expiresInSeconds = message.expiresInSeconds;
        self.expirationTimerView = [[OWSExpirationTimerView alloc] initWithExpiration:expirationTimestamp
                                                               initialDurationSeconds:expiresInSeconds];
        [self.footerView addSubview:self.expirationTimerView];
    }
    if (attributedText) {
        self.footerLabel.attributedText = attributedText;
        self.footerLabel.hidden = NO;
    }

    if (hasExpirationTimer &&
        attributedText) {
        [self.viewConstraints addObjectsFromArray:@[
            [self.expirationTimerView autoVCenterInSuperview],
            [self.footerLabel autoVCenterInSuperview],
            (self.isIncoming ? [self.expirationTimerView autoPinLeadingToSuperviewMargin]
                             : [self.expirationTimerView autoPinTrailingToSuperviewMargin]),
            (self.isIncoming ? [self.footerLabel autoPinLeadingToTrailingEdgeOfView:self.expirationTimerView offset:0.f]
                             : [self.footerLabel autoPinTrailingToLeadingEdgeOfView:self.expirationTimerView offset:0.f]),
            [self.footerView autoSetDimension:ALDimensionHeight toSize:self.footerHeight],
        ]];
    } else if (hasExpirationTimer) {
        [self.viewConstraints addObjectsFromArray:@[
            [self.expirationTimerView autoVCenterInSuperview],
            (self.isIncoming ? [self.expirationTimerView autoPinLeadingToSuperviewMargin]
                             : [self.expirationTimerView autoPinTrailingToSuperviewMargin]),
            [self.footerView autoSetDimension:ALDimensionHeight toSize:self.footerHeight],
        ]];
    } else if (attributedText) {
        [self.viewConstraints addObjectsFromArray:@[
            [self.footerLabel autoVCenterInSuperview],
            (self.isIncoming ? [self.footerLabel autoPinLeadingToSuperviewMargin]
                             : [self.footerLabel autoPinTrailingToSuperviewMargin]),
            [self.footerView autoSetDimension:ALDimensionHeight toSize:self.footerHeight],
        ]];
    } else {
        OWSFail(@"%@ Cell unexpectedly has neither expiration timer nor footer text.", self.logTag);
    }
}

- (UIFont *)dateHeaderDateFont
{
    return [UIFont boldSystemFontOfSize:12.0f];
}

- (UIFont *)dateHeaderTimeFont
{
    return [UIFont systemFontOfSize:12.0f];
}

- (UILabel *)createQuotedTextView
{
    self.quotedTextView.hidden = NO;
    self.quotedTextView.text = self.displayableQuotedText.displayText;
    self.quotedTextView.textColor = self.quotedTextColor;

    // Honor dynamic type in the message bodies.
    self.quotedTextView.font = self.textMessageFont;
    return self.quotedTextView;
}

- (OWSMessageTextView *)createBodyTextViewIfNecessary
{
    BOOL shouldIgnoreEvents = NO;
    if (self.viewItem.interaction.interactionType == OWSInteractionType_OutgoingMessage) {
        // Ignore taps on links in outgoing messages that haven't been sent yet, as
        // this interferes with "tap to retry".
        TSOutgoingMessage *outgoingMessage = (TSOutgoingMessage *)self.viewItem.interaction;
        shouldIgnoreEvents = outgoingMessage.messageState != TSOutgoingMessageStateSentToService;
    }
    [self.class loadForTextDisplay:self.bodyTextView
                              text:self.displayableBodyText.displayText
                         textColor:self.bodyTextColor
                              font:self.textMessageFont
                shouldIgnoreEvents:shouldIgnoreEvents];
    return self.bodyTextView;
}

+ (void)loadForTextDisplay:(OWSMessageTextView *)textView
                      text:(NSString *)text
                 textColor:(UIColor *)textColor
                      font:(UIFont *)font
        shouldIgnoreEvents:(BOOL)shouldIgnoreEvents
{
    textView.hidden = NO;
    textView.text = text;
    textView.textColor = textColor;

    // Honor dynamic type in the message bodies.
    textView.font = font;
    textView.linkTextAttributes = @{
        NSForegroundColorAttributeName : textColor,
        NSUnderlineStyleAttributeName : @(NSUnderlineStyleSingle | NSUnderlinePatternSolid)
    };
    textView.shouldIgnoreEvents = shouldIgnoreEvents;
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

- (UIView *)createQuotedMessageView
{
    OWSAssert(self.isQuotedReply);

    UIView *quotedMessageView = [UIView containerView];
    quotedMessageView.userInteractionEnabled = NO;
    quotedMessageView.clipsToBounds = YES;
    // TODO:
    quotedMessageView.layer.cornerRadius = 3.f;
    quotedMessageView.backgroundColor = [UIColor colorWithRGBHex:0xe2f7fa];

    UIView *quoteStripView = [UIView containerView];
    quoteStripView.backgroundColor = (self.isIncoming ? [UIColor whiteColor] : [UIColor colorWithRGBHex:0x007884]);
    quoteStripView.userInteractionEnabled = NO;
    [quotedMessageView addSubview:quoteStripView];
    [quoteStripView autoPinHeightToSuperview];
    [quoteStripView autoPinLeadingToSuperviewMargin];
    [quoteStripView autoSetDimension:ALDimensionWidth toSize:self.quotedReplyStripeThickness];

    UIView *_Nullable quotedThumbnailView = nil;
    if (self.hasQuotedAttachmentThumbnail) {
        // TODO:
        quotedThumbnailView = [UIView containerView];
        quotedThumbnailView.userInteractionEnabled = NO;
        quotedThumbnailView.backgroundColor = [UIColor redColor];
        [quotedMessageView addSubview:quotedThumbnailView];
        [quotedThumbnailView autoPinTopToSuperviewMargin];
        [quotedThumbnailView autoPinTrailingToSuperviewMargin];
        [quotedThumbnailView autoSetDimension:ALDimensionWidth toSize:self.quotedThumbnailSize];
        [quotedThumbnailView autoSetDimension:ALDimensionHeight toSize:self.quotedThumbnailSize];
    }

    OWSContactsManager *contactsManager = Environment.current.contactsManager;
    NSString *quotedAuthor = [contactsManager displayNameForPhoneIdentifier:self.viewItem.quotedRecipientId];

    UILabel *quotedAuthorLabel = [UILabel new];
    quotedAuthorLabel.text = quotedAuthor;
    quotedAuthorLabel.font = self.quotedAuthorFont;
    quotedAuthorLabel.textColor
        = (self.isIncoming ? [UIColor colorWithRGBHex:0xd84315] : [UIColor colorWithRGBHex:0x007884]);
    quotedAuthorLabel.numberOfLines = 1;
    quotedAuthorLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [quotedMessageView addSubview:quotedAuthorLabel];
    [quotedAuthorLabel autoPinEdgeToSuperviewEdge:ALEdgeTop withInset:self.quotedContentTopInset];
    [quotedAuthorLabel autoPinLeadingToTrailingEdgeOfView:quoteStripView offset:self.quotedReplyStripeHSpacing];
    if (quotedThumbnailView) {
        [quotedAuthorLabel autoPinTrailingToEdgeOfView:quotedThumbnailView offset:self.quotedThumbnailHSpacing];
    } else {
        [quotedAuthorLabel autoPinTrailingToSuperviewMarginWithInset:self.quotedContentTrailingMargin];
    }

    if (self.hasQuotedText) {
        UILabel *quotedTextView = [self createQuotedTextView];

        [quotedMessageView addSubview:quotedTextView];
        [quotedTextView autoPinEdge:ALEdgeTop
                             toEdge:ALEdgeBottom
                             ofView:quotedAuthorLabel
                         withOffset:self.quotedAuthorBottomSpacing];
        [quotedTextView autoPinLeadingToTrailingEdgeOfView:quoteStripView offset:self.quotedReplyStripeHSpacing];
        if (quotedThumbnailView) {
            [quotedTextView autoPinLeadingToTrailingEdgeOfView:quotedThumbnailView offset:self.quotedThumbnailHSpacing];
        } else {
            [quotedTextView autoPinTrailingToSuperviewMarginWithInset:self.quotedContentTrailingMargin];
        }
        [quotedTextView autoPinBottomToSuperviewMarginWithInset:self.quotedContentBottomInset];
    }

    return quotedMessageView;
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
    [self addAttachmentUploadViewIfNecessary:stillImageView];

    __weak OWSMessageCell *weakSelf = self;
    self.loadCellContentBlock = ^{
        OWSMessageCell *strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        OWSCAssert(strongSelf.lastBodyMediaView == stillImageView);
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
        OWSMessageCell *strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        OWSCAssert(strongSelf.lastBodyMediaView == stillImageView);
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
    [self addAttachmentUploadViewIfNecessary:animatedImageView];

    __weak OWSMessageCell *weakSelf = self;
    self.loadCellContentBlock = ^{
        OWSMessageCell *strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        OWSCAssert(strongSelf.lastBodyMediaView == animatedImageView);
        if (animatedImageView.image) {
            return;
        }
        animatedImageView.image = [strongSelf tryToLoadCellMedia:^{
            OWSCAssert([strongSelf.attachmentStream isAnimated]);

            NSString *_Nullable filePath = [strongSelf.attachmentStream filePath];
            YYImage *_Nullable animatedImage = nil;
            if (filePath && [NSData ows_isValidImageAtPath:filePath]) {
                animatedImage = [YYImage imageWithContentsOfFile:filePath];
            }
            return animatedImage;
        }
                                                       mediaView:animatedImageView
                                                        cacheKey:strongSelf.attachmentStream.uniqueId
                                                 shouldSkipCache:NO];
    };
    self.unloadCellContentBlock = ^{
        OWSMessageCell *strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        OWSCAssert(strongSelf.lastBodyMediaView == animatedImageView);
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
                                                                                   viewItem:self.viewItem];
    self.viewItem.lastAudioMessageView = audioMessageView;
    [audioMessageView createContents];
    [self addAttachmentUploadViewIfNecessary:audioMessageView];

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
    [self addAttachmentUploadViewIfNecessary:stillImageView
                     attachmentStateCallback:^(BOOL isAttachmentReady) {
                         videoPlayButton.hidden = !isAttachmentReady;
                     }];

    __weak OWSMessageCell *weakSelf = self;
    self.loadCellContentBlock = ^{
        OWSMessageCell *strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        OWSCAssert(strongSelf.lastBodyMediaView == stillImageView);
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
        OWSMessageCell *strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        OWSCAssert(strongSelf.lastBodyMediaView == stillImageView);
        stillImageView.image = nil;
    };

    return stillImageView;
}

- (UIView *)loadViewForGenericAttachment
{
    OWSAssert(self.viewItem.attachmentStream);
    OWSGenericAttachmentView *attachmentView =
        [[OWSGenericAttachmentView alloc] initWithAttachment:self.attachmentStream isIncoming:self.isIncoming];
    [attachmentView createContents];
    [self addAttachmentUploadViewIfNecessary:attachmentView];

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

    UIView *customView = [UIView new];
    switch (self.attachmentPointer.state) {
        case TSAttachmentPointerStateEnqueued:
            customView.backgroundColor
                = (self.isIncoming ? [UIColor jsq_messageBubbleLightGrayColor] : [UIColor ows_fadedBlueColor]);
            break;
        case TSAttachmentPointerStateDownloading:
            customView.backgroundColor
                = (self.isIncoming ? [UIColor jsq_messageBubbleLightGrayColor] : [UIColor ows_fadedBlueColor]);
            break;
        case TSAttachmentPointerStateFailed:
            customView.backgroundColor = [UIColor grayColor];
            break;
    }

    AttachmentPointerView *attachmentPointerView =
        [[AttachmentPointerView alloc] initWithAttachmentPointer:self.attachmentPointer isIncoming:self.isIncoming];
    [customView addSubview:attachmentPointerView];
    [attachmentPointerView autoPinWidthToSuperviewWithMargin:20.f];
    [attachmentPointerView autoVCenterInSuperview];

    self.loadCellContentBlock = ^{
        // Do nothing.
    };
    self.unloadCellContentBlock = ^{
        // Do nothing.
    };

    return customView;
}

- (void)addAttachmentUploadViewIfNecessary:(UIView *)attachmentView
{
    [self addAttachmentUploadViewIfNecessary:attachmentView
                     attachmentStateCallback:^(BOOL isAttachmentReady){
                     }];
}

- (void)addAttachmentUploadViewIfNecessary:(UIView *)attachmentView
                   attachmentStateCallback:(AttachmentStateBlock)attachmentStateCallback
{
    OWSAssert(attachmentView);
    OWSAssert(attachmentStateCallback);
    OWSAssert(self.attachmentStream);

    if (self.isOutgoing) {
        if (!self.attachmentStream.isUploaded) {
            AttachmentUploadView *attachmentUploadView =
                [[AttachmentUploadView alloc] initWithAttachment:self.attachmentStream
                                         attachmentStateCallback:attachmentStateCallback];
            [attachmentView addSubview:attachmentUploadView];
            [attachmentUploadView autoPinToSuperviewEdges];
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
- (CGSize)bodyTextSizeForContentWidth:(int)contentWidth includeMargins:(BOOL)includeMargins
{
    if (!self.hasBodyText) {
        return CGSizeZero;
    }

    BOOL isRTL = self.isRTL;
    CGFloat leftMargin = isRTL ? self.textTrailingMargin : self.textLeadingMargin;
    CGFloat rightMargin = isRTL ? self.textLeadingMargin : self.textTrailingMargin;

    const int maxMessageWidth = [self maxMessageWidthForContentWidth:contentWidth];
    const int maxTextWidth = (int)floor(maxMessageWidth - (leftMargin + rightMargin));

    self.bodyTextView.text = self.displayableBodyText.displayText;
    // Honor dynamic type in the message bodies.
    self.bodyTextView.font = [self textMessageFont];
    CGSize textSize = CGSizeCeil([self.bodyTextView sizeThatFits:CGSizeMake(maxTextWidth, CGFLOAT_MAX)]);
    CGSize textViewSize = textSize;

    if (includeMargins) {
        textViewSize.width += leftMargin + rightMargin;
        textViewSize.height += self.textTopMargin + self.textBottomMargin;
    }

    return CGSizeCeil(textViewSize);
}

- (CGSize)bodyMediaSizeForContentWidth:(int)contentWidth
{
    const int maxMessageWidth = [self maxMessageWidthForContentWidth:contentWidth];

    switch (self.cellType) {
        case OWSMessageCellType_Unknown:
        case OWSMessageCellType_TextMessage:
        case OWSMessageCellType_OversizeTextMessage: {
            return CGSizeZero;
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
            CGFloat mediaWidth = (CGFloat)round(maxMediaHeight * contentAspectRatio);
            CGFloat mediaHeight = (CGFloat)round(maxMediaHeight);
            if (mediaWidth > maxMediaWidth) {
                mediaWidth = (CGFloat)round(maxMediaWidth);
                mediaHeight = (CGFloat)round(maxMediaWidth / contentAspectRatio);
            }
            return CGSizeMake(mediaWidth, mediaHeight);
        }
        case OWSMessageCellType_Audio:
            return CGSizeMake(maxMessageWidth, OWSAudioMessageView.bubbleHeight);
        case OWSMessageCellType_GenericAttachment:
            return CGSizeMake(maxMessageWidth, [OWSGenericAttachmentView bubbleHeight]);
        case OWSMessageCellType_DownloadingAttachment:
            return CGSizeMake(200, 90);
    }
}

- (int)maxMessageWidthForContentWidth:(int)contentWidth
{
    return (int)floor(contentWidth * 0.8f);
}

- (CGSize)quotedMessageSizeForViewWidth:(int)viewWidth
                           contentWidth:(int)contentWidth
                         includeMargins:(BOOL)includeMargins
{
    OWSAssert(self.viewItem);
    OWSAssert([self.viewItem.interaction isKindOfClass:[TSMessage class]]);

    CGSize result = CGSizeZero;

    if (!self.isQuotedReply) {
        return result;
    }

    result.width += self.quotedMessageHInset;
    result.width += self.quotedReplyStripeThickness;
    result.width += self.quotedReplyStripeHSpacing;

    result.height += self.quotedMessageTopInset;

    CGFloat thumbnailHeight = 0.f;
    if (self.hasQuotedAttachmentThumbnail) {
        result.width += self.quotedThumbnailHSpacing;
        result.width += self.quotedThumbnailSize;

        thumbnailHeight = self.quotedThumbnailSize;
    } else {
        result.width += self.quotedContentTrailingMargin;
    }

    result.width += self.quotedMessageHInset;

    // Once we've determined everything _except_ the size of the text
    // content (i.e. the quoted author and the quoted text (if any)),
    // we can determine the size of the text content.
    const int maxMessageWidth = [self maxMessageWidthForContentWidth:contentWidth];
    CGFloat maxTextWidth = (maxMessageWidth - (self.textTrailingMargin + self.textLeadingMargin + result.width));
    CGFloat textWidth = 0.f;

    // Author
    {
        OWSContactsManager *contactsManager = Environment.current.contactsManager;
        NSString *quotedAuthor = [contactsManager displayNameForPhoneIdentifier:self.viewItem.quotedRecipientId];

        UILabel *quotedAuthorLabel = [UILabel new];
        quotedAuthorLabel.text = quotedAuthor;
        quotedAuthorLabel.font = self.quotedAuthorFont;
        quotedAuthorLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        quotedAuthorLabel.numberOfLines = 1;

        CGSize quotedAuthorSize = CGSizeCeil([quotedAuthorLabel sizeThatFits:CGSizeMake(maxTextWidth, CGFLOAT_MAX)]);

        textWidth = MAX(textWidth, quotedAuthorSize.width);
        result.height += self.quotedContentTopInset;
        result.height += self.quotedAuthorHeight;
    }

    if (self.hasQuotedText) {
        UILabel *quotedTextView = [self createQuotedTextView];

        CGSize textSize = CGSizeCeil([quotedTextView sizeThatFits:CGSizeMake(maxTextWidth, CGFLOAT_MAX)]);

        textWidth = MAX(textWidth, textSize.width);
        result.height += self.quotedAuthorBottomSpacing;
        result.height += textSize.height;
    }

    result.width += textWidth;
    result.height += self.quotedContentBottomInset;

    result.height = MAX(result.height, thumbnailHeight);

    if (includeMargins) {
        result.width += kBubbleThornSideInset;
    }

    return result;
}

- (CGSize)cellSizeForViewWidth:(int)viewWidth contentWidth:(int)contentWidth
{
    OWSAssert(self.viewItem);
    OWSAssert([self.viewItem.interaction isKindOfClass:[TSMessage class]]);

    CGSize cellSize = CGSizeZero;

    CGSize quotedMessageSize =
        [self quotedMessageSizeForViewWidth:viewWidth contentWidth:contentWidth includeMargins:YES];
    cellSize.width = MAX(cellSize.width, quotedMessageSize.width);
    cellSize.height += quotedMessageSize.height;

    CGSize mediaContentSize = [self bodyMediaSizeForContentWidth:contentWidth];
    cellSize.width = MAX(cellSize.width, mediaContentSize.width);
    cellSize.height += mediaContentSize.height;

    CGSize textContentSize = [self bodyTextSizeForContentWidth:contentWidth includeMargins:YES];
    cellSize.width = MAX(cellSize.width, textContentSize.width);
    cellSize.height += textContentSize.height;

    OWSAssert(cellSize.width > 0 && cellSize.height > 0);

    cellSize.height += self.dateHeaderHeight;
    cellSize.height += self.footerHeight;
    if (self.hasTapForMore) {
        cellSize.height += self.tapForMoreHeight;
    }

    if (self.shouldHaveFailedSendBadge) {
        cellSize.width += self.failedSendBadgeSize;
    }

    cellSize = CGSizeCeil(cellSize);

    return cellSize;
}

- (CGFloat)dateHeaderHeight
{
    if (self.viewItem.shouldShowDate) {
        // Add 5pt spacing above and below the date header.
        return (CGFloat)ceil(MAX(self.dateHeaderDateFont.lineHeight, self.dateHeaderTimeFont.lineHeight) + 10.f);
    } else {
        return 0.f;
    }
}

- (UIFont *)tapForMoreFont
{
    return [UIFont ows_regularFontWithSize:12.f];
}

- (CGFloat)tapForMoreHeight
{
    return (CGFloat)ceil([self tapForMoreFont].lineHeight * 1.25);
}

// TODO:
- (UIFont *)quotedAuthorFont
{
    return [UIFont ows_regularFontWithSize:10.f];
}

// TODO:
- (CGFloat)quotedAuthorHeight
{
    return (CGFloat)ceil([self quotedAuthorFont].lineHeight * 1.25);
}

// TODO:
- (CGFloat)quotedAuthorBottomSpacing
{
    return 2.f;
}

// TODO:
- (CGFloat)quotedContentTopInset
{
    return 3.f;
}

// TODO:
- (CGFloat)quotedContentBottomInset
{
    return 3.f;
}

// Distance from top edge of "quoted message" bubble to top of message bubble.
// TODO:
- (CGFloat)quotedMessageTopInset
{
    return 3.f;
}

// Distance from side of "quoted message" bubble to side of message bubble.
// TODO:
- (CGFloat)quotedMessageHInset
{
    return 3.f;
}

// TODO:
- (CGFloat)quotedReplyStripeThickness
{
    return 3.f;
}

// The spacing between the vertical "quoted reply stripe"
// and the quoted message content.
// TODO:
- (CGFloat)quotedReplyStripeHSpacing
{
    return 10.f;
}

// TODO:
- (CGFloat)quotedThumbnailSize
{
    return 30.f;
}

// TODO:
- (CGFloat)quotedThumbnailHSpacing
{
    return 10.f;
}

// TODO:
- (CGFloat)quotedContentTrailingMargin
{
    return 10.f;
}

#pragma mark -

- (BOOL)isIncoming
{
    return self.viewItem.interaction.interactionType == OWSInteractionType_IncomingMessage;
}

- (BOOL)isOutgoing
{
    return self.viewItem.interaction.interactionType == OWSInteractionType_OutgoingMessage;
}

- (CGFloat)textLeadingMargin
{
    CGFloat result = kBubbleTextHInset;
    if (self.isIncoming) {
        result += kBubbleThornSideInset;
    }
    return result;
}

- (CGFloat)textTrailingMargin
{
    CGFloat result = kBubbleTextHInset;
    if (!self.isIncoming) {
        result += kBubbleThornSideInset;
    }
    return result;
}

- (CGFloat)quotedBubbleLeadingMargin
{
    CGFloat result = self.quotedMessageHInset;
    if (self.isIncoming) {
        result += kBubbleThornSideInset;
    }
    return result;
}

- (CGFloat)quotedBubbleTrailingMargin
{
    CGFloat result = self.quotedMessageHInset;
    if (!self.isIncoming) {
        result += kBubbleThornSideInset;
    }
    return result;
}

- (CGFloat)textTopMargin
{
    return kBubbleTextVInset;
}

- (CGFloat)textBottomMargin
{
    return kBubbleTextVInset + kBubbleThornVInset;
}

- (UIColor *)bodyTextColor
{
    return self.isIncoming ? [UIColor blackColor] : [UIColor whiteColor];
}

- (UIColor *)quotedTextColor
{
    return [UIColor blackColor];
}

- (BOOL)isMediaBeingSent
{
    if (self.isIncoming) {
        return NO;
    }
    if (self.cellType == OWSMessageCellType_DownloadingAttachment) {
        return NO;
    }
    if (!self.attachmentStream) {
        return NO;
    }
    TSOutgoingMessage *outgoingMessage = (TSOutgoingMessage *)self.viewItem.interaction;
    return outgoingMessage.messageState == TSOutgoingMessageStateAttemptingOut;
}

- (OWSMessagesBubbleImageFactory *)bubbleFactory
{
    return [OWSMessagesBubbleImageFactory shared];
}

- (void)prepareForReuse
{
    [super prepareForReuse];

    [NSLayoutConstraint deactivateConstraints:self.viewConstraints];
    self.viewConstraints = [NSMutableArray new];

    self.dateHeaderLabel.text = nil;
    self.dateHeaderLabel.hidden = YES;
    [self.bodyTextView removeFromSuperview];
    self.quotedTextView.text = nil;
    self.quotedTextView.hidden = YES;
    [self.quotedTextView removeFromSuperview];
    self.bodyTextView.text = nil;
    self.bodyTextView.hidden = YES;
    [self.failedSendBadgeView removeFromSuperview];
    self.failedSendBadgeView = nil;
    self.footerLabel.text = nil;
    self.footerLabel.hidden = YES;

    self.bubbleView.hidden = YES;
    self.bubbleView.bubbleColor = nil;
    self.bubbleView.bubbleStrokeView = nil;

    for (UIView *subview in self.bubbleView.subviews) {
        [subview removeFromSuperview];
    }

    if (self.unloadCellContentBlock) {
        self.unloadCellContentBlock();
    }
    self.loadCellContentBlock = nil;
    self.unloadCellContentBlock = nil;

    [self.expirationTimerView clearAnimations];
    [self.expirationTimerView removeFromSuperview];
    self.expirationTimerView = nil;

    [self.lastBodyMediaView removeFromSuperview];
    self.lastBodyMediaView = nil;

    [self hideMenuControllerIfNecessary];
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
        if (self.message.shouldStartExpireTimer) {
            [self.expirationTimerView ensureAnimations];
        } else {
            [self.expirationTimerView clearAnimations];
        }
    } else {
        [self.expirationTimerView clearAnimations];

        [self hideMenuControllerIfNecessary];
    }
}

#pragma mark - Gesture recognizers

- (void)handleTapGesture:(UITapGestureRecognizer *)sender
{
    OWSAssert(self.delegate);

    if (sender.state != UIGestureRecognizerStateRecognized) {
        DDLogVerbose(@"%@ Ignoring tap on message: %@", self.logTag, self.viewItem.interaction.debugDescription);
        return;
    }

    if (self.lastBodyMediaView) {
        // Treat this as a "body media" gesture if:
        //
        // * There is a "body media" view.
        // * The gesture occured within or above the "body media" view.
        CGPoint location = [sender locationInView:self.lastBodyMediaView];
        if (location.y <= self.lastBodyMediaView.height) {
            [self handleMediaTapGesture:sender];
            return;
        }
    }

    [self handleTextTapGesture:sender];
}

- (void)handleTextTapGesture:(UITapGestureRecognizer *)sender
{
    OWSAssert(self.delegate);

    if (sender.state != UIGestureRecognizerStateRecognized) {
        DDLogVerbose(@"%@ Ignoring tap on message: %@", self.logTag, self.viewItem.interaction.debugDescription);
        return;
    }

    if (self.viewItem.interaction.interactionType == OWSInteractionType_OutgoingMessage) {
        TSOutgoingMessage *outgoingMessage = (TSOutgoingMessage *)self.viewItem.interaction;
        if (outgoingMessage.messageState == TSOutgoingMessageStateUnsent) {
            [self.delegate didTapFailedOutgoingMessage:outgoingMessage];
            return;
        } else if (outgoingMessage.messageState == TSOutgoingMessageStateAttemptingOut) {
            // Ignore taps on outgoing messages being sent.
            return;
        }
    }

    if (self.hasTapForMore) {
        [self.delegate didTapTruncatedTextMessage:self.viewItem];
        return;
    }
}

- (void)handleMediaTapGesture:(UITapGestureRecognizer *)sender
{
    OWSAssert(self.delegate);

    if (sender.state != UIGestureRecognizerStateRecognized) {
        DDLogVerbose(@"%@ Ignoring tap on message: %@", self.logTag, self.viewItem.interaction.debugDescription);
        return;
    }

    if (self.viewItem.interaction.interactionType == OWSInteractionType_OutgoingMessage) {
        TSOutgoingMessage *outgoingMessage = (TSOutgoingMessage *)self.viewItem.interaction;
        if (outgoingMessage.messageState == TSOutgoingMessageStateUnsent) {
            [self.delegate didTapFailedOutgoingMessage:outgoingMessage];
            return;
        } else if (outgoingMessage.messageState == TSOutgoingMessageStateAttemptingOut) {
            // Ignore taps on outgoing messages being sent.
            return;
        }
    }

    switch (self.cellType) {
        case OWSMessageCellType_Unknown:
            break;
        case OWSMessageCellType_TextMessage:
        case OWSMessageCellType_OversizeTextMessage:
            if (self.hasTapForMore) {
                [self.delegate didTapTruncatedTextMessage:self.viewItem];
                return;
            }
            break;
        case OWSMessageCellType_StillImage:
            OWSAssert(self.lastBodyMediaView);
            [self.delegate didTapImageViewItem:self.viewItem
                              attachmentStream:self.attachmentStream
                                     imageView:self.lastBodyMediaView];
            break;
        case OWSMessageCellType_AnimatedImage:
            OWSAssert(self.lastBodyMediaView);
            [self.delegate didTapImageViewItem:self.viewItem
                              attachmentStream:self.attachmentStream
                                     imageView:self.lastBodyMediaView];
            break;
        case OWSMessageCellType_Audio:
            [self.delegate didTapAudioViewItem:self.viewItem attachmentStream:self.attachmentStream];
            return;
        case OWSMessageCellType_Video:
            OWSAssert(self.lastBodyMediaView);
            [self.delegate didTapVideoViewItem:self.viewItem
                              attachmentStream:self.attachmentStream
                                     imageView:self.lastBodyMediaView];
            return;
        case OWSMessageCellType_GenericAttachment:
            [AttachmentSharing showShareUIForAttachment:self.attachmentStream];
            break;
        case OWSMessageCellType_DownloadingAttachment: {
            OWSAssert(self.attachmentPointer);
            if (self.attachmentPointer.state == TSAttachmentPointerStateFailed) {
                [self.delegate didTapFailedIncomingAttachment:self.viewItem attachmentPointer:self.attachmentPointer];
            }
            break;
        }
    }
}

- (void)handleLongPressGesture:(UILongPressGestureRecognizer *)sender
{
    OWSAssert(self.delegate);

    if (sender.state != UIGestureRecognizerStateBegan) {
        return;
    }

    if (self.lastBodyMediaView) {
        // Treat this as a "body media" gesture if:
        //
        // * There is a "body media" view.
        // * The gesture occured within or above the "body media" view.
        CGPoint location = [sender locationInView:self.lastBodyMediaView];
        if (location.y <= self.lastBodyMediaView.height) {
            [self handleMediaLongPressGesture:sender];
            return;
        }
    }

    [self handleTextLongPressGesture:sender];
}

- (void)handleTextLongPressGesture:(UILongPressGestureRecognizer *)sender
{
    OWSAssert(self.delegate);

    // We "eagerly" respond when the long press begins, not when it ends.
    if (sender.state == UIGestureRecognizerStateBegan) {
        CGPoint location = [sender locationInView:self];
        [self showTextMenuController:location];
    }
}

- (void)handleMediaLongPressGesture:(UILongPressGestureRecognizer *)sender
{
    OWSAssert(self.delegate);

    // We "eagerly" respond when the long press begins, not when it ends.
    if (sender.state == UIGestureRecognizerStateBegan) {
        CGPoint location = [sender locationInView:self];
        [self showMediaMenuController:location];
    }
}

- (void)handlePanGesture:(UIPanGestureRecognizer *)panRecognizer
{
    OWSAssert(self.delegate);

    [self.delegate didPanWithGestureRecognizer:panRecognizer viewItem:self.viewItem];
}

#pragma mark - UIMenuController

- (void)showTextMenuController:(CGPoint)fromLocation
{
    // We don't want taps on messages to hide the keyboard,
    // so we only let messages become first responder
    // while they are trying to present the menu controller.
    self.isPresentingMenuController = YES;

    [self becomeFirstResponder];

    if ([UIMenuController sharedMenuController].isMenuVisible) {
        [[UIMenuController sharedMenuController] setMenuVisible:NO animated:NO];
    }

    // We use custom action selectors so that we can control
    // the ordering of the actions in the menu.
    NSArray *menuItems = self.viewItem.textMenuControllerItems;
    [UIMenuController sharedMenuController].menuItems = menuItems;
    CGRect targetRect = CGRectMake(fromLocation.x, fromLocation.y, 1, 1);
    [[UIMenuController sharedMenuController] setTargetRect:targetRect inView:self];
    [[UIMenuController sharedMenuController] setMenuVisible:YES animated:YES];
}

- (void)showMediaMenuController:(CGPoint)fromLocation
{
    // We don't want taps on messages to hide the keyboard,
    // so we only let messages become first responder
    // while they are trying to present the menu controller.
    self.isPresentingMenuController = YES;

    [self becomeFirstResponder];

    if ([UIMenuController sharedMenuController].isMenuVisible) {
        [[UIMenuController sharedMenuController] setMenuVisible:NO animated:NO];
    }

    // We use custom action selectors so that we can control
    // the ordering of the actions in the menu.
    NSArray *menuItems = self.viewItem.mediaMenuControllerItems;
    [UIMenuController sharedMenuController].menuItems = menuItems;
    CGRect targetRect = CGRectMake(fromLocation.x, fromLocation.y, 1, 1);
    [[UIMenuController sharedMenuController] setTargetRect:targetRect inView:self];
    [[UIMenuController sharedMenuController] setMenuVisible:YES animated:YES];
}

- (BOOL)canPerformAction:(SEL)action withSender:(nullable id)sender
{
    return [self.viewItem canPerformAction:action];
}

- (void)copyTextAction:(nullable id)sender
{
    [self.viewItem copyTextAction];
}

- (void)copyMediaAction:(nullable id)sender
{
    [self.viewItem copyMediaAction];
}

- (void)shareTextAction:(nullable id)sender
{
    [self.viewItem shareTextAction];
}

- (void)shareMediaAction:(nullable id)sender
{
    [self.viewItem shareMediaAction];
}

- (void)saveMediaAction:(nullable id)sender
{
    [self.viewItem saveMediaAction];
}

- (void)deleteAction:(nullable id)sender
{
    [self.viewItem deleteAction];
}

- (void)metadataAction:(nullable id)sender
{
    OWSAssert([self.viewItem.interaction isKindOfClass:[TSMessage class]]);

    [self.delegate showMetadataViewForViewItem:self.viewItem];
}

- (BOOL)canBecomeFirstResponder
{
    return self.isPresentingMenuController;
}

- (void)didHideMenuController:(NSNotification *)notification
{
    self.isPresentingMenuController = NO;
}

- (void)setIsPresentingMenuController:(BOOL)isPresentingMenuController
{
    if (_isPresentingMenuController == isPresentingMenuController) {
        return;
    }

    _isPresentingMenuController = isPresentingMenuController;

    if (isPresentingMenuController) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(didHideMenuController:)
                                                     name:UIMenuControllerDidHideMenuNotification
                                                   object:nil];
    } else {
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                        name:UIMenuControllerDidHideMenuNotification
                                                      object:nil];
    }
}

- (void)hideMenuControllerIfNecessary
{
    if (self.isPresentingMenuController) {
        [[UIMenuController sharedMenuController] setMenuVisible:NO animated:NO];
    }
    self.isPresentingMenuController = NO;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end

NS_ASSUME_NONNULL_END
