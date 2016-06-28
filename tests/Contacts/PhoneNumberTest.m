//
//  PhoneNumberTest.m
//  Signal
//
//  Created by Michael Kirk on 6/28/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "PhoneNumber.h"

@interface PhoneNumberTest : XCTestCase

@end

@implementation PhoneNumberTest

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

@end
