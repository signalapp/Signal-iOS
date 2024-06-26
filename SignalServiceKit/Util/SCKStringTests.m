//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "NSString+OWS.h"
#import <CocoaLumberjack/CocoaLumberjack.h>
#import <XCTest/XCTest.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - private interface in NSString+OWS.h

@interface NSString (OWS_Test)
- (NSString *)removeAllCharactersIn:(NSCharacterSet *)characterSet;
- (NSString *)filterUnsafeFilenameCharacters;
@end

#pragma mark -

@interface SCKStringTests : XCTestCase

@end

#pragma mark -

@implementation SCKStringTests

- (void)setUp
{
    [super setUp];

    [DDLog addLogger:DDTTYLogger.sharedInstance];
}

- (void)testBalancedBidiControlCharacters
{
    static unichar bidiLeftToRightIsolate = 0x2066;
    static unichar bidiRightToLeftIsolate = 0x2067;
    static unichar bidiFirstStrongIsolate = 0x2068;
    static unichar bidiLeftToRightEmbedding = 0x202A;
    static unichar bidiRightToLeftEmbedding = 0x202B;
    static unichar bidiLeftToRightOverride = 0x202D;
    static unichar bidiRightToLeftOverride = 0x202E;
    static unichar bidiPopDirectionalFormatting = 0x202C;
    static unichar bidiPopDirectionalIsolate = 0x2069;

    XCTAssertEqualObjects(@"A", [@"A" ensureBalancedBidiControlCharacters]);

    unichar character1 = 'D';
    unichar character2 = 'E';
    XCTAssertEqualObjects([@"ABC" stringByPrependingCharacter:character1], @"DABC");
    XCTAssertEqualObjects([@"ABC" stringByAppendingCharacter:character1], @"ABCD");

    // If we have too many isolate starts, append PDI to balance
    NSString *string1 = [@"ABC" stringByAppendingCharacter:bidiLeftToRightIsolate];
    XCTAssertEqualObjects(
        [string1 ensureBalancedBidiControlCharacters], [string1 stringByAppendingCharacter:bidiPopDirectionalIsolate]);
    // Control characters interspersed with printing characters.
    NSString *string2 = [[[@"ABC" stringByAppendingCharacter:bidiLeftToRightIsolate]
        stringByAppendingCharacter:character2] stringByAppendingCharacter:bidiLeftToRightIsolate];
    XCTAssertEqualObjects([string2 ensureBalancedBidiControlCharacters],
        [[string2 stringByAppendingCharacter:bidiPopDirectionalIsolate]
            stringByAppendingCharacter:bidiPopDirectionalIsolate]);
    // Various kinds of isolate starts.
    NSString *string3 =
        [[[[[@"ABC" stringByAppendingCharacter:bidiLeftToRightIsolate] stringByAppendingCharacter:character2]
            stringByAppendingCharacter:bidiRightToLeftIsolate] stringByAppendingCharacter:character2]
            stringByAppendingCharacter:bidiFirstStrongIsolate];
    XCTAssertEqualObjects([string3 ensureBalancedBidiControlCharacters],
        [[[string3 stringByAppendingCharacter:bidiPopDirectionalIsolate]
            stringByAppendingCharacter:bidiPopDirectionalIsolate]
            stringByAppendingCharacter:bidiPopDirectionalIsolate]);

    // If we have too many isolate pops, prepend FSI to balance
    // Various kinds of isolate starts.
    NSString *string4 =
        [[[[[@"ABC" stringByAppendingCharacter:bidiPopDirectionalIsolate] stringByAppendingCharacter:character2]
            stringByAppendingCharacter:bidiPopDirectionalIsolate] stringByAppendingCharacter:character2]
            stringByAppendingCharacter:bidiPopDirectionalIsolate];
    XCTAssertEqualObjects([string4 ensureBalancedBidiControlCharacters],
        [[[string4 stringByPrependingCharacter:bidiFirstStrongIsolate]
            stringByPrependingCharacter:bidiFirstStrongIsolate] stringByPrependingCharacter:bidiFirstStrongIsolate]);

    // If we have too many formatting starts, append PDF to balance
    NSString *string5 =
        [[[[[[[@"ABC" stringByAppendingCharacter:bidiLeftToRightEmbedding] stringByAppendingCharacter:character2]
            stringByAppendingCharacter:bidiRightToLeftEmbedding] stringByAppendingCharacter:character2]
            stringByAppendingCharacter:bidiLeftToRightOverride] stringByAppendingCharacter:character2]
            stringByAppendingCharacter:bidiRightToLeftOverride];
    XCTAssertEqualObjects([string5 ensureBalancedBidiControlCharacters],
        [[[[string5 stringByAppendingCharacter:bidiPopDirectionalFormatting]
            stringByAppendingCharacter:bidiPopDirectionalFormatting]
            stringByAppendingCharacter:bidiPopDirectionalFormatting]
            stringByAppendingCharacter:bidiPopDirectionalFormatting]);

    // If we have too many formatting pops, prepend LRE to balance
    NSString *string6 =
        [[[[[[[@"ABC" stringByAppendingCharacter:bidiPopDirectionalFormatting] stringByAppendingCharacter:character2]
            stringByAppendingCharacter:bidiPopDirectionalFormatting] stringByAppendingCharacter:character2]
            stringByAppendingCharacter:bidiPopDirectionalFormatting] stringByAppendingCharacter:character2]
            stringByAppendingCharacter:bidiPopDirectionalFormatting];
    XCTAssertEqualObjects([string6 ensureBalancedBidiControlCharacters],
        [[[[string6 stringByPrependingCharacter:bidiLeftToRightEmbedding]
            stringByPrependingCharacter:bidiLeftToRightEmbedding] stringByPrependingCharacter:bidiLeftToRightEmbedding]
            stringByPrependingCharacter:bidiLeftToRightEmbedding]);
}

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

- (void)testfilterUnsafeFilenameCharacters
{
    XCTAssertEqualObjects(@"1".filterUnsafeFilenameCharacters, @"1");
    XCTAssertEqualObjects(@"alice\u202Dbob".filterUnsafeFilenameCharacters, @"alice\uFFFDbob");
    XCTAssertEqualObjects(@"\u202Dalicebob".filterUnsafeFilenameCharacters, @"\uFFFDalicebob");
    XCTAssertEqualObjects(@"alicebob\u202D".filterUnsafeFilenameCharacters, @"alicebob\uFFFD");
    XCTAssertEqualObjects(@"alice\u202Ebob".filterUnsafeFilenameCharacters, @"alice\uFFFDbob");
    XCTAssertEqualObjects(@"\u202Ealicebob".filterUnsafeFilenameCharacters, @"\uFFFDalicebob");
    XCTAssertEqualObjects(@"alicebob\u202E".filterUnsafeFilenameCharacters, @"alicebob\uFFFD");
    XCTAssertEqualObjects(
        @"alice\u202Dbobalice\u202Ebob".filterUnsafeFilenameCharacters, @"alice\uFFFDbobalice\uFFFDbob");
}

@end

NS_ASSUME_NONNULL_END
