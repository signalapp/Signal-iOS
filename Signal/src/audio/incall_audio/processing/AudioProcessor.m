#import "AudioProcessor.h"

@implementation AudioProcessor

@synthesize codec;

+ (AudioProcessor *)audioProcessor {
    JitterQueue *jitterQueue = [JitterQueue jitterQueue];

    AudioProcessor *newAudioProcessorInstance = [AudioProcessor new];
    newAudioProcessorInstance->codec          = [SpeexCodec speexCodec];
    newAudioProcessorInstance->stretchFactorController =
        [StretchFactorController stretchFactorControllerForJitterQueue:jitterQueue];
    newAudioProcessorInstance->audioStretcher = [AudioStretcher audioStretcher];
    newAudioProcessorInstance->jitterQueue    = jitterQueue;
    newAudioProcessorInstance->audioPacker    = [AudioPacker audioPacker];
    return newAudioProcessorInstance;
}

- (void)receivedPacket:(EncodedAudioPacket *)packet {
    [jitterQueue tryEnqueue:packet];
}
- (NSArray *)encodeAudioPacketsFromBuffer:(CyclicalBuffer *)buffer {
    ows_require(buffer != nil);

    NSMutableArray *encodedFrames = [NSMutableArray array];
    NSUInteger decodedFrameSize   = [codec decodedFrameSizeInBytes];
    while ([buffer enqueuedLength] >= decodedFrameSize) {
        NSData *rawFrame = [buffer dequeueDataWithLength:decodedFrameSize];
        requireState(rawFrame != nil);
        NSData *encodedFrameData = [codec encode:rawFrame];
        [encodedFrames addObject:[EncodedAudioFrame encodedAudioFrameWithData:encodedFrameData]];
    }

    NSMutableArray *encodedPackets = [NSMutableArray array];
    for (EncodedAudioFrame *frame in encodedFrames) {
        [audioPacker packFrame:frame];
        EncodedAudioPacket *packet = [audioPacker tryGetFinishedAudioPacket];
        if (packet != nil)
            [encodedPackets addObject:packet];
    }

    return encodedPackets;
}
- (EncodedAudioFrame *)pullFrame {
    EncodedAudioFrame *frame = [audioPacker tryGetReceivedFrame];
    if (frame != nil)
        return frame;

    EncodedAudioPacket *potentiallyMissingPacket = [jitterQueue tryDequeue];
    [audioPacker unpackPotentiallyMissingAudioPacket:potentiallyMissingPacket];
    return [audioPacker tryGetReceivedFrame];
}
- (NSData *)tryDecodeOrInferFrame {
    EncodedAudioFrame *frame = [self pullFrame];
    haveReceivedDataYet |= !frame.isMissingAudioData;
    if (!haveReceivedDataYet)
        return nil;

    NSData *raw    = [codec decode:frame.tryGetAudioData];
    double stretch = [stretchFactorController getAndUpdateDesiredStretchFactor];
    return [audioStretcher stretchAudioData:raw stretchFactor:stretch];
}

@end
