#import <XCTest/XCTest.h>
#import "TestUtil.h"
#import "Util.h"
#import "CallController.h"
#import "ZRTPManager.h"
#import "ThreadManager.h"
#import "ZRTPHandshakeResult.h"
#import "DiscardingLog.h"
#import "HelloAckPacket.h"
#import "ConfirmAckPacket.h"
#import "HostNameEndPoint.h"
#import "IPAddress.h"
#import "SGNKeychainUtil.h"

bool pm(HandshakePacket* p1, HandshakePacket* p2);
bool pm(HandshakePacket* p1, HandshakePacket* p2) {
    return p1 != nil
    && p2 != nil
    && p1.class == p2.class
    && [[p1 embeddedIntoRTPPacketWithSequenceNumber:0 usingInteropOptions:@[]] isEqualToRTPPacket:[p2 embeddedIntoRTPPacketWithSequenceNumber:0 usingInteropOptions:@[]]];
}
#define AssertPacketsMatch(p1, p2) STAssertTrue(pm(p1, p2), @"")

@interface ZRTPTest : XCTestCase
@end

@implementation ZRTPTest

- (void)setUp{
    [Environment setCurrent:[Release unitTestEnvironment:@[]]];
    [SGNKeychainUtil generateSignaling];
    [Environment setCurrent:testEnv];
}

-(void) testPerturbedZRTPHandshake {
    IPEndPoint* receiver = [[IPEndPoint alloc] initWithAddress:IPAddress.localhost
                                                    onPort:10000 + (in_port_t)arc4random_uniform(20000)];
    
    UDPSocket* u1 = [[UDPSocket alloc] initSocketToFirstSenderOnLocalPort:receiver.port];
    CallController* cc1 = [[CallController alloc] initForCallInitiatedLocally:true
                                                             withRemoteNumber:testPhoneNumber1
                                                andOptionallySpecifiedContact:nil];
    TOCFuture* f1 = [ZRTPManager asyncPerformHandshakeOver:[[RTPSocket alloc] initOverUDPSocket:u1 interopOptions:@[]]
                                         andCallController:cc1];
    
    UDPSocket* u2 = [[UDPSocket alloc] initSocketToRemoteEndPoint:receiver];
    CallController* cc2 = [[CallController alloc] initForCallInitiatedLocally:false
                                                             withRemoteNumber:testPhoneNumber2
                                                andOptionallySpecifiedContact:nil];
    TOCFuture* f2 = [ZRTPManager asyncPerformHandshakeOver:[[RTPSocket alloc] initOverUDPSocket:u2 interopOptions:@[]]
                                         andCallController:cc2];
    
    testChurnUntil(!f1.isIncomplete && !f2.isIncomplete, 15.0);
    test(f1.hasResult);
    test(f2.hasResult);
    
    [cc1 terminateWithReason:CallTerminationTypeHangupLocal withFailureInfo:nil andRelatedInfo:nil];
    [cc2 terminateWithReason:CallTerminationTypeHangupLocal withFailureInfo:nil andRelatedInfo:nil];
}

-(void) testPerturbedZRTPHandshakeWithoutConfAck {
    IPEndPoint* receiver = [[IPEndPoint alloc] initWithAddress:IPAddress.localhost
                                                    onPort:10000 + (in_port_t)arc4random_uniform(20000)];
    [Environment setCurrent:testEnvWith(ENVIRONMENT_TESTING_OPTION_LOSE_CONF_ACK_ON_PURPOSE)];
    
    UDPSocket* u1 = [[UDPSocket alloc] initSocketToFirstSenderOnLocalPort:receiver.port];
    CallController* cc1 = [[CallController alloc] initForCallInitiatedLocally:true
                                                             withRemoteNumber:testPhoneNumber1
                                                andOptionallySpecifiedContact:nil];
    TOCFuture* f1 = [ZRTPManager asyncPerformHandshakeOver:[[RTPSocket alloc] initOverUDPSocket:u1 interopOptions:@[]]
                                         andCallController:cc1];
    
    UDPSocket* u2 = [[UDPSocket alloc] initSocketToRemoteEndPoint:receiver];
    CallController* cc2 = [[CallController alloc] initForCallInitiatedLocally:false
                                                             withRemoteNumber:testPhoneNumber2
                                                andOptionallySpecifiedContact:nil];
    TOCFuture* f2 = [ZRTPManager asyncPerformHandshakeOver:[[RTPSocket alloc] initOverUDPSocket:u2 interopOptions:@[]]
                                         andCallController:cc2];
    
    testChurnUntil(!f2.isIncomplete, 15.0);
    test(f2.hasResult);
    test(f1.isIncomplete);
    
    // send authenticated data to signal end of handshake
    if (f2.hasResult) {
        ZRTPHandshakeResult* result = [f2 forceGetResult];
        SRTPSocket* socket = [result secureRTPSocket];
        [socket startWithHandler:[[PacketHandler alloc] initPacketHandler:^(id packet) { test(false); }
                                             withErrorHandler:^(id error, id relatedInfo, bool causedTermination) { test(!causedTermination); }]
                  untilCancelled:[cc1 untilCancelledToken]];
        [socket secureAndSendRTPPacket:[[RTPPacket alloc] initWithDefaultsAndSequenceNumber:1 andPayload:[NSData data]]];
    }
    
    
    testChurnUntil(!f1.isIncomplete, 5.0);
    test(f1.hasResult);
    
    [cc1 terminateWithReason:CallTerminationTypeHangupLocal withFailureInfo:nil andRelatedInfo:nil];
    [cc2 terminateWithReason:CallTerminationTypeHangupLocal withFailureInfo:nil andRelatedInfo:nil];
}

-(void) testDhHandshake {
    [Environment setCurrent:testEnvWith(TESTING_OPTION_USE_DH_FOR_HANDSHAKE)];

    IPEndPoint* receiver = [[IPEndPoint alloc] initWithAddress:IPAddress.localhost
                                                    onPort:10000 + (in_port_t)arc4random_uniform(20000)];
    
    UDPSocket* u1 = [[UDPSocket alloc] initSocketToFirstSenderOnLocalPort:receiver.port];
    CallController* cc1 = [[CallController alloc] initForCallInitiatedLocally:true
                                                             withRemoteNumber:testPhoneNumber1
                                                andOptionallySpecifiedContact:nil];
    TOCFuture* f1 = [ZRTPManager asyncPerformHandshakeOver:[[RTPSocket alloc] initOverUDPSocket:u1 interopOptions:@[]]
                                         andCallController:cc1];
    
    UDPSocket* u2 = [[UDPSocket alloc] initSocketToRemoteEndPoint:receiver];
    CallController* cc2 = [[CallController alloc] initForCallInitiatedLocally:false
                                                             withRemoteNumber:testPhoneNumber2
                                                andOptionallySpecifiedContact:nil];
    TOCFuture* f2 = [ZRTPManager asyncPerformHandshakeOver:[[RTPSocket alloc] initOverUDPSocket:u2 interopOptions:@[]]
                                         andCallController:cc2];
    
    testChurnUntil(!f1.isIncomplete && !f2.isIncomplete, 15.0);
    test(f1.hasResult);
    test(f2.hasResult);
    
    [cc1 terminateWithReason:CallTerminationTypeHangupLocal withFailureInfo:nil andRelatedInfo:nil];
    [cc2 terminateWithReason:CallTerminationTypeHangupLocal withFailureInfo:nil andRelatedInfo:nil];
}

@end
