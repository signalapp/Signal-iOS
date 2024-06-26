//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/Threading.h>
#import <XCTest/XCTest.h>

NS_ASSUME_NONNULL_BEGIN

@interface AnyPromiseTests : XCTestCase

@end

#pragma mark -

@implementation AnyPromiseTests

- (void)test_simplePromiseChain
{
    XCTestExpectation *expectation = [self expectationWithDescription:@"done"];

    AnyPromise.withFuture(^(AnyFuture *future) { [future resolveWithValue:@1]; })
        .map(^(id value) {
            NSNumber *number = (NSNumber *)value;
            return @(number.integerValue + 2);
        })
        .done(^(id value) {
            NSNumber *number = (NSNumber *)value;
            XCTAssertEqual(number.integerValue, 3);
            [expectation fulfill];
        })
        .catch(^(NSError *error) { XCTAssert(YES, @"Catch should not be called"); });

    [self waitForExpectationsWithTimeout:5 handler:nil];
}

- (void)test_simpleQueueChaining
{
    XCTestExpectation *expectation = [self expectationWithDescription:@"Expect on global queue"];
    XCTestExpectation *mapExpectation = [self expectationWithDescription:@"Expect on global queue"];
    XCTestExpectation *doneExpectation = [self expectationWithDescription:@"Expect on main queue"];

    dispatch_queue_t globalQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    AnyPromise
        .withFutureOn(globalQueue,
            ^(AnyFuture *future) {
                XCTAssertTrue(DispatchQueueIsCurrentQueue(globalQueue));
                [expectation fulfill];
                [future resolveWithValue:@"abc"];
            })
        .mapOn(globalQueue,
            ^(id value) {
                XCTAssertTrue(DispatchQueueIsCurrentQueue(globalQueue));
                [mapExpectation fulfill];
                NSString *string = (NSString *)value;
                return [string stringByAppendingString:@"xyz"];
            })
        .done(^(id value) {
            XCTAssertTrue(DispatchQueueIsCurrentQueue(dispatch_get_main_queue()));
            NSString *string = (NSString *)value;
            XCTAssert([string isEqualToString:@"abcxyz"]);
            [doneExpectation fulfill];
        });

    [self waitForExpectationsWithTimeout:5 handler:nil];
}

- (void)test_mixedQueueChaining
{
    XCTestExpectation *expectation = [self expectationWithDescription:@"Expect on global queue"];
    XCTestExpectation *mapExpectation = [self expectationWithDescription:@"Expect on main queue"];
    XCTestExpectation *doneExpectation = [self expectationWithDescription:@"Expect on main queue"];

    dispatch_queue_t globalQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    AnyPromise
        .withFutureOn(globalQueue,
            ^(AnyFuture *future) {
                XCTAssertTrue(DispatchQueueIsCurrentQueue(globalQueue));
                [expectation fulfill];
                [future resolveWithValue:@"abc"];
            })
        .mapOn(dispatch_get_main_queue(),
            ^(id value) {
                XCTAssertTrue(DispatchQueueIsCurrentQueue(dispatch_get_main_queue()));
                [mapExpectation fulfill];
                NSString *string = (NSString *)value;
                return [string stringByAppendingString:@"xyz"];
            })
        .done(^(id value) {
            XCTAssertTrue(DispatchQueueIsCurrentQueue(dispatch_get_main_queue()));
            NSString *string = (NSString *)value;
            XCTAssert([string isEqualToString:@"abcxyz"]);
            [doneExpectation fulfill];
        });

    [self waitForExpectationsWithTimeout:5 handler:nil];
}

@end

NS_ASSUME_NONNULL_END
