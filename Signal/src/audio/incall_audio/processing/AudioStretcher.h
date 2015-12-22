#import <Foundation/Foundation.h>
#import "AudioStretcher.h"
#import "private/time_scale.h"

/**
 *
 * AudioStretcher is used to make queued audio play faster or slower, without affecting pitch.
 * This capability allows the amount of buffered audio to be controlled.
 *
 * Internally, uses the same spandsp used by the android version of RedPhone.
 *
 **/

@interface AudioStretcher : NSObject {
   @private
    struct time_scale_state_s timeScaleState;
}

+ (AudioStretcher *)audioStretcher;
- (NSData *)stretchAudioData:(NSData *)audioData stretchFactor:(double)stretchFactor;

@end
