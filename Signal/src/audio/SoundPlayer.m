#import "SoundPlayer.h"

@interface SoundInstance ()
- (void)play;
- (void)stop;
@end

@implementation SoundPlayer

NSMutableDictionary *currentActiveAudioPlayers;

- (SoundPlayer *)init {
    currentActiveAudioPlayers = [NSMutableDictionary dictionary];
    return self;
}

#pragma mark Delegate Implementations


- (void)addSoundToManifest:(SoundInstance *)sound {
    @synchronized(currentActiveAudioPlayers) {
        [sound setCompeletionBlock:^(SoundInstance *soundInst) {
          [self removeSoundFromManifest:soundInst];
          if (self.delegate) {
              [self.delegate didCompleteSoundInstanceOfType:soundInst.instanceType];
          }
        }];
        [currentActiveAudioPlayers setValue:sound forKey:sound.getId];
    }
}
- (void)removeSoundFromManifest:(SoundInstance *)sound {
    [self removeSoundFromMainifestById:sound.getId];
}

- (void)removeSoundFromMainifestById:(NSString *)soundId {
    @synchronized(currentActiveAudioPlayers) {
        [currentActiveAudioPlayers removeObjectForKey:soundId];
    }
}

- (void)playSound:(SoundInstance *)sound {
    if (![self isSoundPlaying:sound]) {
        [self addSoundToManifest:sound];
        [sound play];
    }
}

- (void)stopSound:(SoundInstance *)sound {
    SoundInstance *playingSoundInstance = currentActiveAudioPlayers[sound.getId];
    [self removeSoundFromManifest:sound];
    [playingSoundInstance stop];
}

- (void)stopAllAudio {
    for (SoundInstance *sound in currentActiveAudioPlayers.allValues) {
        [self stopSound:sound];
    }
}

- (BOOL)isSoundPlaying:(SoundInstance *)sound {
    return nil != currentActiveAudioPlayers[sound.getId];
}

- (void)awake {
    for (SoundInstance *sound in currentActiveAudioPlayers.allValues) {
        [sound play];
    }
}

@end
