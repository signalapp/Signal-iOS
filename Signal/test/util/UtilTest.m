//
// Copyright 2014 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "UtilTest.h"
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalCoreKit/NSObject+OWS.h>
#import <SignalCoreKit/NSString+OWS.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

#pragma mark -

@interface NSString (OWS_Test)

- (NSString *)removeAllCharactersIn:(NSCharacterSet *)characterSet;

- (NSString *)filterUnsafeFilenameCharacters;

@end

#pragma mark -

@implementation UtilTest

- (void)testRemoveAllCharactersIn
{
    XCTAssert([[@"" removeAllCharactersIn:NSCharacterSet.letterCharacterSet] isEqual:@""]);
    XCTAssert([[@"1" removeAllCharactersIn:NSCharacterSet.letterCharacterSet] isEqual:@"1"]);
    XCTAssert([[@"a" removeAllCharactersIn:NSCharacterSet.letterCharacterSet] isEqual:@""]);
    XCTAssert([[@"A" removeAllCharactersIn:NSCharacterSet.letterCharacterSet] isEqual:@""]);
    XCTAssert([[@"abc123%^&" removeAllCharactersIn:NSCharacterSet.letterCharacterSet] isEqual:@"123%^&"]);

    XCTAssert([[@"" removeAllCharactersIn:NSCharacterSet.decimalDigitCharacterSet] isEqual:@""]);
    XCTAssert([[@"1" removeAllCharactersIn:NSCharacterSet.decimalDigitCharacterSet] isEqual:@""]);
    XCTAssert([[@"a" removeAllCharactersIn:NSCharacterSet.decimalDigitCharacterSet] isEqual:@"a"]);
    XCTAssert([[@"A" removeAllCharactersIn:NSCharacterSet.decimalDigitCharacterSet] isEqual:@"A"]);
    XCTAssert([[@"abc123%^&" removeAllCharactersIn:NSCharacterSet.decimalDigitCharacterSet] isEqual:@"abc%^&"]);
}

- (void)testEnsureArabicNumerals
{
    NSArray<NSString *> *zeroToNineTests = @[
        @"০১২৩৪৫৬৭৮৯", // Bengali
        @"၀၁၂၃၄၅၆၇၈၉", // Burmese
        @"〇一二三四五六七八九", // Chinese (Simplified), Japanese
        @"零一二三四五六七八九", // Chinese (Traditional)
        @"०१२३४५६७८९", // Devanagari (Sanskrit, Hindi, and other Indian languages)
        @"٠١٢٣٤٥٦٧٨٩", // Eastern Arabic
        @"૦૧૨૩૪૫૬૭૮૯", // Gujarati
        @"੦੧੨੩੪੫੬੭੮੯", // Gurmukhi (Punjabi)
        @"೦೧೨೩೪೫೬೭೮೯", // Kannada
        @"൦൧൨൩൪൫൬൭൮൯", // Malayalam
        @"୦୧୨୩୪୫୬୭୮୯", // Odia
        @"۰۱۲۳۴۵۶۷۸۹", // Persian, Urdu
        @"௦௧௨௩௪௫௬௭௮௯", // Tamil
        @"౦౧౨౩౪౫౬౭౮౯", // Telugu
        @"๐๑๒๓๔๕๖๗๘๙", // Thai
        @"0123456789", // Western arabic
    ];

    for (NSString *zeroToNineTest in zeroToNineTests) {
        XCTAssert([zeroToNineTest.ensureArabicNumerals isEqualToString:@"0123456789"]);
    }

    // In mixed strings, only replaces the numerals.
    XCTAssert([@"نمرا ١٢٣٤٥ يا".ensureArabicNumerals isEqualToString:@"نمرا 12345 يا"]);

    // Appropriately handles characters that extend across multiple unicode scalars
    XCTAssert([@"123 👩🏻‍🔬🧛🏿‍♀️🤦🏽‍♀️🏳️‍🌈 ١٢٣".ensureArabicNumerals
        isEqualToString:@"123 👩🏻‍🔬🧛🏿‍♀️🤦🏽‍♀️🏳️‍🌈 123"]);

    // In strings without numerals, does nothing.
    XCTAssert([@"a".ensureArabicNumerals isEqualToString:@"a"]);
    XCTAssert([@"".ensureArabicNumerals isEqualToString:@""]);
}

- (void)testfilterUnsafeFilenameCharacters
{
    XCTAssertEqualObjects(@"1".filterUnsafeFilenameCharacters, @"1");
    XCTAssertEqualObjects(@"alice\u202Dbob".filterUnsafeFilenameCharacters, @"alice\uFFFDbob");
    XCTAssertEqualObjects(@"\u202Dalicebob".filterUnsafeFilenameCharacters, @"\uFFFDalicebob");
    XCTAssertEqualObjects(@"alicebob\u202D".filterUnsafeFilenameCharacters, @"alicebob\uFFFD");
    XCTAssertEqualObjects(@"alice\u202Ebob".filterUnsafeFilenameCharacters, @"alice\uFFFDbob");
    XCTAssertEqualObjects(@"\u202Ealicebob".filterUnsafeFilenameCharacters, @"\uFFFDalicebob");
    XCTAssertEqualObjects(@"alicebob\u202E".filterUnsafeFilenameCharacters, @"alicebob\uFFFD");
    XCTAssertEqualObjects(@"alice\u202Dbobalice\u202Ebob".filterUnsafeFilenameCharacters, @"alice\uFFFDbobalice\uFFFDbob");
}

- (void)testObjectComparison
{
    XCTAssertTrue([NSObject isNullableObject:nil equalTo:nil]);
    XCTAssertFalse([NSObject isNullableObject:@(YES) equalTo:nil]);
    XCTAssertFalse([NSObject isNullableObject:nil equalTo:@(YES)]);
    XCTAssertFalse([NSObject isNullableObject:@(YES) equalTo:@(NO)]);
    XCTAssertTrue([NSObject isNullableObject:@(YES) equalTo:@(YES)]);
}

@end
