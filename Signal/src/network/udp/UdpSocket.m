#import "Constraints.h"
#import "ThreadManager.h"
#import "UdpSocket.h"

@implementation UdpSocket

+(UdpSocket*) udpSocketToFirstSenderOnLocalPort:(in_port_t)localPort {
    ows_require(localPort > 0);
    UdpSocket* p = [UdpSocket new];
    p->specifiedLocalPort = localPort;
    p->specifiedRemoteEndPoint = nil;
    return p;
}

+(UdpSocket*) udpSocketFromLocalPort:(in_port_t)localPort
                    toRemoteEndPoint:(IpEndPoint*)remoteEndPoint {
    ows_require(remoteEndPoint != nil);
    ows_require([remoteEndPoint port] > 0);
    ows_require(localPort > 0);
    
    UdpSocket* p = [UdpSocket new];
    p->specifiedLocalPort = localPort;
    p->specifiedRemoteEndPoint = remoteEndPoint;
    return p;
}
+(UdpSocket*) udpSocketTo:(IpEndPoint*)remoteEndPoint {
    ows_require(remoteEndPoint != nil);
    ows_require([remoteEndPoint port] > 0);
    
    UdpSocket* p = [UdpSocket new];
    p->specifiedLocalPort = 0; // passing port 0 to CFSocketAddress means 'pick one for me'
    p->specifiedRemoteEndPoint = remoteEndPoint;
    return p;
}

-(void) dealloc {
    if (socket != nil) {
        CFSocketInvalidate(socket);
        CFRelease(socket);
    }
}

-(void) send:(NSData*)packet {
    @synchronized(self) {
        ows_require(packet != nil);
        requireState(socket != nil);
        requireState(self.isRemoteEndPointKnown);
        
        hasSentData = true;
        CFTimeInterval t = 2.0;
        CFSocketError result = CFSocketSendData(socket, NULL, (__bridge CFDataRef)packet, t);
        
        if (result != kCFSocketSuccess) {
            [currentHandler handleError:[NSString stringWithFormat:@"Send failed with error code: %ld", result]
                            relatedInfo:packet
                      causedTermination:false];
        }
    }
}

-(bool) isRemoteEndPointKnown {
    @synchronized(self) {
        return specifiedRemoteEndPoint != nil || clientConnectedFromRemoteEndPoint != nil;
    }
}

-(IpEndPoint *)remoteEndPoint {
    requireState(self.isRemoteEndPointKnown);
    if (specifiedRemoteEndPoint != nil) return specifiedRemoteEndPoint;
    return clientConnectedFromRemoteEndPoint;
}


-(bool) isLocalPortKnown {
    @synchronized(self) {
        return specifiedLocalPort != 0 || measuredLocalPort != 0;
    }
}

-(in_port_t) localPort {
    requireState(self.isLocalPortKnown);
    if (specifiedLocalPort != 0) return specifiedLocalPort;
    return measuredLocalPort;
}

void onReceivedData(CFSocketRef socket, CFSocketCallBackType type, CFDataRef address, const void *data, void *info);
void onReceivedData(CFSocketRef socket, CFSocketCallBackType type, CFDataRef address, const void *data, void *info) {
    UdpSocket* udp = (__bridge UdpSocket*)info;
    NSData* copyOfPacketData = [NSData dataWithBytes:CFDataGetBytePtr(data)
                                              length:(NSUInteger)CFDataGetLength((CFDataRef)data)];
    [udp onReceivedData:copyOfPacketData
          withEventType:type
                   from:address];
}
-(void) onReceivedData:(NSData*)data
         withEventType:(CFSocketCallBackType)type
                  from:(CFDataRef)addressData {
    
    @synchronized(self) {
        @try {
            checkOperation(type == kCFSocketDataCallBack);
            
            bool waitingForClient = !self.isRemoteEndPointKnown;
            bool packetHasContent = data.length > 0;
            bool haveNotSentPacketToBeBounced = !hasSentData;
            checkOperationDescribe(packetHasContent || waitingForClient || haveNotSentPacketToBeBounced,
                                   @"Received empty UDP packet. Probably indicates destination is unreachable.");
            
            if (waitingForClient) {
                [self onConnectFrom:addressData];
            }
            
            [currentHandler handlePacket:data];
        } @catch (OperationFailed* ex) {
            [currentHandler handleError:ex
                            relatedInfo:nil
                      causedTermination:true];
            CFSocketInvalidate(socket);
        }
    }
}
-(void) onConnectFrom:(CFDataRef)addressData {
    CFSocketError connectResult = CFSocketConnectToAddress(socket,
                                                           addressData,
                                                           -1);
    
    checkOperationDescribe(connectResult == 0,
                           ([NSString stringWithFormat:@"CFSocketConnectToAddress failed with error code: %ld", connectResult]));
    
    clientConnectedFromRemoteEndPoint = [IpEndPoint ipEndPointFromSockaddrData:(__bridge NSData*)addressData];
}

-(void) setupLocalEndPoint {
    IpEndPoint* specifiedLocalEndPoint = [IpEndPoint ipEndPointAtUnspecifiedAddressOnPort:specifiedLocalPort];
    
    CFSocketError setAddressResult = CFSocketSetAddress(socket, (__bridge CFDataRef)[specifiedLocalEndPoint sockaddrData]);
    checkOperationDescribe(setAddressResult == kCFSocketSuccess,
                           ([NSString stringWithFormat:@"CFSocketSetAddress failed with error code: %ld", setAddressResult]));
    
    IpEndPoint* measuredLocalEndPoint = [IpEndPoint ipEndPointFromSockaddrData:(__bridge_transfer NSData*)CFSocketCopyAddress(socket)];
    measuredLocalPort = [measuredLocalEndPoint port];
}
-(void) setupRemoteEndPoint {
    if (specifiedRemoteEndPoint == nil) return;
    
    CFSocketError connectResult = CFSocketConnectToAddress(socket,
                                                           (__bridge CFDataRef)[specifiedRemoteEndPoint sockaddrData],
                                                           -1);
    
    checkOperationDescribe(connectResult == kCFSocketSuccess,
                           ([NSString stringWithFormat:@"CFSocketConnectToAddress failed with error code: %ld", connectResult]));
    
}

-(void) startWithHandler:(PacketHandler*)handler
          untilCancelled:(TOCCancelToken*)untilCancelledToken {
    
    ows_require(handler != nil);
    
    @synchronized(self) {
        bool isFirstTime = currentHandler == nil;
        currentHandler = handler;
        if (!isFirstTime) return;
    }
    
    @try {
        CFSocketContext socketContext = { 0, (__bridge void *)self, CFRetain, CFRelease, CFCopyDescription };
        
        socket = CFSocketCreate(kCFAllocatorDefault,
                                PF_INET,
                                SOCK_DGRAM,
                                IPPROTO_UDP,
                                kCFSocketDataCallBack,
                                onReceivedData,
                                &socketContext);
        checkOperationDescribe(socket != nil,
                               @"Failed to create socket.");
        
        [self setupLocalEndPoint];
        [self setupRemoteEndPoint];
        
        NSRunLoop* runLoop = [ThreadManager lowLatencyThreadRunLoop];
        CFRunLoopAddSource(runLoop.getCFRunLoop, CFSocketCreateRunLoopSource(NULL, socket, 0), kCFRunLoopCommonModes);
        
        [untilCancelledToken whenCancelledDo:^{
            @synchronized(self) {
                currentHandler = nil;
                CFSocketInvalidate(socket);
            }
        }];
    } @catch (OperationFailed* ex) {
        [handler handleError:ex relatedInfo:nil causedTermination:true];
        CFSocketInvalidate(socket);
    }
}

@end
