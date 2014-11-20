#import "SoundInstance.h"

@interface SoundInstance ()

@property (readwrite, nonatomic) SoundInstanceType soundInstanceType;
@property (strong, nonatomic) AVAudioPlayer *audioPlayer;

@end

@implementation SoundInstance

- (instancetype)initWithFile:(NSString*)audioFile
        andSoundInstanceType:(SoundInstanceType)soundInstanceType {
    if (self = [super init]) {
        self.soundInstanceType = soundInstanceType;
        self.audioPlayer = [SoundInstance createAudioPlayerForFile:audioFile];
        [self.audioPlayer setDelegate:self];
    }
    
    return self;
}

- (NSString*)getId {
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

+ (NSURL*)urlToFile:(NSString*)file {
    return [NSURL fileURLWithPath:[NSString stringWithFormat:@"%@/%@", NSBundle.mainBundle.resourcePath, file]];
}

+ (AVAudioPlayer*)createAudioPlayerForFile:(NSString*)audioFile {
    NSURL* url = [SoundInstance urlToFile:audioFile];
    
    NSError* error;
    AVAudioPlayer* audioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:url error:&error];
    if (!audioPlayer) {
        NSLog(@" %@",[error description]);
    }
    
    return audioPlayer;
}

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer*)player successfully:(BOOL)flag {
    self.completionBlock(self);
}

@end
