//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "TSVideoAttachmentAdapter.h"
#import "AttachmentUploadView.h"
#import "JSQMediaItem+OWS.h"
#import "MIMETypeUtil.h"
#import "TSAttachmentStream.h"
#import "TSMessagesManager.h"
#import "TSStorageManager+keyingMaterial.h"
#import "UIColor+JSQMessages.h"
#import "UIColor+OWS.h"
#import "UIFont+OWS.h"
#import "UIView+OWS.h"
#import "ViewControllerUtils.h"
#import <JSQMessagesViewController/JSQMessagesMediaViewBubbleImageMasker.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import <SignalServiceKit/MIMETypeUtil.h>

NS_ASSUME_NONNULL_BEGIN

@interface TSVideoAttachmentAdapter ()

@property (nonatomic) UIImage *image;
@property (nonatomic, nullable) UIView *cachedMediaView;
@property (nonatomic) TSAttachmentStream *attachment;
@property (nonatomic, nullable) UIButton *audioPlayPauseButton;
@property (nonatomic, nullable) UILabel *audioBottomLabel;
@property (nonatomic) BOOL incoming;
@property (nonatomic, nullable) AttachmentUploadView *attachmentUploadView;
@property (nonatomic) BOOL isAudioPlaying;
@property (nonatomic) CGFloat audioProgressSeconds;
@property (nonatomic) CGFloat audioDurationSeconds;
@property (nonatomic) BOOL isPaused;

// See comments on OWSMessageMediaAdapter.
@property (nonatomic, nullable, weak) id lastPresentingCell;

@end

#pragma mark -

@implementation TSVideoAttachmentAdapter

- (instancetype)initWithAttachment:(TSAttachmentStream *)attachment incoming:(BOOL)incoming {
    self = [super initWithFileURL:[attachment mediaURL] isReadyToPlay:YES];

    if (self) {
        _image           = attachment.image;
        _cachedMediaView = nil;
        _attachmentId    = attachment.uniqueId;
        _contentType     = attachment.contentType;
        _attachment      = attachment;
        _incoming        = incoming;
    }
    return self;
}

- (void)clearAllViews
{
    [_cachedMediaView removeFromSuperview];
    _cachedMediaView = nil;
    _attachmentUploadView = nil;
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
    self.audioDurationSeconds = duration;

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
        NSError *error;
        unsigned long long fileSize =
            [[NSFileManager defaultManager] attributesOfItemAtPath:self.attachment.filePath error:&error].fileSize;
        OWSAssert(!error);
        NSString *bottomText = [ViewControllerUtils formatFileSize:fileSize];
        self.audioBottomLabel.text = bottomText;
    }
}

- (void)setAudioIcon:(UIImage *)image
{
    [_audioPlayPauseButton setImage:image forState:UIControlStateNormal];
    [_audioPlayPauseButton setImage:image forState:UIControlStateDisabled];
    _audioPlayPauseButton.layer.opacity = 0.8f;
}

- (void)setAudioIconToPlay {
    [self setAudioIcon:[UIImage imageNamed:(self.incoming ? @"audio_play_black_40" : @"audio_play_white_40")]];
}

- (void)setAudioIconToPause {
    [self setAudioIcon:[UIImage imageNamed:(self.incoming ? @"audio_pause_black_40" : @"audio_pause_white_40")]];
}

#pragma mark - JSQMessageMediaData protocol

- (CGFloat)bubbleHeight
{
    return 35.f;
}

- (CGFloat)iconSize
{
    return 40.f;
}

- (CGFloat)vMargin
{
    return 10.f;
}

- (UIColor *)audioTextColor
{
    return (self.incoming ? [UIColor colorWithWhite:0.2 alpha:1.f] : [UIColor whiteColor]);
}

- (UIView *)mediaView {
    CGSize size = [self mediaViewDisplaySize];
    if ([self isVideo]) {
        if (self.cachedMediaView == nil) {
            UIImageView *imageView  = [[UIImageView alloc] initWithImage:self.image];
            imageView.contentMode   = UIViewContentModeScaleAspectFill;
            imageView.frame         = CGRectMake(0.0f, 0.0f, size.width, size.height);
            imageView.clipsToBounds = YES;
            [JSQMessagesMediaViewBubbleImageMasker applyBubbleImageMaskToMediaView:imageView
                                                                        isOutgoing:self.appliesMediaViewMaskAsOutgoing];
            self.cachedMediaView = imageView;
            UIImage *img           = [UIImage imageNamed:@"play_button"];
            UIImageView *videoPlayButton = [[UIImageView alloc] initWithImage:img];
            videoPlayButton.frame = CGRectMake((size.width / 2) - 18, (size.height / 2) - 18, 37, 37);
            [self.cachedMediaView addSubview:videoPlayButton];

            if (!_incoming) {
                self.attachmentUploadView = [[AttachmentUploadView alloc] initWithAttachment:self.attachment
                                                                                   superview:imageView
                                                                     attachmentStateCallback:^(BOOL isAttachmentReady) {
                                                                         videoPlayButton.hidden = !isAttachmentReady;
                                                                     }];
            }
        }
    } else if ([self isAudio]) {
        if (self.cachedMediaView == nil) {
            CGSize viewSize = [self mediaViewDisplaySize];
            UIColor *textColor = [self audioTextColor];

            _cachedMediaView = [[UIView alloc] initWithFrame:CGRectMake(0.f, 0.f, viewSize.width, viewSize.height)];

            _cachedMediaView.backgroundColor
                = self.incoming ? [UIColor jsq_messageBubbleLightGrayColor] : [UIColor ows_materialBlueColor];
            [JSQMessagesMediaViewBubbleImageMasker applyBubbleImageMaskToMediaView:_cachedMediaView
                                                                        isOutgoing:!self.incoming];

            const CGFloat kBubbleTailWidth = 6.f;
            CGRect contentFrame = CGRectMake(self.incoming ? kBubbleTailWidth : 0.f,
                self.vMargin,
                viewSize.width - kBubbleTailWidth - (self.incoming ? 10 : 15),
                viewSize.height - self.vMargin * 2);

            CGRect iconFrame = CGRectMake(round(contentFrame.origin.x + 10.f),
                round(contentFrame.origin.y + (contentFrame.size.height - self.iconSize) * 0.5f),
                self.iconSize,
                self.iconSize);
            _audioPlayPauseButton = [[UIButton alloc] initWithFrame:iconFrame];
            _audioPlayPauseButton.enabled = NO;
            [_cachedMediaView addSubview:_audioPlayPauseButton];

            const CGFloat kLabelHSpacing = 3;
            const CGFloat kLabelVSpacing = 2;
            NSString *topText =
                [self.attachment.filename stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (topText.length < 1) {
                topText = [MIMETypeUtil fileExtensionForMIMEType:self.attachment.contentType].uppercaseString;
            }
            if (topText.length < 1) {
                topText = NSLocalizedString(@"GENERIC_ATTACHMENT_LABEL", @"A label for generic attachments.");
            }
            UILabel *topLabel = [UILabel new];
            topLabel.text = topText;
            topLabel.textColor = textColor;
            topLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
            topLabel.font = [UIFont ows_regularFontWithSize:ScaleFromIPhone5To7Plus(13.f, 15.f)];
            [topLabel sizeToFit];
            [_cachedMediaView addSubview:topLabel];

            UILabel *audioBottomLabel = [UILabel new];
            self.audioBottomLabel = audioBottomLabel;
            [self updateAudioBottomLabel];
            audioBottomLabel.textColor = [textColor colorWithAlphaComponent:0.85f];
            audioBottomLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
            audioBottomLabel.font = [UIFont ows_regularFontWithSize:ScaleFromIPhone5To7Plus(11.f, 13.f)];
            [audioBottomLabel sizeToFit];
            [_cachedMediaView addSubview:audioBottomLabel];

            CGRect topLabelFrame = CGRectZero;
            topLabelFrame.size = topLabel.bounds.size;
            topLabelFrame.origin.x = round(iconFrame.origin.x + iconFrame.size.width + kLabelHSpacing);
            topLabelFrame.origin.y = round(contentFrame.origin.y
                + (contentFrame.size.height
                      - (topLabel.frame.size.height + audioBottomLabel.frame.size.height + kLabelVSpacing))
                    * 0.5f);
            topLabelFrame.size.width
                = round((contentFrame.origin.x + contentFrame.size.width) - topLabelFrame.origin.x);
            topLabel.frame = topLabelFrame;

            CGRect audioBottomLabelFrame = topLabelFrame;
            audioBottomLabelFrame.origin.y += topLabelFrame.size.height + kLabelVSpacing;
            audioBottomLabel.frame = audioBottomLabelFrame;

            if (!self.incoming) {
                self.attachmentUploadView = [[AttachmentUploadView alloc] initWithAttachment:self.attachment
                                                                                   superview:_cachedMediaView
                                                                     attachmentStateCallback:nil];
            }
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

- (CGSize)mediaViewDisplaySize {
    CGSize size = [super mediaViewDisplaySize];
    if ([self isAudio]) {
        size.height = ceil(self.bubbleHeight + self.vMargin * 2);
    } else if ([self isVideo]) {
        return [self ows_adjustBubbleSize:size forImage:self.image];
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
                if ([_contentType isEqualToString:@"audio/amr"]) {
                    utiType = @"org.3gpp.adaptive-multi-rate-audio";
                } else if ([_contentType isEqualToString:@"audio/mp3"] ||
                    [_contentType isEqualToString:@"audio/x-mpeg"] || [_contentType isEqualToString:@"audio/mpeg"] ||
                    [_contentType isEqualToString:@"audio/mpeg3"] || [_contentType isEqualToString:@"audio/x-mp3"] ||
                    [_contentType isEqualToString:@"audio/x-mpeg3"]) {
                    utiType = (NSString *)kUTTypeMP3;
                } else if ([_contentType isEqualToString:@"audio/aac"] ||
                    [_contentType isEqualToString:@"audio/x-m4a"]) {
                    utiType = (NSString *)kUTTypeMPEG4Audio;
                } else if ([_contentType isEqualToString:@"audio/aiff"] ||
                    [_contentType isEqualToString:@"audio/x-aiff"]) {
                    utiType = (NSString *)kUTTypeAudioInterchangeFileFormat;
                } else {
                    OWSAssert(0);
                    utiType = (NSString *)kUTTypeAudio;
                }
            }

            NSData *data = [NSData dataWithContentsOfURL:self.fileURL];
            OWSAssert(data);
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

@end

NS_ASSUME_NONNULL_END
