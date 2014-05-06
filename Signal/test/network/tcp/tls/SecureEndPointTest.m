#import "SecureEndPointTest.h"
#import "SecureEndPoint.h"
#import "TestUtil.h"
#import "IpEndPoint.h"

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
