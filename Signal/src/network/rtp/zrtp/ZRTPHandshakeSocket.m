#import "ZRTPHandshakeSocket.h"

@interface ZRTPHandshakeSocket ()

@property (strong, nonatomic) RTPSocket* rtpSocket;
@property (strong, nonatomic) PacketHandler* handshakePacketHandler;
@property (nonatomic) uint16_t nextPacketSequenceNumber;
@property (strong, nonatomic) id<OccurrenceLogger> sentPacketsLogger;
@property (strong, nonatomic) id<OccurrenceLogger> receivedPacketsLogger;

@end

@implementation ZRTPHandshakeSocket

- (instancetype)initOverRTP:(RTPSocket*)rtpSocket {
    self = [super init];
	
    if (self) {
        require(rtpSocket != nil);
        
        self.rtpSocket = rtpSocket;
        self.sentPacketsLogger = [Environment.logging getOccurrenceLoggerForSender:self withKey:@"sent"];
        self.receivedPacketsLogger = [Environment.logging getOccurrenceLoggerForSender:self withKey:@"received"];
    }
    
    return self;
}

- (void)send:(HandshakePacket*)packet {
    require(packet != nil);
    uint16_t sequenceNumber = self.nextPacketSequenceNumber;
    self.nextPacketSequenceNumber += 1;
    [self.sentPacketsLogger markOccurrence:packet];
    [self.rtpSocket send:[packet embeddedIntoRTPPacketWithSequenceNumber:sequenceNumber
                                                     usingInteropOptions:self.rtpSocket.interopOptions]];
}

- (void)startWithHandler:(PacketHandler*)handler untilCancelled:(TOCCancelToken*)untilCancelledToken {
    require(handler != nil);
    requireState(self.handshakePacketHandler == nil);
    
    self.handshakePacketHandler = handler;
    
    PacketHandlerBlock packetHandler = ^(id packet) {
        require(packet != nil);
        require([packet isKindOfClass:[RTPPacket class]]);
        RTPPacket* rtpPacket = packet;
        
        HandshakePacket* handshakePacket = nil;
        @try {
            handshakePacket = [[HandshakePacket alloc] initFromRTPPacket:rtpPacket];
        } @catch (OperationFailed* ex) {
            [handler handleError:ex relatedInfo:packet causedTermination:false];
        }
        if (handshakePacket != nil) {
            [self.receivedPacketsLogger markOccurrence:handshakePacket];
            [self.handshakePacketHandler handlePacket:handshakePacket];
        }
    };
    
    [self.rtpSocket startWithHandler:[[PacketHandler alloc] initPacketHandler:packetHandler
                                                             withErrorHandler:handler.errorHandler]
                      untilCancelled:untilCancelledToken];
}

@end
