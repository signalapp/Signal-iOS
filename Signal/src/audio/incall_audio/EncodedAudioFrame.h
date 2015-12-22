#import <Foundation/Foundation.h>

/**
 *
 * A data structure (frame) that stores encoded audio data
 * Can be an empty frame to be inferred as missing information
 *
**/

@interface EncodedAudioFrame : NSObject {
   @private
    NSData *audioData;
}

+ (EncodedAudioFrame *)encodedAudioFrameWithData:(NSData *)audioData;
+ (EncodedAudioFrame *)encodedAudioFrameWithoutData;

- (bool)isMissingAudioData;
- (NSData *)tryGetAudioData;

@end
