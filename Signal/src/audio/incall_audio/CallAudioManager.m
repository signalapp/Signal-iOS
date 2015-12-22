#import "AnonymousTerminator.h"
#import "CallAudioManager.h"

#define SAFETY_FACTOR_FOR_COMPUTE_DELAY 3.0

@implementation CallAudioManager

+ (CallAudioManager *)callAudioManagerStartedWithAudioSocket:(AudioSocket *)audioSocket
                                             andErrorHandler:(ErrorHandlerBlock)errorHandler
                                              untilCancelled:(TOCCancelToken *)untilCancelledToken {
    ows_require(audioSocket != nil);

    AudioProcessor *processor = [AudioProcessor audioProcessor];

    CallAudioManager *newCallAudioManagerInstance = [CallAudioManager new];
    newCallAudioManagerInstance->audioProcessor   = processor;
    newCallAudioManagerInstance->audioSocket      = audioSocket;

    [newCallAudioManagerInstance startWithErrorHandler:errorHandler untilCancelled:untilCancelledToken];

    return newCallAudioManagerInstance;
}

- (void)startWithErrorHandler:(ErrorHandlerBlock)errorHandler untilCancelled:(TOCCancelToken *)untilCancelledToken {
    ows_require(errorHandler != nil);
    ows_require(untilCancelledToken != nil);
    @synchronized(self) {
        requireState(!started);
        started = true;
        if (untilCancelledToken.isAlreadyCancelled)
            return;
        audioInterface = [RemoteIOAudio remoteIOInterfaceStartedWithDelegate:self untilCancelled:untilCancelledToken];
        PacketHandlerBlock handler = ^(EncodedAudioPacket *packet) {
          [audioProcessor receivedPacket:packet];
        };
        [audioSocket startWithHandler:[PacketHandler packetHandler:handler withErrorHandler:errorHandler]
                       untilCancelled:untilCancelledToken];
    }
}

- (void)handlePlaybackOccurredWithBytesRequested:(NSUInteger)requested andBytesRemaining:(NSUInteger)bytesRemaining {
    if (bytesInPlaybackBuffer >= requested) {
        bytesInPlaybackBuffer -= requested;
    }

    NSUInteger bytesAddedIfPullMore = [audioProcessor.codec decodedFrameSizeInBytes];
    double minSafeBufferSize        = MAX(requested, bytesAddedIfPullMore) * SAFETY_FACTOR_FOR_COMPUTE_DELAY;
    while (bytesInPlaybackBuffer < minSafeBufferSize) {
        NSData *decodedAudioData = [audioProcessor tryDecodeOrInferFrame];
        if (decodedAudioData == nil)
            break;
        [audioInterface populatePlaybackQueueWithData:decodedAudioData];
        bytesInPlaybackBuffer += decodedAudioData.length;
    }
}

- (void)handleNewDataRecorded:(CyclicalBuffer *)recordingQueue {
    NSArray *encodedPackets = [audioProcessor encodeAudioPacketsFromBuffer:recordingQueue];
    for (EncodedAudioPacket *packet in encodedPackets) {
        [audioSocket send:packet];
    }
}

- (BOOL)toggleMute {
    return [audioInterface toggleMute];
}

@end
