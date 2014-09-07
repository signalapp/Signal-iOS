#import "AudioSocket.h"
#import "Constraints.h"
#import "RtpPacket.h"

@implementation AudioSocket

+(AudioSocket*) audioSocketOver:(SrtpSocket*)srtpSocket {
    require(srtpSocket != nil);
    AudioSocket* p = [AudioSocket new];
    p->srtpSocket = srtpSocket;
    return p;
}

-(void) startWithHandler:(PacketHandler*)handler untilCancelled:(TOCCancelToken*)untilCancelledToken {
    require(handler != nil);
    requireState(!started);
    started = true;
    
    PacketHandlerBlock valueHandler = ^(RtpPacket* rtpPacket) {
        require(rtpPacket != nil);
        require([rtpPacket isKindOfClass:[RtpPacket class]]);
        [handler handlePacket:[EncodedAudioPacket encodedAudioPacketWithAudioData:rtpPacket.payload
                                                                     andTimeStamp:rtpPacket.timeStamp
                                                                andSequenceNumber:rtpPacket.sequenceNumber]];
    };
    
    [srtpSocket startWithHandler:[PacketHandler packetHandler:valueHandler
                                             withErrorHandler:handler.errorHandler]
                  untilCancelled:untilCancelledToken];
}
-(void) send:(EncodedAudioPacket*)audioPacket {
    require(audioPacket != nil);
    
    RtpPacket* rtpPacket = [RtpPacket rtpPacketWithDefaultsAndSequenceNumber:audioPacket.sequenceNumber
                                                                andTimeStamp:audioPacket.timeStamp
                                                                  andPayload:audioPacket.audioData];
    [srtpSocket secureAndSendRtpPacket:rtpPacket];
}

@end
