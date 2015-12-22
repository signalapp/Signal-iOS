#import "SoundInstance.h"

@interface SoundInstance () {
    void (^completionBlock)(SoundInstance *);
}
@property (retain) AVAudioPlayer *audioPlayer;


@end

@implementation SoundInstance

+ (SoundInstance *)soundInstanceForFile:(NSString *)audioFile {
    SoundInstance *soundInstance = [SoundInstance new];
    soundInstance.audioPlayer    = [soundInstance.class createAudioPlayerForFile:audioFile];
    [soundInstance.audioPlayer setDelegate:soundInstance];
    return soundInstance;
}

- (NSString *)getId {
    return [[self.audioPlayer url] absoluteString];
}

- (void)play {
    [self.audioPlayer play];
}

- (void)stop {
    [self.audioPlayer stop];
    [self audioPlayerDidFinishPlaying:self.audioPlayer successfully:YES];
}

- (void)setAudioToLoopIndefinitely {
    self.audioPlayer.numberOfLoops = -1;
}

- (void)setAudioLoopCount:(NSInteger)loopCount {
    self.audioPlayer.numberOfLoops = loopCount;
}

- (SoundInstanceType)instanceType {
    if (!_instanceType) {
        _instanceType = SoundInstanceTypeNothing;
    }
    return _instanceType;
}

+ (NSURL *)urlToFile:(NSString *)file {
    return [NSURL fileURLWithPath:[NSString stringWithFormat:@"%@/%@", NSBundle.mainBundle.resourcePath, file]];
}

+ (AVAudioPlayer *)createAudioPlayerForFile:(NSString *)audioFile {
    NSURL *url = [self urlToFile:audioFile];

    NSError *error;
    AVAudioPlayer *audioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:url error:&error];
    if (nil == audioPlayer) {
        NSLog(@" %@", [error description]);
    }
    return audioPlayer;
}

- (void)setCompeletionBlock:(void (^)(SoundInstance *))block {
    completionBlock = block;
}

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag {
    completionBlock(self);
}
@end
