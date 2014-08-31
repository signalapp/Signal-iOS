#import <XCTest/XCTest.h>
#import "TestUtil.h"
#import "PhoneNumber.h"
#import "PhoneNumberUtil.h"

@interface PhoneNumberTest : XCTestCase

@end

@implementation PhoneNumberTest

-(void) testE164 {
    test([[[PhoneNumber tryParsePhoneNumberFromText:@"+1 (902) 555-5555" fromRegion:@"US"] toE164] isEqualToString:@"+19025555555"]);
    test([[[PhoneNumber tryParsePhoneNumberFromText:@"1 (902) 555-5555" fromRegion:@"US"] toE164] isEqualToString:@"+19025555555"]);
    test([[[PhoneNumber tryParsePhoneNumberFromText:@"1-902-555-5555" fromRegion:@"US"] toE164] isEqualToString:@"+19025555555"]);
    test([[[PhoneNumber tryParsePhoneNumberFromText:@"1-902-５５５-5555" fromRegion:@"US"] toE164] isEqualToString:@"+19025555555"]);
}

-(void) testTranslateCursorPosition {
    testThrows([PhoneNumberUtil translateCursorPosition:0 from:nil to:@"" stickingRightward:true]);
    testThrows([PhoneNumberUtil translateCursorPosition:0 from:@"" to:nil stickingRightward:true]);
    testThrows([PhoneNumberUtil translateCursorPosition:1 from:@"" to:@"" stickingRightward:true]);
    
    test([PhoneNumberUtil translateCursorPosition:0 from:@"" to:@"" stickingRightward:true] == 0);

    test([PhoneNumberUtil translateCursorPosition:0 from:@"12" to:@"1" stickingRightward:true] == 0);
    test([PhoneNumberUtil translateCursorPosition:1 from:@"12" to:@"1" stickingRightward:true] == 1);
    test([PhoneNumberUtil translateCursorPosition:2 from:@"12" to:@"1" stickingRightward:true] == 1);
    
    test([PhoneNumberUtil translateCursorPosition:0 from:@"1" to:@"12" stickingRightward:false] == 0);
    test([PhoneNumberUtil translateCursorPosition:0 from:@"1" to:@"12" stickingRightward:true] == 0);
    test([PhoneNumberUtil translateCursorPosition:1 from:@"1" to:@"12" stickingRightward:false] == 1);
    test([PhoneNumberUtil translateCursorPosition:1 from:@"1" to:@"12" stickingRightward:true] == 2);
    
    test([PhoneNumberUtil translateCursorPosition:0 from:@"12" to:@"132" stickingRightward:false] == 0);
    test([PhoneNumberUtil translateCursorPosition:0 from:@"12" to:@"132" stickingRightward:true] == 0);
    test([PhoneNumberUtil translateCursorPosition:1 from:@"12" to:@"132" stickingRightward:false] == 1);
    test([PhoneNumberUtil translateCursorPosition:1 from:@"12" to:@"132" stickingRightward:true] == 2);
    test([PhoneNumberUtil translateCursorPosition:2 from:@"12" to:@"132" stickingRightward:false] == 3);
    test([PhoneNumberUtil translateCursorPosition:2 from:@"12" to:@"132" stickingRightward:true] == 3);

    test([PhoneNumberUtil translateCursorPosition:0 from:@"(55) 123-4567" to:@"(551) 234-567" stickingRightward:true] == 0);
    test([PhoneNumberUtil translateCursorPosition:1 from:@"(55) 123-4567" to:@"(551) 234-567" stickingRightward:true] == 1);
    test([PhoneNumberUtil translateCursorPosition:2 from:@"(55) 123-4567" to:@"(551) 234-567" stickingRightward:true] == 2);
    test([PhoneNumberUtil translateCursorPosition:3 from:@"(55) 123-4567" to:@"(551) 234-567" stickingRightward:true] == 3);
    test([PhoneNumberUtil translateCursorPosition:4 from:@"(55) 123-4567" to:@"(551) 234-567" stickingRightward:true] == 3);
    test([PhoneNumberUtil translateCursorPosition:5 from:@"(55) 123-4567" to:@"(551) 234-567" stickingRightward:true] == 3);
    test([PhoneNumberUtil translateCursorPosition:6 from:@"(55) 123-4567" to:@"(551) 234-567" stickingRightward:true] == 6);
    test([PhoneNumberUtil translateCursorPosition:7 from:@"(55) 123-4567" to:@"(551) 234-567" stickingRightward:true] == 7);
    test([PhoneNumberUtil translateCursorPosition:8 from:@"(55) 123-4567" to:@"(551) 234-567" stickingRightward:true] == 8);
    test([PhoneNumberUtil translateCursorPosition:9 from:@"(55) 123-4567" to:@"(551) 234-567" stickingRightward:true] == 8);
    
    test([PhoneNumberUtil translateCursorPosition:0 from:@"(55) 123-4567" to:@"(551) 234-567" stickingRightward:false] == 0);
    test([PhoneNumberUtil translateCursorPosition:1 from:@"(55) 123-4567" to:@"(551) 234-567" stickingRightward:false] == 1);
    test([PhoneNumberUtil translateCursorPosition:2 from:@"(55) 123-4567" to:@"(551) 234-567" stickingRightward:false] == 2);
    test([PhoneNumberUtil translateCursorPosition:3 from:@"(55) 123-4567" to:@"(551) 234-567" stickingRightward:false] == 3);
    test([PhoneNumberUtil translateCursorPosition:4 from:@"(55) 123-4567" to:@"(551) 234-567" stickingRightward:false] == 3);
    test([PhoneNumberUtil translateCursorPosition:5 from:@"(55) 123-4567" to:@"(551) 234-567" stickingRightward:false] == 3);
    test([PhoneNumberUtil translateCursorPosition:6 from:@"(55) 123-4567" to:@"(551) 234-567" stickingRightward:false] == 4);
    test([PhoneNumberUtil translateCursorPosition:7 from:@"(55) 123-4567" to:@"(551) 234-567" stickingRightward:false] == 7);
    test([PhoneNumberUtil translateCursorPosition:8 from:@"(55) 123-4567" to:@"(551) 234-567" stickingRightward:false] == 8);
    test([PhoneNumberUtil translateCursorPosition:9 from:@"(55) 123-4567" to:@"(551) 234-567" stickingRightward:false] == 8);
    
    test([PhoneNumberUtil translateCursorPosition:0 from:@"(5551) 234-567" to:@"(555) 123-4567" stickingRightward:true] == 0);
    test([PhoneNumberUtil translateCursorPosition:1 from:@"(5551) 234-567" to:@"(555) 123-4567" stickingRightward:true] == 1);
    test([PhoneNumberUtil translateCursorPosition:2 from:@"(5551) 234-567" to:@"(555) 123-4567" stickingRightward:true] == 2);
    test([PhoneNumberUtil translateCursorPosition:3 from:@"(5551) 234-567" to:@"(555) 123-4567" stickingRightward:true] == 3);
    test([PhoneNumberUtil translateCursorPosition:4 from:@"(5551) 234-567" to:@"(555) 123-4567" stickingRightward:true] == 6);
    test([PhoneNumberUtil translateCursorPosition:5 from:@"(5551) 234-567" to:@"(555) 123-4567" stickingRightward:true] == 7);

    test([PhoneNumberUtil translateCursorPosition:0 from:@"(5551) 234-567" to:@"(555) 123-4567" stickingRightward:false] == 0);
    test([PhoneNumberUtil translateCursorPosition:1 from:@"(5551) 234-567" to:@"(555) 123-4567" stickingRightward:false] == 1);
    test([PhoneNumberUtil translateCursorPosition:2 from:@"(5551) 234-567" to:@"(555) 123-4567" stickingRightward:false] == 2);
    test([PhoneNumberUtil translateCursorPosition:3 from:@"(5551) 234-567" to:@"(555) 123-4567" stickingRightward:false] == 3);
    test([PhoneNumberUtil translateCursorPosition:4 from:@"(5551) 234-567" to:@"(555) 123-4567" stickingRightward:false] == 4);
    test([PhoneNumberUtil translateCursorPosition:5 from:@"(5551) 234-567" to:@"(555) 123-4567" stickingRightward:false] == 7);
}

@end
