#import "ZRTPManager.h"
#import "ThreadManager.h"
#import "ZRTPHandshakeSocket.h"
#import "ZRTPHandshakeResult.h"
#import "ZRTPInitiator.h"
#import "ZRTPResponder.h"
#import "ConfirmAckPacket.h"
#import "TimeUtil.h"

#define MAX_RETRANSMIT_COUNT 45
#define MIN_RETRANSMIT_INTERVAL_SECONDS 0.15
#define RETRANSMIT_INTERVAL_GROW_FACTOR 2.0
#define MAX_RETRANSMIT_INTERVAL_SECONDS 1.5
#define MAX_WAIT_FOR_RESPONDER_HELLO_SECONDS 60.0

@interface ZRTPManager ()

@property (nonatomic) int32_t currentPacketTransmitCount;
@property (nonatomic) bool handshakeCompletedSuccesfully;
@property (nonatomic) bool done;

@property (strong, nonatomic) TOCCancelTokenSource* cancelTokenSource;
@property (strong, nonatomic) TOCCancelTokenSource* currentRetransmit;
@property (strong, nonatomic) RTPSocket* rtpSocketToSecure;
@property (strong, nonatomic) ZRTPHandshakeSocket* handshakeSocket;
@property (strong, nonatomic) HandshakePacket* currentPacketToRetransmit;
@property (strong, nonatomic) id<ZRTPRole> zrtpRole;
@property (strong, nonatomic) TOCFutureSource* futureHandshakeResultSource;
@property (strong, nonatomic) CallController* callController;

@end

@implementation ZRTPManager

+ (TOCFuture*)asyncPerformHandshakeOver:(RTPSocket*)rtpSocket
                      andCallController:(CallController*)callController {
    
    require(rtpSocket != nil);
    require(callController != nil);
    
    ZRTPHandshakeSocket* handshakeChannel = [[ZRTPHandshakeSocket alloc] initOverRTP:rtpSocket];
    
    id<ZRTPRole> role = callController.isInitiator
                      ? [[ZRTPInitiator alloc] initWithCallController:callController]
                      : [[ZRTPResponder alloc] initWithCallController:callController];
    
    ZRTPManager* manager = [[ZRTPManager alloc] initWithHandshakeSocket:handshakeChannel
                                                   andRTPSocketToSecure:rtpSocket
                                                            andZRTPRole:role
                                                      andCallController:callController];
    
    return [manager asyncPerformHandshake];
}

- (instancetype)initWithHandshakeSocket:(ZRTPHandshakeSocket*)handshakeSocket
                   andRTPSocketToSecure:(RTPSocket*)rtpSocket
                            andZRTPRole:(id<ZRTPRole>)zrtpRole
                      andCallController:(CallController*)callController {
    if (self = [super init]) {
        require(handshakeSocket != nil);
        require(rtpSocket != nil);
        require(callController != nil);
        require(zrtpRole != nil);
        
        self.callController              = callController;
        self.zrtpRole                    = zrtpRole;
        self.futureHandshakeResultSource = [[TOCFutureSource alloc] init];
        self.rtpSocketToSecure           = rtpSocket;
        self.handshakeSocket             = handshakeSocket;
        self.cancelTokenSource           = [[TOCCancelTokenSource alloc] init];
        [[self.callController untilCancelledToken] whenCancelledTerminate:self];
        
        [self.futureHandshakeResultSource.future catchDo:^(id error) {
            [self.callController terminateWithReason:CallTerminationTypeHandshakeFailed
                                     withFailureInfo:error
                                      andRelatedInfo:nil];
        }];
    }
    
    return self;
}

- (TOCFuture*)asyncPerformHandshake {
    PacketHandlerBlock packetHandler = ^(id packet) {
        require(packet != nil);
        require([packet isKindOfClass:[HandshakePacket class]]);
        [self handleHandshakePacket:(HandshakePacket*)packet];
    };
    
    ErrorHandlerBlock errorHandler = ^(id error, id relatedInfo, bool causedTermination) {
        if (causedTermination) {
            [self terminate];
            [self.futureHandshakeResultSource trySetFailure:error];
            return;
        }
        
        // was Conf2Ack lost, and we're receiving encrypted audio data instead of handshake packets?
        // (the RFC says to treat this as implying a Conf2Ack)
        if ([self.zrtpRole isAuthenticatedAudioDataImplyingConf2Ack:relatedInfo]) {
            // low-priority todo: Can we cache this bit of audio data, so that when the srtp socket is started the data comes out?
            [self handleHandshakePacket:[[ConfirmAckPacket defaultPacket] embeddedIntoHandshakePacket]];
        }
    };
    
    [self.handshakeSocket startWithHandler:[[PacketHandler alloc] initPacketHandler:packetHandler withErrorHandler:errorHandler]
                            untilCancelled:self.cancelTokenSource.token];
    
    HandshakePacket* initialPacket = [self.zrtpRole initialPacket];
    if (initialPacket == nil) {
        [self scheduleTimeoutIfNoHello];
    } else {
        [self setAndSendPacketToTransmit:initialPacket];
    }
    
    return self.futureHandshakeResultSource.future;
}

- (void)setAndSendPacketToTransmit:(HandshakePacket*)packet {
    self.currentPacketTransmitCount = 0;
    self.currentPacketToRetransmit = packet;
    [self transmitCurrentHandshakePacket];
}

- (void)transmitCurrentHandshakePacket {
    if (self.done) return;
    
    requireState(self.currentPacketToRetransmit != nil);
    [self.handshakeSocket send:self.currentPacketToRetransmit];
    
    [self scheduleRetransmit];
}

- (void)scheduleRetransmit {
    double falloffFactor = pow(RETRANSMIT_INTERVAL_GROW_FACTOR, self.currentPacketTransmitCount);
    NSTimeInterval delay = MIN(MIN_RETRANSMIT_INTERVAL_SECONDS * falloffFactor, MAX_RETRANSMIT_INTERVAL_SECONDS);
    self.currentPacketTransmitCount += 1;
    
    [self.currentRetransmit cancel];
    self.currentRetransmit = [[TOCCancelTokenSource alloc] init];
    
    [TimeUtil scheduleRun:^{[self handleRetransmit];}
               afterDelay:delay
                onRunLoop:[ThreadManager lowLatencyThreadRunLoop]
          unlessCancelled:self.currentRetransmit.token];
}

- (void)handleRetransmit {
    if (self.done) return;
    self.currentPacketTransmitCount = 0;
    if (self.currentPacketTransmitCount > MAX_RETRANSMIT_COUNT) {
        self.done = true;
        if (self.currentPacketToRetransmit == nil) {
            [self.callController terminateWithReason:CallTerminationTypeRecipientUnavailable
                                     withFailureInfo:nil
                                      andRelatedInfo:@"retransmit threshold exceeded"];
        } else {
            [self.futureHandshakeResultSource trySetFailure:[[NegotiationFailed alloc] initWithReason:@"retransmit threshold exceeded"]];
        }
        return;
    }
    
    [self transmitCurrentHandshakePacket];
}

- (void)scheduleTimeoutIfNoHello {
    void (^timeoutFail)(void) = ^{
        [self.callController terminateWithReason:CallTerminationTypeRecipientUnavailable
                                 withFailureInfo:nil
                                  andRelatedInfo:nil];
        [self.futureHandshakeResultSource trySetFailure:[[RecipientUnavailable alloc] init]];
    };
    
    self.currentRetransmit = [[TOCCancelTokenSource alloc] init];
    [TimeUtil scheduleRun:timeoutFail
               afterDelay:MAX_WAIT_FOR_RESPONDER_HELLO_SECONDS
                onRunLoop:[ThreadManager lowLatencyThreadRunLoop]
          unlessCancelled:self.currentRetransmit.token];
}

- (void)terminate {
    self.done = true;
    [self.cancelTokenSource cancel];
    [self.currentRetransmit cancel];
}

- (void)handleHandshakePacket:(HandshakePacket*)packet {
    require(packet != nil);
    if (self.done) return;
    
    HandshakePacket* response = [self.zrtpRole handlePacket:packet];
    if (response != nil) {
        [self setAndSendPacketToTransmit:response];
    }
    if (self.zrtpRole.hasHandshakeFinishedSuccessfully) {
        self.done = true;
        self.handshakeCompletedSuccesfully = true;
        
        SRTPSocket* secureChannel = [self.zrtpRole useKeysToSecureRTPSocket:self.rtpSocketToSecure];
        MasterSecret* masterSecret = self.zrtpRole.getMasterSecret;
        
        ZRTPHandshakeResult* result = [[ZRTPHandshakeResult alloc] initWithSecureChannel:secureChannel andMasterSecret:masterSecret];
        
        [self.futureHandshakeResultSource trySetResult:result];
    }
}

@end
