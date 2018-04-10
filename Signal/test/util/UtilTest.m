//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "UtilTest.h"
#import "DateUtil.h"
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

- (void)testDateComparators
{
    NSDate *now = [NSDate new];

    NSDate *oneSecondAgo =
        [NSDate dateWithTimeIntervalSinceReferenceDate:[now timeIntervalSinceReferenceDate] - kSecondInterval];
    NSDate *oneMinuteAgo =
        [NSDate dateWithTimeIntervalSinceReferenceDate:[now timeIntervalSinceReferenceDate] - kMinuteInterval];
    NSDate *oneDayAgo =
        [NSDate dateWithTimeIntervalSinceReferenceDate:[now timeIntervalSinceReferenceDate] - kDayInterval];
    NSDate *threeDaysAgo =
        [NSDate dateWithTimeIntervalSinceReferenceDate:[now timeIntervalSinceReferenceDate] - kDayInterval * 3];
    NSDate *tenDaysAgo =
        [NSDate dateWithTimeIntervalSinceReferenceDate:[now timeIntervalSinceReferenceDate] - kDayInterval * 10];
    NSDate *oneYearAgo =
        [NSDate dateWithTimeIntervalSinceReferenceDate:[now timeIntervalSinceReferenceDate] - kYearInterval];
    NSDate *twoYearsAgo =
        [NSDate dateWithTimeIntervalSinceReferenceDate:[now timeIntervalSinceReferenceDate] - kYearInterval * 2];

    NSDate *oneSecondAhead =
        [NSDate dateWithTimeIntervalSinceReferenceDate:[now timeIntervalSinceReferenceDate] + kSecondInterval];
    NSDate *oneMinuteAhead =
        [NSDate dateWithTimeIntervalSinceReferenceDate:[now timeIntervalSinceReferenceDate] + kMinuteInterval];
    NSDate *oneDayAhead =
        [NSDate dateWithTimeIntervalSinceReferenceDate:[now timeIntervalSinceReferenceDate] + kDayInterval];
    NSDate *threeDaysAhead =
        [NSDate dateWithTimeIntervalSinceReferenceDate:[now timeIntervalSinceReferenceDate] + kDayInterval * 3];
    NSDate *tenDaysAhead =
        [NSDate dateWithTimeIntervalSinceReferenceDate:[now timeIntervalSinceReferenceDate] + kDayInterval * 10];
    NSDate *oneYearAhead =
        [NSDate dateWithTimeIntervalSinceReferenceDate:[now timeIntervalSinceReferenceDate] + kYearInterval];
    NSDate *twoYearsAhead =
        [NSDate dateWithTimeIntervalSinceReferenceDate:[now timeIntervalSinceReferenceDate] + kYearInterval * 2];

    // These might fail around midnight.
    XCTAssertTrue([DateUtil dateIsToday:oneSecondAgo]);
    XCTAssertTrue([DateUtil dateIsToday:oneMinuteAgo]);
    XCTAssertFalse([DateUtil dateIsToday:oneDayAgo]);
    XCTAssertFalse([DateUtil dateIsToday:threeDaysAgo]);
    XCTAssertFalse([DateUtil dateIsToday:tenDaysAgo]);
    XCTAssertFalse([DateUtil dateIsToday:oneYearAgo]);
    XCTAssertFalse([DateUtil dateIsToday:twoYearsAgo]);

    // These might fail around midnight.
    XCTAssertTrue([DateUtil dateIsToday:oneSecondAhead]);
    XCTAssertTrue([DateUtil dateIsToday:oneMinuteAhead]);
    XCTAssertFalse([DateUtil dateIsToday:oneDayAhead]);
    XCTAssertFalse([DateUtil dateIsToday:threeDaysAhead]);
    XCTAssertFalse([DateUtil dateIsToday:tenDaysAhead]);
    XCTAssertFalse([DateUtil dateIsToday:oneYearAhead]);
    XCTAssertFalse([DateUtil dateIsToday:twoYearsAhead]);

    // These might fail around midnight.
    XCTAssertFalse([DateUtil dateIsOlderThanOneDay:oneSecondAgo]);
    XCTAssertFalse([DateUtil dateIsOlderThanOneDay:oneMinuteAgo]);
    XCTAssertTrue([DateUtil dateIsOlderThanOneDay:oneDayAgo]);
    XCTAssertTrue([DateUtil dateIsOlderThanOneDay:threeDaysAgo]);
    XCTAssertTrue([DateUtil dateIsOlderThanOneDay:tenDaysAgo]);
    XCTAssertTrue([DateUtil dateIsOlderThanOneDay:oneYearAgo]);
    XCTAssertTrue([DateUtil dateIsOlderThanOneDay:twoYearsAgo]);

    // These might fail around midnight.
    XCTAssertFalse([DateUtil dateIsOlderThanOneDay:oneSecondAhead]);
    XCTAssertFalse([DateUtil dateIsOlderThanOneDay:oneMinuteAhead]);
    XCTAssertFalse([DateUtil dateIsOlderThanOneDay:oneDayAhead]);
    XCTAssertFalse([DateUtil dateIsOlderThanOneDay:threeDaysAhead]);
    XCTAssertFalse([DateUtil dateIsOlderThanOneDay:tenDaysAhead]);
    XCTAssertFalse([DateUtil dateIsOlderThanOneDay:oneYearAhead]);
    XCTAssertFalse([DateUtil dateIsOlderThanOneDay:twoYearsAhead]);

    // These might fail around midnight.
    XCTAssertFalse([DateUtil dateIsOlderThanOneWeek:oneSecondAgo]);
    XCTAssertFalse([DateUtil dateIsOlderThanOneWeek:oneMinuteAgo]);
    XCTAssertFalse([DateUtil dateIsOlderThanOneWeek:oneDayAgo]);
    XCTAssertFalse([DateUtil dateIsOlderThanOneWeek:threeDaysAgo]);
    XCTAssertTrue([DateUtil dateIsOlderThanOneWeek:tenDaysAgo]);
    XCTAssertTrue([DateUtil dateIsOlderThanOneWeek:oneYearAgo]);
    XCTAssertTrue([DateUtil dateIsOlderThanOneWeek:twoYearsAgo]);

    // These might fail around midnight.
    XCTAssertFalse([DateUtil dateIsOlderThanOneWeek:oneSecondAhead]);
    XCTAssertFalse([DateUtil dateIsOlderThanOneWeek:oneMinuteAhead]);
    XCTAssertFalse([DateUtil dateIsOlderThanOneWeek:oneDayAhead]);
    XCTAssertFalse([DateUtil dateIsOlderThanOneWeek:threeDaysAhead]);
    XCTAssertFalse([DateUtil dateIsOlderThanOneWeek:tenDaysAhead]);
    XCTAssertFalse([DateUtil dateIsOlderThanOneWeek:oneYearAhead]);
    XCTAssertFalse([DateUtil dateIsOlderThanOneWeek:twoYearsAhead]);

    // These might fail around new year's.
    XCTAssertTrue([DateUtil dateIsThisYear:oneSecondAgo]);
    XCTAssertTrue([DateUtil dateIsThisYear:oneMinuteAgo]);
    XCTAssertTrue([DateUtil dateIsThisYear:oneDayAgo]);
    XCTAssertFalse([DateUtil dateIsThisYear:oneYearAgo]);
    XCTAssertFalse([DateUtil dateIsThisYear:twoYearsAgo]);

    // These might fail around new year's.
    XCTAssertTrue([DateUtil dateIsThisYear:oneSecondAhead]);
    XCTAssertTrue([DateUtil dateIsThisYear:oneMinuteAhead]);
    XCTAssertTrue([DateUtil dateIsThisYear:oneDayAhead]);
    XCTAssertFalse([DateUtil dateIsThisYear:oneYearAhead]);
    XCTAssertFalse([DateUtil dateIsThisYear:twoYearsAhead]);
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
