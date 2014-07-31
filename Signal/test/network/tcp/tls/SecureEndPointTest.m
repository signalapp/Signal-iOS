#import <XCTest/XCTest.h>
#import "SecureEndPoint.h"
#import "TestUtil.h"
#import "IpEndPoint.h"

@interface SecureEndPointTest : XCTestCase

@end

@implementation SecureEndPointTest

-(void) testCert {
    Certificate* r = [Certificate certificateFromResourcePath:@"whisperReal"
                                                       ofType:@"der"];
    test(r != nil);
}
-(void) testCert2 {
    Certificate* r = [Certificate certificateFromResourcePath:@"whisperTest"
                                                       ofType:@"der"];
    test(r != nil);
}

@end
