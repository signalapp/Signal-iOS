//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageCell.h"
#import "AttachmentSharing.h"
#import "AttachmentUploadView.h"
#import "ConversationViewItem.h"
#import "NSAttributedString+OWS.h"
#import "OWSAudioMessageView.h"
#import "OWSExpirationTimerView.h"
#import "OWSGenericAttachmentView.h"
#import "Signal-Swift.h"
#import "UIColor+OWS.h"
#import <JSQMessagesViewController/JSQMessagesTimestampFormatter.h>
#import <JSQMessagesViewController/UIColor+JSQMessages.h>

NS_ASSUME_NONNULL_BEGIN

// This approximates the curve of our message bubbles, which makes the animation feel a little smoother.
const CGFloat OWSMessageCellCornerRadius = 17;

@interface BubbleMaskingView : UIView

@property (nonatomic) BOOL isOutgoing;
@property (nonatomic) BOOL hideTail;
@property (nonatomic, nullable, weak) UIView *maskedSubview;

@end

#pragma mark -

@implementation BubbleMaskingView

- (void)setFrame:(CGRect)frame
{
    BOOL didSizeChange = !CGSizeEqualToSize(self.frame.size, frame.size);

    [super setFrame:frame];

    if (didSizeChange) {
        [self updateMask];
    }
}

- (void)setBounds:(CGRect)bounds
{
    BOOL didSizeChange = !CGSizeEqualToSize(self.bounds.size, bounds.size);

    [super setBounds:bounds];

    if (didSizeChange) {
        [self updateMask];
    }
}

- (void)updateMask
{
    UIView *_Nullable maskedSubview = self.maskedSubview;
    if (!maskedSubview) {
        return;
    }
    maskedSubview.frame = self.bounds;
    // The JSQ masks are not RTL-safe, so we need to invert the
    // mask orientation manually.
    BOOL hasOutgoingMask = self.isOutgoing ^ self.isRTL;

    // Since the caption has it's own tail, the media bubble just above
    // it looks better without a tail.
    if (self.hideTail) {
        if (hasOutgoingMask) {
            self.layoutMargins = UIEdgeInsetsMake(0, 0, 2, 8);
        } else {
            self.layoutMargins = UIEdgeInsetsMake(0, 8, 2, 0);
        }
        maskedSubview.clipsToBounds = YES;

        // I arrived at this cornerRadius by superimposing the generated corner
        // over that generated from the JSQMessagesMediaViewBubbleImageMasker
        maskedSubview.layer.cornerRadius = 17;
    } else {
        [JSQMessagesMediaViewBubbleImageMasker applyBubbleImageMaskToMediaView:maskedSubview
                                                                    isOutgoing:hasOutgoingMask];
    }
}

@end

#pragma mark -

@interface OWSMessageTextView : UITextView

@property (nonatomic) BOOL shouldIgnoreEvents;

@end

#pragma mark -

@implementation OWSMessageTextView

// Our message text views are never used for editing;
// suppress their ability to become first responder
// so that tapping on them doesn't hide keyboard.
- (BOOL)canBecomeFirstResponder
{
    return NO;
}

// Ignore interactions with the text view _except_ taps on links.
//
// We want to disable "partial" selection of text in the message
// and we want to enable "tap to resend" by tapping on a message.
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *_Nullable)event
{
    if (self.shouldIgnoreEvents) {
        // We ignore all events for failed messages so that users
        // can tap-to-resend even "all link" messages.
        return NO;
    }

    // Find the nearest text position to the event.
    UITextPosition *_Nullable position = [self closestPositionToPoint:point];
    if (!position) {
        return NO;
    }
    // Find the range of the character in the text which contains the event.
    //
    // Try every layout direction (this might not be necessary).
    UITextRange *_Nullable range = nil;
    for (NSNumber *textLayoutDirection in @[
             @(UITextLayoutDirectionLeft),
             @(UITextLayoutDirectionRight),
             @(UITextLayoutDirectionUp),
             @(UITextLayoutDirectionDown),
         ]) {
        range = [self.tokenizer rangeEnclosingPosition:position
                                       withGranularity:UITextGranularityCharacter
                                           inDirection:(UITextDirection)textLayoutDirection.intValue];
        if (range) {
            break;
        }
    }
    if (!range) {
        return NO;
    }
    // Ignore the event unless it occurred inside a link.
    NSInteger startIndex = [self offsetFromPosition:self.beginningOfDocument toPosition:range.start];
    BOOL result =
        [self.attributedText attribute:NSLinkAttributeName atIndex:(NSUInteger)startIndex effectiveRange:nil] != nil;
    return result;
}

@end

#pragma mark -

@interface OWSMessageCell ()

// The nullable properties are created as needed.
// The non-nullable properties are so frequently used that it's easier
// to always keep one around.
@property (nonatomic) UIView *payloadView;
@property (nonatomic) BubbleMaskingView *mediaMaskingView;
@property (nonatomic) UILabel *dateHeaderLabel;
@property (nonatomic) OWSMessageTextView *textView;
@property (nonatomic, nullable) UIImageView *failedSendBadgeView;
@property (nonatomic, nullable) UILabel *tapForMoreLabel;
@property (nonatomic, nullable) UIImageView *textBubbleImageView;
@property (nonatomic, nullable) AttachmentUploadView *attachmentUploadView;
@property (nonatomic, nullable) UIImageView *stillImageView;
@property (nonatomic, nullable) YYAnimatedImageView *animatedImageView;
@property (nonatomic, nullable) UIView *customView;
@property (nonatomic, nullable) AttachmentPointerView *attachmentPointerView;
@property (nonatomic, nullable) OWSGenericAttachmentView *attachmentView;
@property (nonatomic, nullable) OWSAudioMessageView *audioMessageView;
@property (nonatomic) UIView *footerView;
@property (nonatomic) UILabel *footerLabel;
@property (nonatomic, nullable) OWSExpirationTimerView *expirationTimerView;
@property (nonatomic, nullable) NSArray<NSLayoutConstraint *> *payloadConstraints;
@property (nonatomic, nullable) NSArray<NSLayoutConstraint *> *dateHeaderConstraints;
@property (nonatomic, nullable) NSMutableArray<NSLayoutConstraint *> *contentConstraints;
@property (nonatomic, nullable) NSArray<NSLayoutConstraint *> *footerConstraints;
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
    OWSAssert(!self.textView);

    _contentConstraints = [NSMutableArray new];

    self.layoutMargins = UIEdgeInsetsZero;
    self.contentView.layoutMargins = UIEdgeInsetsZero;

    self.payloadView = [UIView new];
    self.payloadView.layoutMargins = UIEdgeInsetsZero;
    [self.contentView addSubview:self.payloadView];

    self.mediaMaskingView = [BubbleMaskingView new];
    self.mediaMaskingView.layoutMargins = UIEdgeInsetsZero;
    [self.payloadView addSubview:self.mediaMaskingView];

    self.footerView = [UIView containerView];
    [self.contentView addSubview:self.footerView];

    self.dateHeaderLabel = [UILabel new];
    self.dateHeaderLabel.font = [UIFont ows_regularFontWithSize:12.f];
    self.dateHeaderLabel.textAlignment = NSTextAlignmentCenter;
    self.dateHeaderLabel.textColor = [UIColor lightGrayColor];
    [self.contentView addSubview:self.dateHeaderLabel];

    self.textBubbleImageView = [UIImageView new];
    self.textBubbleImageView.layoutMargins = UIEdgeInsetsZero;
    // Enable userInteractionEnabled so that links in textView work.
    self.textBubbleImageView.userInteractionEnabled = YES;

    [self.payloadView addSubview:self.textBubbleImageView];

    self.textView = [OWSMessageTextView new];
    self.textView.backgroundColor = [UIColor clearColor];
    self.textView.opaque = NO;
    self.textView.editable = NO;
    self.textView.selectable = YES;
    self.textView.textContainerInset = UIEdgeInsetsZero;
    self.textView.contentInset = UIEdgeInsetsZero;
    self.textView.scrollEnabled = NO;

    [self.textBubbleImageView addSubview:self.textView];

    OWSAssert(self.textView.superview);

    self.footerLabel = [UILabel new];
    self.footerLabel.font = [UIFont ows_regularFontWithSize:12.f];
    self.footerLabel.textColor = [UIColor lightGrayColor];
    [self.footerView addSubview:self.footerLabel];

    // Hide these views by default.
    self.textBubbleImageView.hidden = YES;
    self.textView.hidden = YES;
    self.dateHeaderLabel.hidden = YES;
    self.footerLabel.hidden = YES;

    [self.payloadView autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:self.dateHeaderLabel];
    [self.footerView autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:self.payloadView];

    [self.mediaMaskingView autoPinEdgeToSuperviewEdge:ALEdgeTop];

    [self.textBubbleImageView autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:self.mediaMaskingView];
    [self.textBubbleImageView autoPinEdgeToSuperviewEdge:ALEdgeBottom];

    [self.footerView autoPinEdgeToSuperviewEdge:ALEdgeBottom];
    [self.footerView autoPinWidthToSuperview];

    UITapGestureRecognizer *mediaTap =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleMediaTapGesture:)];
    [self.mediaMaskingView addGestureRecognizer:mediaTap];

    UITapGestureRecognizer *textTap =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTextTapGesture:)];
    [self.textBubbleImageView addGestureRecognizer:textTap];

    UILongPressGestureRecognizer *mediaLongPress =
        [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleMediaLongPressGesture:)];
    [self.mediaMaskingView addGestureRecognizer:mediaLongPress];

    UILongPressGestureRecognizer *textLongPress =
        [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleTextLongPressGesture:)];
    [self.textBubbleImageView addGestureRecognizer:textLongPress];

    PanDirectionGestureRecognizer *panGesture =
        [[PanDirectionGestureRecognizer alloc] initWithDirection:(self.isRTL ? PanDirectionLeft : PanDirectionRight)
                                                          target:self
                                                          action:@selector(handlePanGesture:)];
    [self addGestureRecognizer:panGesture];
}

+ (NSString *)cellReuseIdentifier
{
    return NSStringFromClass([self class]);
}

- (UIFont *)textMessageFont
{
    OWSAssert(DisplayableText.kMaxJumbomojiCount == 5);

    CGFloat basePointSize = [UIFont ows_dynamicTypeBodyFont].pointSize;
    switch (self.displayableText.jumbomojiCount) {
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
            OWSFail(@"%@ Unexpected jumbomoji count: %zd", self.logTag, self.displayableText.jumbomojiCount);
            break;
    }

    return [UIFont ows_dynamicTypeBodyFont];
}

- (UIFont *)tapForMoreFont
{
    return [UIFont ows_regularFontWithSize:12.f];
}

- (CGFloat)tapForMoreHeight
{
    return (CGFloat)ceil([self tapForMoreFont].lineHeight * 1.25);
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

- (BOOL)hasText
{
    // This should always be valid for the appropriate cell types.
    OWSAssert(self.viewItem);

    return self.viewItem.hasText;
}

- (nullable DisplayableText *)displayableText
{
    // This should always be valid for the appropriate cell types.
    OWSAssert(self.viewItem.displayableText);

    return self.viewItem.displayableText;
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

- (TSMessage *)message
{
    OWSAssert([self.viewItem.interaction isKindOfClass:[TSMessage class]]);

    return (TSMessage *)self.viewItem.interaction;
}

- (void)loadForDisplay
{
    OWSAssert(self.viewItem);
    OWSAssert(self.viewItem.interaction);
    OWSAssert([self.viewItem.interaction isKindOfClass:[TSMessage class]]);

    if (self.shouldHaveFailedSendBadge) {
        self.failedSendBadgeView = [UIImageView new];
        self.failedSendBadgeView.image =
            [self.failedSendBadge imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        self.failedSendBadgeView.tintColor = [UIColor ows_destructiveRedColor];
        [self.contentView addSubview:self.failedSendBadgeView];

        self.payloadConstraints = @[
            [self.payloadView autoPinLeadingToSuperview],
            [self.failedSendBadgeView autoPinLeadingToTrailingOfView:self.payloadView],
            [self.failedSendBadgeView autoPinTrailingToSuperview],
            [self.failedSendBadgeView autoAlignAxis:ALAxisHorizontal toSameAxisOfView:self.payloadView],
            [self.failedSendBadgeView autoSetDimension:ALDimensionWidth toSize:self.failedSendBadgeSize],
            [self.failedSendBadgeView autoSetDimension:ALDimensionHeight toSize:self.failedSendBadgeSize],
        ];
    } else {
        self.payloadConstraints = [self.payloadView autoPinWidthToSuperview];
    }

    JSQMessagesBubbleImage *_Nullable bubbleImageData;
    if ([self.viewItem.interaction isKindOfClass:[TSMessage class]]) {
        TSMessage *message = (TSMessage *)self.viewItem.interaction;
        bubbleImageData = [self.bubbleFactory bubbleWithMessage:message];
    }

    self.textBubbleImageView.image = bubbleImageData.messageBubbleImage;

    [self updateDateHeader];
    [self updateFooter];

    switch (self.cellType) {
        case OWSMessageCellType_Unknown:
            OWSFail(@"Unknown cell type for viewItem: %@", self.viewItem);
            break;
        case OWSMessageCellType_TextMessage:
            [self loadForTextDisplay];
            break;
        case OWSMessageCellType_OversizeTextMessage:
            OWSAssert(self.viewItem.attachmentStream);
            [self loadForTextDisplay];
            break;
        case OWSMessageCellType_StillImage:
            OWSAssert(self.viewItem.attachmentStream);
            [self loadForStillImageDisplay];
            break;
        case OWSMessageCellType_AnimatedImage:
            OWSAssert(self.viewItem.attachmentStream);
            [self loadForAnimatedImageDisplay];
            break;
        case OWSMessageCellType_Audio:
            OWSAssert(self.viewItem.attachmentStream);
            [self loadForAudioDisplay];
            break;
        case OWSMessageCellType_Video:
            OWSAssert(self.viewItem.attachmentStream);
            [self loadForVideoDisplay];
            break;
        case OWSMessageCellType_GenericAttachment: {
            OWSAssert(self.viewItem.attachmentStream);
            self.attachmentView =
                [[OWSGenericAttachmentView alloc] initWithAttachment:self.attachmentStream isIncoming:self.isIncoming];
            [self.attachmentView createContents];
            [self setMediaView:self.attachmentView];
            [self addAttachmentUploadViewIfNecessary:self.attachmentView];
            [self addCaptionIfNecessary];
            break;
        }
        case OWSMessageCellType_DownloadingAttachment: {
            [self loadForDownloadingAttachment];
            [self addCaptionIfNecessary];
            break;
        }
    }

    [self ensureViewMediaState];
}

// We now eagerly create out view hierarchy (to do this exactly once per cell usage)
// but lazy-load any expensive media (photo, gif, etc.) used in those views. Note that
// this lazy-load can fail, in which case we modify the view hierarchy to use an "error"
// state. The didCellMediaFailToLoad reflects media load fails.
- (nullable id)tryToLoadCellMedia:(nullable id (^)(void))loadCellMediaBlock
                        mediaView:(UIView *)mediaView
                         cacheKey:(NSString *)cacheKey
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
        [cellMediaCache setObject:cellMedia forKey:cacheKey];
    } else {
        DDLogError(@"%@ Failed to load cell media: %@", [self logTag], [self.attachmentStream mediaURL]);
        self.viewItem.didCellMediaFailToLoad = YES;
        [mediaView removeFromSuperview];
        // TODO: We need to hide/remove the media view.
        [self showAttachmentErrorView];
    }
    return cellMedia;
}

// We want to lazy-load expensive view contents and eagerly unload if the
// cell is no longer visible.
- (void)ensureViewMediaState
{
    CGSize mediaSize = [self mediaBubbleSizeForContentWidth:self.contentWidth];
    [self.contentConstraints addObjectsFromArray:[self.mediaMaskingView autoSetDimensionsToSize:mediaSize]];

    if (!self.isCellVisible) {
        // Eagerly unload.
        self.stillImageView.image = nil;
        self.animatedImageView.image = nil;
        return;
    }

    switch (self.cellType) {
        case OWSMessageCellType_StillImage: {
            if (self.stillImageView.image) {
                return;
            }
            self.stillImageView.image = [self tryToLoadCellMedia:^{
                OWSAssert([self.attachmentStream isImage]);
                return self.attachmentStream.image;
            }
                                                       mediaView:self.stillImageView
                                                        cacheKey:self.attachmentStream.uniqueId];
            break;
        }
        case OWSMessageCellType_AnimatedImage: {
            if (self.animatedImageView.image) {
                return;
            }
            self.animatedImageView.image = [self tryToLoadCellMedia:^{
                OWSAssert([self.attachmentStream isAnimated]);

                NSString *_Nullable filePath = [self.attachmentStream filePath];
                YYImage *_Nullable animatedImage = nil;
                if (filePath && [NSData ows_isValidImageAtPath:filePath]) {
                    animatedImage = [YYImage imageWithContentsOfFile:filePath];
                }
                return animatedImage;
            }
                                                          mediaView:self.animatedImageView
                                                           cacheKey:self.attachmentStream.uniqueId];
            break;
        }
        case OWSMessageCellType_Video: {
            if (self.stillImageView.image) {
                return;
            }
            self.stillImageView.image = [self tryToLoadCellMedia:^{
                OWSAssert([self.attachmentStream isVideo]);

                return self.attachmentStream.image;
            }
                                                       mediaView:self.stillImageView
                                                        cacheKey:self.attachmentStream.uniqueId];
            break;
        }
        case OWSMessageCellType_TextMessage:
        case OWSMessageCellType_OversizeTextMessage:
        case OWSMessageCellType_GenericAttachment:
        case OWSMessageCellType_DownloadingAttachment:
        case OWSMessageCellType_Audio:
        case OWSMessageCellType_Unknown:
            // Inexpensive cell types don't need to lazy-load or eagerly-unload.
            break;
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

        self.dateHeaderConstraints = @[
            // Date headers should be visually centered within the conversation view,
            // so they need to extend outside the cell's boundaries.
            [self.dateHeaderLabel autoSetDimension:ALDimensionWidth toSize:self.contentWidth],
            (self.isIncoming ? [self.dateHeaderLabel autoPinEdgeToSuperviewEdge:ALEdgeLeading]
                             : [self.dateHeaderLabel autoPinEdgeToSuperviewEdge:ALEdgeTrailing]),
            [self.dateHeaderLabel autoPinEdgeToSuperviewEdge:ALEdgeTop],
            [self.dateHeaderLabel autoSetDimension:ALDimensionHeight toSize:self.dateHeaderHeight],
        ];
    } else {
        self.dateHeaderLabel.hidden = YES;
        self.dateHeaderConstraints = @[
            [self.dateHeaderLabel autoSetDimension:ALDimensionHeight toSize:0],
            [self.dateHeaderLabel autoPinEdgeToSuperviewEdge:ALEdgeTop],
        ];
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

    return (showFooter ? MAX(kExpirationTimerViewSize,
                             self.footerLabel.font.lineHeight)
            : 0.f);
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
        self.footerConstraints = @[
                                   [self.footerView autoSetDimension:ALDimensionHeight toSize:0],
                                   ];
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
        self.footerConstraints = @[
                                   [self.expirationTimerView autoVCenterInSuperview],
                                   [self.footerLabel autoVCenterInSuperview],
                                   (self.isIncoming
                                    ? [self.expirationTimerView autoPinLeadingToSuperview]
                                    : [self.expirationTimerView autoPinTrailingToSuperview]),
                                   (self.isIncoming
                                    ? [self.footerLabel autoPinLeadingToTrailingOfView:self.expirationTimerView margin:0.f]
                                    : [self.footerLabel autoPinTrailingToLeadingOfView:self.expirationTimerView margin:0.f]),
                                   [self.footerView autoSetDimension:ALDimensionHeight toSize:self.footerHeight],
                                   ];
    } else if (hasExpirationTimer) {
        self.footerConstraints = @[
                                   [self.expirationTimerView autoVCenterInSuperview],
                                   (self.isIncoming
                                    ? [self.expirationTimerView autoPinLeadingToSuperview]
                                    : [self.expirationTimerView autoPinTrailingToSuperview]),
                                   [self.footerView autoSetDimension:ALDimensionHeight toSize:self.footerHeight],
                                   ];
    } else if (attributedText) {
        self.footerConstraints = @[
                                   [self.footerLabel autoVCenterInSuperview],
                                   (self.isIncoming
                                    ? [self.footerLabel autoPinLeadingToSuperview]
                                    : [self.footerLabel autoPinTrailingToSuperview]),
                                   [self.footerView autoSetDimension:ALDimensionHeight toSize:self.footerHeight],
                                   ];
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

- (void)loadForTextDisplay
{
    self.textBubbleImageView.hidden = NO;
    self.textView.hidden = NO;
    self.textView.text = self.displayableText.displayText;
    self.textView.textColor = self.textColor;

    // Honor dynamic type in the message bodies.
    self.textView.font = [self textMessageFont];
    self.textView.linkTextAttributes = @{
        NSForegroundColorAttributeName : self.textColor,
        NSUnderlineStyleAttributeName : @(NSUnderlineStyleSingle | NSUnderlinePatternSolid)
    };
    self.textView.dataDetectorTypes
        = (UIDataDetectorTypeLink | UIDataDetectorTypeAddress | UIDataDetectorTypeCalendarEvent);

    if (self.viewItem.interaction.interactionType == OWSInteractionType_OutgoingMessage) {
        // Ignore taps on links in outgoing messages that haven't been sent yet, as
        // this interferes with "tap to retry".
        TSOutgoingMessage *outgoingMessage = (TSOutgoingMessage *)self.viewItem.interaction;
        self.textView.shouldIgnoreEvents = outgoingMessage.messageState != TSOutgoingMessageStateSentToService;
    } else {
        self.textView.shouldIgnoreEvents = NO;
    }

    OWSAssert(self.contentWidth);
    CGSize textBubbleSize = [self textBubbleSizeForContentWidth:self.contentWidth];

    if (self.displayableText.isTextTruncated) {
        self.tapForMoreLabel = [UILabel new];
        self.tapForMoreLabel.text = NSLocalizedString(@"CONVERSATION_VIEW_OVERSIZE_TEXT_TAP_FOR_MORE",
            @"Indicator on truncated text messages that they can be tapped to see the entire text message.");
        self.tapForMoreLabel.font = [self tapForMoreFont];
        self.tapForMoreLabel.textColor = [self.textColor colorWithAlphaComponent:0.85];
        self.tapForMoreLabel.textAlignment = [self.tapForMoreLabel textAlignmentUnnatural];
        [self.textBubbleImageView addSubview:self.tapForMoreLabel];

        [self.contentConstraints addObjectsFromArray:@[
            [self.textBubbleImageView autoSetDimension:ALDimensionWidth toSize:textBubbleSize.width],
            [self.textBubbleImageView autoSetDimension:ALDimensionHeight toSize:textBubbleSize.height],
            [self.textView autoPinLeadingToSuperviewWithMargin:self.textLeadingMargin],
            [self.textView autoPinTrailingToSuperviewWithMargin:self.textTrailingMargin],
            [self.textView autoPinEdgeToSuperviewEdge:ALEdgeTop withInset:self.textVMargin],

            [self.tapForMoreLabel autoPinLeadingToSuperviewWithMargin:self.textLeadingMargin],
            [self.tapForMoreLabel autoPinTrailingToSuperviewWithMargin:self.textTrailingMargin],
            [self.tapForMoreLabel autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:self.textView],
            [self.tapForMoreLabel autoPinEdgeToSuperviewEdge:ALEdgeBottom withInset:self.textVMargin],
            [self.tapForMoreLabel autoSetDimension:ALDimensionHeight toSize:self.tapForMoreHeight],
        ]];
    } else {
        [self.contentConstraints addObjectsFromArray:@[
            [self.textBubbleImageView autoSetDimension:ALDimensionWidth toSize:textBubbleSize.width],
            [self.textBubbleImageView autoSetDimension:ALDimensionHeight toSize:textBubbleSize.height],
            [self.textBubbleImageView autoPinEdgeToSuperviewEdge:(self.isIncoming ? ALEdgeLeading : ALEdgeTrailing)],
            [self.textView autoPinLeadingToSuperviewWithMargin:self.textLeadingMargin],
            [self.textView autoPinTrailingToSuperviewWithMargin:self.textTrailingMargin],
            [self.textView autoPinEdgeToSuperviewEdge:ALEdgeTop withInset:self.textVMargin],
            [self.textView autoPinEdgeToSuperviewEdge:ALEdgeBottom withInset:self.textVMargin],
        ]];
    }
}

- (void)loadForStillImageDisplay
{
    OWSAssert(self.attachmentStream);
    OWSAssert([self.attachmentStream isImage]);

    self.stillImageView = [UIImageView new];
    // We need to specify a contentMode since the size of the image
    // might not match the aspect ratio of the view.
    self.stillImageView.contentMode = UIViewContentModeScaleAspectFill;
    // Use trilinear filters for better scaling quality at
    // some performance cost.
    self.stillImageView.layer.minificationFilter = kCAFilterTrilinear;
    self.stillImageView.layer.magnificationFilter = kCAFilterTrilinear;
    [self setMediaView:self.stillImageView];
    [self addAttachmentUploadViewIfNecessary:self.stillImageView];
    [self addCaptionIfNecessary];
}

- (void)loadForAnimatedImageDisplay
{
    OWSAssert(self.attachmentStream);
    OWSAssert([self.attachmentStream isAnimated]);

    self.animatedImageView = [[YYAnimatedImageView alloc] init];
    // We need to specify a contentMode since the size of the image
    // might not match the aspect ratio of the view.
    self.animatedImageView.contentMode = UIViewContentModeScaleAspectFill;
    [self setMediaView:self.animatedImageView];
    [self addAttachmentUploadViewIfNecessary:self.animatedImageView];
    [self addCaptionIfNecessary];
}

- (void)addCaptionIfNecessary
{
    if (self.hasText) {
        [self loadForTextDisplay];
    } else {
        [self.contentConstraints addObject:[self.textBubbleImageView autoSetDimension:ALDimensionHeight toSize:0]];
    }
}

- (void)loadForAudioDisplay
{
    OWSAssert(self.attachmentStream);
    OWSAssert([self.attachmentStream isAudio]);

    self.audioMessageView = [[OWSAudioMessageView alloc] initWithAttachment:self.attachmentStream
                                                                 isIncoming:self.isIncoming
                                                                   viewItem:self.viewItem];
    self.viewItem.lastAudioMessageView = self.audioMessageView;
    [self.audioMessageView createContents];
    [self setMediaView:self.audioMessageView];
    [self addAttachmentUploadViewIfNecessary:self.audioMessageView];
    [self addCaptionIfNecessary];
}

- (void)loadForVideoDisplay
{
    OWSAssert(self.attachmentStream);
    OWSAssert([self.attachmentStream isVideo]);

    self.stillImageView = [UIImageView new];
    // We need to specify a contentMode since the size of the image
    // might not match the aspect ratio of the view.
    self.stillImageView.contentMode = UIViewContentModeScaleAspectFill;
    // Use trilinear filters for better scaling quality at
    // some performance cost.
    self.stillImageView.layer.minificationFilter = kCAFilterTrilinear;
    self.stillImageView.layer.magnificationFilter = kCAFilterTrilinear;
    [self setMediaView:self.stillImageView];

    UIImage *videoPlayIcon = [UIImage imageNamed:@"play_button"];
    UIImageView *videoPlayButton = [[UIImageView alloc] initWithImage:videoPlayIcon];
    [self.stillImageView addSubview:videoPlayButton];
    [videoPlayButton autoCenterInSuperview];
    [self addAttachmentUploadViewIfNecessary:self.stillImageView
                     attachmentStateCallback:^(BOOL isAttachmentReady) {
                         videoPlayButton.hidden = !isAttachmentReady;
                     }];
    [self addCaptionIfNecessary];
}

- (void)loadForDownloadingAttachment
{
    OWSAssert(self.attachmentPointer);

    self.customView = [UIView new];
    switch (self.attachmentPointer.state) {
        case TSAttachmentPointerStateEnqueued:
            self.customView.backgroundColor
                = (self.isIncoming ? [UIColor jsq_messageBubbleLightGrayColor] : [UIColor ows_fadedBlueColor]);
            break;
        case TSAttachmentPointerStateDownloading:
            self.customView.backgroundColor
                = (self.isIncoming ? [UIColor jsq_messageBubbleLightGrayColor] : [UIColor ows_fadedBlueColor]);
            break;
        case TSAttachmentPointerStateFailed:
            self.customView.backgroundColor = [UIColor grayColor];
            break;
    }
    [self setMediaView:self.customView];

    self.attachmentPointerView =
        [[AttachmentPointerView alloc] initWithAttachmentPointer:self.attachmentPointer isIncoming:self.isIncoming];
    [self.customView addSubview:self.attachmentPointerView];
    [self.attachmentPointerView autoPinWidthToSuperviewWithMargin:20.f];
    [self.attachmentPointerView autoVCenterInSuperview];
    [self addCaptionIfNecessary];
}

- (void)setMediaView:(UIView *)view
{
    OWSAssert(view);

    view.userInteractionEnabled = NO;
    [self.mediaMaskingView addSubview:view];

    [self.contentConstraints
        addObject:[self.mediaMaskingView
                      autoPinEdgeToSuperviewEdge:(self.isIncoming ? ALEdgeLeading : ALEdgeTrailing)]];

    [self.contentConstraints addObjectsFromArray:[view autoPinEdgesToSuperviewMargins]];

    [self cropMediaViewToBubbbleShape:view];
    if (self.isMediaBeingSent) {
        view.layer.opacity = 0.75f;
    }
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
            self.attachmentUploadView = [[AttachmentUploadView alloc] initWithAttachment:self.attachmentStream
                                                                               superview:attachmentView
                                                                 attachmentStateCallback:attachmentStateCallback];
        }
    }
}

- (void)cropMediaViewToBubbbleShape:(UIView *)view
{
    OWSAssert(view);
    OWSAssert(view.superview == self.mediaMaskingView);

    self.mediaMaskingView.isOutgoing = self.isOutgoing;
    // Hide tail on attachments followed by a caption
    self.mediaMaskingView.hideTail = self.hasText;
    self.mediaMaskingView.maskedSubview = view;
    [self.mediaMaskingView updateMask];
}

- (void)showAttachmentErrorView
{
    OWSAssert(!self.customView);

    // TODO: We could do a better job of indicating that the media could not be loaded.
    self.customView = [UIView new];
    self.customView.backgroundColor = [UIColor colorWithWhite:0.85f alpha:1.f];
    self.customView.userInteractionEnabled = NO;
    [self.payloadView addSubview:self.customView];
    [self.contentConstraints addObjectsFromArray:[self.customView autoPinToSuperviewEdges]];
    [self cropMediaViewToBubbbleShape:self.customView];
}

- (CGSize)textBubbleSizeForContentWidth:(int)contentWidth
{
    if (!self.hasText) {
        return CGSizeZero;
    }

    BOOL isRTL = self.isRTL;
    CGFloat leftMargin = isRTL ? self.textTrailingMargin : self.textLeadingMargin;
    CGFloat rightMargin = isRTL ? self.textLeadingMargin : self.textTrailingMargin;
    CGFloat textVMargin = self.textVMargin;

    const int maxMessageWidth = [self maxMessageWidthForContentWidth:contentWidth];
    const int maxTextWidth = (int)floor(maxMessageWidth - (leftMargin + rightMargin));

    self.textView.text = self.displayableText.displayText;
    // Honor dynamic type in the message bodies.
    self.textView.font = [self textMessageFont];
    CGSize textSize = [self.textView sizeThatFits:CGSizeMake(maxTextWidth, CGFLOAT_MAX)];
    CGFloat tapForMoreHeight = (self.displayableText.isTextTruncated ? [self tapForMoreHeight] : 0.f);
    CGSize textViewSize = CGSizeMake((CGFloat)ceil(textSize.width + leftMargin + rightMargin),
        (CGFloat)ceil(textSize.height + textVMargin * 2 + tapForMoreHeight));

    return textViewSize;
}

- (CGSize)mediaBubbleSizeForContentWidth:(int)contentWidth
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
            // TODO: This behavior is a bit different than the old behavior defined
            //       in JSQMediaItem+OWS.h.  Let's discuss.

            CGFloat contentAspectRatio = self.mediaSize.width / self.mediaSize.height;
            // Clamp the aspect ratio so that very thin/wide content is presented
            // in a reasonable way.
            const CGFloat minAspectRatio = 0.25f;
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

- (CGSize)cellSizeForViewWidth:(int)viewWidth contentWidth:(int)contentWidth
{
    OWSAssert(self.viewItem);
    OWSAssert([self.viewItem.interaction isKindOfClass:[TSMessage class]]);

    CGSize mediaContentSize = [self mediaBubbleSizeForContentWidth:contentWidth];
    CGSize textContentSize = [self textBubbleSizeForContentWidth:contentWidth];

    CGFloat cellContentWidth = fmax(mediaContentSize.width, textContentSize.width);
    CGFloat cellContentHeight = mediaContentSize.height + textContentSize.height;
    CGSize cellSize = CGSizeMake(cellContentWidth, cellContentHeight);

    OWSAssert(cellSize.width > 0 && cellSize.height > 0);

    cellSize.height += self.dateHeaderHeight;
    cellSize.height += self.footerHeight;

    if (self.shouldHaveFailedSendBadge) {
        cellSize.width += self.failedSendBadgeSize;
    }

    cellSize.width = ceil(cellSize.width);
    cellSize.height = ceil(cellSize.height);

    return cellSize;
}

- (CGFloat)dateHeaderHeight
{
    if (self.viewItem.shouldShowDate) {
        // Add 5pt spacing above and below the date header.
        return MAX(self.dateHeaderDateFont.lineHeight, self.dateHeaderTimeFont.lineHeight) + 10.f;
    } else {
        return 0.f;
    }
}

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
    return self.isIncoming ? 15 : 10;
}

- (CGFloat)textTrailingMargin
{
    return self.isIncoming ? 10 : 15;
}

- (CGFloat)textVMargin
{
    return 10;
}

- (UIColor *)textColor
{
    return self.isIncoming ? [UIColor blackColor] : [UIColor whiteColor];
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

    [NSLayoutConstraint deactivateConstraints:self.payloadConstraints];
    self.payloadConstraints = nil;
    [NSLayoutConstraint deactivateConstraints:self.contentConstraints];
    self.contentConstraints = [NSMutableArray new];
    [NSLayoutConstraint deactivateConstraints:self.dateHeaderConstraints];
    self.dateHeaderConstraints = nil;
    [NSLayoutConstraint deactivateConstraints:self.footerConstraints];
    self.footerConstraints = nil;

    self.dateHeaderLabel.text = nil;
    self.dateHeaderLabel.hidden = YES;
    self.textView.text = nil;
    self.textView.hidden = YES;
    self.textView.dataDetectorTypes = UIDataDetectorTypeNone;
    [self.failedSendBadgeView removeFromSuperview];
    self.failedSendBadgeView = nil;
    [self.tapForMoreLabel removeFromSuperview];
    self.tapForMoreLabel = nil;
    self.footerLabel.text = nil;
    self.footerLabel.hidden = YES;
    self.textBubbleImageView.image = nil;
    self.textBubbleImageView.hidden = YES;
    self.mediaMaskingView.maskedSubview = nil;
    self.mediaMaskingView.hideTail = NO;
    self.mediaMaskingView.layoutMargins = UIEdgeInsetsZero;

    [self.stillImageView removeFromSuperview];
    self.stillImageView = nil;
    [self.animatedImageView removeFromSuperview];
    self.animatedImageView = nil;
    [self.customView removeFromSuperview];
    self.customView = nil;
    [self.attachmentPointerView removeFromSuperview];
    self.attachmentPointerView = nil;
    [self.attachmentView removeFromSuperview];
    self.attachmentView = nil;
    [self.audioMessageView removeFromSuperview];
    self.audioMessageView = nil;
    [self.attachmentUploadView removeFromSuperview];
    self.attachmentUploadView = nil;
    [self.expirationTimerView clearAnimations];
    [self.expirationTimerView removeFromSuperview];
    self.expirationTimerView = nil;

    [self hideMenuControllerIfNecessary];
}

#pragma mark - Notifications

- (void)setIsCellVisible:(BOOL)isCellVisible {
    BOOL didChange = self.isCellVisible != isCellVisible;

    [super setIsCellVisible:isCellVisible];

    if (!didChange) {
        return;
    }

    [self ensureViewMediaState];

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

    if (self.hasText && self.displayableText.isTextTruncated) {
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
            if (self.displayableText.isTextTruncated) {
                [self.delegate didTapTruncatedTextMessage:self.viewItem];
                return;
            }
            break;
        case OWSMessageCellType_StillImage:
            [self.delegate didTapImageViewItem:self.viewItem
                              attachmentStream:self.attachmentStream
                                     imageView:self.stillImageView];
            break;
        case OWSMessageCellType_AnimatedImage:
            [self.delegate didTapImageViewItem:self.viewItem
                              attachmentStream:self.attachmentStream
                                     imageView:self.animatedImageView];
            break;
        case OWSMessageCellType_Audio:
            [self.delegate didTapAudioViewItem:self.viewItem attachmentStream:self.attachmentStream];
            return;
        case OWSMessageCellType_Video:
            [self.delegate didTapVideoViewItem:self.viewItem
                              attachmentStream:self.attachmentStream
                                     imageView:self.stillImageView];
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
