//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageCell.h"
#import "AttachmentSharing.h"
#import "AttachmentUploadView.h"
#import "ConversationViewItem.h"
#import "OWSAudioMessageView.h"
#import "OWSGenericAttachmentView.h"
#import "UIColor+OWS.h"

//#import <AssetsLibrary/AssetsLibrary.h>
#import "Signal-Swift.h"
#import <JSQMessagesViewController/UIColor+JSQMessages.h>

//#import "OWSExpirationTimerView.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSMessageCell ()

// The text label is used so frequently that we always keep one around.
@property (nonatomic) UILabel *textLabel;
@property (nonatomic, nullable) UIImageView *bubbleImageView;
@property (nonatomic, nullable) AttachmentUploadView *attachmentUploadView;
@property (nonatomic, nullable) UIImageView *stillImageView;
@property (nonatomic, nullable) YYAnimatedImageView *animatedImageView;
@property (nonatomic, nullable) UIView *customView;
@property (nonatomic, nullable) AttachmentPointerView *attachmentPointerView;
@property (nonatomic, nullable) OWSGenericAttachmentView *attachmentView;
@property (nonatomic, nullable) OWSAudioMessageView *audioMessageView;
@property (nonatomic, nullable) NSArray<NSLayoutConstraint *> *contentConstraints;

//@property (strong, nonatomic) OWSExpirationTimerView *expirationTimerView;
//@property (strong, nonatomic) NSLayoutConstraint *expirationTimerViewWidthConstraint;

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

    //    [self setTranslatesAutoresizingMaskIntoConstraints:NO];
    self.layoutMargins = UIEdgeInsetsZero;

    self.contentView.backgroundColor = [UIColor whiteColor];

    self.bubbleImageView = [UIImageView new];
    self.bubbleImageView.layoutMargins = UIEdgeInsetsZero;
    self.bubbleImageView.userInteractionEnabled = NO;
    [self.contentView addSubview:self.bubbleImageView];
    [self.bubbleImageView autoPinToSuperviewEdges];

    self.textLabel = [UILabel new];
    self.textLabel.font = [UIFont ows_regularFontWithSize:16.f];
    self.textLabel.numberOfLines = 0;
    self.textLabel.lineBreakMode = NSLineBreakByWordWrapping;
    self.textLabel.textAlignment = NSTextAlignmentLeft;
    [self.bubbleImageView addSubview:self.textLabel];
    OWSAssert(self.textLabel.superview);

    // Hide these views by default.
    self.bubbleImageView.hidden = YES;
    self.textLabel.hidden = YES;

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
    return self.viewItem.textMessage;
}

- (nullable TSAttachmentStream *)attachmentStream
{
    return self.viewItem.attachmentStream;
}

- (nullable TSAttachmentPointer *)attachmentPointer
{
    return self.viewItem.attachmentPointer;
}

- (CGSize)contentSize
{
    return self.viewItem.contentSize;
}

- (void)loadForDisplay
{
    OWSAssert(self.viewItem);
    OWSAssert(self.viewItem.interaction);
    OWSAssert([self.viewItem.interaction isKindOfClass:[TSMessage class]]);

    BOOL isIncoming = self.isIncoming;
    JSQMessagesBubbleImage *bubbleImageData
        = isIncoming ? [self.bubbleFactory incoming] : [self.bubbleFactory outgoing];
    self.bubbleImageView.image = bubbleImageData.messageBubbleImage;

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

    // If we have an outgoing attachment and we haven't created a
    // AttachmentUploadView yet, do so now.
    //
    // For some attachment types, we may create this view earlier
    // so that we can take advantage of its callback.
    //    if (self.attachmentStream &&
    //        !self.isIncoming &&
    //        !self.attachmentUploadView) {
    //        self.attachmentUploadView = [[AttachmentUploadView alloc] initWithAttachment:self.attachmentStream
    //                                                                           superview:imageView
    //                                                             attachmentStateCallback:^(BOOL isAttachmentReady) {
    //                                                             }];
    //    }

    //    [self.textLabel addBorderWithColor:[UIColor blueColor]];
    //    [self.bubbleImageView addBorderWithColor:[UIColor greenColor]];

    //    dispatch_async(dispatch_get_main_queue(), ^{
    //        NSLog(@"---- %@", self.viewItem.interaction.debugDescription);
    //        NSLog(@"cell: %@", NSStringFromCGRect(self.frame));
    //        NSLog(@"contentView: %@", NSStringFromCGRect(self.contentView.frame));
    //        NSLog(@"textLabel: %@", NSStringFromCGRect(self.textLabel.frame));
    //        NSLog(@"bubbleImageView: %@", NSStringFromCGRect(self.bubbleImageView.frame));
    //    });
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
            [[NSNotificationCenter defaultCenter] addObserver:self
                                                     selector:@selector(attachmentDownloadProgress:)
                                                         name:kAttachmentDownloadProgressNotification
                                                       object:nil];
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
    [self.contentView addSubview:view];
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
    //    OWSAssert(CGRectEqualToRect(self.bounds, self.contentView.frame));
    //    DDLogError(@"cropViewToBubbbleShape: %@ %@", self.viewItem.interaction.uniqueId,
    //    self.viewItem.interaction.description); DDLogError(@"\t %@ %@ %@ %@",
    //               NSStringFromCGRect(self.frame),
    //               NSStringFromCGRect(self.contentView.frame),
    //               NSStringFromCGRect(view.frame),
    //               NSStringFromCGRect(view.superview.bounds));

    //    view.frame = view.superview.bounds;
    view.frame = self.bounds;
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
    [self.contentView addSubview:self.customView];
    self.contentConstraints = [self.customView autoPinToSuperviewEdges];
    [self cropViewToBubbbleShape:self.customView];
}

- (CGSize)cellSizeForViewWidth:(int)viewWidth contentWidth:(int)contentWidth
{
    OWSAssert(self.viewItem);
    OWSAssert([self.viewItem.interaction isKindOfClass:[TSMessage class]]);

    const int maxMessageWidth = (int)floor(contentWidth * 0.7f);

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
            CGSize result = CGSizeMake((CGFloat)ceil(textSize.width + leftMargin + rightMargin),
                (CGFloat)ceil(textSize.height + textVMargin * 2));
            return result;
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
            CGSize result = CGSizeMake(mediaWidth, mediaHeight);
            return result;
        }
        case OWSMessageCellType_Audio:
            return CGSizeMake(maxMessageWidth, OWSAudioMessageView.bubbleHeight);
        case OWSMessageCellType_GenericAttachment:
            return CGSizeMake(maxMessageWidth, [OWSGenericAttachmentView bubbleHeight]);
        case OWSMessageCellType_DownloadingAttachment:
            return CGSizeMake(200, 90);
    }

    return CGSizeMake(maxMessageWidth, maxMessageWidth);
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

    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [NSLayoutConstraint deactivateConstraints:self.contentConstraints];
    self.contentConstraints = nil;

    // The text label is used so frequently that we always keep one around.
    self.textLabel.text = nil;
    self.textLabel.hidden = YES;
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
}

//- (void)awakeFromNib
//{
//    [super awakeFromNib];
//    self.expirationTimerViewWidthConstraint.constant = 0.0;
//
//    // Our text alignment needs to adapt to RTL.
//    self.cellBottomLabel.textAlignment = [self.cellBottomLabel textAlignmentUnnatural];
//}
//
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
//
//// pragma mark - OWSExpirableMessageView
//
//- (void)startExpirationTimerWithExpiresAtSeconds:(double)expiresAtSeconds
//                          initialDurationSeconds:(uint32_t)initialDurationSeconds
//{
//    self.expirationTimerViewWidthConstraint.constant = OWSExpirableMessageViewTimerWidth;
//    [self.expirationTimerView startTimerWithExpiresAtSeconds:expiresAtSeconds
//                                      initialDurationSeconds:initialDurationSeconds];
//}
//
//- (void)stopExpirationTimer
//{
//    [self.expirationTimerView stopTimer];
//}

#pragma mark - Notifications:

// TODO: Move this logic into AttachmentPointerView.
- (void)attachmentDownloadProgress:(NSNotification *)notification
{
    NSNumber *progress = notification.userInfo[kAttachmentDownloadProgressKey];
    NSString *attachmentId = notification.userInfo[kAttachmentDownloadAttachmentIDKey];
    if (!self.attachmentPointer || ![self.attachmentPointer.uniqueId isEqualToString:attachmentId]) {
        OWSFail(@"%@ Unexpected attachment progress notification: %@", self.logTag, attachmentId);
        return;
    }
    self.attachmentPointerView.progress = progress.floatValue;
}

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
                //                [self.delegate didTapGenericAttachment:self.viewItem
                //                attachmentStream:self.attachmentStream];
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
