//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSContactsManager.h"
#import "PhoneNumber.h"
#import "PhoneNumberUtil.h"
#import "TestUtil.h"
#import "TextSecureKitEnv.h"
#import <XCTest/XCTest.h>

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
//+ (NSString *)callingCodeFromCountryCode:(NSString *)code;
//+ (NSString *)countryNameFromCountryCode:(NSString *)code;
//+ (NSArray *)countryCodesForSearchTerm:(NSString *)searchTerm;

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
    testThrows([PhoneNumberUtil countryNameFromCountryCode:nil]);
}

- (void)testCountryCodesForSearchTerm
{
// PhoneNumberUtil needs a valid OWSContactsManager in the TextSecureKitEnv,
// but we want to avoid constructing the entire app apparatus so we pass nil
// for the other parameters of the environemtn and disable nonnull warnings.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
    TextSecureKitEnv *sharedEnv = [[TextSecureKitEnv alloc] initWithCallMessageHandler:nil
                                                                       contactsManager:[OWSContactsManager new]
                                                                  notificationsManager:nil];
#pragma clang diagnostic pop
    [TextSecureKitEnv setSharedEnv:sharedEnv];

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
