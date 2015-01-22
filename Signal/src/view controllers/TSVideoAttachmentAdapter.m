//
//  TSAttachementAdapter.m
//  Signal
//
//  Created by Frederic Jacobs on 17/12/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSVideoAttachmentAdapter.h"
#import "TSMessagesManager.h"

#import "UIDevice+TSHardwareVersion.h"
#import "JSQMessagesMediaViewBubbleImageMasker.h"
#import "FFCircularProgressView.h"
#import "TSStorageManager+keyingMaterial.h"
#import "TSNetworkManager.h"
#import "UIColor+OWS.h"

#define AUDIO_BAR_HEIGHT 30;

@interface TSVideoAttachmentAdapter ()

@property UIImage *image;
@property (strong, nonatomic) UIImageView *cachedImageView;
@property (strong, nonatomic) UIImageView *playButton;
@property (strong, nonatomic) CALayer *maskLayer;
@property (strong, nonatomic) FFCircularProgressView *progressView;
@property (strong, nonatomic) TSAttachmentStream *attachment;
@property (strong, nonatomic) UIProgressView *audioProgress;
@property (strong, nonatomic) UIImageView *playPauseButton;
@property (nonatomic) UILabel *durationLabel;

@end

@implementation TSVideoAttachmentAdapter

- (instancetype)initWithAttachment:(TSAttachmentStream*)attachment{
    self = [super initWithFileURL:[attachment mediaURL] isReadyToPlay:YES];

    if (self) {;
        _image           = attachment.image;
        _cachedImageView = nil;
        _attachmentId    = attachment.uniqueId;
        _contentType     = attachment.contentType;
        _attachment = attachment;

    }
    return self;
}

-(BOOL) isImage{
    return NO;
}

-(BOOL) isAudio {
    return [_contentType containsString:@"audio/"];
}


-(BOOL) isVideo {
    return [_contentType containsString:@"video/"];
}

-(void) setAudioProgressFromFloat:(float)progress {
    [_audioProgress setProgress:progress];
}

-(void) setAudioIconToPause {
    [_playPauseButton removeFromSuperview];
    _playPauseButton = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"pause_icon"]];
    _playPauseButton.frame = CGRectMake(10, 8, 10, 14);
    [_audioProgress addSubview:_playPauseButton];
}

-(void) setAudioIconToPlay {
    [_playPauseButton removeFromSuperview];
    _playPauseButton = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"play_icon"]];
    _playPauseButton.frame = CGRectMake(10, 8, 10, 14);
    [_audioProgress addSubview:_playPauseButton];
}

-(void) setDurationOfAudio:(NSTimeInterval)duration {
    [_durationLabel removeFromSuperview];
    double dur = duration;
    int minutes = (int) (dur/60);
    int seconds = (int) (dur - minutes*60);
    NSString *minutes_str = [NSString stringWithFormat:@"%01d", minutes];
    NSString *seconds_str = [NSString stringWithFormat:@"%02d", seconds];
    NSString *label_text = [NSString stringWithFormat:@"%@:%@", minutes_str, seconds_str];

    CGSize size = [self mediaViewDisplaySize];
    _durationLabel = [[UILabel alloc] initWithFrame:CGRectMake(size.width - 40, 0, 50, 30)];
    _durationLabel.text = label_text;
    _durationLabel.textColor = [UIColor whiteColor];
    [_audioProgress addSubview:_durationLabel];
}

-(void) removeDurationLabel {
    [_durationLabel removeFromSuperview];
}

#pragma mark - JSQMessageMediaData protocol

- (UIView *)mediaView
{
    CGSize size = [self mediaViewDisplaySize];
    if ([self isVideo]) {
        if (self.cachedImageView == nil) {
            UIImageView *imageView = [[UIImageView alloc] initWithImage:self.image];
            imageView.frame = CGRectMake(0.0f, 0.0f, size.width, size.height);
            imageView.contentMode = UIViewContentModeScaleAspectFill;
            imageView.clipsToBounds = YES;
            [JSQMessagesMediaViewBubbleImageMasker applyBubbleImageMaskToMediaView:imageView isOutgoing:self.appliesMediaViewMaskAsOutgoing];
            self.cachedImageView = imageView;
            UIImage *img = [UIImage imageNamed:@"play_button"];
            _playButton = [[UIImageView alloc] initWithImage:img];
            _playButton.frame = CGRectMake((size.width/2)-18, (size.height/2)-18, 37, 37);
            [self.cachedImageView addSubview:_playButton];
            _playButton.hidden = YES;
            _maskLayer = [CALayer layer];
            [_maskLayer setBackgroundColor:[UIColor blackColor].CGColor];
            [_maskLayer setOpacity:0.4f];
            [_maskLayer setFrame:self.cachedImageView.frame];
            [self.cachedImageView.layer addSublayer:_maskLayer];
            _progressView = [[FFCircularProgressView alloc] initWithFrame:CGRectMake((size.width/2)-18, (size.height/2)-18, 37, 37)];
            [_cachedImageView addSubview:_progressView];
            if (_attachment.isDownloaded) {
                _playButton.hidden = NO;
                _maskLayer.hidden = YES;
                _progressView.hidden = YES;
            }
            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(attachmentUploadProgress:) name:@"attachmentUploadProgress" object:nil];
        }
    } else if ([self isAudio]) {
        UIImageView *backgroundImage = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, size.width, 30)];
        backgroundImage.backgroundColor = [UIColor colorWithRed:189/255.0f green:190/255.0f blue:194/255.0f alpha:1.0f];

        _audioProgress = [[UIProgressView alloc] initWithFrame:CGRectMake(0, 0, size.width, 4)];

        _playPauseButton = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"play_icon"]];
        _playPauseButton.frame = CGRectMake(10, 8, 10, 14);
        [_audioProgress addSubview:_playPauseButton];

        return _audioProgress;
    }
    return self.cachedImageView;
}

- (CGSize)mediaViewDisplaySize
{
    CGSize mediaDisplaySize;
    if ([self isVideo]) {
        mediaDisplaySize = [super mediaViewDisplaySize];
    } else if ([self isAudio]) {
        CGSize size = [super mediaViewDisplaySize];
        size.height = AUDIO_BAR_HEIGHT;
        mediaDisplaySize = size;
    }
    return mediaDisplaySize;
}

- (UIView *)mediaPlaceholderView
{
    return [self mediaView];
}

- (NSUInteger)hash
{
    return [super hash];
}

- (void)attachmentUploadProgress:(NSNotification*)notification {
    NSDictionary *userinfo = [notification userInfo];
    double progress = [[userinfo objectForKey:@"progress"] doubleValue];
    NSString *attachmentID = [userinfo objectForKey:@"attachmentID"];
    if ([_attachmentId isEqualToString:attachmentID]) {
        NSLog(@"is downloaded: %d", _attachment.isDownloaded);
        [_progressView setProgress: (float)progress];
        if (progress >= 1) {
            _maskLayer.hidden = YES;
            _progressView.hidden = YES;
            _playButton.hidden = NO;
            _attachment.isDownloaded = YES;
            [[TSMessagesManager sharedManager].dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                [_attachment saveWithTransaction:transaction];
            }];
        }
    }
    //set progress on bar
}

- (void)dealloc {
    _image = nil;
    _cachedImageView = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setAppliesMediaViewMaskAsOutgoing:(BOOL)appliesMediaViewMaskAsOutgoing
{
    [super setAppliesMediaViewMaskAsOutgoing:appliesMediaViewMaskAsOutgoing];
    _cachedImageView = nil;
}

@end
