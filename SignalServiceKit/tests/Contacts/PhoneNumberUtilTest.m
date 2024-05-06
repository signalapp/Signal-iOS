//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "PhoneNumberUtil.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <XCTest/XCTest.h>

@interface PhoneNumberUtilTest : XCTestCase
@end

#pragma mark -

@implementation PhoneNumberUtilTest

- (void)testTranslateCursorPosition
{
    XCTAssertEqual(0, [PhoneNumberUtil translateCursorPosition:0 from:@"" to:@"" stickingRightward:true]);

    XCTAssertEqual(0, [PhoneNumberUtil translateCursorPosition:0 from:@"" to:@"" stickingRightward:true]);
    XCTAssertEqual(0, [PhoneNumberUtil translateCursorPosition:0 from:@"12" to:@"1" stickingRightward:true]);
    XCTAssertEqual(1, [PhoneNumberUtil translateCursorPosition:1 from:@"12" to:@"1" stickingRightward:true]);
    XCTAssertEqual(1, [PhoneNumberUtil translateCursorPosition:2 from:@"12" to:@"1" stickingRightward:true]);

    XCTAssertEqual(0, [PhoneNumberUtil translateCursorPosition:0 from:@"1" to:@"12" stickingRightward:false]);
    XCTAssertEqual(0, [PhoneNumberUtil translateCursorPosition:0 from:@"1" to:@"12" stickingRightward:true]);
    XCTAssertEqual(1, [PhoneNumberUtil translateCursorPosition:1 from:@"1" to:@"12" stickingRightward:false]);
    XCTAssertEqual(2, [PhoneNumberUtil translateCursorPosition:1 from:@"1" to:@"12" stickingRightward:true]);

    XCTAssertEqual(0, [PhoneNumberUtil translateCursorPosition:0 from:@"12" to:@"132" stickingRightward:false]);
    XCTAssertEqual(0, [PhoneNumberUtil translateCursorPosition:0 from:@"12" to:@"132" stickingRightward:true]);
    XCTAssertEqual(1, [PhoneNumberUtil translateCursorPosition:1 from:@"12" to:@"132" stickingRightward:false]);
    XCTAssertEqual(2, [PhoneNumberUtil translateCursorPosition:1 from:@"12" to:@"132" stickingRightward:true]);
    XCTAssertEqual(3, [PhoneNumberUtil translateCursorPosition:2 from:@"12" to:@"132" stickingRightward:false]);
    XCTAssertEqual(3, [PhoneNumberUtil translateCursorPosition:2 from:@"12" to:@"132" stickingRightward:true]);

    XCTAssertEqual(0,
        [PhoneNumberUtil translateCursorPosition:0 from:@"(55) 123-4567" to:@"(551) 234-567" stickingRightward:true]);
    XCTAssertEqual(1,
        [PhoneNumberUtil translateCursorPosition:1 from:@"(55) 123-4567" to:@"(551) 234-567" stickingRightward:true]);
    XCTAssertEqual(2,
        [PhoneNumberUtil translateCursorPosition:2 from:@"(55) 123-4567" to:@"(551) 234-567" stickingRightward:true]);
    XCTAssertEqual(3,
        [PhoneNumberUtil translateCursorPosition:3 from:@"(55) 123-4567" to:@"(551) 234-567" stickingRightward:true]);
    XCTAssertEqual(3,
        [PhoneNumberUtil translateCursorPosition:4 from:@"(55) 123-4567" to:@"(551) 234-567" stickingRightward:true]);
    XCTAssertEqual(3,
        [PhoneNumberUtil translateCursorPosition:5 from:@"(55) 123-4567" to:@"(551) 234-567" stickingRightward:true]);
    XCTAssertEqual(6,
        [PhoneNumberUtil translateCursorPosition:6 from:@"(55) 123-4567" to:@"(551) 234-567" stickingRightward:true]);
    XCTAssertEqual(7,
        [PhoneNumberUtil translateCursorPosition:7 from:@"(55) 123-4567" to:@"(551) 234-567" stickingRightward:true]);
    XCTAssertEqual(8,
        [PhoneNumberUtil translateCursorPosition:8 from:@"(55) 123-4567" to:@"(551) 234-567" stickingRightward:true]);
    XCTAssertEqual(8,
        [PhoneNumberUtil translateCursorPosition:9 from:@"(55) 123-4567" to:@"(551) 234-567" stickingRightward:true]);

    XCTAssertEqual(0,
        [PhoneNumberUtil translateCursorPosition:0 from:@"(55) 123-4567" to:@"(551) 234-567" stickingRightward:false]);
    XCTAssertEqual(1,
        [PhoneNumberUtil translateCursorPosition:1 from:@"(55) 123-4567" to:@"(551) 234-567" stickingRightward:false]);
    XCTAssertEqual(2,
        [PhoneNumberUtil translateCursorPosition:2 from:@"(55) 123-4567" to:@"(551) 234-567" stickingRightward:false]);
    XCTAssertEqual(3,
        [PhoneNumberUtil translateCursorPosition:3 from:@"(55) 123-4567" to:@"(551) 234-567" stickingRightward:false]);
    XCTAssertEqual(3,
        [PhoneNumberUtil translateCursorPosition:4 from:@"(55) 123-4567" to:@"(551) 234-567" stickingRightward:false]);
    XCTAssertEqual(3,
        [PhoneNumberUtil translateCursorPosition:5 from:@"(55) 123-4567" to:@"(551) 234-567" stickingRightward:false]);
    XCTAssertEqual(4,
        [PhoneNumberUtil translateCursorPosition:6 from:@"(55) 123-4567" to:@"(551) 234-567" stickingRightward:false]);
    XCTAssertEqual(7,
        [PhoneNumberUtil translateCursorPosition:7 from:@"(55) 123-4567" to:@"(551) 234-567" stickingRightward:false]);
    XCTAssertEqual(8,
        [PhoneNumberUtil translateCursorPosition:8 from:@"(55) 123-4567" to:@"(551) 234-567" stickingRightward:false]);
    XCTAssertEqual(8,
        [PhoneNumberUtil translateCursorPosition:9 from:@"(55) 123-4567" to:@"(551) 234-567" stickingRightward:false]);

    XCTAssertEqual(0,
        [PhoneNumberUtil translateCursorPosition:0 from:@"(5551) 234-567" to:@"(555) 123-4567" stickingRightward:true]);
    XCTAssertEqual(1,
        [PhoneNumberUtil translateCursorPosition:1 from:@"(5551) 234-567" to:@"(555) 123-4567" stickingRightward:true]);
    XCTAssertEqual(2,
        [PhoneNumberUtil translateCursorPosition:2 from:@"(5551) 234-567" to:@"(555) 123-4567" stickingRightward:true]);
    XCTAssertEqual(3,
        [PhoneNumberUtil translateCursorPosition:3 from:@"(5551) 234-567" to:@"(555) 123-4567" stickingRightward:true]);
    XCTAssertEqual(6,
        [PhoneNumberUtil translateCursorPosition:4 from:@"(5551) 234-567" to:@"(555) 123-4567" stickingRightward:true]);
    XCTAssertEqual(7,
        [PhoneNumberUtil translateCursorPosition:5 from:@"(5551) 234-567" to:@"(555) 123-4567" stickingRightward:true]);

    XCTAssertEqual(0,
        [PhoneNumberUtil translateCursorPosition:0
                                            from:@"(5551) 234-567"
                                              to:@"(555) 123-4567"
                               stickingRightward:false]);
    XCTAssertEqual(1,
        [PhoneNumberUtil translateCursorPosition:1
                                            from:@"(5551) 234-567"
                                              to:@"(555) 123-4567"
                               stickingRightward:false]);
    XCTAssertEqual(2,
        [PhoneNumberUtil translateCursorPosition:2
                                            from:@"(5551) 234-567"
                                              to:@"(555) 123-4567"
                               stickingRightward:false]);
    XCTAssertEqual(3,
        [PhoneNumberUtil translateCursorPosition:3
                                            from:@"(5551) 234-567"
                                              to:@"(555) 123-4567"
                               stickingRightward:false]);
    XCTAssertEqual(4,
        [PhoneNumberUtil translateCursorPosition:4
                                            from:@"(5551) 234-567"
                                              to:@"(555) 123-4567"
                               stickingRightward:false]);
    XCTAssertEqual(7,
        [PhoneNumberUtil translateCursorPosition:5
                                            from:@"(5551) 234-567"
                                              to:@"(555) 123-4567"
                               stickingRightward:false]);
}

- (void)testCountryNameFromCountryCode
{
    XCTAssertEqualObjects([PhoneNumberUtil countryNameFromCountryCode:@"US"], @"United States");
    XCTAssertEqualObjects([PhoneNumberUtil countryNameFromCountryCode:@"GB"], @"United Kingdom");
    XCTAssertEqualObjects([PhoneNumberUtil countryNameFromCountryCode:@"EK"], @"Unknown");
    XCTAssertEqualObjects([PhoneNumberUtil countryNameFromCountryCode:@"ZZZ"], @"Unknown");
    XCTAssertNotEqualObjects([PhoneNumberUtil countryNameFromCountryCode:@""], @"");
}

@end
