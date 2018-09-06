//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSAudioPlayer.h"
#import "TSAttachmentStream.h"
#import <AVFoundation/AVFoundation.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/NSTimer+OWS.h>

NS_ASSUME_NONNULL_BEGIN

// A no-op delegate implementation to be used when we don't need a delegate.
@interface OWSAudioPlayerDelegateStub : NSObject <OWSAudioPlayerDelegate>

@property (nonatomic) AudioPlaybackState audioPlaybackState;

@end

#pragma mark -

@implementation OWSAudioPlayerDelegateStub

- (void)setAudioProgress:(CGFloat)progress duration:(CGFloat)duration
{
    // Do nothing;
}

@end

#pragma mark -

@interface OWSAudioPlayer () <AVAudioPlayerDelegate>

@property (nonatomic, readonly) NSURL *mediaUrl;
@property (nonatomic, nullable) AVAudioPlayer *audioPlayer;
@property (nonatomic, nullable) NSTimer *audioPlayerPoller;
@property (nonatomic, readonly) AudioActivity *audioActivity;

@end

#pragma mark -

@implementation OWSAudioPlayer

- (instancetype)initWithMediaUrl:(NSURL *)mediaUrl
{
    return [self initWithMediaUrl:mediaUrl delegate:[OWSAudioPlayerDelegateStub new]];
}

- (instancetype)initWithMediaUrl:(NSURL *)mediaUrl delegate:(id<OWSAudioPlayerDelegate>)delegate
{
    self = [super init];
    if (!self) {
        return self;
    }

    OWSAssertDebug(mediaUrl);
    OWSAssertDebug(delegate);

    _delegate = delegate;
    _mediaUrl = mediaUrl;

    NSString *audioActivityDescription = [NSString stringWithFormat:@"%@ %@", self.logTag, self.mediaUrl];
    _audioActivity = [[AudioActivity alloc] initWithAudioDescription:audioActivityDescription];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidEnterBackground:)
                                                 name:OWSApplicationDidEnterBackgroundNotification
                                               object:nil];

    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];

    [DeviceSleepManager.sharedInstance removeBlockWithBlockObject:self];

    [self stop];
}

- (void)applicationDidEnterBackground:(NSNotification *)notification
{
    [self stop];
}

#pragma mark - Methods

- (void)playWithCurrentAudioCategory
{
    OWSAssertIsOnMainThread();
    [OWSAudioSession.shared startAudioActivity:self.audioActivity];

    [self play];
}

- (void)playWithPlaybackAudioCategory
{
    OWSAssertIsOnMainThread();
    [OWSAudioSession.shared startPlaybackAudioActivity:self.audioActivity];

    [self play];
}

- (void)play
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(self.mediaUrl);
    OWSAssertDebug([self.delegate audioPlaybackState] != AudioPlaybackState_Playing);

    [self.audioPlayerPoller invalidate];

    self.delegate.audioPlaybackState = AudioPlaybackState_Playing;

    if (!self.audioPlayer) {
        NSError *error;
        self.audioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:self.mediaUrl error:&error];
        if (error) {
            OWSLogError(@"error: %@", error);
            [self stop];

            if ([error.domain isEqualToString:NSOSStatusErrorDomain]
                && (error.code == kAudioFileInvalidFileError || error.code == kAudioFileStreamError_InvalidFile)) {
                [OWSAlerts
                    showErrorAlertWithMessage:NSLocalizedString(@"INVALID_AUDIO_FILE_ALERT_ERROR_MESSAGE",
                                                  @"Message for the alert indicating that an audio file is invalid.")];
            }

            return;
        }
        self.audioPlayer.delegate = self;
        if (self.isLooping) {
            self.audioPlayer.numberOfLoops = -1;
        }
    }

    [self.audioPlayer play];
    [self.audioPlayerPoller invalidate];
    self.audioPlayerPoller = [NSTimer weakScheduledTimerWithTimeInterval:.05f
                                                                  target:self
                                                                selector:@selector(audioPlayerUpdated:)
                                                                userInfo:nil
                                                                 repeats:YES];

    // Prevent device from sleeping while playing audio.
    [DeviceSleepManager.sharedInstance addBlockWithBlockObject:self];
}

- (void)pause
{
    OWSAssertIsOnMainThread();

    self.delegate.audioPlaybackState = AudioPlaybackState_Paused;
    [self.audioPlayer pause];
    [self.audioPlayerPoller invalidate];
    [self.delegate setAudioProgress:(CGFloat)[self.audioPlayer currentTime] duration:(CGFloat)[self.audioPlayer duration]];

    [OWSAudioSession.shared endAudioActivity:self.audioActivity];
    [DeviceSleepManager.sharedInstance removeBlockWithBlockObject:self];
}

- (void)stop
{
    OWSAssertIsOnMainThread();

    self.delegate.audioPlaybackState = AudioPlaybackState_Stopped;
    [self.audioPlayer pause];
    [self.audioPlayerPoller invalidate];
    [self.delegate setAudioProgress:0 duration:0];

    [OWSAudioSession.shared endAudioActivity:self.audioActivity];
    [DeviceSleepManager.sharedInstance removeBlockWithBlockObject:self];
}

- (void)togglePlayState
{
    OWSAssertIsOnMainThread();

    if (self.delegate.audioPlaybackState == AudioPlaybackState_Playing) {
        [self pause];
    } else {
        [self play];
    }
}

#pragma mark - Events

- (void)audioPlayerUpdated:(NSTimer *)timer
{
    OWSAssertIsOnMainThread();

    OWSAssertDebug(self.audioPlayer);
    OWSAssertDebug(self.audioPlayerPoller);

    [self.delegate setAudioProgress:(CGFloat)[self.audioPlayer currentTime] duration:(CGFloat)[self.audioPlayer duration]];
}

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag
{
    OWSAssertIsOnMainThread();

    [self stop];
}

@end

NS_ASSUME_NONNULL_END
