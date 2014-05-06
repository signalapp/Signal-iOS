#import <AVFoundation/AVAudioPlayer.h>

/**
 *  Wrapper for system dependant audio interface.
 **/

@interface SoundInstance : NSObject <AVAudioPlayerDelegate>

+(SoundInstance*) soundInstanceForFile:(NSString*) audioFile;
-(NSString*) getId;

-(void) setAudioToLoopIndefinitely;
-(void) setAudioLoopCount:(NSInteger) loopCount;
-(void) setCompeletionBlock:(void (^)(SoundInstance*)) block;
@end
