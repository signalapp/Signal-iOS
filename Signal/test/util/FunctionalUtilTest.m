//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

#import "SignalBaseTest.h"
#import <SignalServiceKit/FunctionalUtil.h>

@interface FunctionalUtilTest : SignalBaseTest

@end

#pragma mark -

@implementation FunctionalUtilTest

- (void)testFirstMatch
{
    NSArray<NSString *> *testArray = @[ @"Hello", @"my", @"name", @"is", @"Michelle" ];
    NSString *result1 = [testArray firstSatisfying:^BOOL(NSString *item) { return YES; }];
    NSString *result2 = [testArray firstSatisfying:^BOOL(NSString *item) { return item.length > 5; }];
    NSString *result3 = [testArray firstSatisfying:^BOOL(NSString *item) { return item.length <= 2; }];
    NSString *result4 = [testArray firstSatisfying:^BOOL(NSString *item) { return [item isEqualToString:@"Hello"]; }];
    NSString *result5 = [testArray firstSatisfying:^BOOL(NSString *item) { return [item isEqualToString:@"Goodbye"]; }];
    NSString *result6 = [@[] firstSatisfying:^BOOL(id item) { return YES; }];

    XCTAssert(result1 == testArray[0]);
    XCTAssert(result2 == testArray[4]);
    XCTAssert(result3 == testArray[1]);
    XCTAssert(result4 == testArray[0]);
    XCTAssert(result5 == nil);
    XCTAssert(result6 == nil);
}

- (void)testAnySatisfy
{
    XCTAssert(![@[] anySatisfy:^(id x) { return NO; }]);
    XCTAssert(![@[] anySatisfy:^(id x) { return YES; }]);
    XCTAssert(![@[ @1 ] anySatisfy:^(id x) { return NO; }]);
    XCTAssert([@[ @1 ] anySatisfy:^(id x) { return YES; }]);

    XCTAssert([(@[ @2, @3, @5 ]) anySatisfy:^BOOL(NSNumber *x) { return x.intValue == 3; }]);
    XCTAssert(![(@[ @2, @4, @5 ]) anySatisfy:^BOOL(NSNumber *x) { return x.intValue == 3; }]);
}

- (void)testMap
{
    XCTAssert([[@[] map:^(id x) { return x; }] isEqualToArray:@[]]);
    XCTAssert([[(@[ @1, @2 ]) map:^(id x) { return x; }] isEqualToArray:(@[ @1, @2 ])]);
    XCTAssert([[(@[ @1, @2 ]) map:^(NSNumber *x) { return @(x.intValue + 1); }] isEqualToArray:(@[ @2, @3 ])]);
}

- (void)testFilter
{
    XCTAssert([[@[] filter:^(id x) { return YES; }] isEqualToArray:@[]]);
    XCTAssert([[(@[ @1, @2 ]) filter:^(NSNumber *x) { return YES; }] isEqualToArray:(@[ @1, @2 ])]);
    XCTAssert([[(@[ @1, @2 ]) filter:^(NSNumber *x) { return NO; }] isEqualToArray:(@[])]);
    XCTAssert([[(@[ @1, @2 ]) filter:^BOOL(NSNumber *x) { return x.intValue == 1; }] isEqualToArray:(@[ @1 ])]);
    XCTAssert([[(@[ @1, @2 ]) filter:^BOOL(NSNumber *x) { return x.intValue == 2; }] isEqualToArray:(@[ @2 ])]);
}

- (void)testGroupBy
{
    XCTAssert([[@[] groupBy:^id(id value) { return @true; }] isEqual:@{}]);
    XCTAssert([[@[ @1 ] groupBy:^id(id value) { return @true; }] isEqual:@{ @true : @[ @1 ] }]);
    XCTAssert([[(@[ @1, @2 ]) groupBy:^id(id value) { return @true; }] isEqual:@{ @true : (@[ @1, @2 ]) }]);
    XCTAssert([[(@[ @1, @2 ]) groupBy:^id(id value) { return value; }] isEqual:(@{ @1 : @[ @1 ], @2 : @[ @2 ] })]);
    XCTAssert([[(@[ @1, @1, @2, @3, @5 ]) groupBy:^id(NSNumber *value) { return @(value.intValue / 2); }]
        isEqual:(@{ @0 : @[ @1, @1 ], @1 : @[ @2, @3 ], @2 : @[ @5 ] })]);
}

@end
