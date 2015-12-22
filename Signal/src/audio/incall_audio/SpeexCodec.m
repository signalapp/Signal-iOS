#import "Constraints.h"
#import "Environment.h"
#import "SpeexCodec.h"

@implementation SpeexCodec

#define MAX_FRAMES 512
#define DECODED_SAMPLE_SIZE_IN_BYTES 2
#define FRAME_SIZE_IN_SAMPLES 160
#define NUMBER_OF_CHANNELS 1
#define PERPETUAL_ENHANCER_PARAMETER 1
#define VARIABLE_BIT_RATE_PARAMETER 0
#define QUALITY_PARAMETER 3
#define COMPLEXITY_PARAMETER 1

+ (SpeexCodec *)speexCodec {
    SpeexCodec *c = [SpeexCodec new];
    c->logging    = [Environment.logging getConditionLoggerForSender:self];
    [c openSpeex];
    return c;
}
- (void)dealloc {
    [self closeSpeex];
}

+ (NSUInteger)frameSizeInSamples {
    return FRAME_SIZE_IN_SAMPLES;
}

- (NSUInteger)encodedFrameSizeInBytes {
    requireState(cachedEncodedLength != 0);
    return cachedEncodedLength;
}
- (NSUInteger)decodedFrameSizeInBytes {
    return FRAME_SIZE_IN_SAMPLES * DECODED_SAMPLE_SIZE_IN_BYTES;
}

- (void)determineDecodedLength {
    NSData *encoded     = [self encode:[NSMutableData dataWithLength:[self decodedFrameSizeInBytes]]];
    cachedEncodedLength = encoded.length;
}

- (NSData *)encode:(NSData *)rawData {
    ows_require(rawData != nil);
    ows_require(rawData.length == FRAME_SIZE_IN_SAMPLES * DECODED_SAMPLE_SIZE_IN_BYTES);
    speex_bits_reset(&encodingBits);
    speex_encode_int(encodingState, (spx_int16_t *)[rawData bytes], &encodingBits);

    NSMutableData *outputBuffer = [NSMutableData dataWithLength:encodingBufferSizeInBytes];
    int outputSizeInBytes =
        speex_bits_write(&encodingBits, [outputBuffer mutableBytes], (int)encodingBufferSizeInBytes);
    checkOperation(outputSizeInBytes > 0);
    [outputBuffer setLength:(NSUInteger)outputSizeInBytes];

    return outputBuffer;
}

- (NSData *)decode:(NSData *)potentiallyMissingEncodedData {
    NSUInteger encodedDataLength = potentiallyMissingEncodedData.length;
    if (potentiallyMissingEncodedData == nil) {
        encodedDataLength = [self decodedFrameSizeInBytes]; // size for infering audio data
    }
    if (encodedDataLength == 0)
        return nil;

    SpeexBits *dbits = [self getSpeexBitsFromData:potentiallyMissingEncodedData andDataLength:(int)encodedDataLength];

    int decodedLength = [self decodeSpeexBits:dbits withLength:(int)encodedDataLength];

    return [NSData dataWithBytes:decodingBuffer length:(NSUInteger)decodedLength * sizeof(spx_int16_t)];
}

- (NSUInteger)encodedDataLengthFromData:(NSData *)potentiallyMissingEncodedData {
    if (potentiallyMissingEncodedData != nil) {
        return potentiallyMissingEncodedData.length;
    }
    return [self decodedFrameSizeInBytes];
}

- (SpeexBits *)getSpeexBitsFromData:(NSData *)encodedData andDataLength:(int)encodedDataLength {
    SpeexBits *dbits = NULL;
    char *encodingStream;
    if ([encodedData bytes] != NULL) {
        encodingStream = (char *)[encodedData bytes];
        speex_bits_read_from(&decodingBits, encodingStream, encodedDataLength);
        dbits = &decodingBits;
    }
    return dbits;
}

- (int)decodeSpeexBits:(SpeexBits *)dbits withLength:(int)encodedDataLength {
    int decodingBufferIndex  = 0;
    int decodingBufferLength = (int)[self decodedFrameSizeInBytes];
    int count                = 0;
    while (0 == speex_decode_int(decodingState, dbits, decodingBuffer + decodingBufferIndex)) {
        count++;
        decodingBufferIndex += decodingFrameSize;
        if (decodingBufferIndex + decodingFrameSize > decodingBufferLength) {
            [logging
                logWarning:[NSString
                               stringWithFormat:@"out of space in the decArr buffer, idx=%d, frameSize=%d, length=%d",
                                                decodingBufferIndex,
                                                decodingFrameSize,
                                                decodingBufferLength]];
            break;
        }
        if (decodingBufferIndex + decodingFrameSize > decodingFrameSize * MAX_FRAMES) {
            [logging logWarning:[NSString stringWithFormat:@"out of space in the dec_buffer buffer, idx=%d",
                                                           decodingBufferIndex]];
            break;
        }
        if (dbits == NULL) {
            break;
        }
    }
    return decodingBufferIndex;
}

- (void)openSpeex {
    [self initiateEncoderAndDecoder];
    [self applySpeexSettings];
    [self initiateSpeexBuffers];
    [self determineDecodedLength];
}

- (void)initiateEncoderAndDecoder {
    encodingState = speex_encoder_init(&speex_nb_mode);
    decodingState = speex_decoder_init(&speex_nb_mode);

    checkOperationDescribe(encodingState != NULL, @"speex encoder init failed");
    checkOperationDescribe(decodingState != NULL, @"speex decoder init failed");
}

- (void)applySpeexSettings {
    spx_int32_t tmp;
    tmp = PERPETUAL_ENHANCER_PARAMETER;
    speex_decoder_ctl(decodingState, SPEEX_SET_ENH, &tmp);
    tmp = VARIABLE_BIT_RATE_PARAMETER;
    speex_encoder_ctl(encodingState, SPEEX_SET_VBR, &tmp);
    tmp = QUALITY_PARAMETER;
    speex_encoder_ctl(encodingState, SPEEX_SET_QUALITY, &tmp);
    tmp = COMPLEXITY_PARAMETER;
    speex_encoder_ctl(encodingState, SPEEX_SET_COMPLEXITY, &tmp);

    speex_encoder_ctl(encodingState, SPEEX_GET_FRAME_SIZE, &encodingFrameSize);
    speex_decoder_ctl(decodingState, SPEEX_GET_FRAME_SIZE, &decodingFrameSize);

    int sampleRate = (int)SAMPLE_RATE;
    speex_encoder_ctl(encodingState, SPEEX_SET_SAMPLING_RATE, &sampleRate);
    speex_decoder_ctl(decodingState, SPEEX_SET_SAMPLING_RATE, &sampleRate);
}

- (void)initiateSpeexBuffers {
    speex_bits_init(&encodingBits);
    speex_bits_init(&decodingBits);

    encodingBufferSizeInBytes = (NSUInteger)encodingFrameSize * MAX_FRAMES;
    decodingBuffer            = (spx_int16_t *)malloc(sizeof(spx_int16_t) * (NSUInteger)decodingFrameSize * MAX_FRAMES);

    checkOperationDescribe(decodingBuffer != NULL, @"buffer allocation failed");
}

- (void)closeSpeex {
    terminated = true;

    speex_encoder_destroy(encodingState);
    speex_decoder_destroy(decodingState);

    speex_bits_destroy(&encodingBits);
    speex_bits_destroy(&decodingBits);

    free(decodingBuffer);
}

@end
