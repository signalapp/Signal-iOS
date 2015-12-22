#import "ZrtpManager.h"
#import "ThreadManager.h"
#import "ZrtpInitiator.h"
#import "ZrtpResponder.h"
#import "ConfirmAckPacket.h"

#define MAX_RETRANSMIT_COUNT 45
#define MIN_RETRANSMIT_INTERVAL_SECONDS 0.15
#define RETRANSMIT_INTERVAL_GROW_FACTOR 2.0
#define MAX_RETRANSMIT_INTERVAL_SECONDS 1.5
#define MAX_WAIT_FOR_RESPONDER_HELLO_SECONDS 60.0

@implementation ZrtpManager

+(TOCFuture*) asyncPerformHandshakeOver:(RtpSocket*)rtpSocket
                      andCallController:(CallController*)callController {
    
    ows_require(rtpSocket != nil);
    ows_require(callController != nil);
    
    ZrtpHandshakeSocket* handshakeChannel = [ZrtpHandshakeSocket zrtpHandshakeSocketOverRtp:rtpSocket];
    
    id<ZrtpRole> role = callController.isInitiator
                      ? [ZrtpInitiator zrtpInitiatorWithCallController:callController]
                      : [ZrtpResponder zrtpResponderWithCallController:callController];
    
    ZrtpManager* manager = [ZrtpManager zrtpManagerWithHandshakeSocket:handshakeChannel
                                                  andRtpSocketToSecure:rtpSocket
                                                           andZrtpRole:role
                                                     andCallController:callController];
    
    return [manager asyncPerformHandshake];
}

+(ZrtpManager*) zrtpManagerWithHandshakeSocket:(ZrtpHandshakeSocket*)handshakeSocket
                          andRtpSocketToSecure:(RtpSocket*)rtpSocket
                                   andZrtpRole:(id<ZrtpRole>)zrtpRole
                             andCallController:(CallController*)callController {
    
    ows_require(handshakeSocket != nil);
    ows_require(rtpSocket != nil);
    ows_require(callController != nil);
    ows_require(zrtpRole != nil);
    
    ZrtpManager* manager = [ZrtpManager new];
    
    manager->callController                 = callController;
    manager->zrtpRole                       = zrtpRole;
    manager->futureHandshakeResultSource    = [TOCFutureSource new];
    manager->rtpSocketToSecure              = rtpSocket;
    manager->handshakeSocket                = handshakeSocket;
    manager->cancelTokenSource              = [TOCCancelTokenSource new];
    [[callController untilCancelledToken] whenCancelledTerminate:manager];
    
    [manager->futureHandshakeResultSource.future catchDo:^(id error) {
        [callController terminateWithReason:CallTerminationType_HandshakeFailed
                            withFailureInfo:error
                             andRelatedInfo:nil];
    }];
    
    return manager;
}

-(TOCFuture*) asyncPerformHandshake {
    PacketHandlerBlock packetHandler = ^(id packet) {
        ows_require(packet != nil);
        ows_require([packet isKindOfClass:HandshakePacket.class]);
        [self handleHandshakePacket:(HandshakePacket*)packet];
    };
    
    ErrorHandlerBlock errorHandler = ^(id error, id relatedInfo, bool causedTermination) {
        if (causedTermination) {
            [self terminate];
            [futureHandshakeResultSource trySetFailure:error];
            return;
        }
        
        // was Conf2Ack lost, and we're receiving encrypted audio data instead of handshake packets?
        // (the RFC says to treat this as implying a Conf2Ack)
        if ([zrtpRole isAuthenticatedAudioDataImplyingConf2Ack:relatedInfo]) {
            // low-priority todo: Can we cache this bit of audio data, so that when the srtp socket is started the data comes out?
            [self handleHandshakePacket:[[ConfirmAckPacket confirmAckPacket] embeddedIntoHandshakePacket]];
        }
    };
    
    [handshakeSocket startWithHandler:[PacketHandler packetHandler:packetHandler withErrorHandler:errorHandler]
                       untilCancelled:cancelTokenSource.token];
    
    HandshakePacket* initialPacket = [zrtpRole initialPacket];
    if (initialPacket == nil) {
        [self scheduleTimeoutIfNoHello];
    } else {
        [self setAndSendPacketToTransmit:initialPacket];
    }
    
    return futureHandshakeResultSource.future;
}

-(void) setAndSendPacketToTransmit:(HandshakePacket*)packet {
    currentPacketTransmitCount = 0;
    currentPacketToRetransmit = packet;
    [self transmitCurrentHandshakePacket];
}

-(void) transmitCurrentHandshakePacket {
    if (done) return;
    
    requireState(currentPacketToRetransmit != nil);
    [handshakeSocket send:currentPacketToRetransmit];
    
    [self scheduleRetransmit];
}
-(void) scheduleRetransmit {
    double falloffFactor = pow(RETRANSMIT_INTERVAL_GROW_FACTOR, currentPacketTransmitCount);
    NSTimeInterval delay = MIN(MIN_RETRANSMIT_INTERVAL_SECONDS * falloffFactor, MAX_RETRANSMIT_INTERVAL_SECONDS);
    currentPacketTransmitCount += 1;
    
    [currentRetransmit cancel];
    currentRetransmit = [TOCCancelTokenSource new];
    
    [TimeUtil scheduleRun:^{[self handleRetransmit];}
               afterDelay:delay
                onRunLoop:[ThreadManager lowLatencyThreadRunLoop]
          unlessCancelled:currentRetransmit.token];
}

-(void) handleRetransmit {
    if (done) return;
    currentPacketTransmitCount = 0;
    if (currentPacketTransmitCount > MAX_RETRANSMIT_COUNT) {
        done = true;
        if (currentPacketToRetransmit == nil) {
            [callController terminateWithReason:CallTerminationType_RecipientUnavailable
                                withFailureInfo:nil
                                 andRelatedInfo:@"retransmit threshold exceeded"];
        } else {
            [futureHandshakeResultSource trySetFailure:[NegotiationFailed negotiationFailedWithReason:@"retransmit threshold exceeded"]];
        }
        return;
    }
    
    [self transmitCurrentHandshakePacket];
}
-(void) scheduleTimeoutIfNoHello {
    void (^timeoutFail)(void) = ^{
        [callController terminateWithReason:CallTerminationType_RecipientUnavailable
                            withFailureInfo:nil
                             andRelatedInfo:nil];
        [futureHandshakeResultSource trySetFailure:[RecipientUnavailable recipientUnavailable]];
    };
    
    currentRetransmit = [TOCCancelTokenSource new];
    [TimeUtil scheduleRun:timeoutFail
               afterDelay:MAX_WAIT_FOR_RESPONDER_HELLO_SECONDS
                onRunLoop:[ThreadManager lowLatencyThreadRunLoop]
          unlessCancelled:currentRetransmit.token];
}

-(void) terminate {
    done = true;
    [cancelTokenSource cancel];
    [currentRetransmit cancel];
}

-(void) handleHandshakePacket:(HandshakePacket*)packet {
    ows_require(packet != nil);
    if (done) return;
    
    HandshakePacket* response = [zrtpRole handlePacket:packet];
    if (response != nil) {
        [self setAndSendPacketToTransmit:response];
    }
    if (zrtpRole.hasHandshakeFinishedSuccessfully) {
        done = true;
        handshakeCompletedSuccesfully = true;
        
        SrtpSocket* secureChannel = [zrtpRole useKeysToSecureRtpSocket:rtpSocketToSecure];
        MasterSecret* masterSecret          = zrtpRole.getMasterSecret;
        
        ZrtpHandshakeResult* result = [ZrtpHandshakeResult zrtpHandshakeResultWithSecureChannel:secureChannel andMasterSecret:masterSecret];
        
        [futureHandshakeResultSource trySetResult:result];
    }
}
@end
