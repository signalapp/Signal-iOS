#import "SrtpSocket.h"
#import "ZrtpManager.h"

@implementation SrtpSocket

+(SrtpSocket*) srtpSocketOverRtp:(RtpSocket*)rtpSocket
            andIncomingCipherKey:(NSData*)incomingCipherKey
               andIncomingMacKey:(NSData*)incomingMacKey
                 andIncomingSalt:(NSData*)incomingSalt
            andOutgoingCipherKey:(NSData*)outgoingCipherKey
               andOutgoingMacKey:(NSData*)outgoingMacKey
                 andOutgoingSalt:(NSData*)outgoingSalt {
    ows_require(rtpSocket != nil);
    ows_require(incomingCipherKey != nil);
    ows_require(incomingMacKey != nil);
    ows_require(incomingSalt != nil);
    ows_require(outgoingCipherKey != nil);
    ows_require(outgoingMacKey != nil);
    ows_require(outgoingSalt != nil);
    
    SrtpSocket* s = [SrtpSocket new];
    s->incomingContext = [SrtpStream srtpStreamWithCipherKey:incomingCipherKey andMacKey:incomingMacKey andCipherIvSalt:incomingSalt];
    s->outgoingContext = [SrtpStream srtpStreamWithCipherKey:outgoingCipherKey andMacKey:outgoingMacKey andCipherIvSalt:outgoingSalt];
    s->rtpSocket = rtpSocket;
    s->badPacketLogger = [Environment.logging getOccurrenceLoggerForSender:self withKey:@"Bad Packet"];
    return s;
}

-(RtpPacket*) decryptAndAuthenticateReceived:(RtpPacket*)securedRtpPacket {
    ows_require(securedRtpPacket != nil);
    return [incomingContext verifyAuthenticationAndDecryptSecuredRtpPacket:securedRtpPacket];
}
-(RtpPacket*) encryptAndAuthenticateToSend:(RtpPacket*)normalRtpPacket {
    ows_require(normalRtpPacket != nil);
    return [outgoingContext encryptAndAuthenticateNormalRtpPacket:normalRtpPacket];
}

-(void) startWithHandler:(PacketHandler*)handler untilCancelled:(TOCCancelToken*)untilCancelledToken {
    ows_require(handler != nil);
    requireState(!hasBeenStarted);
    hasBeenStarted = true;
    
    PacketHandlerBlock packetHandler = ^(id packet) {
        ows_require(packet != nil);
        ows_require([packet isKindOfClass:RtpPacket.class]);
        
        RtpPacket* decryptedPacket;
        @try {
            decryptedPacket = [self decryptAndAuthenticateReceived:packet] ;
        } @catch (OperationFailed* ex) {
            [badPacketLogger markOccurrence:ex];
            [handler handleError:ex relatedInfo:packet causedTermination:false];
            return;
        }
        
        [handler handlePacket:decryptedPacket];
    };
    [rtpSocket startWithHandler:[PacketHandler packetHandler:packetHandler withErrorHandler:handler.errorHandler]
                 untilCancelled:untilCancelledToken];
}

-(void) secureAndSendRtpPacket:(RtpPacket *)packet {
    ows_require(packet != nil);
    [rtpSocket send:[self encryptAndAuthenticateToSend:packet]];
}
@end
