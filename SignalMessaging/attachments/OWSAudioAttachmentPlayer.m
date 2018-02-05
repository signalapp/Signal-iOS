//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSAudioAttachmentPlayer.h"
#import "TSAttachmentStream.h"
#import <AVFoundation/AVFoundation.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/NSTimer+OWS.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSAudioAttachmentPlayer () <AVAudioPlayerDelegate>

@property (nonatomic, readonly) NSURL *mediaUrl;
@property (nonatomic, nullable) AVAudioPlayer *audioPlayer;
@property (nonatomic, nullable) NSTimer *audioPlayerPoller;

@end

#pragma mark -

@implementation OWSAudioAttachmentPlayer

//+ (void)setAudioIgnoresHardwareMuteSwitch:(BOOL)shouldIgnore
//{
//    NSError *error = nil;
//    BOOL success = [[AVAudioSession sharedInstance]
//        setCategory:(shouldIgnore ? AVAudioSessionCategoryPlayback :
//        AVAudioSessionCategoryPlayAndRecord)error:&error];
//    OWSAssert(!error);
//    if (!success || error) {
//        DDLogError(@"%@ Error in setAudioIgnoresHardwareMuteSwitch: %d", self.logTag, shouldIgnore);
//    }
//}

- (instancetype)initWithMediaUrl:(NSURL *)mediaUrl delegate:(id<OWSAudioAttachmentPlayerDelegate>)delegate
{
    self = [super init];
    if (!self) {
        return self;
    }

    OWSAssert(mediaUrl);
    OWSAssert(delegate);

    _delegate = delegate;
    _mediaUrl = mediaUrl;

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

- (void)play
{
    OWSAssertIsOnMainThread();
    OWSAssert(self.mediaUrl);
    OWSAssert([self.delegate audioPlaybackState] != AudioPlaybackState_Playing);

    [OWSAudioSession.shared setPlaybackCategory];

    [self.audioPlayerPoller invalidate];

    self.delegate.audioPlaybackState = AudioPlaybackState_Playing;

    if (!self.audioPlayer) {
        NSError *error;
        self.audioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:self.mediaUrl error:&error];
        if (error) {
            DDLogError(@"%@ error: %@", self.logTag, error);
            [self stop];

            if ([error.domain isEqualToString:NSOSStatusErrorDomain]
                && (error.code == kAudioFileInvalidFileError || error.code == kAudioFileStreamError_InvalidFile)) {
                [OWSAlerts showAlertWithTitle:NSLocalizedString(@"ALERT_ERROR_TITLE", @"")
                                      message:NSLocalizedString(@"INVALID_AUDIO_FILE_ALERT_ERROR_MESSAGE",
                                                  @"Message for the alert indicating that an audio file is invalid.")];
            }

            return;
        }
        self.audioPlayer.delegate = self;
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
    [self.delegate setAudioProgress:[self.audioPlayer currentTime] duration:[self.audioPlayer duration]];

    [OWSAudioSession.shared endAudioActivity];
    [DeviceSleepManager.sharedInstance removeBlockWithBlockObject:self];
}

- (void)stop
{
    OWSAssertIsOnMainThread();

    self.delegate.audioPlaybackState = AudioPlaybackState_Stopped;
    [self.audioPlayer pause];
    [self.audioPlayerPoller invalidate];
    [self.delegate setAudioProgress:0 duration:0];

    [OWSAudioSession.shared endAudioActivity];
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

    OWSAssert(self.audioPlayer);
    OWSAssert(self.audioPlayerPoller);

    [self.delegate setAudioProgress:[self.audioPlayer currentTime] duration:[self.audioPlayer duration]];
}

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag
{
    OWSAssertIsOnMainThread();

    [self stop];
}

@end

NS_ASSUME_NONNULL_END
