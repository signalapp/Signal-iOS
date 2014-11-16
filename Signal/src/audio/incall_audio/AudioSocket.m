#import "AudioSocket.h"
#import "Constraints.h"
#import "RTPPacket.h"

@implementation AudioSocket

+(AudioSocket*) audioSocketOver:(SRTPSocket*)srtpSocket {
    require(srtpSocket != nil);
    AudioSocket* p = [AudioSocket new];
    p->srtpSocket = srtpSocket;
    return p;
}

-(void) startWithHandler:(PacketHandler*)handler untilCancelled:(TOCCancelToken*)untilCancelledToken {
    require(handler != nil);
    requireState(!started);
    started = true;
    
    PacketHandlerBlock valueHandler = ^(RTPPacket* rtpPacket) {
        require(rtpPacket != nil);
        require([rtpPacket isKindOfClass:[RTPPacket class]]);
        [handler handlePacket:[EncodedAudioPacket encodedAudioPacketWithAudioData:[rtpPacket payload]
                                                                andSequenceNumber:[rtpPacket sequenceNumber]]];
    };
    
    [srtpSocket startWithHandler:[[PacketHandler alloc] initPacketHandler:valueHandler
                                                         withErrorHandler:[handler errorHandler]]
                  untilCancelled:untilCancelledToken];
}
-(void) send:(EncodedAudioPacket*)audioPacket {
    require(audioPacket != nil);
    
    RTPPacket* rtpPacket = [[RTPPacket alloc] initWithDefaultsAndSequenceNumber:[audioPacket sequenceNumber]
                                                                     andPayload:[audioPacket audioData]];
    [srtpSocket secureAndSendRTPPacket:rtpPacket];
}

@end
