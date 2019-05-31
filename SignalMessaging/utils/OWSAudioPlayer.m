//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
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
@property (nonatomic, readonly) OWSAudioActivity *audioActivity;

@end

#pragma mark -

@implementation OWSAudioPlayer

- (instancetype)initWithMediaUrl:(NSURL *)mediaUrl
                   audioBehavior:(OWSAudioBehavior)audioBehavior
{
    return [self initWithMediaUrl:mediaUrl audioBehavior:audioBehavior delegate:[OWSAudioPlayerDelegateStub new]];
}

- (instancetype)initWithMediaUrl:(NSURL *)mediaUrl
                        audioBehavior:(OWSAudioBehavior)audioBehavior
                        delegate:(id<OWSAudioPlayerDelegate>)delegate
{
    self = [super init];
    if (!self) {
        return self;
    }

    OWSAssertDebug(mediaUrl);
    OWSAssertDebug(delegate);

    _mediaUrl = mediaUrl;
    _delegate = delegate;

    NSString *audioActivityDescription = [NSString stringWithFormat:@"%@ %@", self.logTag, self.mediaUrl];
    _audioActivity = [[OWSAudioActivity alloc] initWithAudioDescription:audioActivityDescription behavior:audioBehavior];

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

#pragma mark - Dependencies

- (OWSAudioSession *)audioSession
{
    return Environment.shared.audioSession;
}

#pragma mark

- (void)applicationDidEnterBackground:(NSNotification *)notification
{
    [self stop];
}

#pragma mark - Methods

- (void)play
{

    // get current audio activity
    OWSAssertIsOnMainThread();
    [self playWithAudioActivity:self.audioActivity];
}

- (void)playWithAudioActivity:(OWSAudioActivity *)audioActivity
{
    OWSAssertIsOnMainThread();

    BOOL success = [self.audioSession startAudioActivity:audioActivity];
    OWSAssertDebug(success);

    [self setupAudioPlayer];

    self.delegate.audioPlaybackState = AudioPlaybackState_Playing;
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

    [self endAudioActivities];
    [DeviceSleepManager.sharedInstance removeBlockWithBlockObject:self];
}

- (void)setupAudioPlayer
{
    OWSAssertIsOnMainThread();

    if (self.delegate.audioPlaybackState != AudioPlaybackState_Stopped) {
        return;
    }

    OWSAssertDebug(self.mediaUrl);

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

    if (self.delegate.audioPlaybackState == AudioPlaybackState_Stopped) {
        self.delegate.audioPlaybackState = AudioPlaybackState_Paused;
    }
}

- (void)stop
{
    OWSAssertIsOnMainThread();

    self.delegate.audioPlaybackState = AudioPlaybackState_Stopped;
    [self.audioPlayer pause];
    [self.audioPlayerPoller invalidate];
    [self.delegate setAudioProgress:0 duration:0];

    [self endAudioActivities];
    [DeviceSleepManager.sharedInstance removeBlockWithBlockObject:self];
}

- (void)endAudioActivities
{
    [self.audioSession endAudioActivity:self.audioActivity];
}

- (void)togglePlayState
{
    OWSAssertIsOnMainThread();

    if (self.delegate.audioPlaybackState == AudioPlaybackState_Playing) {
        [self pause];
    } else {
        [self playWithAudioActivity:self.audioActivity];
    }
}

- (void)setCurrentTime:(NSTimeInterval)currentTime
{
    self.audioPlayer.currentTime = currentTime;

    [self.delegate setAudioProgress:(CGFloat)[self.audioPlayer currentTime]
                           duration:(CGFloat)[self.audioPlayer duration]];
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

    if ([self.delegate respondsToSelector:@selector(audioPlayerDidFinish)]) {
        [self.delegate audioPlayerDidFinish];
    }
}

@end

NS_ASSUME_NONNULL_END
