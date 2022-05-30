//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSAudioPlayer.h"
#import <AVFoundation/AVFoundation.h>
#import <SessionUtilitiesKit/SessionUtilitiesKit.h>
#import <SessionMessagingKit/SessionMessagingKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

// A no-op delegate implementation to be used when we don't need a delegate.
@interface OWSAudioPlayerDelegateStub : NSObject <OWSAudioPlayerDelegate>

@property (nonatomic) AudioPlaybackState audioPlaybackState;

@end

#pragma mark -

@implementation OWSAudioPlayerDelegateStub

- (void)setAudioProgress:(CGFloat)progress duration:(CGFloat)duration
{
    // Do nothing
}

- (void)showInvalidAudioFileAlert
{
    // Do nothing
}

- (void)audioPlayerDidFinishPlaying:(OWSAudioPlayer *)player successfully:(BOOL)flag
{
    // Do nothing
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
                        delegate:(nullable id<OWSAudioPlayerDelegate>)delegate
{
    self = [super init];
    if (!self) {
        return self;
    }

    _mediaUrl = mediaUrl;
    _delegate = delegate;

    NSString *audioActivityDescription = [NSString stringWithFormat:@"%@ %@", @"OWSAudioPlayer", self.mediaUrl];
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
    return SMKEnvironment.shared.audioSession;
}

#pragma mark

- (void)applicationDidEnterBackground:(NSNotification *)notification
{
    [self stop];
}

#pragma mark - Methods

- (BOOL)isPlaying
{
    return (self.delegate.audioPlaybackState == AudioPlaybackState_Playing);
}

- (void)play
{
    // get current audio activity
    [self playWithAudioActivity:self.audioActivity];
}

- (void)playWithAudioActivity:(OWSAudioActivity *)audioActivity
{
    [self.audioPlayerPoller invalidate];

    self.delegate.audioPlaybackState = AudioPlaybackState_Playing;

    [[AVAudioSession sharedInstance] setCategory: AVAudioSessionCategoryPlayback error: nil];

    if (!self.audioPlayer) {
        NSError *error;
        self.audioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:self.mediaUrl error:&error];
        self.audioPlayer.enableRate = YES;
        if (error) {
            [self stop];

            if ([error.domain isEqualToString:NSOSStatusErrorDomain]
                && (error.code == kAudioFileInvalidFileError || error.code == kAudioFileStreamError_InvalidFile)) {
                [self.delegate showInvalidAudioFileAlert];
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

- (void)setCurrentTime:(NSTimeInterval)currentTime
{
    [self.audioPlayer setCurrentTime:currentTime];
}

- (float)getPlaybackRate
{
    return self.audioPlayer.rate;
}

- (NSTimeInterval)duration
{
    return [self.audioPlayer duration];
}

- (void)setPlaybackRate:(float)rate
{
    [self.audioPlayer setRate:rate];
}

- (void)pause
{
    self.delegate.audioPlaybackState = AudioPlaybackState_Paused;
    [self.audioPlayer pause];
    [self.audioPlayerPoller invalidate];
    [self.delegate setAudioProgress:(CGFloat)[self.audioPlayer currentTime] duration:(CGFloat)[self.audioPlayer duration]];

    [self endAudioActivities];
    [DeviceSleepManager.sharedInstance removeBlockWithBlockObject:self];
}

- (void)stop
{
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
    if (self.isPlaying) {
        [self pause];
    } else {
        [self playWithAudioActivity:self.audioActivity];
    }
}

#pragma mark - Events

- (void)audioPlayerUpdated:(NSTimer *)timer
{
    [self.delegate setAudioProgress:(CGFloat)[self.audioPlayer currentTime] duration:(CGFloat)[self.audioPlayer duration]];
}

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag
{
    [self stop];
    [self.delegate audioPlayerDidFinishPlaying:self successfully:flag];
}

@end

NS_ASSUME_NONNULL_END
