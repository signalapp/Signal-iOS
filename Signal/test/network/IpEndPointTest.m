#import <XCTest/XCTest.h>
#import "TestUtil.h"
#import "IpAddress.h"

@interface IpEndPointTest : XCTestCase

@end

@implementation IpEndPointTest
-(void) testTrivial {
    IpAddress* a = IpAddress.localhost;
    IpEndPoint* p = [IpEndPoint ipEndPointAtAddress:a onPort:2];
    test([p address] == a);
    test([p port] == 2);
}
-(void) testFromSockaddrLoop {
    for (NSString* s in @[@"4.5.6.7", @"2001:0db8:85a3:0001:0002:8a2e:0370:7334"]) {
        IpAddress* a = [IpAddress ipAddressFromString:s];
        IpEndPoint* p = [IpEndPoint ipEndPointFromSockaddrData:[[IpEndPoint ipEndPointAtAddress:a onPort:6] sockaddrData]];
        test([[[p address] description] isEqualToString:[a description]]);
        test([p port] == 6);
    }
}
@end
