#import "AudioSocket.h"
#import "Constraints.h"
#import "RTPPacket.h"

@interface AudioSocket ()

@property (strong, nonatomic) SRTPSocket* srtpSocket;
@property (nonatomic) bool started;

@end

@implementation AudioSocket

- (instancetype)initOverSRTPSocket:(SRTPSocket*)srtpSocket {
    if (self = [super init]) {
        require(srtpSocket != nil);
        
        self.srtpSocket = srtpSocket;
    }
    
    return self;
}

- (void)startWithHandler:(PacketHandler*)handler untilCancelled:(TOCCancelToken*)untilCancelledToken {
    require(handler != nil);
    requireState(!self.started);
    self.started = true;
    
    PacketHandlerBlock valueHandler = ^(RTPPacket* rtpPacket) {
        require(rtpPacket != nil);
        require([rtpPacket isKindOfClass:[RTPPacket class]]);
        [handler handlePacket:[[EncodedAudioPacket alloc] initWithAudioData:[rtpPacket payload]
                                                          andSequenceNumber:[rtpPacket sequenceNumber]]];
    };
    
    [self.srtpSocket startWithHandler:[[PacketHandler alloc] initPacketHandler:valueHandler
                                                              withErrorHandler:[handler errorHandler]]
                       untilCancelled:untilCancelledToken];
}

- (void)send:(EncodedAudioPacket*)audioPacket {
    require(audioPacket != nil);
    
    RTPPacket* rtpPacket = [[RTPPacket alloc] initWithDefaultsAndSequenceNumber:[audioPacket sequenceNumber]
                                                                     andPayload:[audioPacket audioData]];
    [self.srtpSocket secureAndSendRTPPacket:rtpPacket];
}

@end
