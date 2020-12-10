//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSAudioPlayer.h"
#import "TSAttachmentStream.h"
#import <AVFoundation/AVFoundation.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/NSTimer+OWS.h>

@import MediaPlayer;

NS_ASSUME_NONNULL_BEGIN

// A no-op delegate implementation to be used when we don't need a delegate.
@interface OWSAudioPlayerDelegateStub : NSObject <OWSAudioPlayerDelegate>

@property (nonatomic) AudioPlaybackState audioPlaybackState;

@end

#pragma mark -

@implementation OWSAudioPlayerDelegateStub

- (void)setAudioProgress:(NSTimeInterval)progress duration:(NSTimeInterval)duration
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
    self = [super init];
    if (!self) {
        return self;
    }

    OWSAssertDebug(mediaUrl);

    _mediaUrl = mediaUrl;
    _delegate = [OWSAudioPlayerDelegateStub new];

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

    [DeviceSleepManager.shared removeBlockWithBlockObject:self];

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
    if (self.supportsBackgroundPlayback) {
        return;
    }

    [self stop];
}

- (BOOL)supportsBackgroundPlayback
{
    return self.audioActivity.supportsBackgroundPlayback;
}

- (BOOL)supportsBackgroundPlaybackControls
{
    return self.supportsBackgroundPlayback && self.audioActivity.backgroundPlaybackName.length > 0;
}

- (void)updateNowPlayingInfo
{
    // Only update the now playing info if the activity supports background playback
    if (!self.supportsBackgroundPlaybackControls) {
        return;
    }

    MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo = @{
        MPMediaItemPropertyTitle : self.audioActivity.backgroundPlaybackName,
        MPMediaItemPropertyPlaybackDuration : @(self.audioPlayer.duration),
        MPNowPlayingInfoPropertyElapsedPlaybackTime : @(self.audioPlayer.currentTime)
    };
}

- (void)setupRemoteCommandCenter
{
    // Only setup the command if the activity supports background playback
    if (!self.supportsBackgroundPlaybackControls) {
        return;
    }

    __weak __typeof(self) weakSelf = self;

    MPRemoteCommandCenter *commandCenter = MPRemoteCommandCenter.sharedCommandCenter;
    [commandCenter.playCommand setEnabled:YES];
    [commandCenter.playCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *event) {
        [weakSelf play];
        return MPRemoteCommandHandlerStatusSuccess;
    }];

    [commandCenter.pauseCommand setEnabled:YES];
    [commandCenter.pauseCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *event) {
        [weakSelf pause];
        return MPRemoteCommandHandlerStatusSuccess;
    }];

    [commandCenter.changePlaybackPositionCommand setEnabled:YES];
    [commandCenter.changePlaybackPositionCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(
                                                                                                    MPRemoteCommandEvent *event) {
        OWSAssertDebug([event isKindOfClass:[MPChangePlaybackPositionCommandEvent class]]);
        MPChangePlaybackPositionCommandEvent *playbackChangeEvent = (MPChangePlaybackPositionCommandEvent *)event;
        [weakSelf setCurrentTime:playbackChangeEvent.positionTime];
        return MPRemoteCommandHandlerStatusSuccess;
    }];

    [self updateNowPlayingInfo];
}

- (void)teardownRemoteCommandCenter
{
    // If there's nothing left that wants background playback, disable lockscreen / control center controls
    if (!self.audioSession.wantsBackgroundPlayback) {
        MPRemoteCommandCenter *commandCenter = MPRemoteCommandCenter.sharedCommandCenter;
        [commandCenter.playCommand setEnabled:NO];
        [commandCenter.pauseCommand setEnabled:NO];

        [commandCenter.changePlaybackPositionCommand setEnabled:NO];

        MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo = @{};
    }
}

#pragma mark - Methods

- (void)play
{
    OWSAssertIsOnMainThread();

    BOOL success = [self.audioSession startAudioActivity:self.audioActivity];
    OWSAssertDebug(success);

    [self setupAudioPlayer];

    [self setupRemoteCommandCenter];

    self.delegate.audioPlaybackState = AudioPlaybackState_Playing;
    [self.audioPlayer play];
    [self.audioPlayerPoller invalidate];
    self.audioPlayerPoller = [NSTimer weakScheduledTimerWithTimeInterval:.05f
                                                                  target:self
                                                                selector:@selector(audioPlayerUpdated:)
                                                                userInfo:nil
                                                                 repeats:YES];

    // Prevent device from sleeping while playing audio.
    [DeviceSleepManager.shared addBlockWithBlockObject:self];
}

- (void)pause
{
    OWSAssertIsOnMainThread();

    self.delegate.audioPlaybackState = AudioPlaybackState_Paused;
    [self.audioPlayer pause];
    [self.audioPlayerPoller invalidate];
    [self.delegate setAudioProgress:self.audioPlayer.currentTime duration:self.audioPlayer.duration];
    [self updateNowPlayingInfo];

    [self endAudioActivities];
    [DeviceSleepManager.shared removeBlockWithBlockObject:self];
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
                [OWSActionSheets
                    showErrorAlertWithMessage:NSLocalizedString(@"INVALID_AUDIO_FILE_ALERT_ERROR_MESSAGE",
                                                  @"Message for the alert indicating that an audio file is invalid.")];
            }

            return;
        }
        self.audioPlayer.delegate = self;
        [self.audioPlayer prepareToPlay];
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
    [DeviceSleepManager.shared removeBlockWithBlockObject:self];
    [self teardownRemoteCommandCenter];
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
        [self play];
    }
}

- (void)setCurrentTime:(NSTimeInterval)currentTime
{
    self.audioPlayer.currentTime = currentTime;

    [self.delegate setAudioProgress:self.audioPlayer.currentTime duration:self.audioPlayer.duration];

    [self updateNowPlayingInfo];
}

#pragma mark - Events

- (void)audioPlayerUpdated:(NSTimer *)timer
{
    OWSAssertIsOnMainThread();

    OWSAssertDebug(self.audioPlayer);
    OWSAssertDebug(self.audioPlayerPoller);

    [self.delegate setAudioProgress:self.audioPlayer.currentTime duration:self.audioPlayer.duration];
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
