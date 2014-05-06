#import "PhoneNumberTest.h"
#import "TestUtil.h"
#import "PhoneNumber.h"

@implementation PhoneNumberTest

-(void) testE164 {
    test([[[PhoneNumber tryParsePhoneNumberFromText:@"+1 (902) 555-5555" fromRegion:@"US"] toE164] isEqualToString:@"+19025555555"]);
    test([[[PhoneNumber tryParsePhoneNumberFromText:@"1 (902) 555-5555" fromRegion:@"US"] toE164] isEqualToString:@"+19025555555"]);
    test([[[PhoneNumber tryParsePhoneNumberFromText:@"1-902-555-5555" fromRegion:@"US"] toE164] isEqualToString:@"+19025555555"]);
    test([[[PhoneNumber tryParsePhoneNumberFromText:@"1-902-５５５-5555" fromRegion:@"US"] toE164] isEqualToString:@"+19025555555"]);
}

@end
