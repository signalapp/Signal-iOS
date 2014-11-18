#import <Foundation/Foundation.h>
#import <speex/speex.h>
#import <speex/speex_resampler.h>
#import "Logging.h"

/**
 *
 * SpeexCodec is responsible for encoding and decoding audio using the speex codec.
 *
 **/

@interface SpeexCodec : NSObject

- (instancetype)init;
+ (NSUInteger)frameSizeInSamples;
- (NSUInteger)encodedFrameSizeInBytes;
- (NSUInteger)decodedFrameSizeInBytes;

- (NSData*)decode:(NSData*)encodedData;
- (NSData*)encode:(NSData*)rawData;

@end
