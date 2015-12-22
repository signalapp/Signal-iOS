#import "AudioSocket.h"

@implementation AudioSocket

+ (AudioSocket *)audioSocketOver:(SrtpSocket *)srtpSocket {
    ows_require(srtpSocket != nil);
    AudioSocket *p = [AudioSocket new];
    p->srtpSocket  = srtpSocket;
    return p;
}

- (void)startWithHandler:(PacketHandler *)handler untilCancelled:(TOCCancelToken *)untilCancelledToken {
    ows_require(handler != nil);
    requireState(!started);
    started = true;

    PacketHandlerBlock valueHandler = ^(RtpPacket *rtpPacket) {
      ows_require(rtpPacket != nil);
      ows_require([rtpPacket isKindOfClass:[RtpPacket class]]);
      [handler handlePacket:[EncodedAudioPacket encodedAudioPacketWithAudioData:[rtpPacket payload]
                                                              andSequenceNumber:[rtpPacket sequenceNumber]]];
    };

    [srtpSocket startWithHandler:[PacketHandler packetHandler:valueHandler withErrorHandler:[handler errorHandler]]
                  untilCancelled:untilCancelledToken];
}
- (void)send:(EncodedAudioPacket *)audioPacket {
    ows_require(audioPacket != nil);

    RtpPacket *rtpPacket = [RtpPacket rtpPacketWithDefaultsAndSequenceNumber:[audioPacket sequenceNumber]
                                                                  andPayload:[audioPacket audioData]];
    [srtpSocket secureAndSendRtpPacket:rtpPacket];
}

@end
