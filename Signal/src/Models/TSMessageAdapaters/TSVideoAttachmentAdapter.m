//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "TSVideoAttachmentAdapter.h"
#import "AttachmentUploadView.h"
#import "JSQMediaItem+OWS.h"
#import "MIMETypeUtil.h"
#import "Signal-Swift.h"
#import "TSAttachmentStream.h"
#import "TSMessagesManager.h"
#import "TSStorageManager+keyingMaterial.h"
#import "UIColor+JSQMessages.h"
#import "UIColor+OWS.h"
#import "UIDevice+TSHardwareVersion.h"
#import "UIFont+OWS.h"
#import "UIView+OWS.h"
#import "ViewControllerUtils.h"
#import <JSQMessagesViewController/JSQMessagesMediaViewBubbleImageMasker.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import <SignalServiceKit/MIMETypeUtil.h>

NS_ASSUME_NONNULL_BEGIN

@interface TSVideoAttachmentAdapter ()

@property (nonatomic, nullable) UIView *cachedMediaView;
@property (nonatomic) TSAttachmentStream *attachment;
@property (nonatomic, nullable) UIButton *audioPlayPauseButton;
@property (nonatomic, nullable) UILabel *audioBottomLabel;
@property (nonatomic, nullable) AudioProgressView *audioProgressView;
@property (nonatomic) BOOL incoming;
@property (nonatomic, nullable) AttachmentUploadView *attachmentUploadView;
@property (nonatomic) BOOL isAudioPlaying;
@property (nonatomic) CGFloat audioProgressSeconds;
@property (nonatomic) CGFloat audioDurationSeconds;
@property (nonatomic) BOOL isPaused;
@property (nonatomic) CGSize imageSize;

// See comments on OWSMessageMediaAdapter.
@property (nonatomic, nullable, weak) id lastPresentingCell;

@end

#pragma mark -

@implementation TSVideoAttachmentAdapter

- (instancetype)initWithAttachment:(TSAttachmentStream *)attachment incoming:(BOOL)incoming {
    self = [super initWithFileURL:[attachment mediaURL] isReadyToPlay:YES];

    if (self) {
        _cachedMediaView = nil;
        _attachmentId    = attachment.uniqueId;
        _contentType     = attachment.contentType;
        _attachment      = attachment;
        _incoming        = incoming;
        _imageSize = [attachment imageSizeWithoutTransaction];
    }
    return self;
}

- (void)clearAllViews
{
    [self.cachedMediaView removeFromSuperview];
    self.cachedMediaView = nil;
    self.attachmentUploadView = nil;
    self.audioProgressView = nil;
}

- (void)clearCachedMediaViews
{
    [super clearCachedMediaViews];
    [self clearAllViews];
}

- (void)setAppliesMediaViewMaskAsOutgoing:(BOOL)appliesMediaViewMaskAsOutgoing
{
    [super setAppliesMediaViewMaskAsOutgoing:appliesMediaViewMaskAsOutgoing];
    [self clearAllViews];
}

- (BOOL)isAudio {
    return [MIMETypeUtil isSupportedAudioMIMEType:_contentType];
}

- (BOOL)isVideo {
    return [MIMETypeUtil isSupportedVideoMIMEType:_contentType];
}

- (void)setAudioProgress:(CGFloat)progress duration:(CGFloat)duration
{
    OWSAssert([NSThread isMainThread]);

    self.audioProgressSeconds = progress;
    if (duration > 0) {
        self.audioDurationSeconds = duration;
    }

    [self updateAudioProgressView];

    [self updateAudioBottomLabel];
}

- (void)updateAudioBottomLabel
{
    if (self.isAudioPlaying && self.audioProgressSeconds > 0 && self.audioDurationSeconds > 0) {
        self.audioBottomLabel.text =
            [NSString stringWithFormat:@"%@ / %@",
                      [ViewControllerUtils formatDurationSeconds:(long)round(self.audioProgressSeconds)],
                      [ViewControllerUtils formatDurationSeconds:(long)round(self.audioDurationSeconds)]];
    } else {
        self.audioBottomLabel.text = [NSString
            stringWithFormat:@"%@", [ViewControllerUtils formatDurationSeconds:(long)round(self.audioDurationSeconds)]];
    }
}

- (void)setAudioIcon:(UIImage *)icon iconColor:(UIColor *)iconColor
{
    icon = [icon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    [_audioPlayPauseButton setImage:icon forState:UIControlStateNormal];
    [_audioPlayPauseButton setImage:icon forState:UIControlStateDisabled];
    _audioPlayPauseButton.imageView.tintColor = self.bubbleBackgroundColor;
    _audioPlayPauseButton.backgroundColor = iconColor;
    _audioPlayPauseButton.layer.cornerRadius
        = MIN(_audioPlayPauseButton.bounds.size.width, _audioPlayPauseButton.bounds.size.height) * 0.5f;
}

- (void)setAudioIconToPlay {
    [self setAudioIcon:[UIImage imageNamed:@"audio_play_black_40"]
             iconColor:(self.incoming ? [UIColor colorWithRGBHex:0x9e9e9e] : [self audioColorWithOpacity:0.15f])];
}

- (void)setAudioIconToPause {
    [self setAudioIcon:[UIImage imageNamed:@"audio_pause_black_40"]
             iconColor:(self.incoming ? [UIColor colorWithRGBHex:0x9e9e9e] : [self audioColorWithOpacity:0.15f])];
}

- (void)setIsAudioPlaying:(BOOL)isAudioPlaying
{
    _isAudioPlaying = isAudioPlaying;

    [self updateAudioProgressView];
}

- (void)updateAudioProgressView
{
    [self.audioProgressView
        setProgress:(self.audioDurationSeconds > 0 ? self.audioProgressSeconds / self.audioDurationSeconds : 0.f)];

    self.audioProgressView.horizontalBarColor = [self audioColorWithOpacity:0.75f];
    self.audioProgressView.progressColor
        = (self.isAudioPlaying ? [self audioColorWithOpacity:self.incoming ? 0.2f : 0.1f]
                               : [self audioColorWithOpacity:0.4f]);
}

#pragma mark - JSQMessageMediaData protocol

- (CGFloat)audioIconHMargin
{
    return 12.f;
}

- (CGFloat)audioIconHSpacing
{
    return 10.f;
}

- (CGFloat)audioIconVMargin
{
    return 12.f;
}

- (CGFloat)audioBubbleHeight
{
    return self.iconSize + self.audioIconVMargin * 2;
}

- (CGFloat)iconSize
{
    return 40.f;
}

- (UIColor *)audioTextColor
{
    return (self.incoming ? [UIColor colorWithWhite:0.2f alpha:1.f] : [UIColor whiteColor]);
}

- (UIColor *)audioColorWithOpacity:(CGFloat)alpha
{
    return [self.audioTextColor blendWithColor:self.bubbleBackgroundColor alpha:alpha];
}

- (UIColor *)bubbleBackgroundColor
{
    return self.incoming ? [UIColor jsq_messageBubbleLightGrayColor] : [UIColor ows_materialBlueColor];
}

- (UIView *)mediaView {
    if ([self isVideo]) {
        if (self.cachedMediaView == nil) {
            self.cachedMediaView = [self createVideoMediaView];
        }
    } else if ([self isAudio]) {
        if (self.cachedMediaView == nil) {
            self.cachedMediaView = [self createAudioMediaView];
        }

        if (self.isAudioPlaying) {
            [self setAudioIconToPause];
        } else {
            [self setAudioIconToPlay];
        }
    } else {
        // Unknown media type.
        OWSAssert(0);
    }
    return self.cachedMediaView;
}

- (UIView *)createVideoMediaView
{
    OWSAssert([self isVideo]);

    CGSize size = [self mediaViewDisplaySize];

    UIImage *image = self.attachment.image;
    if (!image) {
        DDLogError(@"%@ Could not load image: %@", [self tag], [self.attachment mediaURL]);
        OWSAssert(0);
        return nil;
    }
    UIImageView *imageView = [[UIImageView alloc] initWithImage:image];
    imageView.contentMode = UIViewContentModeScaleAspectFill;
    imageView.frame = CGRectMake(0.0f, 0.0f, size.width, size.height);
    imageView.clipsToBounds = YES;
    [JSQMessagesMediaViewBubbleImageMasker applyBubbleImageMaskToMediaView:imageView
                                                                isOutgoing:self.appliesMediaViewMaskAsOutgoing];
    UIImage *img = [UIImage imageNamed:@"play_button"];
    UIImageView *videoPlayButton = [[UIImageView alloc] initWithImage:img];
    videoPlayButton.frame = CGRectMake((size.width / 2) - 18, (size.height / 2) - 18, 37, 37);
    [imageView addSubview:videoPlayButton];

    if (!_incoming) {
        self.attachmentUploadView = [[AttachmentUploadView alloc] initWithAttachment:self.attachment
                                                                           superview:imageView
                                                             attachmentStateCallback:^(BOOL isAttachmentReady) {
                                                                 videoPlayButton.hidden = !isAttachmentReady;
                                                             }];
    }

    return imageView;
}

- (BOOL)isVoiceMessage
{
    OWSAssert([self isAudio]);

    // We want to treat "pre-voice messages flag" messages as voice messages if
    // they have no file name.
    //
    // TODO: Remove this after the flag has been in production for a few months.
    return (self.attachment.isVoiceMessage || self.attachment.sourceFilename.length < 1);
}

- (UIView *)createAudioMediaView
{
    OWSAssert([self isAudio]);

    self.audioDurationSeconds = [self.attachment audioDurationSecondsWithoutTransaction];

    CGSize viewSize = [self mediaViewDisplaySize];
    UIColor *textColor = [self audioTextColor];

    UIView *mediaView = [[UIView alloc] initWithFrame:CGRectMake(0.f, 0.f, viewSize.width, viewSize.height)];

    mediaView.backgroundColor = self.bubbleBackgroundColor;
    [JSQMessagesMediaViewBubbleImageMasker applyBubbleImageMaskToMediaView:mediaView isOutgoing:!self.incoming];

    const CGFloat kBubbleTailWidth = 6.f;
    CGRect contentFrame = CGRectMake(self.incoming ? kBubbleTailWidth : 0.f,
        self.audioIconVMargin,
        viewSize.width - kBubbleTailWidth - self.audioIconHMargin,
        viewSize.height - self.audioIconVMargin * 2);

    CGRect iconFrame = CGRectMake((CGFloat)round(contentFrame.origin.x + self.audioIconHMargin),
        (CGFloat)round(contentFrame.origin.y + (contentFrame.size.height - self.iconSize) * 0.5f),
        self.iconSize,
        self.iconSize);
    _audioPlayPauseButton = [[UIButton alloc] initWithFrame:iconFrame];
    _audioPlayPauseButton.enabled = NO;
    [mediaView addSubview:_audioPlayPauseButton];

    const CGFloat kLabelHSpacing = self.audioIconHSpacing;
    const CGFloat kLabelVSpacing = 2;
    NSString *filename = self.attachment.sourceFilename;
    if (!filename) {
        filename = [[self.attachment filePath] lastPathComponent];
    }
    NSString *topText = [[filename stringByDeletingPathExtension]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (topText.length < 1) {
        topText = [MIMETypeUtil fileExtensionForMIMEType:self.attachment.contentType].uppercaseString;
    }
    if (topText.length < 1) {
        topText = NSLocalizedString(@"GENERIC_ATTACHMENT_LABEL", @"A label for generic attachments.");
    }
    if (self.isVoiceMessage) {
        topText = nil;
    }
    UILabel *topLabel = [UILabel new];
    topLabel.text = topText;
    topLabel.textColor = [textColor colorWithAlphaComponent:0.85f];
    topLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    topLabel.font = [UIFont ows_regularFontWithSize:ScaleFromIPhone5To7Plus(11.f, 13.f)];
    [topLabel sizeToFit];
    [mediaView addSubview:topLabel];

    AudioProgressView *audioProgressView = [AudioProgressView new];
    self.audioProgressView = audioProgressView;
    [self updateAudioProgressView];
    [mediaView addSubview:audioProgressView];

    UILabel *bottomLabel = [UILabel new];
    self.audioBottomLabel = bottomLabel;
    [self updateAudioBottomLabel];
    bottomLabel.textColor = [textColor colorWithAlphaComponent:0.85f];
    bottomLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    bottomLabel.font = [UIFont ows_regularFontWithSize:ScaleFromIPhone5To7Plus(11.f, 13.f)];
    [bottomLabel sizeToFit];
    [mediaView addSubview:bottomLabel];

    const CGFloat topLabelHeight = (CGFloat)ceil(topLabel.font.lineHeight);
    const CGFloat kAudioProgressViewHeight = 12.f;
    const CGFloat bottomLabelHeight = (CGFloat)ceil(bottomLabel.font.lineHeight);
    CGRect labelsBounds = CGRectZero;
    labelsBounds.origin.x = (CGFloat)round(iconFrame.origin.x + iconFrame.size.width + kLabelHSpacing);
    labelsBounds.size.width = contentFrame.origin.x + contentFrame.size.width - labelsBounds.origin.x;
    labelsBounds.size.height = topLabelHeight + kAudioProgressViewHeight + bottomLabelHeight + kLabelVSpacing * 2;
    labelsBounds.origin.y
        = (CGFloat)round(contentFrame.origin.y + (contentFrame.size.height - labelsBounds.size.height) * 0.5f);

    CGFloat y = labelsBounds.origin.y;
    topLabel.frame
        = CGRectMake(labelsBounds.origin.x, labelsBounds.origin.y, labelsBounds.size.width, topLabelHeight);
    y += topLabelHeight + kLabelVSpacing;
    audioProgressView.frame = CGRectMake(labelsBounds.origin.x, y, labelsBounds.size.width, kAudioProgressViewHeight);
    y += kAudioProgressViewHeight + kLabelVSpacing;
    bottomLabel.frame = CGRectMake(labelsBounds.origin.x, y, labelsBounds.size.width, bottomLabelHeight);

    if (!self.incoming) {
        self.attachmentUploadView = [[AttachmentUploadView alloc] initWithAttachment:self.attachment
                                                                           superview:mediaView
                                                             attachmentStateCallback:nil];
    }

    return mediaView;
}

- (CGSize)mediaViewDisplaySize {
    CGSize size = [super mediaViewDisplaySize];
    if ([self isAudio]) {
        size.width = [self ows_maxMediaBubbleWidth:size];
        size.height = (CGFloat)ceil(self.audioBubbleHeight);
    } else if ([self isVideo]) {
        return [self ows_adjustBubbleSize:size forImageSize:self.imageSize];
    }
    return size;
}

- (UIView *)mediaPlaceholderView {
    return [self mediaView];
}

- (NSUInteger)hash {
    return [super hash];
}

#pragma mark - OWSMessageEditing Protocol

- (BOOL)canPerformEditingAction:(SEL)action
{
    if ([self isVideo]) {
        return (action == @selector(copy:) || action == NSSelectorFromString(@"save:"));
    } else if ([self isAudio]) {
        return (action == @selector(copy:));
    }

    NSString *actionString = NSStringFromSelector(action);
    DDLogError(
        @"Unexpected action: %@ for VideoAttachmentAdapter with contentType: %@", actionString, self.contentType);
    return NO;
}

- (void)performEditingAction:(SEL)action
{
    if ([self isVideo]) {
        if (action == @selector(copy:)) {
            NSString *utiType = [MIMETypeUtil utiTypeForMIMEType:_contentType];
            if (!utiType) {
                OWSAssert(0);
                utiType = (NSString *)kUTTypeVideo;
            }
            NSData *data = [NSData dataWithContentsOfURL:self.fileURL];
            if (!data) {
                OWSAssert(data);
                DDLogError(@"%@ Could not load data: %@", [self tag], [self.attachment mediaURL]);
                return;
            }
            [UIPasteboard.generalPasteboard setData:data forPasteboardType:utiType];
            return;
        } else if (action == NSSelectorFromString(@"save:")) {
            if (UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(self.fileURL.path)) {
                UISaveVideoAtPathToSavedPhotosAlbum(self.fileURL.path, self, nil, nil);
            } else {
                DDLogWarn(@"cowardly refusing to save incompatible video attachment");
            }
        }
    } else if ([self isAudio]) {
        if (action == @selector(copy:)) {
            NSString *utiType = [MIMETypeUtil utiTypeForMIMEType:_contentType];
            if (!utiType) {
                OWSAssert(0);
                utiType = (NSString *)kUTTypeAudio;
            }

            NSData *data = [NSData dataWithContentsOfURL:self.fileURL];
            if (!data) {
                OWSAssert(data);
                DDLogError(@"%@ Could not load data: %@", [self tag], [self.attachment mediaURL]);
                return;
            }
            [UIPasteboard.generalPasteboard setData:data forPasteboardType:utiType];
        }
    } else {
        // Shouldn't get here, as only supported actions should be exposed via canPerformEditingAction
        NSString *actionString = NSStringFromSelector(action);
        DDLogError(
            @"Unexpected action: %@ for VideoAttachmentAdapter with contentType: %@", actionString, self.contentType);
        OWSAssert(NO);
    }
}

#pragma mark - OWSMessageMediaAdapter

- (void)setCellVisible:(BOOL)isVisible
{
    // Ignore.
}

- (void)clearCachedMediaViewsIfLastPresentingCell:(id)cell
{
    OWSAssert(cell);

    if (cell == self.lastPresentingCell) {
        [self clearCachedMediaViews];
    }
}

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end

NS_ASSUME_NONNULL_END
