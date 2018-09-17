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

-(void) testAny {
    test(![@[] any:^(id x) { return false; }]);
    test(![@[] any:^(id x) { return true; }]);
    test(![@[@1] any:^(id x) { return false; }]);
    test([@[@1] any:^(id x) { return true; }]);
    
    test([(@[@2, @3, @5]) any:^(NSNumber* x) { return x.intValue == 3; }]);
    test(![(@[@2, @4, @5]) any:^(NSNumber* x) { return x.intValue == 3; }]);
}

-(void) testMap {
    test([[@[] map:^(id x) { return x; }] isEqualToArray:@[]]);
    test([[(@[@1,@2]) map:^(id x) { return x; }] isEqualToArray:(@[@1,@2])]);
    test([[(@[@1,@2]) map:^(NSNumber* x) { return @(x.intValue + 1); }] isEqualToArray:(@[@2,@3])]);
}

-(void) testFilter {
    test([[@[] filter:^(id x) { return true; }] isEqualToArray:@[]]);
    test([[(@[@1,@2]) filter:^(NSNumber* x) { return true; }] isEqualToArray:(@[@1,@2])]);
    test([[(@[@1,@2]) filter:^(NSNumber* x) { return false; }] isEqualToArray:(@[])]);
    test([[(@[@1,@2]) filter:^(NSNumber* x) { return x.intValue == 1; }] isEqualToArray:(@[@1])]);
    test([[(@[@1,@2]) filter:^(NSNumber* x) { return x.intValue == 2; }] isEqualToArray:(@[@2])]);
}

-(void) testKeyedBy {
	test([[@[] keyedBy:^id(id value) { return @true; }] isEqual:@{}]);
	test([[@[@1] keyedBy:^id(id value) { return @true; }] isEqual:@{@true : @1}]);
	testThrows(([(@[@1, @2]) keyedBy:^id(id value) { return @true; }]));
	test([[(@[@1, @2]) keyedBy:^id(id value) { return value; }] isEqual:(@{@1 : @1, @2 : @2})]);
	testThrows([(@[@1, @1, @2, @3, @5]) keyedBy:^id(NSNumber* value) { return @(value.intValue/2); }]);
	test([[(@[@3, @5, @7, @11, @13]) keyedBy:^id(NSNumber* value) { return @(value.intValue/2); }] isEqual:(@{@1 : @3, @2 : @5, @3 : @7, @5 : @11, @6 : @13})]);
}

-(void) testGroupBy {
	test([[@[] groupBy:^id(id value) { return @true; }] isEqual:@{}]);
	test([[@[@1] groupBy:^id(id value) { return @true; }] isEqual:@{@true : @[@1]}]);
	test([[(@[@1, @2]) groupBy:^id(id value) { return @true; }] isEqual:@{@true : (@[@1, @2])}]);
	test([[(@[@1, @2]) groupBy:^id(id value) { return value; }] isEqual:(@{@1 : @[@1], @2 : @[@2]})]);
	test([[(@[@1, @1, @2, @3, @5]) groupBy:^id(NSNumber* value) { return @(value.intValue/2); }] isEqual:(@{@0 : @[@1, @1], @1 : @[@2, @3], @2 : @[@5]})]);
}

@end
