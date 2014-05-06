#import "SrtpSocket.h"
#import "ZrtpManager.h"
#import "ZrtpHandshakeSocket.h"

@implementation SrtpSocket

+(SrtpSocket*) srtpSocketOverRtp:(RtpSocket*)rtpSocket
            andIncomingCipherKey:(NSData*)incomingCipherKey
               andIncomingMacKey:(NSData*)incomingMacKey
                 andIncomingSalt:(NSData*)incomingSalt
            andOutgoingCipherKey:(NSData*)outgoingCipherKey
               andOutgoingMacKey:(NSData*)outgoingMacKey
                 andOutgoingSalt:(NSData*)outgoingSalt {
    require(rtpSocket != nil);
    require(incomingCipherKey != nil);
    require(incomingMacKey != nil);
    require(incomingSalt != nil);
    require(outgoingCipherKey != nil);
    require(outgoingMacKey != nil);
    require(outgoingSalt != nil);
    
    SrtpSocket* s = [SrtpSocket new];
    s->incomingContext = [SrtpStream srtpStreamWithCipherKey:incomingCipherKey andMacKey:incomingMacKey andCipherIvSalt:incomingSalt];
    s->outgoingContext = [SrtpStream srtpStreamWithCipherKey:outgoingCipherKey andMacKey:outgoingMacKey andCipherIvSalt:outgoingSalt];
    s->rtpSocket = rtpSocket;
    s->badPacketLogger = [[Environment logging] getOccurrenceLoggerForSender:self withKey:@"Bad Packet"];
    return s;
}

-(RtpPacket*) decryptAndAuthenticateReceived:(RtpPacket*)securedRtpPacket {
    require(securedRtpPacket != nil);
    return [incomingContext verifyAuthenticationAndDecryptSecuredRtpPacket:securedRtpPacket];
}
-(RtpPacket*) encryptAndAuthenticateToSend:(RtpPacket*)normalRtpPacket {
    require(normalRtpPacket != nil);
    return [outgoingContext encryptAndAuthenticateNormalRtpPacket:normalRtpPacket];
}

-(void) startWithHandler:(PacketHandler*)handler untilCancelled:(id<CancelToken>)untilCancelledToken {
    require(handler != nil);
    requireState(!hasBeenStarted);
    hasBeenStarted = true;
    
    PacketHandlerBlock packetHandler = ^(id packet) {
        require(packet != nil);
        require([packet isKindOfClass:[RtpPacket class]]);
        
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
    require(packet != nil);
    [rtpSocket send:[self encryptAndAuthenticateToSend:packet]];
}
@end
