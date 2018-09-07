//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "PhoneNumberUtil.h"
#import "SSKBaseTest.h"

@interface PhoneNumberUtilTest : SSKBaseTest

@end

@implementation PhoneNumberUtilTest

- (void)testQueryMatching
{
    XCTAssertTrue([PhoneNumberUtil name:@"dave" matchesQuery:@"dave"]);
    XCTAssertTrue([PhoneNumberUtil name:@"big dave" matchesQuery:@"big dave"]);
    XCTAssertTrue([PhoneNumberUtil name:@"big dave" matchesQuery:@"big dave dave"]);
    XCTAssertTrue([PhoneNumberUtil name:@"big big dave" matchesQuery:@"big dave"]);
    XCTAssertTrue([PhoneNumberUtil name:@"big dave" matchesQuery:@"dave big"]);
    XCTAssertTrue([PhoneNumberUtil name:@"big dave" matchesQuery:@"dave"]);
    XCTAssertTrue([PhoneNumberUtil name:@"big dave" matchesQuery:@"big"]);
    XCTAssertTrue([PhoneNumberUtil name:@"big dave" matchesQuery:@"big "]);
    XCTAssertTrue([PhoneNumberUtil name:@"big dave" matchesQuery:@"      big       "]);
    XCTAssertTrue([PhoneNumberUtil name:@"big dave" matchesQuery:@"dav"]);
    XCTAssertTrue([PhoneNumberUtil name:@"big dave" matchesQuery:@"bi dav"]);
    XCTAssertTrue([PhoneNumberUtil name:@"big dave"
                           matchesQuery:@"big big big big big big big big big big dave dave dave dave dave"]);

    XCTAssertFalse([PhoneNumberUtil name:@"big dave" matchesQuery:@"ave"]);
    XCTAssertFalse([PhoneNumberUtil name:@"big dave" matchesQuery:@"dare"]);
    XCTAssertFalse([PhoneNumberUtil name:@"big dave" matchesQuery:@"mike"]);
    XCTAssertFalse([PhoneNumberUtil name:@"dave" matchesQuery:@"big"]);
}

- (void)testTranslateCursorPosition
{
    XCTAssertThrows([PhoneNumberUtil translateCursorPosition:0 from:nil to:@"" stickingRightward:true]);
    XCTAssertThrows([PhoneNumberUtil translateCursorPosition:0 from:@"" to:nil stickingRightward:true]);
    XCTAssertThrows([PhoneNumberUtil translateCursorPosition:1 from:@"" to:@"" stickingRightward:true]);

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

- (void)testCallingCodeFromCountryCode
{
    XCTAssertEqualObjects([PhoneNumberUtil callingCodeFromCountryCode:@"US"], @"+1");
    XCTAssertEqualObjects([PhoneNumberUtil callingCodeFromCountryCode:@"GB"], @"+44");
    // Invalid country code.
    XCTAssertEqualObjects([PhoneNumberUtil callingCodeFromCountryCode:@"EK"], @"+0");
    XCTAssertEqualObjects([PhoneNumberUtil callingCodeFromCountryCode:@"ZZZ"], @"+0");
    XCTAssertEqualObjects([PhoneNumberUtil callingCodeFromCountryCode:nil], @"+0");
}

- (void)testCountryNameFromCountryCode
{
    XCTAssertEqualObjects([PhoneNumberUtil countryNameFromCountryCode:@"US"], @"United States");
    XCTAssertEqualObjects([PhoneNumberUtil countryNameFromCountryCode:@"GB"], @"United Kingdom");
    // Invalid country code.
    XCTAssertEqualObjects([PhoneNumberUtil countryNameFromCountryCode:@"EK"], @"EK");
    XCTAssertEqualObjects([PhoneNumberUtil countryNameFromCountryCode:@"ZZZ"], @"ZZZ");
    XCTAssertThrows([PhoneNumberUtil countryNameFromCountryCode:nil]);
}

- (void)testCountryCodesForSearchTerm
{
    // Empty search.
    XCTAssertGreaterThan([PhoneNumberUtil countryCodesForSearchTerm:nil].count, (NSUInteger)30);
    XCTAssertGreaterThan([PhoneNumberUtil countryCodesForSearchTerm:@""].count, (NSUInteger)30);
    XCTAssertGreaterThan([PhoneNumberUtil countryCodesForSearchTerm:@" "].count, (NSUInteger)30);

    // Searches with no results.
    XCTAssertEqual([PhoneNumberUtil countryCodesForSearchTerm:@" . "].count, (NSUInteger)0);
    XCTAssertEqual([PhoneNumberUtil countryCodesForSearchTerm:@" XXXXX "].count, (NSUInteger)0);
    XCTAssertEqual([PhoneNumberUtil countryCodesForSearchTerm:@" ! "].count, (NSUInteger)0);

    // Search by country code.
    XCTAssertEqualObjects([PhoneNumberUtil countryCodesForSearchTerm:@"GB"], (@[ @"GB" ]));
    XCTAssertEqualObjects([PhoneNumberUtil countryCodesForSearchTerm:@"gb"], (@[ @"GB" ]));
    XCTAssertEqualObjects([PhoneNumberUtil countryCodesForSearchTerm:@"GB "], (@[ @"GB" ]));
    XCTAssertEqualObjects([PhoneNumberUtil countryCodesForSearchTerm:@" GB"], (@[ @"GB" ]));
    XCTAssertTrue([[PhoneNumberUtil countryCodesForSearchTerm:@" G"] containsObject:@"GB"]);
    XCTAssertFalse([[PhoneNumberUtil countryCodesForSearchTerm:@" B"] containsObject:@"GB"]);

    // Search by country name.
    XCTAssertEqualObjects([PhoneNumberUtil countryCodesForSearchTerm:@"united kingdom"], (@[ @"GB" ]));
    XCTAssertEqualObjects([PhoneNumberUtil countryCodesForSearchTerm:@" UNITED KINGDOM "], (@[ @"GB" ]));
    XCTAssertEqualObjects([PhoneNumberUtil countryCodesForSearchTerm:@" UNITED KING "], (@[ @"GB" ]));
    XCTAssertEqualObjects([PhoneNumberUtil countryCodesForSearchTerm:@" UNI KING "], (@[ @"GB" ]));
    XCTAssertEqualObjects([PhoneNumberUtil countryCodesForSearchTerm:@" u k "], (@[ @"GB" ]));
    XCTAssertTrue([[PhoneNumberUtil countryCodesForSearchTerm:@" u"] containsObject:@"GB"]);
    XCTAssertTrue([[PhoneNumberUtil countryCodesForSearchTerm:@" k"] containsObject:@"GB"]);
    XCTAssertFalse([[PhoneNumberUtil countryCodesForSearchTerm:@" m"] containsObject:@"GB"]);

    // Search by calling code.
    XCTAssertTrue([[PhoneNumberUtil countryCodesForSearchTerm:@" +44 "] containsObject:@"GB"]);
    XCTAssertTrue([[PhoneNumberUtil countryCodesForSearchTerm:@" 44 "] containsObject:@"GB"]);
    XCTAssertTrue([[PhoneNumberUtil countryCodesForSearchTerm:@" +4 "] containsObject:@"GB"]);
    XCTAssertTrue([[PhoneNumberUtil countryCodesForSearchTerm:@" 4 "] containsObject:@"GB"]);
    XCTAssertFalse([[PhoneNumberUtil countryCodesForSearchTerm:@" +123 "] containsObject:@"GB"]);
    XCTAssertFalse([[PhoneNumberUtil countryCodesForSearchTerm:@" +444 "] containsObject:@"GB"]);
}

@end
