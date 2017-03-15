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
#import <JSQMessagesViewController/JSQMessagesMediaViewBubbleImageMasker.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import <SCWaveformView.h>
#define AUDIO_BAR_HEIGHT 36

@interface TSVideoAttachmentAdapter ()

@property (nonatomic) UIImage *image;
@property (nonatomic) UIImageView *cachedImageView;
@property (nonatomic) UIImageView *videoPlayButton;
@property (nonatomic) TSAttachmentStream *attachment;
@property (nonatomic) UIProgressView *audioProgress;
@property (nonatomic) SCWaveformView *waveform;
@property (nonatomic) UIButton *audioPlayPauseButton;
@property (nonatomic) UILabel *durationLabel;
@property (nonatomic) UIView *audioBubble;
@property (nonatomic) BOOL incoming;
@property (nonatomic) AttachmentUploadView *attachmentUploadView;

@end

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

- (BOOL)isImage {
    return NO;
}

- (BOOL)isAudio {
    return [MIMETypeUtil isSupportedAudioMIMEType:_contentType];
}


- (BOOL)isVideo {
    return [MIMETypeUtil isSupportedVideoMIMEType:_contentType];
}

- (NSString *)formatDuration:(NSTimeInterval)duration {
    double dur            = duration;
    int minutes           = (int)(dur / 60);
    int seconds           = (int)(dur - minutes * 60);
    NSString *minutes_str = [NSString stringWithFormat:@"%01d", minutes];
    NSString *seconds_str = [NSString stringWithFormat:@"%02d", seconds];
    NSString *label_text  = [NSString stringWithFormat:@"%@:%@", minutes_str, seconds_str];
    return label_text;
}

- (void)setAudioProgressFromFloat:(float)progress {
    dispatch_async(dispatch_get_main_queue(), ^{
      if (!isnan(progress)) {
          [_waveform setProgress:progress];
          [_waveform generateWaveforms];
          [_waveform setNeedsDisplay];
      }
    });
}

- (void)resetAudioDuration {
    NSError *err;
    AVAudioPlayer *player = [[AVAudioPlayer alloc] initWithContentsOfURL:_attachment.mediaURL error:&err];
    _durationLabel.text   = [self formatDuration:player.duration];
}

- (void)setDurationOfAudio:(NSTimeInterval)duration {
    _durationLabel.text = [self formatDuration:duration];
}

- (void)setAudioIconToPlay {
    [_audioPlayPauseButton setBackgroundImage:[UIImage imageNamed:@"audio_play_button_blue"]
                                     forState:UIControlStateNormal];
}

- (void)setAudioIconToPause {
    [_audioPlayPauseButton setBackgroundImage:[UIImage imageNamed:@"audio_pause_button_blue"]
                                     forState:UIControlStateNormal];
}

- (void)removeDurationLabel {
    [_durationLabel removeFromSuperview];
}

#pragma mark - JSQMessageMediaData protocol

- (UIView *)mediaView {
    CGSize size = [self mediaViewDisplaySize];
    if ([self isVideo]) {
        if (self.cachedImageView == nil) {
            UIImageView *imageView  = [[UIImageView alloc] initWithImage:self.image];
            imageView.frame         = CGRectMake(0.0f, 0.0f, size.width, size.height);
            imageView.contentMode   = UIViewContentModeScaleAspectFill;
            imageView.clipsToBounds = YES;
            [JSQMessagesMediaViewBubbleImageMasker applyBubbleImageMaskToMediaView:imageView
                                                                        isOutgoing:self.appliesMediaViewMaskAsOutgoing];
            self.cachedImageView   = imageView;
            UIImage *img           = [UIImage imageNamed:@"play_button"];
            _videoPlayButton       = [[UIImageView alloc] initWithImage:img];
            _videoPlayButton.frame = CGRectMake((size.width / 2) - 18, (size.height / 2) - 18, 37, 37);
            [self.cachedImageView addSubview:_videoPlayButton];
            _videoPlayButton.hidden = YES;

            if (!_incoming) {
                __weak TSVideoAttachmentAdapter *weakSelf = self;
                self.attachmentUploadView = [[AttachmentUploadView alloc] initWithAttachment:self.attachment
                                                                                   superview:imageView
                                                                     attachmentStateCallback:^(BOOL isAttachmentReady) {
                                                                         weakSelf.videoPlayButton.hidden
                                                                             = !isAttachmentReady;
                                                                     }];
            }
        }
    } else if ([self isAudio]) {
        NSError *err = NULL;
        NSURL *url =
            [MIMETypeUtil simLinkCorrectExtensionOfFile:_attachment.mediaURL ofMIMEType:_attachment.contentType];

        if (!self.waveform) {
            AVURLAsset *asset         = [[AVURLAsset alloc] initWithURL:url options:nil];
            self.waveform                 = [[SCWaveformView alloc] init];
            self.waveform.frame           = CGRectMake(42.0, 0.0, size.width - 84, size.height);
            self.waveform.asset           = asset;
            self.waveform.progressColor   = [UIColor whiteColor];
            self.waveform.backgroundColor = [UIColor colorWithRed:229 / 255.0f green:228 / 255.0f blue:234 / 255.0f alpha:1.0f];
            [self.waveform generateWaveforms];
            self.waveform.progress = 0.0;
        }

        _audioBubble = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, size.width, size.height)];
        _audioBubble.backgroundColor =
            [UIColor colorWithRed:10 / 255.0f green:130 / 255.0f blue:253 / 255.0f alpha:1.0f];
        _audioBubble.layer.cornerRadius  = 18;
        _audioBubble.layer.masksToBounds = YES;

        _audioPlayPauseButton = [[UIButton alloc] initWithFrame:CGRectMake(3, 3, 30, 30)];
        [_audioPlayPauseButton setBackgroundImage:[UIImage imageNamed:@"audio_play_button"]
                                         forState:UIControlStateNormal];

        AVAudioPlayer *player = [[AVAudioPlayer alloc] initWithContentsOfURL:url error:&err];
        _durationLabel        = [[UILabel alloc] init];
        _durationLabel.text   = [self formatDuration:player.duration];
        _durationLabel.font   = [UIFont systemFontOfSize:14];
        [_durationLabel sizeToFit];
        _durationLabel.frame = CGRectMake((size.width - _durationLabel.frame.size.width) - 10,
                                          _durationLabel.frame.origin.y,
                                          _durationLabel.frame.size.width,
                                          AUDIO_BAR_HEIGHT);
        _durationLabel.backgroundColor = [UIColor clearColor];
        _durationLabel.textColor       = [UIColor whiteColor];

        if (_incoming) {
            _audioBubble.backgroundColor =
                [UIColor colorWithRed:229 / 255.0f green:228 / 255.0f blue:234 / 255.0f alpha:1.0f];
            _waveform.normalColor = [UIColor whiteColor];
            _waveform.progressColor =
                [UIColor colorWithRed:107 / 255.0f green:185 / 255.0f blue:254 / 255.0f alpha:1.0f];
            [_audioPlayPauseButton setBackgroundImage:[UIImage imageNamed:@"audio_play_button_blue"]
                                             forState:UIControlStateNormal];
            _durationLabel.textColor = [UIColor darkTextColor];
        }

        [_audioBubble addSubview:_waveform];
        [_audioBubble addSubview:_audioPlayPauseButton];
        [_audioBubble addSubview:_durationLabel];

        if (!_incoming) {
            __weak TSVideoAttachmentAdapter *weakSelf = self;
            self.attachmentUploadView = [[AttachmentUploadView alloc] initWithAttachment:self.attachment
                                                                               superview:_audioBubble
                                                                 attachmentStateCallback:^(BOOL isAttachmentReady) {
                                                                     weakSelf.audioPlayPauseButton.enabled
                                                                         = isAttachmentReady;
                                                                 }];
        }

        return _audioBubble;
    } else {
        // Unknown media type.
        OWSAssert(0);
    }
    return self.cachedImageView;
}

- (CGSize)mediaViewDisplaySize {
    CGSize size = [super mediaViewDisplaySize];
    if ([self isAudio]) {
        size.height = AUDIO_BAR_HEIGHT;
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

- (void)setAppliesMediaViewMaskAsOutgoing:(BOOL)appliesMediaViewMaskAsOutgoing {
    [super setAppliesMediaViewMaskAsOutgoing:appliesMediaViewMaskAsOutgoing];
    _cachedImageView = nil;
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
            [UIPasteboard.generalPasteboard setData:data forPasteboardType:(NSString *)UIPasteboardNameGeneral];

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
    }
}

@end
