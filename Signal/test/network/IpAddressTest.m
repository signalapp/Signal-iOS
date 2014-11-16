#import <XCTest/XCTest.h>
#import "TestUtil.h"
#import "IPAddress.h"

@interface IPAddressTest : XCTestCase

@end

@implementation IPAddressTest
-(void) testFromString {
    testThrows([[IPAddress alloc] initFromString:nil]);
    testThrows([[IPAddress alloc] initFromString:@""]);
    testThrows([[IPAddress alloc] initFromString:@"^"]);
    testThrows([[IPAddress alloc] initFromString:@"127.6.5"]);
    testThrows([[IPAddress alloc] initFromString:@"127.6.5.8:80"]);
    testThrows([[IPAddress alloc] initFromString:@"2:5"]);
    testThrows([[IPAddress alloc] initFromString:@"256.256.256.256"]);
    testThrows([[IPAddress alloc] initFromString:@"0db8:85a3:0000:0000:8a2e:0370:7334"]);
    testThrows([[IPAddress alloc] initFromString:@"AAAA:2001:0db8:85a3:0000:0000:8a2e:0370:7334"]);

    [[IPAddress alloc] initFromString:@"127.0.0.1"];
    [[IPAddress alloc] initFromString:@"255.255.255.255"];
    [[IPAddress alloc] initFromString:@"0.0.0.0"];

    [[IPAddress alloc] initFromString:@"ab01::"];
    [[IPAddress alloc] initFromString:@"AB01::"];
    [[IPAddress alloc] initFromString:@"::AB01"];
    [[IPAddress alloc] initFromString:@"AB01::1001"];
    [[IPAddress alloc] initFromString:@"2001:0db8:85a3:0000:0000:8a2e:0370:7334"];
}
-(void) testFromIpv4String {
    testThrows([[IPAddress alloc] initIPv4AddressFromString:nil]);
    testThrows([[IPAddress alloc] initIPv4AddressFromString:@""]);
    testThrows([[IPAddress alloc] initIPv4AddressFromString:@"^"]);
    testThrows([[IPAddress alloc] initIPv4AddressFromString:@"127.6.5"]);
    testThrows([[IPAddress alloc] initIPv4AddressFromString:@"127.6.5.8:80"]);
    testThrows([[IPAddress alloc] initIPv4AddressFromString:@"2:5"]);
    testThrows([[IPAddress alloc] initIPv4AddressFromString:@"256.256.256.256"]);
    testThrows([[IPAddress alloc] initIPv4AddressFromString:@"0db8:85a3:0000:0000:8a2e:0370:7334"]);
    testThrows([[IPAddress alloc] initIPv4AddressFromString:@"AAAA:2001:0db8:85a3:0000:0000:8a2e:0370:7334"]);
    
    [[IPAddress alloc] initIPv4AddressFromString:@"127.0.0.1"];
    [[IPAddress alloc] initIPv4AddressFromString:@"255.255.255.255"];
    [[IPAddress alloc] initIPv4AddressFromString:@"0.0.0.0"];
    
    testThrows([[IPAddress alloc] initIPv4AddressFromString:@"AB01::"]);
    testThrows([[IPAddress alloc] initIPv4AddressFromString:@"::AB01"]);
    testThrows([[IPAddress alloc] initIPv4AddressFromString:@"AB01::1001"]);
    testThrows([[IPAddress alloc] initIPv4AddressFromString:@"2001:0db8:85a3:0000:0000:8a2e:0370:7334"]);
}
-(void) testFromIpv6String {
    testThrows([[IPAddress alloc] initIPv6AddressFromString:nil]);
    testThrows([[IPAddress alloc] initIPv6AddressFromString:@""]);
    testThrows([[IPAddress alloc] initIPv6AddressFromString:@"^"]);
    testThrows([[IPAddress alloc] initIPv6AddressFromString:@"127.6.5"]);
    testThrows([[IPAddress alloc] initIPv6AddressFromString:@"127.6.5.8:80"]);
    testThrows([[IPAddress alloc] initIPv6AddressFromString:@"2:5"]);
    testThrows([[IPAddress alloc] initIPv6AddressFromString:@"256.256.256.256"]);
    testThrows([[IPAddress alloc] initIPv6AddressFromString:@"0db8:85a3:0000:0000:8a2e:0370:7336"]);
    testThrows([[IPAddress alloc] initIPv6AddressFromString:@"AAAA:2001:0db8:85a3:0000:0000:8a2e:0370:7336"]);
    
    testThrows([[IPAddress alloc] initIPv6AddressFromString:@"127.0.0.1"]);
    testThrows([[IPAddress alloc] initIPv6AddressFromString:@"255.255.255.255"]);
    testThrows([[IPAddress alloc] initIPv6AddressFromString:@"0.0.0.0"]);
    
    [[IPAddress alloc] initIPv6AddressFromString:@"AB01::"];
    [[IPAddress alloc] initIPv6AddressFromString:@"ab01::"];
    [[IPAddress alloc] initIPv6AddressFromString:@"::AB01"];
    [[IPAddress alloc] initIPv6AddressFromString:@"AB01::1001"];
    [[IPAddress alloc] initIPv6AddressFromString:@"2001:0db8:85a3:0000:0000:8a2e:0370:7334"];
}

-(void) testDescription {
    for (NSString* s in @[@"4.5.6.7", @"abcd:cdef:85a3:1234:2345:8a2e:6789:7334"]) {
        test([[[[IPAddress alloc] initFromString:s] description] isEqualToString:s]);
    }
}
-(void) testSockaddrDataIpv4 {
    NSData* d = [[[IPAddress alloc] initFromString:@"4.5.6.7"] sockaddrDataWithPort:5];
    struct sockaddr_in s;
    test(d.length >= sizeof(struct sockaddr_in));
    memcpy(&s, [d bytes], sizeof(struct sockaddr_in));
    test(s.sin_port == ntohs(5));
    test(s.sin_family == AF_INET);
    test(s.sin_addr.s_addr == 0x07060504);
}
-(void) testSockaddrDataIpv6 {
    NSData* d = [[[IPAddress alloc] initFromString:@"2001:0db8:85a3:0000:0000:8a2e:0370:7334"] sockaddrDataWithPort:5];
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
