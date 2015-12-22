#import "AudioPacker.h"
#import "Conversions.h"
#import "CryptoTools.h"
#import "Util.h"

@implementation AudioPacker

+ (AudioPacker *)audioPacker {
    AudioPacker *newAudioPackerInstance              = [AudioPacker new];
    newAudioPackerInstance->audioFrameToReceiveQueue = [Queue new];
    newAudioPackerInstance->framesToSend             = [NSMutableArray array];
    newAudioPackerInstance->nextSequenceNumber       = [CryptoTools generateSecureRandomUInt16];

    // interop fix:
    // cut off the high bit (the sign bit), to avoid confusion over signed-ness when peer receives the initial number
    // also cut off the next bit, so that at least 2^14 packets (instead of 1) must fail to arrive before confusion can
    // be caused
    newAudioPackerInstance->nextSequenceNumber &= 0x3FFF;

    return newAudioPackerInstance;
}

- (void)packFrame:(EncodedAudioFrame *)frame {
    ows_require(frame != nil);
    ows_require(!frame.isMissingAudioData);
    [framesToSend addObject:frame.tryGetAudioData];
}

- (EncodedAudioPacket *)tryGetFinishedAudioPacket {
    if (framesToSend.count < AUDIO_FRAMES_PER_PACKET)
        return nil;

    uint16_t sequenceNumber = nextSequenceNumber++;
    NSData *payload         = [framesToSend ows_concatDatas];

    [framesToSend removeAllObjects];
    return [EncodedAudioPacket encodedAudioPacketWithAudioData:payload andSequenceNumber:sequenceNumber];
}

- (void)unpackPotentiallyMissingAudioPacket:(EncodedAudioPacket *)potentiallyMissingPacket {
    if (potentiallyMissingPacket != nil) {
        [self enqueueFramesForPacket:potentiallyMissingPacket];
    } else {
        [self enqueueFramesForMissingPacket];
    }
}

- (EncodedAudioFrame *)tryGetReceivedFrame {
    return [audioFrameToReceiveQueue tryDequeue];
}

#pragma mark -
#pragma mark Private Methods

- (void)enqueueFramesForPacket:(EncodedAudioPacket *)packet {
    ows_require(packet != nil);

    NSData *audioData = [packet audioData];
    requireState(audioData.length % AUDIO_FRAMES_PER_PACKET == 0);

    NSUInteger frameSize = audioData.length / AUDIO_FRAMES_PER_PACKET;
    for (NSUInteger i = 0; i < AUDIO_FRAMES_PER_PACKET; i++) {
        NSData *frameData = [audioData subdataWithRange:NSMakeRange(frameSize * i, frameSize)];
        [audioFrameToReceiveQueue enqueue:[EncodedAudioFrame encodedAudioFrameWithData:frameData]];
    }
}
- (void)enqueueFramesForMissingPacket {
    for (NSUInteger i = 0; i < AUDIO_FRAMES_PER_PACKET; i++) {
        [audioFrameToReceiveQueue enqueue:[EncodedAudioFrame encodedAudioFrameWithoutData]];
    }
}

@end
