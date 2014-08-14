#import <XCTest/XCTest.h>
#import "TestUtil.h"
#import "IpAddress.h"

@interface IpAddressTest : XCTestCase

@end

@implementation IpAddressTest
-(void) testFromString {
    testThrows([IpAddress ipAddressFromString:nil]);
    testThrows([IpAddress ipAddressFromString:@""]);
    testThrows([IpAddress ipAddressFromString:@"^"]);
    testThrows([IpAddress ipAddressFromString:@"127.6.5"]);
    testThrows([IpAddress ipAddressFromString:@"127.6.5.8:80"]);
    testThrows([IpAddress ipAddressFromString:@"2:5"]);
    testThrows([IpAddress ipAddressFromString:@"256.256.256.256"]);
    testThrows([IpAddress ipAddressFromString:@"0db8:85a3:0000:0000:8a2e:0370:7334"]);
    testThrows([IpAddress ipAddressFromString:@"AAAA:2001:0db8:85a3:0000:0000:8a2e:0370:7334"]);

    [IpAddress ipAddressFromString:@"127.0.0.1"];
    [IpAddress ipAddressFromString:@"255.255.255.255"];
    [IpAddress ipAddressFromString:@"0.0.0.0"];

    [IpAddress ipAddressFromString:@"ab01::"];
    [IpAddress ipAddressFromString:@"AB01::"];
    [IpAddress ipAddressFromString:@"::AB01"];
    [IpAddress ipAddressFromString:@"AB01::1001"];
    [IpAddress ipAddressFromString:@"2001:0db8:85a3:0000:0000:8a2e:0370:7334"];
}
-(void) testFromIpv4String {
    testThrows([IpAddress ipv4AddressFromString:nil]);
    testThrows([IpAddress ipv4AddressFromString:@""]);
    testThrows([IpAddress ipv4AddressFromString:@"^"]);
    testThrows([IpAddress ipv4AddressFromString:@"127.6.5"]);
    testThrows([IpAddress ipv4AddressFromString:@"127.6.5.8:80"]);
    testThrows([IpAddress ipv4AddressFromString:@"2:5"]);
    testThrows([IpAddress ipv4AddressFromString:@"256.256.256.256"]);
    testThrows([IpAddress ipv4AddressFromString:@"0db8:85a3:0000:0000:8a2e:0370:7334"]);
    testThrows([IpAddress ipv4AddressFromString:@"AAAA:2001:0db8:85a3:0000:0000:8a2e:0370:7334"]);
    
    [IpAddress ipv4AddressFromString:@"127.0.0.1"];
    [IpAddress ipv4AddressFromString:@"255.255.255.255"];
    [IpAddress ipv4AddressFromString:@"0.0.0.0"];
    
    testThrows([IpAddress ipv4AddressFromString:@"AB01::"]);
    testThrows([IpAddress ipv4AddressFromString:@"::AB01"]);
    testThrows([IpAddress ipv4AddressFromString:@"AB01::1001"]);
    testThrows([IpAddress ipv4AddressFromString:@"2001:0db8:85a3:0000:0000:8a2e:0370:7334"]);
}
-(void) testFromIpv6String {
    testThrows([IpAddress ipv6AddressFromString:nil]);
    testThrows([IpAddress ipv6AddressFromString:@""]);
    testThrows([IpAddress ipv6AddressFromString:@"^"]);
    testThrows([IpAddress ipv6AddressFromString:@"127.6.5"]);
    testThrows([IpAddress ipv6AddressFromString:@"127.6.5.8:80"]);
    testThrows([IpAddress ipv6AddressFromString:@"2:5"]);
    testThrows([IpAddress ipv6AddressFromString:@"256.256.256.256"]);
    testThrows([IpAddress ipv6AddressFromString:@"0db8:85a3:0000:0000:8a2e:0370:7336"]);
    testThrows([IpAddress ipv6AddressFromString:@"AAAA:2001:0db8:85a3:0000:0000:8a2e:0370:7336"]);
    
    testThrows([IpAddress ipv6AddressFromString:@"127.0.0.1"]);
    testThrows([IpAddress ipv6AddressFromString:@"255.255.255.255"]);
    testThrows([IpAddress ipv6AddressFromString:@"0.0.0.0"]);
    
    [IpAddress ipv6AddressFromString:@"AB01::"];
    [IpAddress ipv6AddressFromString:@"ab01::"];
    [IpAddress ipv6AddressFromString:@"::AB01"];
    [IpAddress ipv6AddressFromString:@"AB01::1001"];
    [IpAddress ipv6AddressFromString:@"2001:0db8:85a3:0000:0000:8a2e:0370:7334"];
}

-(void) testDescription {
    for (NSString* s in @[@"4.5.6.7", @"abcd:cdef:85a3:1234:2345:8a2e:6789:7334"]) {
        test([[[IpAddress ipAddressFromString:s] description] isEqualToString:s]);
    }
}
-(void) testSockaddrDataIpv4 {
    NSData* d = [[IpAddress ipAddressFromString:@"4.5.6.7"] sockaddrDataWithPort:5];
    struct sockaddr_in s;
    test(d.length >= sizeof(struct sockaddr_in));
    memcpy(&s, [d bytes], sizeof(struct sockaddr_in));
    test(s.sin_port == ntohs(5));
    test(s.sin_family == AF_INET);
    test(s.sin_addr.s_addr == 0x07060504);
}
-(void) testSockaddrDataIpv6 {
    NSData* d = [[IpAddress ipAddressFromString:@"2001:0db8:85a3:0000:0000:8a2e:0370:7334"] sockaddrDataWithPort:5];
    struct sockaddr_in6 s;
    test(d.length >= sizeof(struct sockaddr_in6));
    memcpy(&s, [d bytes], sizeof(struct sockaddr_in6));
    test(s.sin6_port == ntohs(5));
    test(s.sin6_family == AF_INET6);
    
    uint16_t* x = s.sin6_addr.__u6_addr.__u6_addr16;
    test(x[0] == ntohs(0x2001));
    test(x[1] == ntohs(0x0db8));
    test(x[2] == ntohs(0x85a3));
    test(x[3] == 0);
    test(x[4] == 0);
    test(x[5] == ntohs(0x8a2e));
    test(x[6] == ntohs(0x0370));
    test(x[7] == ntohs(0x7334));
}
@end
