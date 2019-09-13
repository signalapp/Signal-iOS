//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSDisappearingMessagesConfiguration.h"
#import "SSKBaseTestObjC.h"
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSContactThread.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSDisappearingMessagesConfiguration (Tests)

+ (nullable instancetype)fetchWithThread:(TSThread *)thread transaction:(SDSAnyReadTransaction *)transaction;

@end

#pragma mark -

@interface OWSDisappearingMessagesConfigurationTest : SSKBaseTestObjC

@end

#pragma mark -

@implementation OWSDisappearingMessagesConfigurationTest

- (void)testUpsert
{
    [self writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        SignalServiceAddress *address = [[SignalServiceAddress alloc] initWithPhoneNumber:@"+12223334444"];
        TSContactThread *thread = [[TSContactThread alloc] initWithContactAddress:address];
        [thread anyInsertWithTransaction:transaction];

        XCTAssertNil([OWSDisappearingMessagesConfiguration fetchWithThread:thread transaction:transaction]);
        XCTAssertNotNil([OWSDisappearingMessagesConfiguration fetchOrBuildDefaultWithThread:thread
                                                                                transaction:transaction]);

        OWSDisappearingMessagesConfiguration *configuration =
            [thread disappearingMessagesConfigurationWithTransaction:transaction];
        configuration = [configuration copyAsEnabledWithDurationSeconds:10];

        XCTAssertTrue([configuration hasChangedWithTransaction:transaction]);

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [configuration anyUpsertWithTransaction:transaction];
#pragma clang diagnostic pop

        XCTAssertNotNil([OWSDisappearingMessagesConfiguration fetchWithThread:thread transaction:transaction]);
        XCTAssertFalse([configuration hasChangedWithTransaction:transaction]);
    }];
}

- (void)testDefaultVsEnabledIsChanged
{
    SignalServiceAddress *address = [[SignalServiceAddress alloc] initWithPhoneNumber:@"+12223334444"];
    TSContactThread *thread = [[TSContactThread alloc] initWithContactAddress:address];
    [self writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [thread anyInsertWithTransaction:transaction];

        XCTAssertNil([OWSDisappearingMessagesConfiguration fetchWithThread:thread transaction:transaction]);
        XCTAssertNotNil([OWSDisappearingMessagesConfiguration fetchOrBuildDefaultWithThread:thread
                                                                                transaction:transaction]);

        OWSDisappearingMessagesConfiguration *configuration =
            [OWSDisappearingMessagesConfiguration fetchOrBuildDefaultWithThread:thread transaction:transaction];
        XCTAssertFalse([configuration hasChangedWithTransaction:transaction]);
        configuration = [configuration copyWithIsEnabled:YES];
        XCTAssertTrue([configuration hasChangedWithTransaction:transaction]);

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [configuration anyUpsertWithTransaction:transaction];
#pragma clang diagnostic pop

        XCTAssertNotNil([OWSDisappearingMessagesConfiguration fetchWithThread:thread transaction:transaction]);
        XCTAssertFalse([configuration hasChangedWithTransaction:transaction]);
    }];
}

- (void)testDefaultVsNonDefaultDurationIsChanged
{
    SignalServiceAddress *address = [[SignalServiceAddress alloc] initWithPhoneNumber:@"+12223334444"];
    TSContactThread *thread = [[TSContactThread alloc] initWithContactAddress:address];
    [self writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [thread anyInsertWithTransaction:transaction];

        XCTAssertNil([OWSDisappearingMessagesConfiguration fetchWithThread:thread transaction:transaction]);
        XCTAssertNotNil([OWSDisappearingMessagesConfiguration fetchOrBuildDefaultWithThread:thread
                                                                                transaction:transaction]);

        OWSDisappearingMessagesConfiguration *configuration =
            [OWSDisappearingMessagesConfiguration fetchOrBuildDefaultWithThread:thread transaction:transaction];
        XCTAssertFalse([configuration hasChangedWithTransaction:transaction]);
        configuration = [configuration copyWithDurationSeconds:kWeekInterval];
        XCTAssertTrue([configuration hasChangedWithTransaction:transaction]);

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [configuration anyUpsertWithTransaction:transaction];
#pragma clang diagnostic pop

        XCTAssertNotNil([OWSDisappearingMessagesConfiguration fetchWithThread:thread transaction:transaction]);
        XCTAssertFalse([configuration hasChangedWithTransaction:transaction]);
    }];
}

- (void)testDefaultVsAllNonDefaultsIsChanged
{
    SignalServiceAddress *address = [[SignalServiceAddress alloc] initWithPhoneNumber:@"+12223334444"];
    TSContactThread *thread = [[TSContactThread alloc] initWithContactAddress:address];
    [self writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [thread anyInsertWithTransaction:transaction];

        XCTAssertNil([OWSDisappearingMessagesConfiguration fetchWithThread:thread transaction:transaction]);
        XCTAssertNotNil([OWSDisappearingMessagesConfiguration fetchOrBuildDefaultWithThread:thread
                                                                                transaction:transaction]);

        OWSDisappearingMessagesConfiguration *configuration =
            [OWSDisappearingMessagesConfiguration fetchOrBuildDefaultWithThread:thread transaction:transaction];
        XCTAssertFalse([configuration hasChangedWithTransaction:transaction]);
        configuration = [configuration copyAsEnabledWithDurationSeconds:kWeekInterval];
        XCTAssertTrue([configuration hasChangedWithTransaction:transaction]);

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [configuration anyUpsertWithTransaction:transaction];
#pragma clang diagnostic pop

        XCTAssertNotNil([OWSDisappearingMessagesConfiguration fetchWithThread:thread transaction:transaction]);
        XCTAssertFalse([configuration hasChangedWithTransaction:transaction]);
    }];
}

- (void)testDefaultVsNotEnabledIsNotChanged
{
    SignalServiceAddress *address = [[SignalServiceAddress alloc] initWithPhoneNumber:@"+12223334444"];
    TSContactThread *thread = [[TSContactThread alloc] initWithContactAddress:address];
    [self writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [thread anyInsertWithTransaction:transaction];

        XCTAssertNil([OWSDisappearingMessagesConfiguration fetchWithThread:thread transaction:transaction]);
        XCTAssertNotNil([OWSDisappearingMessagesConfiguration fetchOrBuildDefaultWithThread:thread
                                                                                transaction:transaction]);

        OWSDisappearingMessagesConfiguration *configuration =
            [OWSDisappearingMessagesConfiguration fetchOrBuildDefaultWithThread:thread transaction:transaction];
        XCTAssertFalse([configuration hasChangedWithTransaction:transaction]);
        configuration = [configuration copyWithIsEnabled:NO];
        XCTAssertFalse([configuration hasChangedWithTransaction:transaction]);

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [configuration anyUpsertWithTransaction:transaction];
#pragma clang diagnostic pop

        XCTAssertNotNil([OWSDisappearingMessagesConfiguration fetchWithThread:thread transaction:transaction]);
        XCTAssertFalse([configuration hasChangedWithTransaction:transaction]);
    }];
}

- (void)testDefaultVsDefaultDurationIsNotChanged
{
    SignalServiceAddress *address = [[SignalServiceAddress alloc] initWithPhoneNumber:@"+12223334444"];
    TSContactThread *thread = [[TSContactThread alloc] initWithContactAddress:address];
    [self writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [thread anyInsertWithTransaction:transaction];

        XCTAssertNil([OWSDisappearingMessagesConfiguration fetchWithThread:thread transaction:transaction]);
        XCTAssertNotNil([OWSDisappearingMessagesConfiguration fetchOrBuildDefaultWithThread:thread
                                                                                transaction:transaction]);

        OWSDisappearingMessagesConfiguration *configuration =
            [OWSDisappearingMessagesConfiguration fetchOrBuildDefaultWithThread:thread transaction:transaction];
        XCTAssertFalse([configuration hasChangedWithTransaction:transaction]);
        configuration =
            [configuration copyWithDurationSeconds:OWSDisappearingMessagesConfigurationDefaultExpirationDuration];
        XCTAssertFalse([configuration hasChangedWithTransaction:transaction]);

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [configuration anyUpsertWithTransaction:transaction];
#pragma clang diagnostic pop

        XCTAssertNotNil([OWSDisappearingMessagesConfiguration fetchWithThread:thread transaction:transaction]);
        XCTAssertFalse([configuration hasChangedWithTransaction:transaction]);
    }];
}

- (void)testMultipleWrites
{
    SignalServiceAddress *address = [[SignalServiceAddress alloc] initWithPhoneNumber:@"+12223334444"];
    TSContactThread *thread = [[TSContactThread alloc] initWithContactAddress:address];

    [self writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [thread anyInsertWithTransaction:transaction];

        XCTAssertNil([OWSDisappearingMessagesConfiguration fetchWithThread:thread transaction:transaction]);
        XCTAssertNotNil([OWSDisappearingMessagesConfiguration fetchOrBuildDefaultWithThread:thread
                                                                                transaction:transaction]);

        OWSDisappearingMessagesConfiguration *configuration =
            [OWSDisappearingMessagesConfiguration fetchOrBuildDefaultWithThread:thread transaction:transaction];
        XCTAssertFalse([configuration hasChangedWithTransaction:transaction]);

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [configuration anyUpsertWithTransaction:transaction];
#pragma clang diagnostic pop

        XCTAssertFalse([configuration hasChangedWithTransaction:transaction]);

        configuration = [configuration copyWithIsEnabled:YES];

        XCTAssertTrue([configuration hasChangedWithTransaction:transaction]);

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [configuration anyUpsertWithTransaction:transaction];
#pragma clang diagnostic pop

        XCTAssertFalse([configuration hasChangedWithTransaction:transaction]);

        configuration = [configuration copyWithDurationSeconds:kWeekInterval];

        XCTAssertTrue([configuration hasChangedWithTransaction:transaction]);

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [configuration anyUpsertWithTransaction:transaction];
#pragma clang diagnostic pop

        XCTAssertFalse([configuration hasChangedWithTransaction:transaction]);
    }];

    [self writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        OWSDisappearingMessagesConfiguration *configuration =
            [OWSDisappearingMessagesConfiguration fetchOrBuildDefaultWithThread:thread transaction:transaction];
        XCTAssertFalse([configuration hasChangedWithTransaction:transaction]);

        configuration = [configuration copyWithDurationSeconds:kDayInterval];

        XCTAssertTrue([configuration hasChangedWithTransaction:transaction]);

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [configuration anyUpsertWithTransaction:transaction];
#pragma clang diagnostic pop

        XCTAssertFalse([configuration hasChangedWithTransaction:transaction]);
    }];

    [self writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        OWSDisappearingMessagesConfiguration *configuration =
            [OWSDisappearingMessagesConfiguration fetchOrBuildDefaultWithThread:thread transaction:transaction];
        XCTAssertFalse([configuration hasChangedWithTransaction:transaction]);

        configuration = [configuration copyWithIsEnabled:NO];

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
