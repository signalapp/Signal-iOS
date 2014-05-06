#import "ShortAuthenticationStringGeneratorTest.h"
#import "ShortAuthenticationStringGenerator.h"
#import "Util.h"
#import "TestUtil.h"

@implementation ShortAuthenticationStringGeneratorTest
-(void) testSAS {
    test([[ShortAuthenticationStringGenerator generateFromData:[(@[@0,@0]) toUint8Data]] isEqualToString:@"aardvark adroitness"]);
    test([[ShortAuthenticationStringGenerator generateFromData:[(@[@0xFF,@0xFF]) toUint8Data]] isEqualToString:@"Zulu Yucatan"]);
}
@end
