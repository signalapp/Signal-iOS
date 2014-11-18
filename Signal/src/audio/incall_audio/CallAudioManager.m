#import "AnonymousTerminator.h"
#import "CallAudioManager.h"
#import "PropertyListPreferences+Util.h"
#import "ThreadManager.h"
#import "Util.h"

#define SAFETY_FACTOR_FOR_COMPUTE_DELAY 3.0

@interface CallAudioManager ()

@property (strong, nonatomic) RemoteIOAudio* audioInterface;
@property (strong, nonatomic) AudioProcessor* audioProcessor;
@property (strong, nonatomic) AudioSocket* audioSocket;
@property (nonatomic) bool started;
@property (nonatomic) NSUInteger bytesInPlaybackBuffer;

@end

@implementation CallAudioManager

- (instancetype)initWithAudioSocket:(AudioSocket*)audioSocket
                    andErrorHandler:(ErrorHandlerBlock)errorHandler
                     untilCancelled:(TOCCancelToken*)untilCancelledToken {
    if (self = [super init]) {
        require(audioSocket != nil);
        
        self.audioProcessor = [[AudioProcessor alloc] init];
        self.audioSocket = audioSocket;
        
        [self startWithErrorHandler:errorHandler untilCancelled:untilCancelledToken];
    }
    
    return self;
}

- (void)startWithErrorHandler:(ErrorHandlerBlock)errorHandler untilCancelled:(TOCCancelToken*)untilCancelledToken {
    require(errorHandler != nil);
    require(untilCancelledToken != nil);
    @synchronized(self) {
        requireState(!self.started);
        self.started = true;
        if (untilCancelledToken.isAlreadyCancelled) return;
        self.audioInterface = [[RemoteIOAudio alloc] initWithDelegate:self untilCancelled:untilCancelledToken];
        PacketHandlerBlock handler = ^(EncodedAudioPacket* packet) {
            [self.audioProcessor receivedPacket:packet];
        };
        [self.audioSocket startWithHandler:[[PacketHandler alloc] initPacketHandler:handler withErrorHandler:errorHandler]
                            untilCancelled:untilCancelledToken];
    }
}

- (void)handlePlaybackOccurredWithBytesRequested:(NSUInteger)requested andBytesRemaining:(NSUInteger)bytesRemaining {
    if (self.bytesInPlaybackBuffer >= requested) {
        self.bytesInPlaybackBuffer -= requested;
    }
    
    NSUInteger bytesAddedIfPullMore = [self.audioProcessor.codec decodedFrameSizeInBytes];
    double minSafeBufferSize = MAX(requested, bytesAddedIfPullMore)*SAFETY_FACTOR_FOR_COMPUTE_DELAY;
    while (self.bytesInPlaybackBuffer < minSafeBufferSize) {
        NSData* decodedAudioData = [self.audioProcessor tryDecodeOrInferFrame];
        if (decodedAudioData == nil) break;
        [self.audioInterface populatePlaybackQueueWithData:decodedAudioData];
        self.bytesInPlaybackBuffer += decodedAudioData.length;
    }
}

- (void)handleNewDataRecorded:(CyclicalBuffer*)recordingQueue {
    NSArray* encodedPackets = [self.audioProcessor encodeAudioPacketsFromBuffer:recordingQueue];
    for (EncodedAudioPacket* packet in encodedPackets) {
        [self.audioSocket send:packet];
    }
}

- (BOOL)toggleMute {
	return [self.audioInterface toggleMute];
}

@end
