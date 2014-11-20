#import "IPEndPoint.h"
#import "DNSManager.h"
#import "Util.h"

@interface IPEndPoint ()

@property (strong, readwrite, nonatomic) IPAddress* address;
@property (readwrite, nonatomic) in_port_t port;

@end

@implementation IPEndPoint

- (instancetype)initWithAddress:(IPAddress*)address
                         onPort:(in_port_t)port {
    self = [super init];
	
    if (self) {
        require(address != nil);
        
        self.address = address;
        self.port = port;
    }
    
    return self;
}

- (instancetype)initWithUnspecifiedAddressOnPort:(in_port_t)port {
    self = [super init];
	
    if (self) {
        struct sockaddr_in s;
        memset(&s, 0, sizeof(struct sockaddr_in));
        s.sin_len = sizeof(struct sockaddr_in);
        s.sin_family = AF_INET;
        s.sin_port = htons(port);
        
        self.address = [[IPAddress alloc] initIPv4AddressFromString:@"0.0.0.0"];
        self.port = port;
    }
    
    return self;
}

- (instancetype)initFromSockaddrData:(NSData*)sockaddrData {
    require(sockaddrData != nil);
    require(sockaddrData.length >= sizeof(struct sockaddr));
    
    struct sockaddr sock;
    memcpy(&sock, [sockaddrData bytes], sizeof(struct sockaddr));
    
    if (sock.sa_family == AF_INET) return [self initFromIPv4SockaddrData:sockaddrData];
    if (sock.sa_family == AF_INET6) return [self initFromIPv6SockaddrData:sockaddrData];
    
    [BadArgument raise:[NSString stringWithFormat:@"Unrecognized sockaddr family: %d", sock.sa_family]];
    return nil;
}

- (instancetype)initFromIPv4SockaddrData:(NSData*)sockaddrData {
    require(sockaddrData != nil);
    require(sockaddrData.length >= sizeof(struct sockaddr_in));
    
    struct sockaddr_in sock;
    memcpy(&sock, [sockaddrData bytes], sizeof(struct sockaddr_in));
    
    IPAddress* address = [[IPAddress alloc] initIPv4AddressFromSockaddr:sock];
    in_port_t port = ntohs(sock.sin_port);
    
    return [self initWithAddress:address onPort:port];
}

- (instancetype)initFromIPv6SockaddrData:(NSData*)sockaddrData {
    require(sockaddrData != nil);
    require(sockaddrData.length >= sizeof(struct sockaddr_in6));
    
    struct sockaddr_in6 sock;
    memcpy(&sock, [sockaddrData bytes], sizeof(struct sockaddr_in6));
    
    IPAddress* address = [[IPAddress alloc] initIPv6AddressFromSockaddr:sock];
    in_port_t port = ntohs(sock.sin6_port);
    
    return [self initWithAddress:address onPort:port];
}

- (NSData*)sockaddrData {
    return [self.address sockaddrDataWithPort:self.port];
}

- (NSString*)description {
    return [NSString stringWithFormat:@"Address: %@, port: %d", self.address, self.port];
}

- (void)handleStreamsOpened:(StreamPair*)streamPair {
    // no work needed
}

- (TOCFuture*)asyncHandleStreamsConnected:(StreamPair*)streamPair {
    return [TOCFuture futureWithResult:@YES];
}

- (StreamPair*)createStreamPair {
    CFReadStreamRef readStream;
    CFWriteStreamRef writeStream;
    CFStreamCreatePairWithSocketToHost(NULL, (__bridge CFStringRef)[self.address description], self.port, &readStream, &writeStream);
    return [[StreamPair alloc] initWithInput:(__bridge_transfer NSInputStream*)readStream
                                   andOutput:(__bridge_transfer NSOutputStream*)writeStream];
}

- (TOCFuture*)asyncResolveToSpecificEndPointsUnlessCancelled:(TOCCancelToken*)unlessCancelledToken {
    return [TOCFuture futureWithResult:@[self]];
}

@end
