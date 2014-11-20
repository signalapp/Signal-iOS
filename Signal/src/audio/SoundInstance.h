#import <AVFoundation/AVAudioPlayer.h>

/**
 *  Wrapper for system dependant audio interface.
 **/

typedef NS_ENUM(NSInteger, SoundInstanceType) {
    SoundInstanceTypeNothing,
    SoundInstanceTypeInboundRingtone,
    SoundInstanceTypeOutboundRingtone,
    SoundInstanceTypeHandshakeSound,
    SoundInstanceTypeCompletedSound,
    SoundInstanceTypeBusySound,
    SoundInstanceTypeErrorAlert,
    SoundInstanceTypeAlert
};

@interface SoundInstance : NSObject <AVAudioPlayerDelegate>

@property (strong, nonatomic) void (^completionBlock)(SoundInstance*);
@property (readonly, nonatomic) SoundInstanceType soundInstanceType;

- (instancetype)initWithFile:(NSString*)audioFile
        andSoundInstanceType:(SoundInstanceType)soundInstanceType;
- (NSString*)getId;

- (void)setAudioToLoopIndefinitely;
- (void)setAudioLoopCount:(NSInteger)loopCount;

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer*)player
                       successfully:(BOOL)flag;

@end
