#import <AVFoundation/AVAudioPlayer.h>

/**
 *  Wrapper for system dependant audio interface.
 **/

@interface SoundInstance : NSObject <AVAudioPlayerDelegate>

typedef enum {
    SoundInstanceTypeNothing,
    SoundInstanceTypeInboundRingtone,
    SoundInstanceTypeOutboundRingtone,
    SoundInstanceTypeHandshakeSound,
    SoundInstanceTypeCompletedSound,
    SoundInstanceTypeBusySound,
    SoundInstanceTypeErrorAlert,
    SoundInstanceTypeAlert
} SoundInstanceType;

@property (nonatomic) SoundInstanceType instanceType;

+ (SoundInstance *)soundInstanceForFile:(NSString *)audioFile;
- (NSString *)getId;

- (void)setAudioToLoopIndefinitely;
- (void)setAudioLoopCount:(NSInteger)loopCount;
- (void)setCompeletionBlock:(void (^)(SoundInstance *))block;

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag;
@end
