#import "IpEndPoint.h"

#import "DnsManager.h"
#import "Util.h"

@implementation IpEndPoint

+(IpEndPoint*) ipEndPointAtAddress:(IpAddress*)address
                            onPort:(in_port_t)port {
    ows_require(address != nil);
    IpEndPoint* p = [IpEndPoint new];
    p->address = address;
    p->port = port;
    return p;
}

+(IpEndPoint*) ipEndPointAtUnspecifiedAddressOnPort:(in_port_t)port {
    struct sockaddr_in s;
    memset(&s, 0, sizeof(struct sockaddr_in));
    s.sin_len = sizeof(struct sockaddr_in);
    s.sin_family = AF_INET;
    s.sin_port = htons(port);
    
    IpEndPoint* a = [IpEndPoint new];
    a->address = [IpAddress ipv4AddressFromString:@"0.0.0.0"];
    a->port = port;
    return a;
}

+(IpEndPoint*) ipEndPointFromSockaddrData:(NSData*)sockaddrData {
    ows_require(sockaddrData != nil);
    ows_require(sockaddrData.length >= sizeof(struct sockaddr));
    
    struct sockaddr s;
    memcpy(&s, [sockaddrData bytes], sizeof(struct sockaddr));
    
    if (s.sa_family == AF_INET) return [IpEndPoint ipv4EndPointFromSockaddrData:sockaddrData];
    if (s.sa_family == AF_INET6) return [IpEndPoint ipv6EndPointFromSockaddrData:sockaddrData];
    
    [BadArgument raise:[NSString stringWithFormat:@"Unrecognized sockaddr family: %d", s.sa_family]];
    return nil;
}
+(IpEndPoint*) ipv4EndPointFromSockaddrData:(NSData*)sockaddrData {
    ows_require(sockaddrData != nil);
    ows_require(sockaddrData.length >= sizeof(struct sockaddr_in));
    
    struct sockaddr_in s;
    memcpy(&s, [sockaddrData bytes], sizeof(struct sockaddr_in));

    return [[IpAddress ipv4AddressFromSockaddr:s] withPort:ntohs(s.sin_port)];
}
+(IpEndPoint*) ipv6EndPointFromSockaddrData:(NSData*)sockaddrData {
    ows_require(sockaddrData != nil);
    ows_require(sockaddrData.length >= sizeof(struct sockaddr_in6));
    
    struct sockaddr_in6 s;
    memcpy(&s, [sockaddrData bytes], sizeof(struct sockaddr_in6));
    
    return [[IpAddress ipv6AddressFromSockaddr:s] withPort:ntohs(s.sin6_port)];
}

-(IpAddress*) address {
    return address;
}
-(in_port_t) port {
    return port;
}
-(NSData*) sockaddrData {
    return [address sockaddrDataWithPort:port];
}

-(NSString*) description {
    return [NSString stringWithFormat:@"Address: %@, port: %d", address, port];
}

-(void) handleStreamsOpened:(StreamPair *)streamPair {
    // no work needed
}
-(TOCFuture*) asyncHandleStreamsConnected:(StreamPair *)streamPair {
    return [TOCFuture futureWithResult:@YES];
}

-(StreamPair*)createStreamPair {
    CFReadStreamRef readStream;
    CFWriteStreamRef writeStream;
    CFStreamCreatePairWithSocketToHost(NULL, (__bridge CFStringRef)[address description], port, &readStream, &writeStream);
    return [StreamPair streamPairWithInput:(__bridge_transfer NSInputStream*)readStream
                                 andOutput:(__bridge_transfer NSOutputStream*)writeStream];
}

-(TOCFuture*) asyncResolveToSpecificEndPointsUnlessCancelled:(TOCCancelToken*)unlessCancelledToken {
    return [TOCFuture futureWithResult:@[self]];
}

@end
