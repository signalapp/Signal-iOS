#import "Environment.h"
#import "Constraints.h"
#import "SpeexCodec.h"

#define MAX_FRAMES 512
#define DECODED_SAMPLE_SIZE_IN_BYTES 2
#define FRAME_SIZE_IN_SAMPLES 160
#define NUMBER_OF_CHANNELS 1
#define PERPETUAL_ENHANCER_PARAMETER 1
#define VARIABLE_BIT_RATE_PARAMETER 0
#define QUALITY_PARAMETER 3
#define COMPLEXITY_PARAMETER 1

@interface SpeexCodec ()

@property (nonatomic) void* decodingState;
@property (nonatomic) SpeexBits decodingBits;
@property (nonatomic) spx_int16_t decodingFrameSize;
@property (nonatomic) spx_int16_t* decodingBuffer;

@property (nonatomic) void* encodingState;
@property (nonatomic) SpeexBits encodingBits;
@property (nonatomic) spx_int16_t encodingFrameSize;
@property (nonatomic) NSUInteger encodingBufferSizeInBytes;

@property (nonatomic) BOOL terminated;

@property (strong, nonatomic) id<ConditionLogger> logging;
@property (nonatomic) NSUInteger cachedEncodedLength;

@end

@implementation SpeexCodec

@synthesize decodingBits = _decodingBits, encodingBits = _encodingBits;

- (instancetype)init {
    if (self = [super init]) {
        self.logging = [Environment.logging getConditionLoggerForSender:[SpeexCodec class]];
        [self openSpeex];
    }
    
    return self;
}

- (void)dealloc {
    [self closeSpeex];
}

+ (NSUInteger)frameSizeInSamples {
    return FRAME_SIZE_IN_SAMPLES;
}

- (NSUInteger)encodedFrameSizeInBytes {
    requireState(self.cachedEncodedLength != 0);
    return self.cachedEncodedLength;
}

- (NSUInteger)decodedFrameSizeInBytes {
    return FRAME_SIZE_IN_SAMPLES*DECODED_SAMPLE_SIZE_IN_BYTES;
}


- (NSData*)encode:(NSData*)rawData {
    require(rawData != nil);
    require(rawData.length == FRAME_SIZE_IN_SAMPLES*DECODED_SAMPLE_SIZE_IN_BYTES);
    speex_bits_reset(&_encodingBits);
    speex_encode_int(self.encodingState, (spx_int16_t*)[rawData bytes], &_encodingBits);
    
    NSMutableData* outputBuffer = [NSMutableData dataWithLength:self.encodingBufferSizeInBytes];
    int outputSizeInBytes = speex_bits_write(&_encodingBits, [outputBuffer mutableBytes], (int)self.encodingBufferSizeInBytes);
    checkOperation(outputSizeInBytes > 0);
    [outputBuffer setLength:(NSUInteger)outputSizeInBytes];
    
    return outputBuffer;
}

- (NSData*)decode:(NSData*)potentiallyMissingEncodedData {
    NSUInteger encodedDataLength = potentiallyMissingEncodedData.length;
    if (potentiallyMissingEncodedData == nil) {
        encodedDataLength = [self decodedFrameSizeInBytes]; // size for infering audio data
    }
    if(encodedDataLength == 0) return nil;
    
    SpeexBits *dbits = [self getSpeexBitsFromData:potentiallyMissingEncodedData andDataLength:(int)encodedDataLength];
    
    int decodedLength = [self decodeSpeexBits:dbits withLength:(int)encodedDataLength];
    
    return [NSData dataWithBytes:self.decodingBuffer length:(NSUInteger)decodedLength*sizeof(spx_int16_t)];
}

- (NSUInteger)encodedDataLengthFromData:(NSData*)potentiallyMissingEncodedData {
    if (potentiallyMissingEncodedData != nil) {
        return potentiallyMissingEncodedData.length;
    }
    return [self decodedFrameSizeInBytes];
}

- (SpeexBits*)getSpeexBitsFromData:(NSData*)encodedData andDataLength:(int)encodedDataLength {
    SpeexBits* dbits = NULL;
    char* encodingStream;
    if ([encodedData bytes] != NULL) {
        encodingStream = (char*)[encodedData bytes];
        speex_bits_read_from(&_decodingBits, encodingStream, encodedDataLength);
        dbits = &_decodingBits;
    }
    return dbits;
}

- (int)decodeSpeexBits:(SpeexBits*)dbits withLength:(int)encodedDataLength {
    int decodingBufferIndex = 0;
    int decodingBufferLength = (int)[self decodedFrameSizeInBytes];
    int count = 0;
    while (0 == speex_decode_int(self.decodingState, dbits, self.decodingBuffer + decodingBufferIndex)) {
        count++;
        decodingBufferIndex += self.decodingFrameSize;
        if (decodingBufferIndex + self.decodingFrameSize > decodingBufferLength) {
            [self.logging logWarning:[NSString stringWithFormat:@"out of space in the decArr buffer, idx=%d, frameSize=%d, length=%d", decodingBufferIndex, self.decodingFrameSize, decodingBufferLength]];
            break;
        }
        if (decodingBufferIndex + self.decodingFrameSize > self.decodingFrameSize * MAX_FRAMES) {
            [self.logging logWarning:[NSString stringWithFormat:@"out of space in the dec_buffer buffer, idx=%d", decodingBufferIndex]];
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
    
    self.encodingState = speex_encoder_init(&speex_nb_mode);
    self.decodingState = speex_decoder_init(&speex_nb_mode);
    
    checkOperationDescribe(self.encodingState != NULL, @"speex encoder init failed");
    checkOperationDescribe(self.decodingState != NULL, @"speex decoder init failed");
}

- (void)applySpeexSettings {
    spx_int32_t tmp;
    tmp=PERPETUAL_ENHANCER_PARAMETER;
    speex_decoder_ctl(self.decodingState, SPEEX_SET_ENH, &tmp);
    tmp=VARIABLE_BIT_RATE_PARAMETER;
    speex_encoder_ctl(self.encodingState, SPEEX_SET_VBR, &tmp);
    tmp=QUALITY_PARAMETER;
    speex_encoder_ctl(self.encodingState, SPEEX_SET_QUALITY, &tmp);
    tmp=COMPLEXITY_PARAMETER;
    speex_encoder_ctl(self.encodingState, SPEEX_SET_COMPLEXITY, &tmp);
    
    spx_int16_t frameSize;
    speex_encoder_ctl(self.encodingState, SPEEX_GET_FRAME_SIZE, &frameSize);
    self.encodingFrameSize = frameSize;
    speex_decoder_ctl(self.decodingState, SPEEX_GET_FRAME_SIZE, &frameSize);
    self.decodingFrameSize = frameSize;
    
    int sampleRate = (int)SAMPLE_RATE;
    speex_encoder_ctl(self.encodingState, SPEEX_SET_SAMPLING_RATE, &sampleRate);
    speex_decoder_ctl(self.decodingState, SPEEX_SET_SAMPLING_RATE, &sampleRate);
}

- (void)initiateSpeexBuffers {
    speex_bits_init(&_encodingBits);
    speex_bits_init(&_decodingBits);
    
    self.encodingBufferSizeInBytes = (NSUInteger)self.encodingFrameSize * MAX_FRAMES;
    self.decodingBuffer = (spx_int16_t*) malloc( sizeof(spx_int16_t) * (NSUInteger)self.decodingFrameSize * MAX_FRAMES );
    
    checkOperationDescribe(self.decodingBuffer != NULL, @"buffer allocation failed");
}

- (void)determineDecodedLength {
    NSData* encoded = [self encode:[NSMutableData dataWithLength:[self decodedFrameSizeInBytes]]];
    self.cachedEncodedLength = encoded.length;
}

- (void)closeSpeex {
    self.terminated = true;
    
    speex_encoder_destroy( self.encodingState );
    speex_decoder_destroy( self.decodingState );
    
    speex_bits_destroy( &_encodingBits );
    speex_bits_destroy( &_decodingBits );
    
    free(self.decodingBuffer);
}

@end
