//
//  TSAttachementAdapter.m
//  Signal
//
//  Created by Frederic Jacobs on 17/12/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSMessagesManager.h"
#import "TSVideoAttachmentAdapter.h"

#import "FFCircularProgressView.h"
#import "JSQMessagesMediaViewBubbleImageMasker.h"
#import "MIMETypeUtil.h"
#import "SCWaveformView.h"
#import "TSStorageManager+keyingMaterial.h"
#define AUDIO_BAR_HEIGHT 36

@interface TSVideoAttachmentAdapter ()

@property UIImage *image;
@property (strong, nonatomic) UIImageView *cachedImageView;
@property (strong, nonatomic) UIImageView *videoPlayButton;
@property (strong, nonatomic) CALayer *maskLayer;
@property (strong, nonatomic) FFCircularProgressView *progressView;
@property (strong, nonatomic) TSAttachmentStream *attachment;
@property (strong, nonatomic) UIProgressView *audioProgress;
@property (strong, nonatomic) SCWaveformView *waveform;
@property (strong, nonatomic) UIButton *audioPlayPauseButton;
@property (strong, nonatomic) UILabel *durationLabel;
@property (strong, nonatomic) UIView *audioBubble;
@property (nonatomic) BOOL incoming;

@end

@implementation TSVideoAttachmentAdapter

- (instancetype)initWithAttachment:(TSAttachmentStream *)attachment incoming:(BOOL)incoming {
    self = [super initWithFileURL:[attachment mediaURL] isReadyToPlay:YES];

    if (self) {
        ;
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
            _maskLayer              = [CALayer layer];
            [_maskLayer setBackgroundColor:[UIColor blackColor].CGColor];
            [_maskLayer setOpacity:0.4f];
            [_maskLayer setFrame:self.cachedImageView.frame];
            [self.cachedImageView.layer addSublayer:_maskLayer];
            _progressView = [[FFCircularProgressView alloc]
                initWithFrame:CGRectMake((size.width / 2) - 18, (size.height / 2) - 18, 37, 37)];
            [_cachedImageView addSubview:_progressView];
            if (_attachment.isDownloaded) {
                _videoPlayButton.hidden = NO;
                _maskLayer.hidden       = YES;
                _progressView.hidden    = YES;
            }
            [[NSNotificationCenter defaultCenter] addObserver:self
                                                     selector:@selector(attachmentUploadProgress:)
                                                         name:@"attachmentUploadProgress"
                                                       object:nil];
        }
    } else if ([self isAudio]) {
        NSError *err = NULL;
        NSURL *url =
            [MIMETypeUtil simLinkCorrectExtensionOfFile:_attachment.mediaURL ofMIMEType:_attachment.contentType];

        AVURLAsset *asset         = [[AVURLAsset alloc] initWithURL:url options:nil];
        _waveform                 = [[SCWaveformView alloc] init];
        _waveform.frame           = CGRectMake(42.0, 0.0, size.width - 84, size.height);
        _waveform.asset           = asset;
        _waveform.progressColor   = [UIColor whiteColor];
        _waveform.backgroundColor = [UIColor colorWithRed:229 / 255.0f green:228 / 255.0f blue:234 / 255.0f alpha:1.0f];
        [_waveform generateWaveforms];
        _waveform.progress = 0.0;

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

        return _audioBubble;
    }
    return self.cachedImageView;
}

- (CGSize)mediaViewDisplaySize {
    CGSize mediaDisplaySize;
    if ([self isVideo]) {
        mediaDisplaySize = [super mediaViewDisplaySize];
    } else if ([self isAudio]) {
        CGSize size      = [super mediaViewDisplaySize];
        size.height      = AUDIO_BAR_HEIGHT;
        mediaDisplaySize = size;
    }
    return mediaDisplaySize;
}

- (UIView *)mediaPlaceholderView {
    return [self mediaView];
}

- (NSUInteger)hash {
    return [super hash];
}

- (void)attachmentUploadProgress:(NSNotification *)notification {
    NSDictionary *userinfo = [notification userInfo];
    double progress        = [[userinfo objectForKey:@"progress"] doubleValue];
    NSString *attachmentID = [userinfo objectForKey:@"attachmentID"];
    if ([_attachmentId isEqualToString:attachmentID]) {
        NSLog(@"is downloaded: %d", _attachment.isDownloaded);
        if (!isnan(progress)) {
            [_progressView setProgress:(float)progress];
        }
        if (progress >= 1) {
            _maskLayer.hidden        = YES;
            _progressView.hidden     = YES;
            _videoPlayButton.hidden  = NO;
            _attachment.isDownloaded = YES;
            [[TSMessagesManager sharedManager]
                    .dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
              [_attachment saveWithTransaction:transaction];
            }];
        }
    }
    // set progress on bar
}

- (void)dealloc {
    _image           = nil;
    _cachedImageView = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setAppliesMediaViewMaskAsOutgoing:(BOOL)appliesMediaViewMaskAsOutgoing {
    [super setAppliesMediaViewMaskAsOutgoing:appliesMediaViewMaskAsOutgoing];
    _cachedImageView = nil;
}

@end
