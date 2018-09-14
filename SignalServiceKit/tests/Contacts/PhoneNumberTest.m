//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "PhoneNumber.h"
#import "SSKBaseTest.h"

@interface PhoneNumberTest : SSKBaseTest

@end

#pragma mark -

@implementation PhoneNumberTest

-(void)testE164 {
    XCTAssertEqualObjects(@"+19025555555", [[PhoneNumber tryParsePhoneNumberFromUserSpecifiedText:@"+1 (902) 555-5555"] toE164]);
    XCTAssertEqualObjects(@"+19025555555", [[PhoneNumber tryParsePhoneNumberFromUserSpecifiedText:@"1 (902) 555-5555"] toE164]);
    XCTAssertEqualObjects(@"+19025555555", [[PhoneNumber tryParsePhoneNumberFromUserSpecifiedText:@"1-902-555-5555"] toE164]);
    XCTAssertEqualObjects(@"+19025555555", [[PhoneNumber tryParsePhoneNumberFromUserSpecifiedText:@"1-902-５５５-5555"] toE164]);

    // Phone numbers missing a calling code.
    XCTAssertEqualObjects(@"+19025555555", [[PhoneNumber tryParsePhoneNumberFromUserSpecifiedText:@"9025555555"] toE164]);

    // Phone numbers with a calling code but without a plus
    XCTAssertEqualObjects(@"+19025555555", [[PhoneNumber tryParsePhoneNumberFromUserSpecifiedText:@"19025555555"] toE164]);

    // Empty input.
    XCTAssertEqualObjects(nil, [[PhoneNumber tryParsePhoneNumberFromUserSpecifiedText:@""] toE164]);
}

- (void)testTryParsePhoneNumberFromUserSpecifiedTextAssumesLocalRegion {
    PhoneNumber *actual = [PhoneNumber tryParsePhoneNumberFromUserSpecifiedText:@"3235551234"];
    XCTAssertEqualObjects(@"+13235551234", [actual toE164]);
}

- (void)testTryParsePhoneNumberFromUserSpecifiedTextWithExplicitRegionCode {
    PhoneNumber *actual = [PhoneNumber tryParsePhoneNumberFromUserSpecifiedText:@"+33 1 70 39 38 00"];
    XCTAssertEqualObjects(@"+33170393800", [actual toE164]);
}

- (void)testTryParsePhoneNumberFromUserSpecifiedTextWithoutPlus {
    PhoneNumber *actual = [PhoneNumber tryParsePhoneNumberFromUserSpecifiedText:@"33 1 70 39 38 00"];

    // This might not be desired, but documents existing behavior.
    // You *must* include a plus when dialing outside of your locale.
    XCTAssertEqualObjects(@"+133170393800", [actual toE164]);
}

- (void)testTryParsePhoneNumberFromUserSpecifiedTextRemovesAnyFormatting {
    PhoneNumber *actual = [PhoneNumber tryParsePhoneNumberFromUserSpecifiedText:@"323 555 1234"];
    XCTAssertEqualObjects(@"+13235551234", [actual toE164]);

    actual = [PhoneNumber tryParsePhoneNumberFromUserSpecifiedText:@"323-555-1234"];
    XCTAssertEqualObjects(@"+13235551234", [actual toE164]);

    actual = [PhoneNumber tryParsePhoneNumberFromUserSpecifiedText:@"323.555.1234"];
    XCTAssertEqualObjects(@"+13235551234", [actual toE164]);

    actual = [PhoneNumber tryParsePhoneNumberFromUserSpecifiedText:@"1-323-555-1234"];
    XCTAssertEqualObjects(@"+13235551234", [actual toE164]);
}

- (NSArray<NSString *> *)unpackTryParsePhoneNumbersFromsUserSpecifiedText:(NSString *)text
                                                        clientPhoneNumber:(NSString *)clientPhoneNumber
{
    NSArray<PhoneNumber *> *phoneNumbers =
        [PhoneNumber tryParsePhoneNumbersFromsUserSpecifiedText:text clientPhoneNumber:clientPhoneNumber];
    NSMutableArray<NSString *> *result = [NSMutableArray new];
    for (PhoneNumber *phoneNumber in phoneNumbers) {
        [result addObject:phoneNumber.toE164];
    }
    return result;
}

- (void)testTryParsePhoneNumbersFromsUserSpecifiedText_SimpleUSA
{
    NSArray<NSString *> *parsed =
        [self unpackTryParsePhoneNumbersFromsUserSpecifiedText:@"323 555 1234" clientPhoneNumber:@"+13213214321"];
    XCTAssertTrue(parsed.count >= 1);
    XCTAssertTrue([parsed containsObject:@"+13235551234"]);
    XCTAssertEqualObjects(parsed.firstObject, @"+13235551234");

    parsed = [self unpackTryParsePhoneNumbersFromsUserSpecifiedText:@"323-555-1234" clientPhoneNumber:@"+13213214321"];
    XCTAssertTrue(parsed.count >= 1);
    XCTAssertTrue([parsed containsObject:@"+13235551234"]);
    XCTAssertEqualObjects(parsed.firstObject, @"+13235551234");

    parsed = [self unpackTryParsePhoneNumbersFromsUserSpecifiedText:@"323.555.1234" clientPhoneNumber:@"+13213214321"];
    XCTAssertTrue(parsed.count >= 1);
    XCTAssertTrue([parsed containsObject:@"+13235551234"]);
    XCTAssertEqualObjects(parsed.firstObject, @"+13235551234");

    parsed =
        [self unpackTryParsePhoneNumbersFromsUserSpecifiedText:@"1-323-555-1234" clientPhoneNumber:@"+13213214321"];
    XCTAssertTrue(parsed.count >= 1);
    XCTAssertTrue([parsed containsObject:@"+13235551234"]);
    XCTAssertEqualObjects(parsed.firstObject, @"+13235551234");

    parsed = [self unpackTryParsePhoneNumbersFromsUserSpecifiedText:@"+13235551234" clientPhoneNumber:@"+13213214321"];
    XCTAssertTrue(parsed.count >= 1);
    XCTAssertTrue([parsed containsObject:@"+13235551234"]);
    XCTAssertEqualObjects(parsed.firstObject, @"+13235551234");
}

- (void)testTryParsePhoneNumbersFromsUserSpecifiedText_Mexico1
{
    NSArray<NSString *> *parsed =
        [self unpackTryParsePhoneNumbersFromsUserSpecifiedText:@"528341639157" clientPhoneNumber:@"+528341639144"];
    XCTAssertTrue(parsed.count >= 1);
    XCTAssertTrue([parsed containsObject:@"+528341639157"]);

    parsed = [self unpackTryParsePhoneNumbersFromsUserSpecifiedText:@"8341639157" clientPhoneNumber:@"+528341639144"];
    XCTAssertTrue(parsed.count >= 1);
    XCTAssertTrue([parsed containsObject:@"+528341639157"]);

    parsed = [self unpackTryParsePhoneNumbersFromsUserSpecifiedText:@"341639157" clientPhoneNumber:@"+528341639144"];
    XCTAssertTrue(parsed.count >= 1);
    // The parsing logic should try adding Mexico's national prefix for cell numbers "1"
    // after the country code.
    XCTAssertTrue([parsed containsObject:@"+52341639157"]);
    XCTAssertTrue([parsed containsObject:@"+521341639157"]);

    parsed = [self unpackTryParsePhoneNumbersFromsUserSpecifiedText:@"528341639157" clientPhoneNumber:@"+13213214321"];
    XCTAssertTrue(parsed.count >= 1);
    XCTAssertTrue([parsed containsObject:@"+528341639157"]);

    parsed = [self unpackTryParsePhoneNumbersFromsUserSpecifiedText:@"13235551234" clientPhoneNumber:@"+528341639144"];
    XCTAssertTrue(parsed.count >= 1);
    XCTAssertTrue([parsed containsObject:@"+13235551234"]);
}

@end
