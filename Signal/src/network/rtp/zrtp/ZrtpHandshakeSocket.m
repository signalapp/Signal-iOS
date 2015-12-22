#import "ZrtpHandshakeSocket.h"

@implementation ZrtpHandshakeSocket

+(ZrtpHandshakeSocket*) zrtpHandshakeSocketOverRtp:(RtpSocket*)rtpSocket {
    ows_require(rtpSocket != nil);
    
    ZrtpHandshakeSocket* z = [ZrtpHandshakeSocket new];
    z->rtpSocket = rtpSocket;
    z->sentPacketsLogger = [Environment.logging getOccurrenceLoggerForSender:self withKey:@"sent"];
    z->receivedPacketsLogger = [Environment.logging getOccurrenceLoggerForSender:self withKey:@"received"];
    return z;
}
-(void) send:(HandshakePacket*)packet {
    ows_require(packet != nil);
    uint16_t sequenceNumber = nextPacketSequenceNumber;
    nextPacketSequenceNumber += 1;
    [sentPacketsLogger markOccurrence:packet];
    [rtpSocket send:[packet embeddedIntoRtpPacketWithSequenceNumber:sequenceNumber
                                                usingInteropOptions:rtpSocket->interopOptions]];
}
-(void) startWithHandler:(PacketHandler*)handler untilCancelled:(TOCCancelToken*)untilCancelledToken {
    ows_require(handler != nil);
    requireState(handshakePacketHandler == nil);
    
    handshakePacketHandler = handler;
    
    PacketHandlerBlock packetHandler = ^(id packet) {
        ows_require(packet != nil);
        ows_require([packet isKindOfClass:RtpPacket.class]);
        RtpPacket* rtpPacket = packet;
        
        HandshakePacket* handshakePacket = nil;
        @try {
            handshakePacket = [HandshakePacket handshakePacketParsedFromRtpPacket:rtpPacket];
        } @catch (OperationFailed* ex) {
            [handler handleError:ex relatedInfo:packet causedTermination:false];
        }
        if (handshakePacket != nil) {
            [receivedPacketsLogger markOccurrence:handshakePacket];
            [handshakePacketHandler handlePacket:handshakePacket];
        }
    };
    
    [rtpSocket startWithHandler:[PacketHandler packetHandler:packetHandler
                                            withErrorHandler:handler.errorHandler]
                 untilCancelled:untilCancelledToken];
}

@end
