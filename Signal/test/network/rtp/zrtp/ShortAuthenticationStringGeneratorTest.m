#import <XCTest/XCTest.h>
#import "ShortAuthenticationStringGenerator.h"
#import "Util.h"
#import "TestUtil.h"

@interface ShortAuthenticationStringGeneratorTest : XCTestCase

@end

@implementation ShortAuthenticationStringGeneratorTest
-(void) testSAS {
    test([[ShortAuthenticationStringGenerator generateFromData:[(@[@0,@0]) ows_toUint8Data]] isEqualToString:@"aardvark adroitness"]);
    test([[ShortAuthenticationStringGenerator generateFromData:[(@[@0xFF,@0xFF]) ows_toUint8Data]] isEqualToString:@"Zulu Yucatan"]);
}
@end
