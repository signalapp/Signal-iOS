//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSAudioAttachmentPlayer.h"
#import "TSAttachment.h"
#import "TSAttachmentStream.h"
#import "TSVideoAttachmentAdapter.h"
#import "ViewControllerUtils.h"
#import <YapDatabase/YapDatabaseConnection.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSAudioAttachmentPlayer ()

@property (nonatomic) TSAttachmentStream *attachmentStream;

@property (nonatomic, nullable) AVAudioPlayer *audioPlayer;
@property (nonatomic, nullable) NSTimer *audioPlayerPoller;

@end

#pragma mark -

@implementation OWSAudioAttachmentPlayer

- (instancetype)initWithMediaAdapter:(TSVideoAttachmentAdapter *)mediaAdapter
                  databaseConnection:(YapDatabaseConnection *)databaseConnection
{
    self = [super init];
    if (!self) {
        return self;
    }

    OWSAssert(mediaAdapter);
    OWSAssert([mediaAdapter isAudio]);
    OWSAssert(mediaAdapter.attachmentId);
    OWSAssert(databaseConnection);

    _mediaAdapter = mediaAdapter;

    __block TSAttachment *attachment = nil;
    [databaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        attachment = [TSAttachment fetchObjectWithUniqueID:mediaAdapter.attachmentId transaction:transaction];
    }];
    OWSAssert(attachment);

    if ([attachment isKindOfClass:[TSAttachmentStream class]]) {
        self.attachmentStream = (TSAttachmentStream *)attachment;
    }
    OWSAssert(self.attachmentStream);

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidEnterBackground:)
                                                 name:UIApplicationDidEnterBackgroundNotification
                                               object:nil];

    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];

    [self stop];
}

- (void)applicationDidEnterBackground:(NSNotification *)notification
{
    [self stop];
}

#pragma mark - Methods

- (void)play
{
    OWSAssert(self.attachmentStream);
    OWSAssert(![self.mediaAdapter isAudioPlaying]);

    [ViewControllerUtils setAudioIgnoresHardwareMuteSwitch:YES];

    [self.audioPlayerPoller invalidate];

    self.mediaAdapter.isAudioPlaying = YES;
    self.mediaAdapter.isPaused = NO;
    [self.mediaAdapter setAudioIconToPause];

    if (!self.audioPlayer) {
        NSError *error;
        self.audioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:self.attachmentStream.mediaURL error:&error];
        if (error) {
            DDLogError(@"%@ error: %@", self.tag, error);
            [self stop];
            return;
        }
        self.audioPlayer.delegate = self;
    }

    [self.audioPlayer prepareToPlay];
    [self.audioPlayer play];
    self.audioPlayerPoller = [NSTimer scheduledTimerWithTimeInterval:.05
                                                              target:self
                                                            selector:@selector(audioPlayerUpdated:)
                                                            userInfo:nil
                                                             repeats:YES];
}

- (void)pause
{
    OWSAssert(self.attachmentStream);

    self.mediaAdapter.isAudioPlaying = NO;
    self.mediaAdapter.isPaused = YES;
    [self.audioPlayer pause];
    [self.audioPlayerPoller invalidate];
    double current = [self.audioPlayer currentTime] / [self.audioPlayer duration];
    [self.mediaAdapter setAudioProgressFromFloat:(float)current];
    [self.mediaAdapter setAudioIconToPlay];
}

- (void)stop
{
    OWSAssert(self.attachmentStream);

    [self.audioPlayer pause];
    [self.audioPlayerPoller invalidate];
    [self.mediaAdapter setAudioProgressFromFloat:0];
    [self.mediaAdapter setDurationOfAudio:self.audioPlayer.duration];
    [self.mediaAdapter setAudioIconToPlay];
    self.mediaAdapter.isAudioPlaying = NO;
    self.mediaAdapter.isPaused = NO;
}

- (void)togglePlayState
{
    OWSAssert(self.attachmentStream);

    if (self.mediaAdapter.isAudioPlaying) {
        [self pause];
    } else {
        [self play];
    }
}

#pragma mark - Events

- (void)audioPlayerUpdated:(NSTimer *)timer
{
    OWSAssert(self.audioPlayer);
    OWSAssert(self.audioPlayerPoller);

    double current = [self.audioPlayer currentTime] / [self.audioPlayer duration];
    double interval = [self.audioPlayer duration] - [self.audioPlayer currentTime];
    [self.mediaAdapter setDurationOfAudio:interval];
    [self.mediaAdapter setAudioProgressFromFloat:(float)current];
}

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag
{
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
