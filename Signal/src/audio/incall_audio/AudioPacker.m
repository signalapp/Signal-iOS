#import "AudioPacker.h"
#import "CryptoTools.h"
#import "NSData+Conversions.h"
#import "Util.h"

@interface AudioPacker ()

@property (strong, nonatomic) NSMutableArray* framesToSend;
@property (strong, nonatomic) Queue* audioFrameToReceiveQueue;
@property (nonatomic) uint16_t nextSequenceNumber;

@end

@implementation AudioPacker

- (instancetype)init {
    if (self = [super init]) {
        self.audioFrameToReceiveQueue = [[Queue alloc] init];
        self.framesToSend = [[NSMutableArray alloc] init];
        self.nextSequenceNumber = [CryptoTools generateSecureRandomUInt16];
        
        // interop fix:
        // cut off the high bit (the sign bit), to avoid confusion over signed-ness when peer receives the initial number
        // also cut off the next bit, so that at least 2^14 packets (instead of 1) must fail to arrive before confusion can be caused
        self.nextSequenceNumber &= 0x3FFF;
    }
    
    return self;
}

- (void)packFrame:(EncodedAudioFrame*)frame {
    require(frame != nil);
    require(![frame isMissingAudioData]);
    [self.framesToSend addObject:[frame tryGetAudioData]];
}

- (EncodedAudioPacket*)tryGetFinishedAudioPacket {
    if (self.framesToSend.count < AUDIO_FRAMES_PER_PACKET) return nil;
    
    uint16_t sequenceNumber = self.nextSequenceNumber++;
    NSData* payload = [self.framesToSend concatDatas];
    
    [self.framesToSend removeAllObjects];
    return [[EncodedAudioPacket alloc] initWithAudioData:payload andSequenceNumber:sequenceNumber];
}

- (void)unpackPotentiallyMissingAudioPacket:(EncodedAudioPacket*)potentiallyMissingPacket {
    if (potentiallyMissingPacket != nil) {
        [self enqueueFramesForPacket:potentiallyMissingPacket];
    } else {
        [self enqueueFramesForMissingPacket];
    }
}

- (EncodedAudioFrame*)tryGetReceivedFrame {
    return [self.audioFrameToReceiveQueue tryDequeue];
}

#pragma mark -
#pragma mark Private Methods

- (void)enqueueFramesForPacket:(EncodedAudioPacket*)packet {
    require(packet != nil);
    
    NSData* audioData = [packet audioData];
    requireState(audioData.length % AUDIO_FRAMES_PER_PACKET == 0);
    
    NSUInteger frameSize = audioData.length / AUDIO_FRAMES_PER_PACKET;
    for (NSUInteger i = 0; i < AUDIO_FRAMES_PER_PACKET; i++) {
        NSData* frameData = [audioData subdataWithRange:NSMakeRange(frameSize*i, frameSize)];
        [self.audioFrameToReceiveQueue enqueue:[[EncodedAudioFrame alloc] initWithData:frameData]];
    }
}

- (void)enqueueFramesForMissingPacket {
    for (NSUInteger i = 0; i < AUDIO_FRAMES_PER_PACKET; i++) {
        [self.audioFrameToReceiveQueue enqueue:[EncodedAudioFrame emptyFrame]];
    }
}

@end
