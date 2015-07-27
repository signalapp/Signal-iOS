#import <XCTest/XCTest.h>
#import "SecureEndPoint.h"
#import "TestUtil.h"

@interface SecureEndPointTest : XCTestCase

@end

@implementation SecureEndPointTest

-(void) testCert {
    Certificate* r = [Certificate certificateFromResourcePath:@"redphone"
                                                       ofType:@"cer"];
    test(r != nil);
}

@end
