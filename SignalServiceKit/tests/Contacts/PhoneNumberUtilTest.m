//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "PhoneNumberUtil.h"
#import "SSKBaseTestObjC.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

@interface PhoneNumberUtilTest : XCTestCase
@property (nonatomic, readonly) PhoneNumberUtil *phoneNumberUtilRef;
@end

#pragma mark -

@implementation PhoneNumberUtilTest

- (void)setUp
{
    [super setUp];
    _phoneNumberUtilRef = [[PhoneNumberUtil alloc] init];
}

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
    // Invalid country code.
    if (@available(iOS 17, *)) {
        XCTAssertEqualObjects([PhoneNumberUtil countryNameFromCountryCode:@"EK"], @"Unknown");
        XCTAssertEqualObjects([PhoneNumberUtil countryNameFromCountryCode:@"ZZZ"], @"Unknown");
    } else {
        XCTAssertEqualObjects([PhoneNumberUtil countryNameFromCountryCode:@"EK"], @"EK");
        XCTAssertEqualObjects([PhoneNumberUtil countryNameFromCountryCode:@"ZZZ"], @"ZZZ");
    }
    XCTAssertNotEqualObjects([PhoneNumberUtil countryNameFromCountryCode:@""], @"");
}

- (void)testCountryCodesForSearchTerm
{
    // Empty search.
    XCTAssertGreaterThan([self.phoneNumberUtilRef countryCodesForSearchTerm:nil].count, (NSUInteger)30);
    XCTAssertGreaterThan([self.phoneNumberUtilRef countryCodesForSearchTerm:@""].count, (NSUInteger)30);
    XCTAssertGreaterThan([self.phoneNumberUtilRef countryCodesForSearchTerm:@" "].count, (NSUInteger)30);

    // Searches with no results.
    XCTAssertEqual([self.phoneNumberUtilRef countryCodesForSearchTerm:@" . "].count, (NSUInteger)0);
    XCTAssertEqual([self.phoneNumberUtilRef countryCodesForSearchTerm:@" XXXXX "].count, (NSUInteger)0);
    XCTAssertEqual([self.phoneNumberUtilRef countryCodesForSearchTerm:@" ! "].count, (NSUInteger)0);

    // Search by country code.
    XCTAssertEqualObjects([self.phoneNumberUtilRef countryCodesForSearchTerm:@"GB"], (@[ @"GB" ]));
    XCTAssertEqualObjects([self.phoneNumberUtilRef countryCodesForSearchTerm:@"gb"], (@[ @"GB" ]));
    XCTAssertEqualObjects([self.phoneNumberUtilRef countryCodesForSearchTerm:@"GB "], (@[ @"GB" ]));
    XCTAssertEqualObjects([self.phoneNumberUtilRef countryCodesForSearchTerm:@" GB"], (@[ @"GB" ]));
    XCTAssertTrue([[self.phoneNumberUtilRef countryCodesForSearchTerm:@" G"] containsObject:@"GB"]);
    XCTAssertFalse([[self.phoneNumberUtilRef countryCodesForSearchTerm:@" B"] containsObject:@"GB"]);

    // Search by country name.
    XCTAssertEqualObjects([self.phoneNumberUtilRef countryCodesForSearchTerm:@"united kingdom"], (@[ @"GB" ]));
    XCTAssertEqualObjects([self.phoneNumberUtilRef countryCodesForSearchTerm:@" UNITED KINGDOM "], (@[ @"GB" ]));
    XCTAssertEqualObjects([self.phoneNumberUtilRef countryCodesForSearchTerm:@" UNITED KING "], (@[ @"GB" ]));
    XCTAssertEqualObjects([self.phoneNumberUtilRef countryCodesForSearchTerm:@" UNI KING "], (@[ @"GB" ]));
    XCTAssertEqualObjects([self.phoneNumberUtilRef countryCodesForSearchTerm:@" u k "], (@[ @"GB" ]));
    XCTAssertTrue([[self.phoneNumberUtilRef countryCodesForSearchTerm:@" u"] containsObject:@"GB"]);
    XCTAssertTrue([[self.phoneNumberUtilRef countryCodesForSearchTerm:@" k"] containsObject:@"GB"]);
    XCTAssertFalse([[self.phoneNumberUtilRef countryCodesForSearchTerm:@" m"] containsObject:@"GB"]);

    // Search by calling code.
    XCTAssertTrue([[self.phoneNumberUtilRef countryCodesForSearchTerm:@" +44 "] containsObject:@"GB"]);
    XCTAssertTrue([[self.phoneNumberUtilRef countryCodesForSearchTerm:@" 44 "] containsObject:@"GB"]);
    XCTAssertTrue([[self.phoneNumberUtilRef countryCodesForSearchTerm:@" +4 "] containsObject:@"GB"]);
    XCTAssertTrue([[self.phoneNumberUtilRef countryCodesForSearchTerm:@" 4 "] containsObject:@"GB"]);
    XCTAssertFalse([[self.phoneNumberUtilRef countryCodesForSearchTerm:@" +123 "] containsObject:@"GB"]);
    XCTAssertFalse([[self.phoneNumberUtilRef countryCodesForSearchTerm:@" +444 "] containsObject:@"GB"]);
}

@end
