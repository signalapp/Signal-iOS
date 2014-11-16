#import <XCTest/XCTest.h>
#import "SecureEndPoint.h"
#import "TestUtil.h"
#import "IPEndPoint.h"

@interface SecureEndPointTest : XCTestCase

@end

@implementation SecureEndPointTest

-(void) testCert {
    Certificate* r = [[Certificate alloc] initFromResourcePath:@"whisperReal"
                                                        ofType:@"cer"];
    test(r != nil);
}

@end
