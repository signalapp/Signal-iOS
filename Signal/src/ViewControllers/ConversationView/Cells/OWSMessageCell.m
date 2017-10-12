//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
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

@interface OWSMessageCell ()

// The text label is used so frequently that we always keep one around.
@property (nonatomic) UIView *payloadView;
@property (nonatomic) UILabel *dateHeaderLabel;
@property (nonatomic) UILabel *textLabel;
@property (nonatomic, nullable) UIImageView *bubbleImageView;
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
@property (nonatomic, nullable) NSArray<NSLayoutConstraint *> *dateHeaderConstraints;
@property (nonatomic, nullable) NSArray<NSLayoutConstraint *> *contentConstraints;
@property (nonatomic, nullable) NSArray<NSLayoutConstraint *> *footerConstraints;

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
    OWSAssert(!self.textLabel);

    self.layoutMargins = UIEdgeInsetsZero;

    self.payloadView = [UIView containerView];
    [self.contentView addSubview:self.payloadView];

    self.footerView = [UIView containerView];
    [self.contentView addSubview:self.footerView];

    self.dateHeaderLabel = [UILabel new];
    self.dateHeaderLabel.font = [UIFont ows_regularFontWithSize:12.f];
    self.dateHeaderLabel.textAlignment = NSTextAlignmentCenter;
    self.dateHeaderLabel.textColor = [UIColor lightGrayColor];
    [self.contentView addSubview:self.dateHeaderLabel];

    self.bubbleImageView = [UIImageView new];
    self.bubbleImageView.layoutMargins = UIEdgeInsetsZero;
    self.bubbleImageView.userInteractionEnabled = NO;
    [self.payloadView addSubview:self.bubbleImageView];
    [self.bubbleImageView autoPinToSuperviewEdges];

    self.textLabel = [UILabel new];
    self.textLabel.font = [UIFont ows_regularFontWithSize:16.f];
    self.textLabel.numberOfLines = 0;
    self.textLabel.lineBreakMode = NSLineBreakByWordWrapping;
    self.textLabel.textAlignment = NSTextAlignmentLeft;
    [self.bubbleImageView addSubview:self.textLabel];
    OWSAssert(self.textLabel.superview);

    self.footerLabel = [UILabel new];
    self.footerLabel.font = [UIFont ows_regularFontWithSize:12.f];
    self.footerLabel.textColor = [UIColor lightGrayColor];
    [self.footerView addSubview:self.footerLabel];

    // Hide these views by default.
    self.bubbleImageView.hidden = YES;
    self.textLabel.hidden = YES;
    self.dateHeaderLabel.hidden = YES;
    self.footerLabel.hidden = YES;

    [self.dateHeaderLabel autoPinEdgeToSuperviewEdge:ALEdgeTop];
    [self.payloadView autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:self.dateHeaderLabel];
    [self.payloadView autoPinWidthToSuperview];
    [self.footerView autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:self.payloadView];
    [self.footerView autoPinEdgeToSuperviewEdge:ALEdgeBottom];
    [self.footerView autoPinWidthToSuperview];

    UITapGestureRecognizer *tap =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTapGesture:)];
    [self addGestureRecognizer:tap];

    UILongPressGestureRecognizer *longPress =
        [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPressGesture:)];
    [self addGestureRecognizer:longPress];
}

- (OWSMessageCellType)cellType
{
    return self.viewItem.messageCellType;
}

- (nullable NSString *)textMessage
{
    // This should always be valid for the appropriate cell types.
    OWSAssert(self.viewItem.textMessage);

    return self.viewItem.textMessage;
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

- (CGSize)contentSize
{
    // This should always be valid for the appropriate cell types.
    OWSAssert(self.viewItem.contentSize.width > 0 && self.viewItem.contentSize.height > 0);

    return self.viewItem.contentSize;
}

- (void)loadForDisplay:(int)contentWidth
{
    OWSAssert(self.viewItem);
    OWSAssert(self.viewItem.interaction);
    OWSAssert([self.viewItem.interaction isKindOfClass:[TSMessage class]]);

    DDLogError(@"%p loadForDisplay: %@", self, NSStringForOWSMessageCellType(self.cellType));

    BOOL isIncoming = self.isIncoming;
    JSQMessagesBubbleImage *bubbleImageData
        = isIncoming ? [self.bubbleFactory incoming] : [self.bubbleFactory outgoing];
    self.bubbleImageView.image = bubbleImageData.messageBubbleImage;

    [self updateDateHeader:contentWidth];
    [self updateFooter];

    switch (self.cellType) {
        case OWSMessageCellType_TextMessage:
        case OWSMessageCellType_OversizeTextMessage:
            [self loadForTextDisplay];
            break;
        case OWSMessageCellType_StillImage:
            [self loadForStillImageDisplay];
            break;
        case OWSMessageCellType_AnimatedImage:
            [self loadForAnimatedImageDisplay];
            break;
        case OWSMessageCellType_Audio:
            [self loadForAudioDisplay];
            break;
        case OWSMessageCellType_Video:
            [self loadForVideoDisplay];
            break;
        case OWSMessageCellType_GenericAttachment: {
            self.attachmentView =
                [[OWSGenericAttachmentView alloc] initWithAttachment:self.attachmentStream isIncoming:self.isIncoming];
            [self.attachmentView createContentsForSize:self.bounds.size];
            [self replaceBubbleWithView:self.attachmentView];
            [self addAttachmentUploadViewIfNecessary:self.attachmentView];
            break;
        }
        case OWSMessageCellType_DownloadingAttachment: {
            [self loadForDownloadingAttachment];
            break;
        }
    }

    //    dispatch_async(dispatch_get_main_queue(), ^{
    //        NSLog(@"---- %@", self.viewItem.interaction.debugDescription);
    //        NSLog(@"cell: %@", NSStringFromCGRect(self.frame));
    //        NSLog(@"contentView: %@", NSStringFromCGRect(self.contentView.frame));
    //        NSLog(@"textLabel: %@", NSStringFromCGRect(self.textLabel.frame));
    //        NSLog(@"bubbleImageView: %@", NSStringFromCGRect(self.bubbleImageView.frame));
    //    });
}

- (void)updateDateHeader:(int)contentWidth
{
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
            [self.dateHeaderLabel autoSetDimension:ALDimensionWidth toSize:contentWidth],
            (self.isIncoming ? [self.dateHeaderLabel autoPinEdgeToSuperviewEdge:ALEdgeLeading]
                             : [self.dateHeaderLabel autoPinEdgeToSuperviewEdge:ALEdgeTrailing]),
            [self.dateHeaderLabel autoSetDimension:ALDimensionHeight toSize:self.dateHeaderHeight],
        ];
    } else {
        self.dateHeaderLabel.hidden = YES;
        self.dateHeaderConstraints = @[
            [self.dateHeaderLabel autoSetDimension:ALDimensionHeight toSize:0],
        ];
    }
}

- (CGFloat)footerHeight
{
    BOOL showFooter = NO;

    TSMessage *message = (TSMessage *)self.viewItem.interaction;
    BOOL hasExpirationTimer = message.shouldStartExpireTimer;

    if (hasExpirationTimer) {
        showFooter = YES;
    } else if (!self.isIncoming) {
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

    TSMessage *message = (TSMessage *)self.viewItem.interaction;
    BOOL hasExpirationTimer = message.shouldStartExpireTimer;
    NSAttributedString *attributedText = nil;
    if (!self.isIncoming) {
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
    
    if (hasExpirationTimer)
    {
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
    self.bubbleImageView.hidden = NO;
    self.textLabel.hidden = NO;
    self.textLabel.text = self.textMessage;
    self.textLabel.textColor = [self textColor];

    self.contentConstraints = @[
        [self.textLabel autoPinLeadingToSuperviewWithMargin:self.textLeadingMargin],
        [self.textLabel autoPinTrailingToSuperviewWithMargin:self.textTrailingMargin],
        [self.textLabel autoPinEdgeToSuperviewEdge:ALEdgeTop withInset:self.textVMargin],
        [self.textLabel autoPinEdgeToSuperviewEdge:ALEdgeBottom withInset:self.textVMargin],
    ];
}

- (void)loadForStillImageDisplay
{
    OWSAssert(self.attachmentStream);
    OWSAssert([self.attachmentStream isImage]);

    UIImage *_Nullable image = self.attachmentStream.image;
    if (!image) {
        DDLogError(@"%@ Could not load image: %@", [self logTag], [self.attachmentStream mediaURL]);
        [self showAttachmentErrorView];
        return;
    }

    self.stillImageView = [[UIImageView alloc] initWithImage:image];
    // We need to specify a contentMode since the size of the image
    // might not match the aspect ratio of the view.
    self.stillImageView.contentMode = UIViewContentModeScaleAspectFill;
    // Use trilinear filters for better scaling quality at
    // some performance cost.
    self.stillImageView.layer.minificationFilter = kCAFilterTrilinear;
    self.stillImageView.layer.magnificationFilter = kCAFilterTrilinear;
    [self replaceBubbleWithView:self.stillImageView];
    [self addAttachmentUploadViewIfNecessary:self.stillImageView];
}

- (void)loadForAnimatedImageDisplay
{
    OWSAssert(self.attachmentStream);
    OWSAssert([self.attachmentStream isAnimated]);

    NSString *_Nullable filePath = [self.attachmentStream filePath];
    YYImage *_Nullable animatedImage = nil;
    if (filePath && [NSData ows_isValidImageAtPath:filePath]) {
        animatedImage = [YYImage imageWithContentsOfFile:filePath];
    }
    if (!animatedImage) {
        DDLogError(@"%@ Could not load animated image: %@", [self logTag], [self.attachmentStream mediaURL]);
        [self showAttachmentErrorView];
        return;
    }

    self.animatedImageView = [[YYAnimatedImageView alloc] init];
    self.animatedImageView.image = animatedImage;
    // We need to specify a contentMode since the size of the image
    // might not match the aspect ratio of the view.
    self.animatedImageView.contentMode = UIViewContentModeScaleAspectFill;
    [self replaceBubbleWithView:self.animatedImageView];
    [self addAttachmentUploadViewIfNecessary:self.animatedImageView];
}

- (void)loadForAudioDisplay
{
    OWSAssert(self.attachmentStream);
    OWSAssert([self.attachmentStream isAudio]);

    self.audioMessageView = [[OWSAudioMessageView alloc] initWithAttachment:self.attachmentStream
                                                                 isIncoming:self.isIncoming
                                                                   viewItem:self.viewItem];
    self.viewItem.lastAudioMessageView = self.audioMessageView;
    [self.audioMessageView createContentsForSize:self.bounds.size];
    [self replaceBubbleWithView:self.audioMessageView];
    [self addAttachmentUploadViewIfNecessary:self.audioMessageView];
}

- (void)loadForVideoDisplay
{
    OWSAssert(self.attachmentStream);
    OWSAssert([self.attachmentStream isVideo]);

    //    CGSize size = [self mediaViewDisplaySize];

    UIImage *_Nullable image = self.attachmentStream.image;
    if (!image) {
        DDLogError(@"%@ Could not load image: %@", [self logTag], [self.attachmentStream mediaURL]);
        [self showAttachmentErrorView];
        return;
    }

    self.stillImageView = [[UIImageView alloc] initWithImage:image];
    // We need to specify a contentMode since the size of the image
    // might not match the aspect ratio of the view.
    self.stillImageView.contentMode = UIViewContentModeScaleAspectFill;
    // Use trilinear filters for better scaling quality at
    // some performance cost.
    self.stillImageView.layer.minificationFilter = kCAFilterTrilinear;
    self.stillImageView.layer.magnificationFilter = kCAFilterTrilinear;
    [self replaceBubbleWithView:self.stillImageView];

    UIImage *videoPlayIcon = [UIImage imageNamed:@"play_button"];
    UIImageView *videoPlayButton = [[UIImageView alloc] initWithImage:videoPlayIcon];
    [self.stillImageView addSubview:videoPlayButton];
    [videoPlayButton autoCenterInSuperview];
    [self addAttachmentUploadViewIfNecessary:self.stillImageView
                     attachmentStateCallback:^(BOOL isAttachmentReady) {
                         videoPlayButton.hidden = !isAttachmentReady;
                     }];
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
    [self replaceBubbleWithView:self.customView];

    self.attachmentPointerView =
        [[AttachmentPointerView alloc] initWithAttachmentPointer:self.attachmentPointer isIncoming:self.isIncoming];
    [self.customView addSubview:self.attachmentPointerView];
    [self.attachmentPointerView autoPinWidthToSuperviewWithMargin:20.f];
    [self.attachmentPointerView autoVCenterInSuperview];
}

- (void)replaceBubbleWithView:(UIView *)view
{
    OWSAssert(view);

    view.userInteractionEnabled = NO;
    [self.payloadView addSubview:view];
    self.contentConstraints = [view autoPinToSuperviewEdges];
    [self cropViewToBubbbleShape:view];
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

    if (!self.isIncoming) {
        self.attachmentUploadView = [[AttachmentUploadView alloc] initWithAttachment:self.attachmentStream
                                                                           superview:attachmentView
                                                             attachmentStateCallback:attachmentStateCallback];
    }
}

- (void)cropViewToBubbbleShape:(UIView *)view
{
    [self layoutIfNeeded];
    view.frame = self.payloadView.bounds;
    [JSQMessagesMediaViewBubbleImageMasker applyBubbleImageMaskToMediaView:view isOutgoing:!self.isIncoming];
}

//// TODO:
//- (void)setFrame:(CGRect)frame {
//    [super setFrame:frame];
//
//    DDLogError(@"setFrame: %@ %@ %@", self.viewItem.interaction.uniqueId, self.viewItem.interaction.description,
//    NSStringFromCGRect(frame));
//}
//
//// TODO:
//- (void)setBounds:(CGRect)bounds {
//    [super setBounds:bounds];
//
//    DDLogError(@"setBounds: %@ %@ %@", self.viewItem.interaction.uniqueId, self.viewItem.interaction.description,
//    NSStringFromCGRect(bounds));
//}

- (void)showAttachmentErrorView
{
    // TODO: We could do a better job of indicating that the image could not be loaded.
    self.customView = [UIView new];
    self.customView.backgroundColor = [UIColor colorWithWhite:0.85f alpha:1.f];
    self.customView.userInteractionEnabled = NO;
    [self.payloadView addSubview:self.customView];
    self.contentConstraints = [self.customView autoPinToSuperviewEdges];
    [self cropViewToBubbbleShape:self.customView];
}

- (CGSize)cellSizeForViewWidth:(int)viewWidth contentWidth:(int)contentWidth
{
    OWSAssert(self.viewItem);
    OWSAssert([self.viewItem.interaction isKindOfClass:[TSMessage class]]);

    const int maxMessageWidth = (int)floor(contentWidth * 0.7f);

    CGSize cellSize = CGSizeZero;
    switch (self.cellType) {
        case OWSMessageCellType_TextMessage:
        case OWSMessageCellType_OversizeTextMessage: {
            BOOL isRTL = self.isRTL;
            CGFloat leftMargin = isRTL ? self.textTrailingMargin : self.textLeadingMargin;
            CGFloat rightMargin = isRTL ? self.textLeadingMargin : self.textTrailingMargin;
            CGFloat textVMargin = self.textVMargin;
            const int maxTextWidth = (int)floor(maxMessageWidth - (leftMargin + rightMargin));

            self.textLabel.text = self.textMessage;
            CGSize textSize = [self.textLabel sizeThatFits:CGSizeMake(maxTextWidth, CGFLOAT_MAX)];
            cellSize = CGSizeMake((CGFloat)ceil(textSize.width + leftMargin + rightMargin),
                (CGFloat)ceil(textSize.height + textVMargin * 2));
            break;
        }
        case OWSMessageCellType_StillImage:
        case OWSMessageCellType_AnimatedImage:
        case OWSMessageCellType_Video: {
            OWSAssert(self.contentSize.width > 0);
            OWSAssert(self.contentSize.height > 0);

            // TODO: Adjust this behavior.
            // TODO: This behavior is a bit different than the old behavior defined
            //       in JSQMediaItem+OWS.h.  Let's discuss.
            const CGFloat maxMediaWidth = maxMessageWidth;
            const CGFloat maxMediaHeight = maxMessageWidth;
            CGFloat mediaWidth = (CGFloat)round(maxMediaWidth);
            CGFloat mediaHeight = (CGFloat)round(maxMediaWidth * self.contentSize.height / self.contentSize.width);
            if (mediaHeight > maxMediaHeight) {
                mediaWidth = (CGFloat)round(maxMediaHeight * self.contentSize.width / self.contentSize.height);
                mediaHeight = (CGFloat)round(maxMediaHeight);
            }
            cellSize = CGSizeMake(mediaWidth, mediaHeight);
            break;
        }
        case OWSMessageCellType_Audio:
            cellSize = CGSizeMake(maxMessageWidth, OWSAudioMessageView.bubbleHeight);
            break;
        case OWSMessageCellType_GenericAttachment:
            cellSize = CGSizeMake(maxMessageWidth, [OWSGenericAttachmentView bubbleHeight]);
            break;
        case OWSMessageCellType_DownloadingAttachment:
            cellSize = CGSizeMake(200, 90);
            break;
    }

    OWSAssert(cellSize.width > 0 && cellSize.height > 0);

    cellSize.height += self.dateHeaderHeight;
    cellSize.height += self.footerHeight;

    cellSize.width = ceil(cellSize.width);
    cellSize.height = ceil(cellSize.height);

    return cellSize;
}

- (CGFloat)dateHeaderHeight
{
    if (self.viewItem.shouldShowDate) {
        return MAX(self.dateHeaderDateFont.lineHeight, self.dateHeaderTimeFont.lineHeight);
    } else {
        return 0.f;
    }
}

- (BOOL)isIncoming
{
    return YES;
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
    if (!self.attachmentStream) {
        return NO;
    }
    TSOutgoingMessage *outgoingMessage = (TSOutgoingMessage *)self.viewItem.interaction;
    return outgoingMessage.messageState == TSOutgoingMessageStateAttemptingOut;
}

- (OWSMessagesBubbleImageFactory *)bubbleFactory
{
    static OWSMessagesBubbleImageFactory *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [OWSMessagesBubbleImageFactory new];
    });
    return instance;
}

- (void)prepareForReuse
{
    [super prepareForReuse];

    [NSLayoutConstraint deactivateConstraints:self.contentConstraints];
    self.contentConstraints = nil;
    [NSLayoutConstraint deactivateConstraints:self.dateHeaderConstraints];
    self.dateHeaderConstraints = nil;
    [NSLayoutConstraint deactivateConstraints:self.footerConstraints];
    self.footerConstraints = nil;

    // The text label is used so frequently that we always keep one around.
    self.dateHeaderLabel.text = nil;
    self.dateHeaderLabel.hidden = YES;
    self.textLabel.text = nil;
    self.textLabel.hidden = YES;
    self.footerLabel.text = nil;
    self.footerLabel.hidden = YES;
    self.bubbleImageView.image = nil;
    self.bubbleImageView.hidden = YES;

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
    self.attachmentUploadView = nil;
    [self.expirationTimerView clearAnimations];
    [self.expirationTimerView removeFromSuperview];
    self.expirationTimerView = nil;
}

//- (void)prepareForReuse
//{
//    [super prepareForReuse];
//    self.mediaView.alpha = 1.0;
//    self.expirationTimerViewWidthConstraint.constant = 0.0f;
//
//    [self.mediaAdapter setCellVisible:NO];
//
//    // Clear this adapter's views IFF this was the last cell to use this adapter.
//    [self.mediaAdapter clearCachedMediaViewsIfLastPresentingCell:self];
//    [_mediaAdapter setLastPresentingCell:nil];
//
//    self.mediaAdapter = nil;
//}
//
//- (void)setMediaAdapter:(nullable id<OWSMessageMediaAdapter>)mediaAdapter
//{
//    _mediaAdapter = mediaAdapter;
//
//    // Mark this as the last cell to use this adapter.
//    [_mediaAdapter setLastPresentingCell:self];
//}
//
//// pragma mark - OWSMessageCollectionViewCell
//
//- (void)setCellVisible:(BOOL)isVisible
//{
//    [self.mediaAdapter setCellVisible:isVisible];
//}
//
//- (UIColor *)ows_textColor
//{
//    return [UIColor whiteColor];
//}

#pragma mark - Notifications

- (void)setIsCellVisible:(BOOL)isCellVisible {
    if (self.isCellVisible == isCellVisible) {
        return;
    }
    
    [super setIsCellVisible:isCellVisible];
    
    if (isCellVisible) {
        TSMessage *message = (TSMessage *)self.viewItem.interaction;
        if (message.shouldStartExpireTimer) {
            [self.expirationTimerView ensureAnimations];
        } else {
            [self.expirationTimerView clearAnimations];
        }
    } else {
        [self.expirationTimerView clearAnimations];
    }
}

// case TSInfoMessageAdapter: {
//    // HACK this will get called when we get a new info message, but there's gotta be a better spot for this.
//    OWSDisappearingMessagesConfiguration *configuration =
//    [OWSDisappearingMessagesConfiguration fetchObjectWithUniqueID:self.thread.uniqueId];
//    [self setBarButtonItemsForDisappearingMessagesConfiguration:configuration];
//
//    if (message.shouldStartExpireTimer && [cell conformsToProtocol:@protocol(OWSExpirableMessageView)]) {
//        id<OWSExpirableMessageView> expirableView = (id<OWSExpirableMessageView>)cell;
//        [expirableView startExpirationTimerWithExpiresAtSeconds:message.expiresAtSeconds
//                                         initialDurationSeconds:message.expiresInSeconds];
//    }
//

#pragma mark - Gesture recognizers

- (void)handleTapGesture:(UITapGestureRecognizer *)sender
{
    OWSAssert(self.delegate);

    if (sender.state == UIGestureRecognizerStateRecognized) {

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
            case OWSMessageCellType_TextMessage:
                break;
            case OWSMessageCellType_OversizeTextMessage:
                [self.delegate didTapOversizeTextMessage:self.textMessage attachmentStream:self.attachmentStream];
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
                [self.delegate didTapVideoViewItem:self.viewItem attachmentStream:self.attachmentStream];
                return;
            case OWSMessageCellType_GenericAttachment:
                [AttachmentSharing showShareUIForAttachment:self.attachmentStream];
                break;
            case OWSMessageCellType_DownloadingAttachment: {
                OWSAssert(self.attachmentPointer);
                if (self.attachmentPointer.state == TSAttachmentPointerStateFailed) {
                    [self.delegate didTapFailedIncomingAttachment:self.viewItem
                                                attachmentPointer:self.attachmentPointer];
                }
                break;
            }
        }

        DDLogInfo(@"%@ Ignoring tap on message: %@", self.logTag, self.viewItem.interaction.debugDescription);
    }
}

- (void)handleLongPressGesture:(UILongPressGestureRecognizer *)sender
{
    OWSAssert(self.delegate);

    // We "eagerly" respond when the long press begins, not when it ends.
    if (sender.state == UIGestureRecognizerStateBegan) {
        CGPoint location = [sender locationInView:self];
        [self showMenuController:location];
    }
}

#pragma mark - UIMenuController

- (void)showMenuController:(CGPoint)fromLocation
{
    [self becomeFirstResponder];

    if ([UIMenuController sharedMenuController].isMenuVisible) {
        [[UIMenuController sharedMenuController] setMenuVisible:NO animated:NO];
    }

    // We use custom action selectors so that we can control
    // the ordering of the actions in the menu.
    NSArray *menuItems = self.viewItem.menuControllerItems;
    [UIMenuController sharedMenuController].menuItems = menuItems;
    CGRect targetRect = CGRectMake(fromLocation.x, fromLocation.y, 1, 1);
    [[UIMenuController sharedMenuController] setTargetRect:targetRect inView:self];
    [[UIMenuController sharedMenuController] setMenuVisible:YES animated:YES];
}

- (BOOL)canPerformAction:(SEL)action withSender:(nullable id)sender
{
    return [self.viewItem canPerformAction:action];
}

- (void)copyAction:(nullable id)sender
{
    [self.viewItem copyAction];
}

- (void)shareAction:(nullable id)sender
{
    [self.viewItem shareAction];
}

- (void)saveAction:(nullable id)sender
{
    [self.viewItem saveAction];
}

- (void)deleteAction:(nullable id)sender
{
    [self.viewItem deleteAction];
}

- (void)metadataAction:(nullable id)sender
{
    OWSAssert([self.viewItem.interaction isKindOfClass:[TSMessage class]]);

    [self.delegate showMetadataViewForMessage:(TSMessage *)self.viewItem.interaction];
}

- (BOOL)canBecomeFirstResponder
{
    return YES;
}

#pragma mark - Logging

+ (NSString *)logTag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)logTag
{
    return self.class.logTag;
}

@end

NS_ASSUME_NONNULL_END
