//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSDisappearingMessagesConfiguration.h"
#import "SSKBaseTestObjC.h"
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSDisappearingMessagesConfigurationTest : SSKBaseTestObjC

@end

@implementation OWSDisappearingMessagesConfigurationTest

- (void)testUpsert
{
    [self writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        NSString *threadId = @"fake-thread-id-1";

        XCTAssertNil([OWSDisappearingMessagesConfiguration anyFetchWithUniqueId:threadId transaction:transaction]);
        XCTAssertNotNil(
            [OWSDisappearingMessagesConfiguration disappearingMessagesConfigurationForThreadId:threadId
                                                                                   transaction:transaction]);

        OWSDisappearingMessagesConfiguration *configuration =
            [OWSDisappearingMessagesConfiguration disappearingMessagesConfigurationForThreadId:threadId
                                                                                   transaction:transaction];
        XCTAssertFalse([configuration hasChangedWithTransaction:transaction]);
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [configuration anyUpsertWithTransaction:transaction];
#pragma clang diagnostic pop

        XCTAssertFalse([configuration hasChangedWithTransaction:transaction]);
        XCTAssertNotNil([OWSDisappearingMessagesConfiguration anyFetchWithUniqueId:threadId transaction:transaction]);
        XCTAssertNotNil(
            [OWSDisappearingMessagesConfiguration disappearingMessagesConfigurationForThreadId:threadId
                                                                                   transaction:transaction]);
    }];
}

- (void)testDefaultVsEnabledIsChanged
{
    [self readWithBlock:^(SDSAnyReadTransaction *transaction) {
        NSString *threadId = @"fake-thread-id-1";

        XCTAssertNil([OWSDisappearingMessagesConfiguration anyFetchWithUniqueId:threadId transaction:transaction]);
        XCTAssertNotNil(
            [OWSDisappearingMessagesConfiguration disappearingMessagesConfigurationForThreadId:threadId
                                                                                   transaction:transaction]);

        OWSDisappearingMessagesConfiguration *configuration =
            [OWSDisappearingMessagesConfiguration disappearingMessagesConfigurationForThreadId:threadId
                                                                                   transaction:transaction];
        XCTAssertFalse([configuration hasChangedWithTransaction:transaction]);
        configuration.enabled = YES;
        XCTAssertTrue([configuration hasChangedWithTransaction:transaction]);
    }];
}

- (void)testDefaultVsNonDefaultDurationIsChanged
{
    [self readWithBlock:^(SDSAnyReadTransaction *transaction) {
        NSString *threadId = @"fake-thread-id-2";

        XCTAssertNil([OWSDisappearingMessagesConfiguration anyFetchWithUniqueId:threadId transaction:transaction]);
        XCTAssertNotNil(
            [OWSDisappearingMessagesConfiguration disappearingMessagesConfigurationForThreadId:threadId
                                                                                   transaction:transaction]);

        OWSDisappearingMessagesConfiguration *configuration =
            [OWSDisappearingMessagesConfiguration disappearingMessagesConfigurationForThreadId:threadId
                                                                                   transaction:transaction];
        XCTAssertFalse([configuration hasChangedWithTransaction:transaction]);
        configuration.durationSeconds = kWeekInterval;
        XCTAssertTrue([configuration hasChangedWithTransaction:transaction]);
    }];
}

- (void)testDefaultVsAllNonDefaultsIsChanged
{
    [self readWithBlock:^(SDSAnyReadTransaction *transaction) {
        NSString *threadId = @"fake-thread-id-3";

        XCTAssertNil([OWSDisappearingMessagesConfiguration anyFetchWithUniqueId:threadId transaction:transaction]);
        XCTAssertNotNil(
            [OWSDisappearingMessagesConfiguration disappearingMessagesConfigurationForThreadId:threadId
                                                                                   transaction:transaction]);

        OWSDisappearingMessagesConfiguration *configuration =
            [OWSDisappearingMessagesConfiguration disappearingMessagesConfigurationForThreadId:threadId
                                                                                   transaction:transaction];
        XCTAssertFalse([configuration hasChangedWithTransaction:transaction]);
        configuration.enabled = YES;
        configuration.durationSeconds = kWeekInterval;
        XCTAssertTrue([configuration hasChangedWithTransaction:transaction]);
    }];
}

- (void)testDefaultVsNotEnabledIsNotChanged
{
    [self readWithBlock:^(SDSAnyReadTransaction *transaction) {
        NSString *threadId = @"fake-thread-id-4";

        XCTAssertNil([OWSDisappearingMessagesConfiguration anyFetchWithUniqueId:threadId transaction:transaction]);
        XCTAssertNotNil(
            [OWSDisappearingMessagesConfiguration disappearingMessagesConfigurationForThreadId:threadId
                                                                                   transaction:transaction]);

        OWSDisappearingMessagesConfiguration *configuration =
            [OWSDisappearingMessagesConfiguration disappearingMessagesConfigurationForThreadId:threadId
                                                                                   transaction:transaction];
        XCTAssertFalse([configuration hasChangedWithTransaction:transaction]);
        configuration.enabled = NO;
        XCTAssertFalse([configuration hasChangedWithTransaction:transaction]);
    }];
}

- (void)testDefaultVsDefaultDurationIsNotChanged
{
    [self readWithBlock:^(SDSAnyReadTransaction *transaction) {
        NSString *threadId = @"fake-thread-id-1";

        XCTAssertNil([OWSDisappearingMessagesConfiguration anyFetchWithUniqueId:threadId transaction:transaction]);
        XCTAssertNotNil(
            [OWSDisappearingMessagesConfiguration disappearingMessagesConfigurationForThreadId:threadId
                                                                                   transaction:transaction]);

        OWSDisappearingMessagesConfiguration *configuration =
            [OWSDisappearingMessagesConfiguration disappearingMessagesConfigurationForThreadId:threadId
                                                                                   transaction:transaction];
        XCTAssertFalse([configuration hasChangedWithTransaction:transaction]);
        configuration.durationSeconds = OWSDisappearingMessagesConfigurationDefaultExpirationDuration;
        XCTAssertFalse([configuration hasChangedWithTransaction:transaction]);
    }];
}

- (void)testMultipleWrites
{
    NSString *threadId = @"fake-thread-id-1";

    [self writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        XCTAssertNil([OWSDisappearingMessagesConfiguration anyFetchWithUniqueId:threadId transaction:transaction]);
        XCTAssertNotNil(
            [OWSDisappearingMessagesConfiguration disappearingMessagesConfigurationForThreadId:threadId
                                                                                   transaction:transaction]);

        OWSDisappearingMessagesConfiguration *configuration =
            [OWSDisappearingMessagesConfiguration disappearingMessagesConfigurationForThreadId:threadId
                                                                                   transaction:transaction];
        XCTAssertFalse([configuration hasChangedWithTransaction:transaction]);

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [configuration anyUpsertWithTransaction:transaction];
#pragma clang diagnostic pop

        XCTAssertFalse([configuration hasChangedWithTransaction:transaction]);

        configuration.enabled = YES;

        XCTAssertTrue([configuration hasChangedWithTransaction:transaction]);

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [configuration anyUpsertWithTransaction:transaction];
#pragma clang diagnostic pop

        XCTAssertFalse([configuration hasChangedWithTransaction:transaction]);

        configuration.durationSeconds = kWeekInterval;

        XCTAssertTrue([configuration hasChangedWithTransaction:transaction]);

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [configuration anyUpsertWithTransaction:transaction];
#pragma clang diagnostic pop

        XCTAssertFalse([configuration hasChangedWithTransaction:transaction]);
    }];

    [self writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        OWSDisappearingMessagesConfiguration *configuration =
            [OWSDisappearingMessagesConfiguration disappearingMessagesConfigurationForThreadId:threadId
                                                                                   transaction:transaction];
        XCTAssertFalse([configuration hasChangedWithTransaction:transaction]);

        configuration.durationSeconds = kDayInterval;

        XCTAssertTrue([configuration hasChangedWithTransaction:transaction]);

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [configuration anyUpsertWithTransaction:transaction];
#pragma clang diagnostic pop

        XCTAssertFalse([configuration hasChangedWithTransaction:transaction]);
    }];

    [self writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        OWSDisappearingMessagesConfiguration *configuration =
            [OWSDisappearingMessagesConfiguration disappearingMessagesConfigurationForThreadId:threadId
                                                                                   transaction:transaction];
        XCTAssertFalse([configuration hasChangedWithTransaction:transaction]);

        configuration.enabled = NO;

        XCTAssertTrue([configuration hasChangedWithTransaction:transaction]);

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [configuration anyUpsertWithTransaction:transaction];
#pragma clang diagnostic pop

        XCTAssertFalse([configuration hasChangedWithTransaction:transaction]);
    }];
}

@end

NS_ASSUME_NONNULL_END
