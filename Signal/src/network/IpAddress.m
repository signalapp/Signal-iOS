#import "IpAddress.h"
#import "Util.h"
#import "IpEndPoint.h"

#define LOCAL_HOST_IP @"127.0.0.1"

@implementation IpAddress

+(IpAddress*) localhost {
    return [IpAddress ipv4AddressFromString:LOCAL_HOST_IP];
}
+(IpAddress*) ipAddressFromString:(NSString*)text {
    ows_require(text != nil);
    if ([IpAddress isIpv4Text:text]) return [IpAddress ipv4AddressFromString:text];
    if ([IpAddress isIpv6Text:text]) return [IpAddress ipv6AddressFromString:text];
    [BadArgument raise:[NSString stringWithFormat:@"Invalid IP address: %@", text]];
    return nil;
}
+(IpAddress*) tryGetIpAddressFromString:(NSString*)text {
    ows_require(text != nil);
    if ([IpAddress isIpv4Text:text]) return [IpAddress ipv4AddressFromString:text];
    if ([IpAddress isIpv6Text:text]) return [IpAddress ipv6AddressFromString:text];
    return nil;
}
+(IpAddress*) ipv4AddressFromString:(NSString*)text {
    ows_require(text != nil);
    
    IpAddress* a = [IpAddress new];
    
    struct sockaddr_in s;
    memset(&s, 0, sizeof(struct sockaddr_in));
    s.sin_len = sizeof(s);
    s.sin_family = AF_INET;
    int inet_pton_result = inet_pton(AF_INET, [text UTF8String], &(s.sin_addr));
    
    if (inet_pton_result == -1) {
        [BadArgument raise:[NSString stringWithFormat:@"Error parsing IPv4 address: %@, %s", text, strerror(errno)]];
    }
    if (inet_pton_result != +1) {
        [BadArgument raise:[NSString stringWithFormat:@"Invalid IPv4 address: %@", text]];
    }
    
    a->isIpv4 = true;
    a->ipv4Data = s;
    return a;
}
+(IpAddress*) ipv6AddressFromString:(NSString*)text {
    ows_require(text != nil);
    
    IpAddress* a = [IpAddress new];

    struct sockaddr_in6 s;
    memset(&s, 0, sizeof(struct sockaddr_in6));
    s.sin6_len = sizeof(s);
    s.sin6_family = AF_INET6;
    int inet_pton_result = inet_pton(AF_INET6, [text UTF8String], &(s.sin6_addr));
    
    if (inet_pton_result == -1) {
        [BadArgument raise:[NSString stringWithFormat:@"Error parsing IPv6 address: %@, %s", text, strerror(errno)]];
    }
    if (inet_pton_result != +1) {
        [BadArgument raise:[NSString stringWithFormat:@"Invalid IPv6 address: %@", text]];
    }

    a->ipv6Data = s;
    a->isIpv6 = true;
    return a;
}

+(IpAddress*) ipv4AddressFromSockaddr:(struct sockaddr_in)sockaddr {
    IpAddress* a = [IpAddress new];
    a->ipv4Data = sockaddr;
    a->isIpv4 = true;
    return a;
}
+(IpAddress*) ipv6AddressFromSockaddr:(struct sockaddr_in6)sockaddr {
    IpAddress* a = [IpAddress new];
    a->ipv6Data = sockaddr;
    a->isIpv6 = true;
    return a;
}

-(IpEndPoint*) withPort:(in_port_t)port {
    return [IpEndPoint ipEndPointAtAddress:self onPort:port];
}

-(NSData*) sockaddrData {
    return [self sockaddrDataWithPort:0];
}
-(NSData*) sockaddrDataWithPort:(in_port_t)port {
    requireState(isIpv4 || isIpv6);
    if (isIpv4) {
        struct sockaddr_in s = ipv4Data;
        s.sin_port = htons(port);
        NSMutableData* d = [NSMutableData dataWithLength:sizeof(struct sockaddr_in)];
        memcpy([d mutableBytes], &s, sizeof(struct sockaddr_in));
        return d;
    } else {
        struct sockaddr_in6 s = ipv6Data;
        s.sin6_port = htons(port);
        NSMutableData* d = [NSMutableData dataWithLength:sizeof(struct sockaddr_in6)];
        memcpy([d mutableBytes], &s, sizeof(struct sockaddr_in6));
        return d;
    }
}

-(NSString*) description {
    requireState(isIpv4 || isIpv6);
    return isIpv4
        ? [IpAddress ipv4AddressToString:&ipv4Data]
        : [IpAddress ipv6AddressToString:&ipv6Data];
}

+(bool) isIpv4Text:(NSString*)text {
    ows_require(text != nil);
    struct sockaddr_in s;
    return inet_pton(AF_INET, [text UTF8String], &(s.sin_addr)) == 1;
}
+(bool) isIpv6Text:(NSString*)text {
    ows_require(text != nil);
    struct sockaddr_in6 s;
    return inet_pton(AF_INET6, [text UTF8String], &(s.sin6_addr)) == 1;
}
+(NSString*) ipv4AddressToString:(const struct sockaddr_in*)addr {
    char buffer[INET_ADDRSTRLEN];
    const char* result = inet_ntop(AF_INET, &addr->sin_addr, buffer, INET_ADDRSTRLEN);
    checkOperationDescribe(result != NULL, @"Invalid ipv4 address data");
    return @(result);
}
+(NSString*) ipv6AddressToString:(const struct sockaddr_in6*)addr {
    char buffer[INET6_ADDRSTRLEN];
    const char* result = inet_ntop(AF_INET6, &addr->sin6_addr, buffer, INET6_ADDRSTRLEN);
    checkOperationDescribe(result != NULL, @"Invalid ipv6 address data");
    return @(result);
}

@end
