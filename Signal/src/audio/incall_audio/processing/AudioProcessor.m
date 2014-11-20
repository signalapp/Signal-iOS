#import "AudioProcessor.h"
#import "Environment.h"
#import "Constraints.h"
#import "SpeexCodec.h"
#import "Util.h"

@interface AudioProcessor ()

@property (strong, readwrite, nonatomic) SpeexCodec* codec;
@property (strong, nonatomic) StretchFactorController* stretchFactorController;
@property (strong, nonatomic) AudioStretcher* audioStretcher;
@property (strong, nonatomic) AudioPacker* audioPacker;
@property (strong, nonatomic) JitterQueue* jitterQueue;
@property (nonatomic) bool haveReceivedDataYet;

@end

@implementation AudioProcessor

- (instancetype)init {
    self = [super init];
	
    if (self) {
        self.jitterQueue             = [[JitterQueue alloc] init];
        self.stretchFactorController = [[StretchFactorController alloc] initForJitterQueue:self.jitterQueue];
        self.codec                   = [[SpeexCodec alloc] init];
        self.audioStretcher          = [[AudioStretcher alloc] init];
        self.audioPacker             = [[AudioPacker alloc] init];
    }
    
    return self;
}

- (void)receivedPacket:(EncodedAudioPacket*)packet {
    [self.jitterQueue tryEnqueue:packet];
}

- (NSArray*)encodeAudioPacketsFromBuffer:(CyclicalBuffer*)buffer {
    require(buffer != nil);
    
    NSMutableArray* encodedFrames = [[NSMutableArray alloc] init];
    NSUInteger decodedFrameSize = [self.codec decodedFrameSizeInBytes];
    while([buffer enqueuedLength] >= decodedFrameSize) {
        NSData* rawFrame = [buffer dequeueDataWithLength:decodedFrameSize];
        requireState(rawFrame != nil);
        NSData* encodedFrameData = [self.codec encode:rawFrame];
        [encodedFrames addObject:[[EncodedAudioFrame alloc] initWithData:encodedFrameData]];
    }
    
    NSMutableArray* encodedPackets = [[NSMutableArray alloc] init];
    for (EncodedAudioFrame* frame in encodedFrames) {
        [self.audioPacker packFrame:frame];
        EncodedAudioPacket* packet = [self.audioPacker tryGetFinishedAudioPacket];
        if (packet != nil) [encodedPackets addObject:packet];
    }
    
    return encodedPackets;
}

- (EncodedAudioFrame*)pullFrame {
    EncodedAudioFrame* frame = [self.audioPacker tryGetReceivedFrame];
    if (frame != nil) return frame;
    
    EncodedAudioPacket* potentiallyMissingPacket = [self.jitterQueue tryDequeue];
    [self.audioPacker unpackPotentiallyMissingAudioPacket:potentiallyMissingPacket];
    return [self.audioPacker tryGetReceivedFrame];
}

- (NSData*)tryDecodeOrInferFrame {
    EncodedAudioFrame* frame = [self pullFrame];
    self.haveReceivedDataYet |= !frame.isMissingAudioData;
    if (!self.haveReceivedDataYet) return nil;
    
    NSData* raw = [self.codec decode:frame.tryGetAudioData];
    double stretch = [self.stretchFactorController getAndUpdateDesiredStretchFactor];
    return [self.audioStretcher stretchAudioData:raw stretchFactor:stretch];
}

@end
