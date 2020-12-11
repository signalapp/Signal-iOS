//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "FunctionalUtil.h"
#import "SignalBaseTest.h"
#import "TestUtil.h"

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

    test(result1 == testArray[0]);
    test(result2 == testArray[4]);
    test(result3 == testArray[1]);
    test(result4 == testArray[0]);
    test(result5 == nil);
    test(result6 == nil);
}

- (void)testAnySatisfy
{
    test(![@[] anySatisfy:^(id x) { return NO; }]);
    test(![@[] anySatisfy:^(id x) { return YES; }]);
    test(![@[ @1 ] anySatisfy:^(id x) { return NO; }]);
    test([@[ @1 ] anySatisfy:^(id x) { return YES; }]);

    test([(@[ @2, @3, @5 ]) anySatisfy:^BOOL(NSNumber *x) { return x.intValue == 3; }]);
    test(![(@[ @2, @4, @5 ]) anySatisfy:^BOOL(NSNumber *x) { return x.intValue == 3; }]);
}

- (void)testMap
{
    test([[@[] map:^(id x) { return x; }] isEqualToArray:@[]]);
    test([[(@[@1,@2]) map:^(id x) { return x; }] isEqualToArray:(@[@1,@2])]);
    test([[(@[@1,@2]) map:^(NSNumber* x) { return @(x.intValue + 1); }] isEqualToArray:(@[@2,@3])]);
}

- (void)testFilter
{
    test([[@[] filter:^(id x) { return YES; }] isEqualToArray:@[]]);
    test([[(@[ @1, @2 ]) filter:^(NSNumber *x) { return YES; }] isEqualToArray:(@[ @1, @2 ])]);
    test([[(@[ @1, @2 ]) filter:^(NSNumber *x) { return NO; }] isEqualToArray:(@[])]);
    test([[(@[ @1, @2 ]) filter:^BOOL(NSNumber *x) { return x.intValue == 1; }] isEqualToArray:(@[ @1 ])]);
    test([[(@[ @1, @2 ]) filter:^BOOL(NSNumber *x) { return x.intValue == 2; }] isEqualToArray:(@[ @2 ])]);
}

- (void)testGroupBy
{
    test([[@[] groupBy:^id(id value) { return @true; }] isEqual:@{}]);
    test([[@[ @1 ] groupBy:^id(id value) { return @true; }] isEqual:@{ @true : @[ @1 ] }]);
    test([[(@[ @1, @2 ]) groupBy:^id(id value) { return @true; }] isEqual:@{ @true : (@[ @1, @2 ]) }]);
    test([[(@[ @1, @2 ]) groupBy:^id(id value) { return value; }] isEqual:(@{ @1 : @[ @1 ], @2 : @[ @2 ] })]);
    test([[(@[ @1, @1, @2, @3, @5 ]) groupBy:^id(NSNumber *value) { return @(value.intValue / 2); }]
        isEqual:(@{ @0 : @[ @1, @1 ], @1 : @[ @2, @3 ], @2 : @[ @5 ] })]);
}

@end
