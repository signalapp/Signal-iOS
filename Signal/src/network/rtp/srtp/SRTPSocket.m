#import "SRTPSocket.h"
#import "ZRTPManager.h"
#import "ZRTPHandshakeSocket.h"

@interface SRTPSocket ()

@property (strong, nonatomic) SRTPStream* incomingContext;
@property (strong, nonatomic) SRTPStream* outgoingContext;
@property (strong, nonatomic) RTPSocket* rtpSocket;
@property (nonatomic) bool hasBeenStarted;
@property (strong, nonatomic) id<OccurrenceLogger> badPacketLogger;

@end

@implementation SRTPSocket

- (instancetype) initOverRTP:(RTPSocket*)rtpSocket
        andIncomingCipherKey:(NSData*)incomingCipherKey
           andIncomingMacKey:(NSData*)incomingMacKey
             andIncomingSalt:(NSData*)incomingSalt
        andOutgoingCipherKey:(NSData*)outgoingCipherKey
           andOutgoingMacKey:(NSData*)outgoingMacKey
             andOutgoingSalt:(NSData*)outgoingSalt {
    self = [super init];
	
    if (self) {
        require(rtpSocket != nil);
        require(incomingCipherKey != nil);
        require(incomingMacKey != nil);
        require(incomingSalt != nil);
        require(outgoingCipherKey != nil);
        require(outgoingMacKey != nil);
        require(outgoingSalt != nil);
        
        self.incomingContext = [[SRTPStream alloc] initWithCipherKey:incomingCipherKey andMacKey:incomingMacKey andCipherIVSalt:incomingSalt];
        self.outgoingContext = [[SRTPStream alloc] initWithCipherKey:outgoingCipherKey andMacKey:outgoingMacKey andCipherIVSalt:outgoingSalt];
        self.rtpSocket = rtpSocket;
        self.badPacketLogger = [Environment.logging getOccurrenceLoggerForSender:self withKey:@"Bad Packet"];
    }
    
    return self;
}

- (RTPPacket*)decryptAndAuthenticateReceived:(RTPPacket*)securedRTPPacket {
    require(securedRTPPacket != nil);
    return [self.incomingContext verifyAuthenticationAndDecryptSecuredRTPPacket:securedRTPPacket];
}

- (RTPPacket*)encryptAndAuthenticateToSend:(RTPPacket*)normalRTPPacket {
    require(normalRTPPacket != nil);
    return [self.outgoingContext encryptAndAuthenticateNormalRTPPacket:normalRTPPacket];
}

- (void)startWithHandler:(PacketHandler*)handler untilCancelled:(TOCCancelToken*)untilCancelledToken {
    require(handler != nil);
    requireState(!self.hasBeenStarted);
    self.hasBeenStarted = true;
    
    PacketHandlerBlock packetHandler = ^(id packet) {
        require(packet != nil);
        require([packet isKindOfClass:[RTPPacket class]]);
        
        RTPPacket* decryptedPacket;
        @try {
            decryptedPacket = [self decryptAndAuthenticateReceived:packet] ;
        } @catch (OperationFailed* ex) {
            [self.badPacketLogger markOccurrence:ex];
            [handler handleError:ex relatedInfo:packet causedTermination:false];
            return;
        }
        
        [handler handlePacket:decryptedPacket];
    };
    [self.rtpSocket startWithHandler:[[PacketHandler alloc] initPacketHandler:packetHandler withErrorHandler:handler.errorHandler]
                      untilCancelled:untilCancelledToken];
}

- (void)secureAndSendRTPPacket:(RTPPacket*)packet {
    require(packet != nil);
    [self.rtpSocket send:[self encryptAndAuthenticateToSend:packet]];
}

@end
