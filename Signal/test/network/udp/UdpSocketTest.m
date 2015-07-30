#import <XCTest/XCTest.h>
#import "IpAddress.h"
#import "TestUtil.h"
#import "UdpSocket.h"

@interface UdpSocketTest : XCTestCase

@end

@implementation UdpSocketTest
-(void) testSpecifiedPortLocally {
    TOCCancelTokenSource* receiverLife = [TOCCancelTokenSource new];
    TOCCancelTokenSource* senderLife = [TOCCancelTokenSource new];
    
    __block NSData* received = nil;
    __block bool senderReceivedData = false;
    NSData* r1 = [@[@2,@3,@5] ows_toUint8Data];
    NSData* r2 = [@[@7,@11,@13] ows_toUint8Data];
    NSData* r3 = [@[@17,@19,@23] ows_toUint8Data];
    
    in_port_t port1 = (in_port_t)(arc4random_uniform(40000) + 10000);
    in_port_t port2 = port1 + (in_port_t)1;
    
    UdpSocket* receiver = [UdpSocket udpSocketFromLocalPort:port1 toRemoteEndPoint:[IpEndPoint ipEndPointAtAddress:IpAddress.localhost onPort:port2]];
    UdpSocket* sender = [UdpSocket udpSocketFromLocalPort:port2 toRemoteEndPoint:[IpEndPoint ipEndPointAtAddress:IpAddress.localhost onPort:port1]];
    [receiver startWithHandler:[PacketHandler packetHandler:^(id packet) {
        received = packet;
    } withErrorHandler:^(id error, id relatedInfo, bool causedTermination) {
        test(false);
    }] untilCancelled:receiverLife.token];
    __block bool failed = false;
    [sender startWithHandler:[PacketHandler packetHandler:^(NSData* packet) {
        // there's a length check here because when the destination is unreachable the sender sometimes gets a superfluous empty data callback... no idea why.
        senderReceivedData |= packet.length > 0;
    } withErrorHandler:^(id error, id relatedInfo, bool causedTermination) {
        failed = true;
    }] untilCancelled:senderLife.token];
    
    test(receiver.isLocalPortKnown);
    test(receiver.localPort == port1);
    test(sender.isLocalPortKnown);
    test(sender.localPort == port2);

    testChurnAndConditionMustStayTrue(received == nil, 0.1);
    
    [sender send:r1];
    testChurnUntil([received isEqualToData:r1], 1.0);
    test([received isEqualToData:r1]);
    
    [sender send:r2];
    testChurnUntil([received isEqualToData:r2], 1.0);
    
    [receiverLife cancel];
    test(!failed);
    [sender send:r3];
    testChurnUntil(failed, 1.0);
    test([received isEqualToData:r2]);
    
    [senderLife cancel];
    test(!senderReceivedData);
}
-(void) testArbitraryPortLocally {
    TOCCancelTokenSource* receiverLife = [TOCCancelTokenSource new];
    TOCCancelTokenSource* senderLife = [TOCCancelTokenSource new];
    
    __block NSData* received = nil;
    __block bool senderReceivedData = false;
    NSData* r1 = [@[@2,@3,@5] ows_toUint8Data];
    NSData* r2 = [@[@7,@11,@13] ows_toUint8Data];
    NSData* r3 = [@[@17,@19,@23] ows_toUint8Data];
    
    in_port_t unusedPort = (in_port_t)(arc4random_uniform(40000) + 10000);
    
    UdpSocket* receiver = [UdpSocket udpSocketTo:[IpEndPoint ipEndPointAtAddress:IpAddress.localhost
                                                                          onPort:unusedPort]];
    [receiver startWithHandler:[PacketHandler packetHandler:^(id packet) {
        @synchronized (churnLock()) {
            received = packet;
        }
    } withErrorHandler:^(id error, id relatedInfo, bool causedTermination) {
        test(false);
    }] untilCancelled:receiverLife.token];
    
    __block bool failed = false;
    UdpSocket* sender = [UdpSocket udpSocketFromLocalPort:unusedPort
                                         toRemoteEndPoint:[IpEndPoint ipEndPointAtAddress:IpAddress.localhost
                                                                                   onPort:receiver.localPort]];
    [sender startWithHandler:[PacketHandler packetHandler:^(NSData* packet) {
        // there's a length check here because when the destination is unreachable the sender sometimes gets a superfluous empty data callback... no idea why.
        senderReceivedData |= packet.length > 0;
    } withErrorHandler:^(id error, id relatedInfo, bool causedTermination) {
        failed = true;
    }] untilCancelled:senderLife.token];
    
    
    testChurnAndConditionMustStayTrue(received == nil, 0.1);
    
    [sender send:r1];
    testChurnUntil([received isEqualToData:r1], 1.0);
    
    [sender send:r2];
    testChurnUntil([received isEqualToData:r2], 1.0);
    
    [receiverLife cancel];
    test(!failed);
    [sender send:r3];
    testChurnAndConditionMustStayTrue([received isEqualToData:r2], 0.1);
    test([received isEqualToData:r2]);
    
    [senderLife cancel];
    test(!senderReceivedData);
}
-(void) testUdpListen {
    TOCCancelTokenSource* receiverLife = [TOCCancelTokenSource new];
    TOCCancelTokenSource* senderLife = [TOCCancelTokenSource new];
    
    __block NSUInteger listenerReceiveCount = 0;
    __block NSUInteger listenerReceiveLength = 0;
    __block NSData* listenerReceivedLast = nil;
    __block NSUInteger clientReceiveCount = 0;
    __block NSUInteger clientReceiveLength = 0;
    __block NSData* clientReceivedLast = nil;
    
    in_port_t port = (in_port_t)(arc4random_uniform(40000) + 10000);
    
    UdpSocket* listener = [UdpSocket udpSocketToFirstSenderOnLocalPort:port];
    [listener startWithHandler:[PacketHandler packetHandler:^(NSData* packet) {
        listenerReceiveCount += 1;
        listenerReceiveLength += packet.length;
        listenerReceivedLast = packet;
    } withErrorHandler:^(id error, id relatedInfo, bool causedTermination) {
        test(false);
    }] untilCancelled:receiverLife.token];
    
    IpEndPoint* e = [IpEndPoint ipEndPointAtAddress:IpAddress.localhost onPort:port];
    UdpSocket* client = [UdpSocket udpSocketTo:e];
    [client startWithHandler:[PacketHandler packetHandler:^(NSData* packet) {
        clientReceiveCount += 1;
        clientReceiveLength += packet.length;
        clientReceivedLast = packet;
    } withErrorHandler:^(id error, id relatedInfo, bool causedTermination) {
        test(false);
    }] untilCancelled:senderLife.token];
    
    test(!listener.isRemoteEndPointKnown);
    testThrows([listener remoteEndPoint]);
    test(client.isRemoteEndPointKnown);
    test([client remoteEndPoint] == e);
    test(listenerReceiveCount == 0);
    test(clientReceiveCount == 0);
    
    [client send:increasingData(10)];
    testChurnUntil(listenerReceiveCount > 0, 1.0);
    test(clientReceiveCount == 0);
    test(listener.isRemoteEndPointKnown);
    test([[[[listener remoteEndPoint] address] description] isEqualToString:@"127.0.0.1"]);
    test(listenerReceiveLength == 10);
    test([listenerReceivedLast isEqualToData:increasingData(10)]);
    
    [listener send:increasingData(20)];
    testChurnUntil(clientReceiveCount > 0, 1.0);
    test(listenerReceiveCount == 1);
    test(clientReceiveCount == 1);
    test(clientReceiveLength == 20);
    test([clientReceivedLast isEqualToData:increasingData(20)]);
    
    [receiverLife cancel];
    [senderLife cancel];
}
-(void) testUdpFail {
    TOCCancelTokenSource* life = [TOCCancelTokenSource new];
    
    in_port_t unusedPort = 10000 + (in_port_t)arc4random_uniform(30000);
    UdpSocket* udp = [UdpSocket udpSocketTo:[IpEndPoint ipEndPointAtAddress:IpAddress.localhost onPort:unusedPort]];
    __block bool failed = false;
    [udp startWithHandler:[PacketHandler packetHandler:^(id packet) {
        test(false);
    } withErrorHandler:^(id error, id relatedInfo, bool causedTermination) {
        failed = true;
    }] untilCancelled:life.token];
    
    [udp send:increasingData(20)];
    testChurnUntil(failed, 1.0);
    
    [life cancel];
}
@end
