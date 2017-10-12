//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSAudioAttachmentPlayer.h"
#import "Signal-Swift.h"
#import "TSAttachmentStream.h"
#import "ViewControllerUtils.h"
#import <AVFoundation/AVFoundation.h>
#import <SignalServiceKit/NSTimer+OWS.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSAudioAttachmentPlayer () <AVAudioPlayerDelegate>

@property (nonatomic, readonly) NSURL *mediaUrl;
@property (nonatomic, nullable) AVAudioPlayer *audioPlayer;
@property (nonatomic, nullable) NSTimer *audioPlayerPoller;

@end

#pragma mark -

@implementation OWSAudioAttachmentPlayer

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
                                                 name:UIApplicationDidEnterBackgroundNotification
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
    OWSAssert([NSThread isMainThread]);
    OWSAssert(self.mediaUrl);
    OWSAssert([self.delegate audioPlaybackState] != AudioPlaybackState_Playing);

    [ViewControllerUtils setAudioIgnoresHardwareMuteSwitch:YES];

    [self.audioPlayerPoller invalidate];

    self.delegate.audioPlaybackState = AudioPlaybackState_Playing;

    if (!self.audioPlayer) {
        NSError *error;
        self.audioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:self.mediaUrl error:&error];
        if (error) {
            DDLogError(@"%@ error: %@", self.tag, error);
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

    [self.audioPlayer prepareToPlay];
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
    OWSAssert([NSThread isMainThread]);

    self.delegate.audioPlaybackState = AudioPlaybackState_Paused;
    [self.audioPlayer pause];
    [self.audioPlayerPoller invalidate];
    [self.delegate setAudioProgress:[self.audioPlayer currentTime] duration:[self.audioPlayer duration]];

    [DeviceSleepManager.sharedInstance removeBlockWithBlockObject:self];
}

- (void)stop
{
    OWSAssert([NSThread isMainThread]);

    self.delegate.audioPlaybackState = AudioPlaybackState_Stopped;
    [self.audioPlayer pause];
    [self.audioPlayerPoller invalidate];
    [self.delegate setAudioProgress:0 duration:0];

    [DeviceSleepManager.sharedInstance removeBlockWithBlockObject:self];
}

- (void)togglePlayState
{
    OWSAssert([NSThread isMainThread]);

    if (self.delegate.audioPlaybackState == AudioPlaybackState_Playing) {
        [self pause];
    } else {
        [self play];
    }
}

#pragma mark - Events

- (void)audioPlayerUpdated:(NSTimer *)timer
{
    OWSAssert([NSThread isMainThread]);

    OWSAssert(self.audioPlayer);
    OWSAssert(self.audioPlayerPoller);

    [self.delegate setAudioProgress:[self.audioPlayer currentTime] duration:[self.audioPlayer duration]];
}

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag
{
    OWSAssert([NSThread isMainThread]);

    [self stop];
}

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end

NS_ASSUME_NONNULL_END
