#import "ZrtpTest.h"
#import "ZrtpHandshakeResult.h"
#import "TestUtil.h"
#import "ThreadManager.h"
#import "ZrtpHandshakeResult.h"
#import "DiscardingLog.h"
#import "HelloAckPacket.h"
#import "ConfirmAckPacket.h"
#import "HostNameEndPoint.h"
#import "IpAddress.h"
#import "SGNKeychainUtil.h"

bool pm(HandshakePacket* p1, HandshakePacket* p2);
bool pm(HandshakePacket* p1, HandshakePacket* p2) {
    return p1 != nil
    && p2 != nil
    && [p1 class] == [p2 class]
    && [[p1 embeddedIntoRtpPacketWithSequenceNumber:0 usingInteropOptions:@[]] isEqualToRtpPacket:[p2 embeddedIntoRtpPacketWithSequenceNumber:0 usingInteropOptions:@[]]];
}
#define AssertPacketsMatch(p1, p2) STAssertTrue(pm(p1, p2), @"")

@implementation ZrtpTest

- (void)setUp{
    [Environment setCurrent:[Release unitTestEnvironment:@[]]];
    [SGNKeychainUtil generateSignaling];
    [Environment setCurrent:testEnv];
}

-(void) testPerturbedZrtpHandshake {
    IpEndPoint* receiver = [IpEndPoint ipEndPointAtAddress:[IpAddress localhost]
                                                    onPort:10000 + (in_port_t)arc4random_uniform(20000)];
    
    UdpSocket* u1 = [UdpSocket udpSocketToFirstSenderOnLocalPort:receiver.port];
    CallController* cc1 = [CallController callControllerForCallInitiatedLocally:true
                                                               withRemoteNumber:testPhoneNumber1
                                                  andOptionallySpecifiedContact:nil];
    Future* f1 = [ZrtpManager asyncPerformHandshakeOver:[RtpSocket rtpSocketOverUdp:u1 interopOptions:@[]]
                                      andCallController:cc1];
    
    UdpSocket* u2 = [UdpSocket udpSocketTo:receiver];
    CallController* cc2 = [CallController callControllerForCallInitiatedLocally:false
                                                               withRemoteNumber:testPhoneNumber2
                                                  andOptionallySpecifiedContact:nil];
    Future* f2 = [ZrtpManager asyncPerformHandshakeOver:[RtpSocket rtpSocketOverUdp:u2 interopOptions:@[]]
                                      andCallController:cc2];
    
    testChurnUntil(![f1 isIncomplete] && ![f2 isIncomplete], 15.0);
    test([f1 hasSucceeded]);
    test([f2 hasSucceeded]);
    
    [cc1 terminateWithReason:CallTerminationType_HangupLocal withFailureInfo:nil andRelatedInfo:nil];
    [cc2 terminateWithReason:CallTerminationType_HangupLocal withFailureInfo:nil andRelatedInfo:nil];
}

-(void) testPerturbedZrtpHandshakeWithoutConfAck {
    IpEndPoint* receiver = [IpEndPoint ipEndPointAtAddress:[IpAddress localhost]
                                                    onPort:10000 + (in_port_t)arc4random_uniform(20000)];
    [Environment setCurrent:testEnvWith(ENVIRONMENT_TESTING_OPTION_LOSE_CONF_ACK_ON_PURPOSE)];
    
    UdpSocket* u1 = [UdpSocket udpSocketToFirstSenderOnLocalPort:receiver.port];
    CallController* cc1 = [CallController callControllerForCallInitiatedLocally:true
                                                               withRemoteNumber:testPhoneNumber1
                                                  andOptionallySpecifiedContact:nil];
    Future* f1 = [ZrtpManager asyncPerformHandshakeOver:[RtpSocket rtpSocketOverUdp:u1 interopOptions:@[]]
                                      andCallController:cc1];
    
    UdpSocket* u2 = [UdpSocket udpSocketTo:receiver];
    CallController* cc2 = [CallController callControllerForCallInitiatedLocally:false
                                                               withRemoteNumber:testPhoneNumber2
                                                  andOptionallySpecifiedContact:nil];
    Future* f2 = [ZrtpManager asyncPerformHandshakeOver:[RtpSocket rtpSocketOverUdp:u2 interopOptions:@[]]
                                      andCallController:cc2];
    
    testChurnUntil(![f2 isIncomplete], 15.0);
    test([f2 hasSucceeded]);
    test([f1 isIncomplete]);
    
    // send authenticated data to signal end of handshake
    if ([f2 hasSucceeded]) {
        ZrtpHandshakeResult* result = [f2 forceGetResult];
        SrtpSocket* socket = [result secureRtpSocket];
        [socket startWithHandler:[PacketHandler packetHandler:^(id packet) { test(false); }
                                             withErrorHandler:^(id error, id relatedInfo, bool causedTermination) { test(!causedTermination); }]
                  untilCancelled:[cc1 untilCancelledToken]];
        [socket secureAndSendRtpPacket:[RtpPacket rtpPacketWithDefaultsAndSequenceNumber:1 andPayload:[NSData data]]];
    }
    
    
    testChurnUntil(![f1 isIncomplete], 5.0);
    test([f1 hasSucceeded]);
    
    [cc1 terminateWithReason:CallTerminationType_HangupLocal withFailureInfo:nil andRelatedInfo:nil];
    [cc2 terminateWithReason:CallTerminationType_HangupLocal withFailureInfo:nil andRelatedInfo:nil];
}

@end
