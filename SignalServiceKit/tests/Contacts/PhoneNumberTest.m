//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "PhoneNumber.h"
#import "SSKBaseTestObjC.h"

@interface PhoneNumberTest : SSKBaseTestObjC

@end

#pragma mark -

@implementation PhoneNumberTest

- (NSArray<NSString *> *)unpackTryParsePhoneNumbersFromsUserSpecifiedText:(NSString *)text
                                                        clientPhoneNumber:(NSString *)clientPhoneNumber
{
    NSArray<PhoneNumber *> *phoneNumbers =
        [PhoneNumber tryParsePhoneNumbersFromUserSpecifiedText:text clientPhoneNumber:clientPhoneNumber];
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

- (void)testMissingAreaCode_USA
{
    // Add area code to numbers that look like "local" numbers
    NSArray<NSString *> *parsed =
        [self unpackTryParsePhoneNumbersFromsUserSpecifiedText:@"555-1234" clientPhoneNumber:@"+13233214321"];
    XCTAssertTrue([parsed containsObject:@"+13235551234"]);

    parsed = [self unpackTryParsePhoneNumbersFromsUserSpecifiedText:@"5551234" clientPhoneNumber:@"+13233214321"];
    XCTAssertTrue([parsed containsObject:@"+13235551234"]);

    parsed = [self unpackTryParsePhoneNumbersFromsUserSpecifiedText:@"555 1234" clientPhoneNumber:@"+13233214321"];
    XCTAssertTrue([parsed containsObject:@"+13235551234"]);

    // Discard numbers which libPhoneNumber considers "impossible", even if they have a leading "+"
    parsed = [self unpackTryParsePhoneNumbersFromsUserSpecifiedText:@"+5551234" clientPhoneNumber:@"+13213214321"];
    XCTAssertFalse([parsed containsObject:@"+5551234"]);

    // Don't infer area code when number already has one
    parsed = [self unpackTryParsePhoneNumbersFromsUserSpecifiedText:@"570 555 1234" clientPhoneNumber:@"+13233214321"];
    XCTAssertTrue([parsed containsObject:@"+15705551234"]);

    // Don't touch numbers that are already in e164
    parsed = [self unpackTryParsePhoneNumbersFromsUserSpecifiedText:@"+33170393800" clientPhoneNumber:@"+13213214321"];
    XCTAssertTrue([parsed containsObject:@"+33170393800"]);
}

- (void)testMissingAreaCode_Brazil
{
    // Add area code to land-line numbers that look like "local" numbers
    NSArray<NSString *> *parsed =
        [self unpackTryParsePhoneNumbersFromsUserSpecifiedText:@"87654321" clientPhoneNumber:@"+5521912345678"];
    XCTAssertTrue([parsed containsObject:@"+552187654321"]);

    parsed = [self unpackTryParsePhoneNumbersFromsUserSpecifiedText:@"8765-4321" clientPhoneNumber:@"+5521912345678"];
    XCTAssertTrue([parsed containsObject:@"+552187654321"]);

    parsed = [self unpackTryParsePhoneNumbersFromsUserSpecifiedText:@"8765 4321" clientPhoneNumber:@"+5521912345678"];
    XCTAssertTrue([parsed containsObject:@"+552187654321"]);

    // Add area code to mobile numbers that look like "local" numbers
    parsed = [self unpackTryParsePhoneNumbersFromsUserSpecifiedText:@"987654321" clientPhoneNumber:@"+5521912345678"];
    XCTAssertTrue([parsed containsObject:@"+5521987654321"]);

    parsed = [self unpackTryParsePhoneNumbersFromsUserSpecifiedText:@"9 8765-4321" clientPhoneNumber:@"+5521912345678"];
    XCTAssertTrue([parsed containsObject:@"+5521987654321"]);

    parsed = [self unpackTryParsePhoneNumbersFromsUserSpecifiedText:@"9 8765 4321" clientPhoneNumber:@"+5521912345678"];
    XCTAssertTrue([parsed containsObject:@"+5521987654321"]);

    // Don't touch land-line numbers that already have an area code
    parsed =
        [self unpackTryParsePhoneNumbersFromsUserSpecifiedText:@"22 8765 4321" clientPhoneNumber:@"+5521912345678"];
    XCTAssertTrue([parsed containsObject:@"+552287654321"]);

    // Don't touch mobile numbers that already have an area code
    parsed =
        [self unpackTryParsePhoneNumbersFromsUserSpecifiedText:@"22 9 8765 4321" clientPhoneNumber:@"+5521912345678"];
    XCTAssertTrue([parsed containsObject:@"+5522987654321"]);

    // Don't touch numbers that are already in e164
    parsed =
        [self unpackTryParsePhoneNumbersFromsUserSpecifiedText:@"+33170393800" clientPhoneNumber:@"+5521912345678"];
    XCTAssertTrue([parsed containsObject:@"+33170393800"]);
}


@end
