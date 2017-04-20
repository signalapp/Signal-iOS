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
#import "UIColor+OWS.h"
#import "UIFont+OWS.h"
#import "UIView+OWS.h"
#import <JSQMessagesViewController/JSQMessagesMediaViewBubbleImageMasker.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import <SignalServiceKit/MIMETypeUtil.h>

const CGFloat kAudioViewWidth = 100;
const CGFloat kAudioButtonHeight = kAudioViewWidth;
const CGFloat kAudioViewVSpacing = 5;
const CGFloat kAudioLabelHeight = 20;
const CGFloat kAudioBottomMargin = 5;

NS_ASSUME_NONNULL_BEGIN

@interface TSVideoAttachmentAdapter ()

@property (nonatomic) UIImage *image;
@property (nonatomic, nullable) UIImageView *cachedImageView;
@property (nonatomic) TSAttachmentStream *attachment;
@property (nonatomic, nullable) UIButton *audioPlayPauseButton;
@property (nonatomic, nullable) UILabel *audioLabel;
@property (nonatomic) BOOL incoming;
@property (nonatomic, nullable) AttachmentUploadView *attachmentUploadView;
@property (nonatomic) BOOL isAudioPlaying;
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
        _cachedImageView = nil;
        _attachmentId    = attachment.uniqueId;
        _contentType     = attachment.contentType;
        _attachment      = attachment;
        _incoming        = incoming;
    }
    return self;
}

- (void)clearAllViews
{
    [_cachedImageView removeFromSuperview];
    _cachedImageView = nil;
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

- (void)setAudioIconToPlay {
    [_audioPlayPauseButton
        setImage:[UIImage imageNamed:(_incoming ? @"audio_play_blue_bubble" : @"audio_play_white_bubble")]
        forState:UIControlStateNormal];
}

- (void)setAudioIconToPause {
    [_audioPlayPauseButton
        setImage:[UIImage imageNamed:(_incoming ? @"audio_pause_blue_bubble" : @"audio_pause_white_bubble")]
        forState:UIControlStateNormal];
}

#pragma mark - JSQMessageMediaData protocol

- (UIView *)mediaView {
    CGSize size = [self mediaViewDisplaySize];
    if ([self isVideo]) {
        if (self.cachedImageView == nil) {
            UIImageView *imageView  = [[UIImageView alloc] initWithImage:self.image];
            imageView.contentMode   = UIViewContentModeScaleAspectFill;
            imageView.frame         = CGRectMake(0.0f, 0.0f, size.width, size.height);
            imageView.clipsToBounds = YES;
            [JSQMessagesMediaViewBubbleImageMasker applyBubbleImageMaskToMediaView:imageView
                                                                        isOutgoing:self.appliesMediaViewMaskAsOutgoing];
            self.cachedImageView   = imageView;
            UIImage *img           = [UIImage imageNamed:@"play_button"];
            UIImageView *videoPlayButton = [[UIImageView alloc] initWithImage:img];
            videoPlayButton.frame = CGRectMake((size.width / 2) - 18, (size.height / 2) - 18, 37, 37);
            [self.cachedImageView addSubview:videoPlayButton];

            if (!_incoming) {
                self.attachmentUploadView = [[AttachmentUploadView alloc] initWithAttachment:self.attachment
                                                                                   superview:imageView
                                                                     attachmentStateCallback:^(BOOL isAttachmentReady) {
                                                                         videoPlayButton.hidden = !isAttachmentReady;
                                                                     }];
            }
        }
    } else if ([self isAudio]) {
        UIView *audioBubble = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, size.width, size.height)];
        audioBubble.backgroundColor =
            [UIColor colorWithRed:10 / 255.0f green:130 / 255.0f blue:253 / 255.0f alpha:1.0f];
        audioBubble.layer.cornerRadius = 18;
        audioBubble.layer.masksToBounds = YES;

        _audioPlayPauseButton = [[UIButton alloc] initWithFrame:CGRectMake(0, 0, kAudioViewWidth, kAudioButtonHeight)];
        _audioPlayPauseButton.enabled = NO;

        NSString *audioLabelText = [[MIMETypeUtil fileExtensionForMIMEType:self.contentType] uppercaseString];
        if (!audioLabelText) {
            audioLabelText = NSLocalizedString(
                @"MESSAGES_VIEW_AUDIO_TYPE_GENERIC", @"A label for audio attachments of unknown type.");
        }

        _audioLabel = [[UILabel alloc] init];
        _audioLabel.text = audioLabelText;
        _audioLabel.font = [UIFont ows_mediumFontWithSize:14.f];
        _audioLabel.textColor = (_incoming ? [UIColor colorWithRGBHex:0x0b83fd] : [UIColor whiteColor]);
        _audioLabel.textAlignment = NSTextAlignmentCenter;
        _audioLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [_audioLabel sizeToFit];
        _audioLabel.frame = CGRectMake(0, kAudioButtonHeight + kAudioViewVSpacing, kAudioViewWidth, kAudioLabelHeight);

        if (_incoming) {
            audioBubble.backgroundColor =
                [UIColor colorWithRed:229 / 255.0f green:228 / 255.0f blue:234 / 255.0f alpha:1.0f];
        }

        [audioBubble addSubview:_audioPlayPauseButton];
        [audioBubble addSubview:_audioLabel];

        if (!_incoming) {
            self.attachmentUploadView = [[AttachmentUploadView alloc] initWithAttachment:self.attachment
                                                                               superview:audioBubble
                                                                 attachmentStateCallback:nil];
        }

        if (self.isAudioPlaying) {
            [self setAudioIconToPause];
        } else {
            [self setAudioIconToPlay];
        }

        return audioBubble;
    } else {
        // Unknown media type.
        OWSAssert(0);
    }
    return self.cachedImageView;
}

- (CGSize)mediaViewDisplaySize {
    CGSize size = [super mediaViewDisplaySize];
    if ([self isAudio]) {
        size.width = kAudioViewWidth;
        size.height = kAudioButtonHeight + kAudioViewVSpacing + kAudioLabelHeight + kAudioBottomMargin;

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
            NSData *data = [NSData dataWithContentsOfURL:self.fileURL];
            // TODO: This assumes all videos are mp4.
            [UIPasteboard.generalPasteboard setData:data forPasteboardType:(NSString *)kUTTypeMPEG4];
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
            NSData *data = [NSData dataWithContentsOfURL:self.fileURL];

            NSString *pasteboardType = [MIMETypeUtil getSupportedExtensionFromAudioMIMEType:self.contentType];

            if ([pasteboardType isEqualToString:@"mp3"]) {
                [UIPasteboard.generalPasteboard setData:data forPasteboardType:(NSString *)kUTTypeMP3];
            } else if ([pasteboardType isEqualToString:@"aiff"]) {
                [UIPasteboard.generalPasteboard setData:data
                                      forPasteboardType:(NSString *)kUTTypeAudioInterchangeFileFormat];
            } else if ([pasteboardType isEqualToString:@"m4a"]) {
                [UIPasteboard.generalPasteboard setData:data forPasteboardType:(NSString *)kUTTypeMPEG4Audio];
            } else if ([pasteboardType isEqualToString:@"amr"]) {
                [UIPasteboard.generalPasteboard setData:data forPasteboardType:@"org.3gpp.adaptive-multi-rate-audio"];
            } else {
                [UIPasteboard.generalPasteboard setData:data forPasteboardType:(NSString *)kUTTypeAudio];
            }
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
