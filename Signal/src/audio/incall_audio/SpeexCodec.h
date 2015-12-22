#import <Foundation/Foundation.h>
#import <speex/speex.h>
#import <speex/speex_resampler.h>
#import "Logging.h"

/**
 *
 * SpeexCodec is responsible for encoding and decoding audio using the speex codec.
 *
 **/
@interface SpeexCodec : NSObject {
    void *decodingState;
    SpeexBits decodingBits;
    spx_int16_t decodingFrameSize;
    spx_int16_t *decodingBuffer;

    void *encodingState;
    SpeexBits encodingBits;
    spx_int16_t encodingFrameSize;
    NSUInteger encodingBufferSizeInBytes;

    BOOL terminated;

    id<ConditionLogger> logging;
    NSUInteger cachedEncodedLength;
}

+ (SpeexCodec *)speexCodec;
+ (NSUInteger)frameSizeInSamples;
- (NSUInteger)encodedFrameSizeInBytes;
- (NSUInteger)decodedFrameSizeInBytes;

- (NSData *)decode:(NSData *)encodedData;
- (NSData *)encode:(NSData *)rawData;

@end
