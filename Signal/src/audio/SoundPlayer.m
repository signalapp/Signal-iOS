#import "SoundPlayer.h"
#import "SoundBoard.h"

@interface SoundInstance ()

- (void)play;
- (void)stop;

@end

@interface SoundPlayer ()

@property (strong, nonatomic) NSMutableDictionary* currentActiveAudioPlayers;

@end

@implementation SoundPlayer

#pragma mark Creation

+ (instancetype)sharedInstance {
    static SoundPlayer* sharedInstance = nil;
    static dispatch_once_t onceToken = 0;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[SoundPlayer alloc] init];
        sharedInstance.currentActiveAudioPlayers = [[NSMutableDictionary alloc] init];
    });
    return sharedInstance;
}

#pragma mark Delegate Implementations

- (void)addSoundToManifest:(SoundInstance*)sound {
    @synchronized(self.currentActiveAudioPlayers) {
        sound.completionBlock = ^(SoundInstance* soundInstance) {
            [self removeSoundFromManifest:soundInstance];
            id delegate = self.delegate;
            [delegate didCompleteSoundInstanceOfType:soundInstance.soundInstanceType];
        };
        [self.currentActiveAudioPlayers setValue:sound forKey:sound.getId];
    }
}

- (void)removeSoundFromManifest:(SoundInstance*)sound {
    [self removeSoundFromMainifestById:sound.getId];
}

- (void)removeSoundFromMainifestById:(NSString*)soundId {
    @synchronized(self.currentActiveAudioPlayers) {
        [self.currentActiveAudioPlayers removeObjectForKey:soundId];
    }
}

- (void)playSound:(SoundInstance*)sound {
    if (![self isSoundPlaying:sound]) {
        [self addSoundToManifest:sound];
        [sound play];
    }
}

- (void)stopSound:(SoundInstance*)sound {
    SoundInstance* playingSoundInstance = self.currentActiveAudioPlayers[sound.getId];
    [self removeSoundFromManifest:sound];
    [playingSoundInstance stop];
}

- (void)stopAllAudio {
    for (SoundInstance* sound in self.currentActiveAudioPlayers.allValues) {
        [self stopSound:sound];
    }
}

- (BOOL)isSoundPlaying:(SoundInstance*)sound {
    return nil != self.currentActiveAudioPlayers[sound.getId];
}

- (void)awake {
    [self.currentActiveAudioPlayers.allValues makeObjectsPerformSelector:@selector(play)];
}

@end
