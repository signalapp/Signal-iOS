//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "UtilTest.h"
#import "TestUtil.h"
#import <SignalMessaging/NSString+OWS.h>
#import <SignalServiceKit/NSDate+OWS.h>
#import <SignalServiceKit/NSObject+OWS.h>
#import <SignalServiceKit/NSString+SSK.h>

@interface NSString (OWS_Test)

- (NSString *)removeAllCharactersIn:(NSCharacterSet *)characterSet;

- (NSString *)filterUnsafeFilenameCharacters;

@end

#pragma mark -

@implementation UtilTest

-(void) testRemoveAllCharactersIn {
    testThrows([@"" removeAllCharactersIn:nil]);

    test([[@"" removeAllCharactersIn:NSCharacterSet.letterCharacterSet] isEqual:@""]);
    test([[@"1" removeAllCharactersIn:NSCharacterSet.letterCharacterSet] isEqual:@"1"]);
    test([[@"a" removeAllCharactersIn:NSCharacterSet.letterCharacterSet] isEqual:@""]);
    test([[@"A" removeAllCharactersIn:NSCharacterSet.letterCharacterSet] isEqual:@""]);
    test([[@"abc123%^&" removeAllCharactersIn:NSCharacterSet.letterCharacterSet] isEqual:@"123%^&"]);

    test([[@"" removeAllCharactersIn:NSCharacterSet.decimalDigitCharacterSet] isEqual:@""]);
    test([[@"1" removeAllCharactersIn:NSCharacterSet.decimalDigitCharacterSet] isEqual:@""]);
    test([[@"a" removeAllCharactersIn:NSCharacterSet.decimalDigitCharacterSet] isEqual:@"a"]);
    test([[@"A" removeAllCharactersIn:NSCharacterSet.decimalDigitCharacterSet] isEqual:@"A"]);
    test([[@"abc123%^&" removeAllCharactersIn:NSCharacterSet.decimalDigitCharacterSet] isEqual:@"abc%^&"]);
}

-(void) testDigitsOnly {
    test([@"".digitsOnly isEqual:@""]);
    test([@"1".digitsOnly isEqual:@"1"]);
    test([@"a".digitsOnly isEqual:@""]);
    test([@"(555) 235-7111".digitsOnly isEqual:@"5552357111"]);
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

- (void)testDateComparison
{
    NSDate *firstDate = [NSDate new];

    NSDate *sameDate = [NSDate dateWithTimeIntervalSinceReferenceDate:firstDate.timeIntervalSinceReferenceDate];
    NSDate *laterDate = [NSDate dateWithTimeIntervalSinceReferenceDate:firstDate.timeIntervalSinceReferenceDate + 1.f];

    XCTAssertEqual(firstDate.timeIntervalSinceReferenceDate, sameDate.timeIntervalSinceReferenceDate);
    XCTAssertNotEqual(firstDate.timeIntervalSinceReferenceDate, laterDate.timeIntervalSinceReferenceDate);
    XCTAssertEqualObjects(firstDate, sameDate);
    XCTAssertNotEqualObjects(firstDate, laterDate);
    XCTAssertTrue(firstDate.timeIntervalSinceReferenceDate < laterDate.timeIntervalSinceReferenceDate);
    XCTAssertFalse([firstDate isBeforeDate:sameDate]);
    XCTAssertTrue([firstDate isBeforeDate:laterDate]);
    XCTAssertFalse([laterDate isBeforeDate:firstDate]);
    XCTAssertFalse([firstDate isAfterDate:sameDate]);
    XCTAssertFalse([firstDate isAfterDate:laterDate]);
    XCTAssertTrue([laterDate isAfterDate:firstDate]);
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
