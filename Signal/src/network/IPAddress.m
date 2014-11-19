#import "IPAddress.h"
#import "Util.h"
#import "Constraints.h"
#import "IPEndPoint.h"

#define LOCAL_HOST_IP @"127.0.0.1"

@interface IPAddress ()

@property (nonatomic) bool isIPv4;
@property (nonatomic) bool isIPv6;
@property (nonatomic) struct sockaddr_in ipv4Data;
@property (nonatomic) struct sockaddr_in6 ipv6Data;

@end

@implementation IPAddress

+ (instancetype)localhost {
    return [[self alloc] initIPv4AddressFromString:LOCAL_HOST_IP];
}

- (instancetype)initFromString:(NSString*)text {
    require(text != nil);
    
    if ([IPAddress isIPv4Text:text]) {
        return [[IPAddress alloc] initIPv4AddressFromString:text];
    }
    
    if ([IPAddress isIPv6Text:text]) {
        return [[IPAddress alloc] initIPv6AddressFromString:text];
    }
    
    [BadArgument raise:[NSString stringWithFormat:@"Invalid IP address: %@", text]];
    
    return nil;
}

- (instancetype)initIPv4AddressFromString:(NSString*)text {
    if (self = [super init]) {
        require(text != nil);
        
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
        
        self.isIPv4 = true;
        self.ipv4Data = s;
    }
    
    return self;
}

- (instancetype)initIPv6AddressFromString:(NSString*)text {
    if (self = [super init]) {
        require(text != nil);
        
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
        
        self.ipv6Data = s;
        self.isIPv6 = true;
    }
    
    return self;
}

- (instancetype)initIPv4AddressFromSockaddr:(struct sockaddr_in)sockaddr {
    if (self = [super init]) {
        self.ipv4Data = sockaddr;
        self.isIPv4 = true;
    }
    
    return self;
}

- (instancetype)initIPv6AddressFromSockaddr:(struct sockaddr_in6)sockaddr {
    if (self = [super init]) {
        self.ipv6Data = sockaddr;
        self.isIPv6 = true;
    }
    
    return self;
}

- (NSData*)sockaddrData {
    return [self sockaddrDataWithPort:0];
}

- (NSData*)sockaddrDataWithPort:(in_port_t)port {
    requireState(self.isIPv4 || self.isIPv6);
    if (self.isIPv4) {
        struct sockaddr_in s = self.ipv4Data;
        s.sin_port = htons(port);
        NSMutableData* d = [NSMutableData dataWithLength:sizeof(struct sockaddr_in)];
        memcpy([d mutableBytes], &s, sizeof(struct sockaddr_in));
        return d;
    } else {
        struct sockaddr_in6 s = self.ipv6Data;
        s.sin6_port = htons(port);
        NSMutableData* d = [NSMutableData dataWithLength:sizeof(struct sockaddr_in6)];
        memcpy([d mutableBytes], &s, sizeof(struct sockaddr_in6));
        return d;
    }
}

- (NSString*)description {
    requireState(self.isIPv4 || self.isIPv6);
    if (self.isIPv4) {
        struct sockaddr_in data = self.ipv4Data;
        return [IPAddress ipv4AddressToString:&data];
    } else {
        struct sockaddr_in6 data = self.ipv6Data;
        return [IPAddress ipv6AddressToString:&data];
    }
}

+ (bool)isIPv4Text:(NSString*)text {
    require(text != nil);
    struct sockaddr_in s;
    return inet_pton(AF_INET, [text UTF8String], &(s.sin_addr)) == 1;
}

+ (bool)isIPv6Text:(NSString*)text {
    require(text != nil);
    struct sockaddr_in6 s;
    return inet_pton(AF_INET6, [text UTF8String], &(s.sin6_addr)) == 1;
}

+ (NSString*)ipv4AddressToString:(const struct sockaddr_in*)addr {
    char buffer[INET_ADDRSTRLEN];
    const char* result = inet_ntop(AF_INET, &addr->sin_addr, buffer, INET_ADDRSTRLEN);
    checkOperationDescribe(result != NULL, @"Invalid IPv4 address data");
    return @(result);
}

+ (NSString*)ipv6AddressToString:(const struct sockaddr_in6*)addr {
    char buffer[INET6_ADDRSTRLEN];
    const char* result = inet_ntop(AF_INET6, &addr->sin6_addr, buffer, INET6_ADDRSTRLEN);
    checkOperationDescribe(result != NULL, @"Invalid IPv6 address data");
    return @(result);
}

// Removed due to disuse
/*
+(IPAddress*) tryGetIPAddressFromString:(NSString*)text {
 require(text != nil);
 if ([IPAddress isIPv4Text:text]) return [[IPAddress alloc] initIPv4AddressFromString:text];
 if ([IPAddress isIPv6Text:text]) return [[IPAddress alloc] initIPv6AddressFromString:text];
 return nil;
 }
*/

@end
