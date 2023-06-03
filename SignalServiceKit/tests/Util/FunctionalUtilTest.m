//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "SSKBaseTestObjC.h"
#import <SignalServiceKit/FunctionalUtil.h>

@interface FunctionalUtilTest : SSKBaseTestObjC

@end

#pragma mark -

@implementation FunctionalUtilTest

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

@end
