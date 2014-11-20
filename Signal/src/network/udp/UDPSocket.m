#import "Constraints.h"
#import "ThreadManager.h"
#import "UDPSocket.h"
#import "Util.h"

@interface UDPSocket ()

@property (nonatomic) CFSocketRef socket;
@property (nonatomic) in_port_t specifiedLocalPort;
@property (nonatomic) in_port_t measuredLocalPort;
@property (nonatomic) bool hasSentData;
@property (strong, nonatomic) IPEndPoint* specifiedRemoteEndPoint;
@property (strong, nonatomic) IPEndPoint* clientConnectedFromRemoteEndPoint;

@end

@implementation UDPSocket

- (instancetype)initSocketToFirstSenderOnLocalPort:(in_port_t)localPort {
    self = [super init];
	
    if (self) {
        require(localPort > 0);
        self.specifiedLocalPort = localPort;
    }
    
    return self;
}

- (instancetype)initSocketFromLocalPort:(in_port_t)localPort
                       toRemoteEndPoint:(IPEndPoint*)remoteEndPoint {
    self = [super init];
	
    if (self) {
        require(remoteEndPoint != nil);
        require([remoteEndPoint port] > 0);
        require(localPort > 0);
        
        self.specifiedLocalPort = localPort;
        self.specifiedRemoteEndPoint = remoteEndPoint;
    }
    
    return self;
}

- (instancetype)initSocketToRemoteEndPoint:(IPEndPoint*)remoteEndPoint {
    self = [super init];
	
    if (self) {
        require(remoteEndPoint != nil);
        require([remoteEndPoint port] > 0);
        
        self.specifiedLocalPort = 0; // passing port 0 to CFSocketAddress means 'pick one for me'
        self.specifiedRemoteEndPoint = remoteEndPoint;
    }
    
    return self;
}

- (void)dealloc {
    if (self.socket != nil) {
        CFSocketInvalidate(self.socket);
        CFRelease(self.socket);
    }
}

- (void)send:(NSData*)packet {
    @synchronized(self) {
        require(packet != nil);
        requireState(self.socket != nil);
        requireState(self.isRemoteEndPointKnown);
        
        self.hasSentData = true;
        CFTimeInterval t = 2.0;
        CFSocketError result = CFSocketSendData(self.socket, NULL, (__bridge CFDataRef)packet, t);
        
        if (result != kCFSocketSuccess) {
            [self.currentHandler handleError:[NSString stringWithFormat:@"Send failed with error code: %ld", result]
                                 relatedInfo:packet
                           causedTermination:false];
        }
    }
}

- (bool)isRemoteEndPointKnown {
    @synchronized(self) {
        return self.specifiedRemoteEndPoint != nil || self.clientConnectedFromRemoteEndPoint != nil;
    }
}

- (IPEndPoint*)remoteEndPoint {
    requireState(self.isRemoteEndPointKnown);
    if (self.specifiedRemoteEndPoint != nil) return self.specifiedRemoteEndPoint;
    return self.clientConnectedFromRemoteEndPoint;
}


- (bool)isLocalPortKnown {
    @synchronized(self) {
        return self.specifiedLocalPort != 0 || self.measuredLocalPort != 0;
    }
}

- (in_port_t)localPort {
    requireState(self.isLocalPortKnown);
    if (self.specifiedLocalPort != 0) return self.specifiedLocalPort;
    return self.measuredLocalPort;
}

void onReceivedData(CFSocketRef socket, CFSocketCallBackType type, CFDataRef address, const void *data, void *info);
void onReceivedData(CFSocketRef socket, CFSocketCallBackType type, CFDataRef address, const void *data, void *info) {
    UDPSocket* udp = (__bridge UDPSocket*)info;
    NSData* copyOfPacketData = [NSData dataWithBytes:CFDataGetBytePtr(data)
                                              length:(NSUInteger)CFDataGetLength((CFDataRef)data)];
    [udp onReceivedData:copyOfPacketData
          withEventType:type
                   from:address];
}

- (void)onReceivedData:(NSData*)data
         withEventType:(CFSocketCallBackType)type
                  from:(CFDataRef)addressData {
    
    @synchronized(self) {
        @try {
            checkOperation(type == kCFSocketDataCallBack);
            
            bool waitingForClient = !self.isRemoteEndPointKnown;
            bool packetHasContent = data.length > 0;
            bool haveNotSentPacketToBeBounced = !self.hasSentData;
            checkOperationDescribe(packetHasContent || waitingForClient || haveNotSentPacketToBeBounced,
                                   @"Received empty UDP packet. Probably indicates destination is unreachable.");
            
            if (waitingForClient) {
                [self onConnectFrom:addressData];
            }
            
            [self.currentHandler handlePacket:data];
        } @catch (OperationFailed* ex) {
            [self.currentHandler handleError:ex
                                 relatedInfo:nil
                           causedTermination:true];
            CFSocketInvalidate(self.socket);
        }
    }
}
- (void)onConnectFrom:(CFDataRef)addressData {
    CFSocketError connectResult = CFSocketConnectToAddress(self.socket,
                                                           addressData,
                                                           -1);
    
    checkOperationDescribe(connectResult == 0,
                           ([NSString stringWithFormat:@"CFSocketConnectToAddress failed with error code: %ld", connectResult]));
    
    self.clientConnectedFromRemoteEndPoint = [[IPEndPoint alloc] initFromSockaddrData:(__bridge NSData*)addressData];
}

- (void)setupLocalEndPoint {
    IPEndPoint* specifiedLocalEndPoint = [[IPEndPoint alloc] initWithUnspecifiedAddressOnPort:self.specifiedLocalPort];
    
    CFSocketError setAddressResult = CFSocketSetAddress(self.socket, (__bridge CFDataRef)[specifiedLocalEndPoint sockaddrData]);
    checkOperationDescribe(setAddressResult == kCFSocketSuccess,
                           ([NSString stringWithFormat:@"CFSocketSetAddress failed with error code: %ld", setAddressResult]));
    
    IPEndPoint* measuredLocalEndPoint = [[IPEndPoint alloc] initFromSockaddrData:(__bridge_transfer NSData*)CFSocketCopyAddress(self.socket)];
    self.measuredLocalPort = [measuredLocalEndPoint port];
}

- (void)setupRemoteEndPoint {
    if (self.specifiedRemoteEndPoint == nil) return;
    
    CFSocketError connectResult = CFSocketConnectToAddress(self.socket,
                                                           (__bridge CFDataRef)[self.specifiedRemoteEndPoint sockaddrData],
                                                           -1);
    
    checkOperationDescribe(connectResult == kCFSocketSuccess,
                           ([NSString stringWithFormat:@"CFSocketConnectToAddress failed with error code: %ld", connectResult]));
    
}

- (void)startWithHandler:(PacketHandler*)handler
          untilCancelled:(TOCCancelToken*)untilCancelledToken {
    
    require(handler != nil);
    
    @synchronized(self) {
        bool isFirstTime = self.currentHandler == nil;
        self.currentHandler = handler;
        if (!isFirstTime) return;
    }
    
    @try {
        CFSocketContext socketContext = { 0, (__bridge void*)self, CFRetain, CFRelease, CFCopyDescription };
        
        self.socket = CFSocketCreate(kCFAllocatorDefault,
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
        CFRunLoopAddSource(runLoop.getCFRunLoop, CFSocketCreateRunLoopSource(NULL, self.socket, 0), kCFRunLoopCommonModes);
        
        [untilCancelledToken whenCancelledDo:^{
            @synchronized(self) {
                self.currentHandler = nil;
                CFSocketInvalidate(self.socket);
            }
        }];
    } @catch (OperationFailed* ex) {
        [handler handleError:ex relatedInfo:nil causedTermination:true];
        CFSocketInvalidate(self.socket);
    }
}

@end
