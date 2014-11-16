#import <XCTest/XCTest.h>
#import "TestUtil.h"
#import "IPEndPoint.h"
#import "IPAddress.h"

@interface IPEndPointTest : XCTestCase

@end

@implementation IPEndPointTest
-(void) testTrivial {
    IPAddress* a = IPAddress.localhost;
    IPEndPoint* p = [[IPEndPoint alloc] initWithAddress:a onPort:2];
    test([p address] == a);
    test([p port] == 2);
}
-(void) testFromSockaddrLoop {
    for (NSString* s in @[@"4.5.6.7", @"2001:0db8:85a3:0001:0002:8a2e:0370:7334"]) {
        IPAddress* a = [[IPAddress alloc] initFromString:s];
        IPEndPoint* p = [[IPEndPoint alloc] initFromSockaddrData:[[[IPEndPoint alloc] initWithAddress:a onPort:6] sockaddrData]];
        test([[[p address] description] isEqualToString:[a description]]);
        test([p port] == 6);
    }
}
@end
