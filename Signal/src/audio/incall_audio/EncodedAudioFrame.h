#import <Foundation/Foundation.h>

/**
 *
 * A data structure (frame) that stores encoded audio data
 * Can be an empty frame to be inferred as missing information
 *
**/

@interface EncodedAudioFrame : NSObject

@property (strong, readonly, nonatomic, getter=tryGetAudioData) NSData* audioData;

- (instancetype)initWithData:(NSData*)audioData;
+ (instancetype)emptyFrame;

- (bool)isMissingAudioData;

@end
