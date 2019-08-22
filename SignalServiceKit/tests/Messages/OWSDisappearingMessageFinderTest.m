//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "MockSSKEnvironment.h"
#import "OWSDisappearingMessagesFinder.h"
#import "SSKBaseTestObjC.h"
#import "TSContactThread.h"
#import "TSIncomingMessage.h"
#import "TSOutgoingMessage.h"
#import "TestAppContext.h"
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/StorageCoordinator.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSDisappearingMessagesFinder (Testing)

- (NSArray<TSMessage *> *)fetchExpiredMessagesWithTransaction:(SDSAnyReadTransaction *)transaction;
- (NSArray<TSMessage *> *)fetchUnstartedExpiringMessagesInThread:(TSThread *)thread
                                                     transaction:(SDSAnyReadTransaction *)transaction;

@end

#pragma mark -

@interface OWSDisappearingMessageFinderTest : SSKBaseTestObjC

@property (nonatomic, nullable) OWSDisappearingMessagesFinder *finder;
@property (nonatomic) uint64_t now;

@end

#pragma mark -

@implementation OWSDisappearingMessageFinderTest

#pragma mark - Dependencies

- (SDSDatabaseStorage *)databaseStorage
{
    return SSKEnvironment.shared.databaseStorage;
}

- (StorageCoordinator *)storageCoordinator
{
    return SSKEnvironment.shared.storageCoordinator;
}

#pragma mark -

- (void)setUp
{
    [super setUp];

    self.now = [NSDate ows_millisecondTimeStamp];

    // Test subject
    self.finder = [OWSDisappearingMessagesFinder new];
}

- (SignalServiceAddress *)localAddress
{
    return [[SignalServiceAddress alloc] initWithPhoneNumber:@"+1333444555"];
}

- (SignalServiceAddress *)otherAddress
{
    return [[SignalServiceAddress alloc] initWithPhoneNumber:@"+12223334444"];
}

- (TSThread *)threadWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    return [TSContactThread getOrCreateThreadWithContactAddress:self.otherAddress transaction:transaction];
}

- (TSMessage *)messageWithBody:(NSString *)body
              expiresInSeconds:(uint32_t)expiresInSeconds
               expireStartedAt:(uint64_t)expireStartedAt
{
    __block TSIncomingMessage *message;
    [self writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        TSThread *thread = [self threadWithTransaction:transaction];

        message = [[TSIncomingMessage alloc] initIncomingMessageWithTimestamp:1
                                                                     inThread:thread
                                                                authorAddress:self.otherAddress
                                                               sourceDeviceId:0
                                                                  messageBody:body
                                                                attachmentIds:@[]
                                                             expiresInSeconds:expiresInSeconds
                                                                quotedMessage:nil
                                                                 contactShare:nil
                                                                  linkPreview:nil
                                                               messageSticker:nil
                                                              serverTimestamp:nil
                                                              wasReceivedByUD:NO
                                                            isViewOnceMessage:NO];
        [message anyInsertWithTransaction:transaction];
        if (expireStartedAt > 0) {
            [message updateWithExpireStartedAt:expireStartedAt transaction:transaction];
        }
    }];
    return message;
}

- (void)testExpiredMessages
{
    TSMessage *expiredMessage1 =
        [self messageWithBody:@"expiredMessage1" expiresInSeconds:2 expireStartedAt:self.now - 2001];
    TSMessage *expiredMessage2 =
        [self messageWithBody:@"expiredMessage2" expiresInSeconds:1 expireStartedAt:self.now - 20000];

    __unused TSMessage *notYetExpiredMessage =
        [self messageWithBody:@"notYetExpiredMessage" expiresInSeconds:20 expireStartedAt:self.now - 10000];

    __unused TSMessage *unreadExpiringMessage =
        [self messageWithBody:@"unreadExpiringMessage" expiresInSeconds:10 expireStartedAt:0];

    __unused TSMessage *unExpiringMessage =
        [self messageWithBody:@"unexpiringMessage" expiresInSeconds:0 expireStartedAt:0];

    __unused TSMessage *unExpiringMessage2 =
        [self messageWithBody:@"unexpiringMessage2" expiresInSeconds:0 expireStartedAt:0];

    NSMutableSet<NSString *> *actualMessageIds = [NSMutableSet new];
    [self readWithBlock:^(SDSAnyReadTransaction *transaction) {
        for (TSMessage *message in [self.finder fetchExpiredMessagesWithTransaction:transaction]) {
            [actualMessageIds addObject:message.uniqueId];
        }
    }];

    NSSet<NSString *> *expectedMessageIds = [NSSet setWithArray:@[
        expiredMessage1.uniqueId,
        expiredMessage2.uniqueId,
    ]];
    XCTAssertEqualObjects(expectedMessageIds, actualMessageIds);
}

- (void)testUnstartedExpiredMessagesForThread
{
    __unused TSMessage *expiredMessage =
        [self messageWithBody:@"expiredMessage2" expiresInSeconds:2 expireStartedAt:self.now - 2001];

    __unused TSMessage *notYetExpiredMessage =
        [self messageWithBody:@"notYetExpiredMessage" expiresInSeconds:20 expireStartedAt:self.now - 10000];

    __unused TSMessage *unreadExpiringMessage =
        [self messageWithBody:@"unereadExpiringMessage" expiresInSeconds:10 expireStartedAt:0];

    __unused TSMessage *unExpiringMessage =
        [self messageWithBody:@"unexpiringMessage" expiresInSeconds:0 expireStartedAt:0];

    __unused TSMessage *unExpiringMessage2 =
        [self messageWithBody:@"unexpiringMessage2" expiresInSeconds:0 expireStartedAt:0];

    NSMutableSet<NSString *> *actualMessageIds = [NSMutableSet new];
    [self writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        TSThread *thread = [self threadWithTransaction:transaction];

        for (TSMessage *message in
            [self.finder fetchUnstartedExpiringMessagesInThread:thread transaction:transaction]) {
            [actualMessageIds addObject:message.uniqueId];
        }
    }];

    NSSet<NSString *> *expectedMessageIds = [NSSet setWithArray:@[
        unreadExpiringMessage.uniqueId,
    ]];
    XCTAssertEqualObjects(expectedMessageIds, actualMessageIds);
}

- (nullable NSNumber *)nextExpirationTimestamp
{
    __block NSNumber *_Nullable nextExpirationTimestamp;

    [self readWithBlock:^(SDSAnyReadTransaction *transaction) {
        XCTAssertNotNil(self.finder);
        nextExpirationTimestamp = [self.finder nextExpirationTimestampWithTransaction:transaction];
    }];

    return nextExpirationTimestamp;
}

- (void)testNextExpirationTimestampNilWhenNoExpiringMessages
{
    // Sanity check.

    XCTAssertNil(self.nextExpirationTimestamp);

    __unused TSMessage *unExpiringMessage =
        [self messageWithBody:@"unexpiringMessage" expiresInSeconds:0 expireStartedAt:0];
    XCTAssertNil(self.nextExpirationTimestamp);
}

- (void)testNextExpirationTimestampNotNilWithUpcomingExpiringMessages
{
    __unused TSMessage *soonToExpireMessage =
        [self messageWithBody:@"soonToExpireMessage" expiresInSeconds:10 expireStartedAt:self.now - 9000];

    XCTAssertNotNil(self.nextExpirationTimestamp);
    XCTAssertEqual(self.now + 1000, [self.nextExpirationTimestamp unsignedLongLongValue]);

    // expired message should take precedence
    __unused TSMessage *expiredMessage =
        [self messageWithBody:@"expiredMessage" expiresInSeconds:10 expireStartedAt:self.now - 11000];

    XCTAssertNotNil(self.nextExpirationTimestamp);
    XCTAssertEqual(self.now - 1000, [self.nextExpirationTimestamp unsignedLongLongValue]);
}

@end

NS_ASSUME_NONNULL_END
