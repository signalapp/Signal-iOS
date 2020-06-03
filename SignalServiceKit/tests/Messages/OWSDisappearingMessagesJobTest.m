//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSDisappearingMessagesConfiguration.h"
#import "OWSDisappearingMessagesFinder.h"
#import "OWSDisappearingMessagesJob.h"
#import "SSKBaseTestObjC.h"
#import "TSContactThread.h"
#import "TSIncomingMessage.h"
#import "TSMessage.h"
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSDisappearingMessagesJobTest : SSKBaseTestObjC

@property TSThread *thread;

@end

@implementation OWSDisappearingMessagesJobTest

- (SignalServiceAddress *)localAddress
{
    return [[SignalServiceAddress alloc] initWithPhoneNumber:@"+13334445555"];
}

- (SignalServiceAddress *)otherAddress
{
    return [[SignalServiceAddress alloc] initWithPhoneNumber:@"+12223334444"];
}

- (void)setUp
{
    [super setUp];

    self.thread = [TSContactThread getOrCreateThreadWithContactAddress:self.localAddress];
}

- (TSMessage *)messageWithBody:(NSString *)body
              expiresInSeconds:(uint32_t)expiresInSeconds
               expireStartedAt:(uint64_t)expireStartedAt
{
    TSIncomingMessageBuilder *incomingMessageBuilder =
        [TSIncomingMessageBuilder incomingMessageBuilderWithThread:self.thread messageBody:body];
    incomingMessageBuilder.timestamp = 1;
    incomingMessageBuilder.expiresInSeconds = expiresInSeconds;
    incomingMessageBuilder.expireStartedAt = expireStartedAt;
    return [incomingMessageBuilder build];
}

- (void)testRemoveAnyExpiredMessage
{
    uint64_t now = [NSDate ows_millisecondTimeStamp];
    TSMessage *expiredMessage1 =
        [self messageWithBody:@"expiredMessage1" expiresInSeconds:1 expireStartedAt:now - 20000];

    TSMessage *expiredMessage2 =
        [self messageWithBody:@"expiredMessage2" expiresInSeconds:2 expireStartedAt:now - 2001];

    TSMessage *notYetExpiredMessage =
        [self messageWithBody:@"notYetExpiredMessage" expiresInSeconds:20 expireStartedAt:now - 10000];

    TSMessage *unExpiringMessage = [self messageWithBody:@"unexpiringMessage" expiresInSeconds:0 expireStartedAt:0];

    [self writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [expiredMessage1 anyInsertWithTransaction:transaction];
        [expiredMessage2 anyInsertWithTransaction:transaction];
        [notYetExpiredMessage anyInsertWithTransaction:transaction];
        [unExpiringMessage anyInsertWithTransaction:transaction];
    }];

    OWSDisappearingMessagesJob *job = [OWSDisappearingMessagesJob sharedJob];

    // Sanity Check.
    [self readWithBlock:^(SDSAnyReadTransaction *transaction) {
        XCTAssertEqual(4, [TSMessage anyCountWithTransaction:transaction]);
    }];
    [job syncPassForTests];
    [self readWithBlock:^(SDSAnyReadTransaction *transaction) {
        XCTAssertEqual(2, [TSMessage anyCountWithTransaction:transaction]);
    }];
}

@end

NS_ASSUME_NONNULL_END
