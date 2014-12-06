#import <XCTest/XCTest.h>
#import "SecureEndPoint.h"
#import "TestUtil.h"
#import "IpEndPoint.h"

@interface SecureEndPointTest : XCTestCase

@end

@implementation SecureEndPointTest

-(void) testCert {
    Certificate* r = [Certificate certificateFromResourcePath:@"redphone"
                                                       ofType:@"cer"];
    test(r != nil);
}

@end
