//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "MockSSKEnvironment.h"
#import "OWSDisappearingMessagesFinder.h"
#import "SSKBaseTestObjC.h"
#import "TSContactThread.h"
#import "TSIncomingMessage.h"
#import "TSOutgoingMessage.h"
#import "TestAppContext.h"
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalServiceKit/SSKAccessors+SDS.h>
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
    return [[SignalServiceAddress alloc] initWithPhoneNumber:@"+13334445555"];
}

- (SignalServiceAddress *)otherAddress
{
    return [[SignalServiceAddress alloc] initWithPhoneNumber:@"+12223334444"];
}

- (TSThread *)threadWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    return [TSContactThread getOrCreateThreadWithContactAddress:self.otherAddress transaction:transaction];
}

- (TSIncomingMessage *)incomingMessageWithBody:(NSString *)body
                              expiresInSeconds:(uint32_t)expiresInSeconds
                               expireStartedAt:(uint64_t)expireStartedAt
{
    return [self incomingMessageWithBody:body
                        expiresInSeconds:expiresInSeconds
                         expireStartedAt:expireStartedAt
                              markAsRead:NO];
}

- (TSIncomingMessage *)incomingMessageWithBody:(NSString *)body
                              expiresInSeconds:(uint32_t)expiresInSeconds
                               expireStartedAt:(uint64_t)expireStartedAt
                                    markAsRead:(BOOL)markAsRead
{
    // It only makes sense to "mark as read" if expiration hasn't started,
    // since we don't start expiration for unread incoming messages.
    OWSAssertDebug(!markAsRead || expireStartedAt == 0);

    __block TSIncomingMessage *message;
    [self writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        TSThread *thread = [self threadWithTransaction:transaction];

        TSIncomingMessageBuilder *incomingMessageBuilder =
            [TSIncomingMessageBuilder incomingMessageBuilderWithThread:thread messageBody:body];
        incomingMessageBuilder.timestamp = 1;
        incomingMessageBuilder.authorAddress = self.otherAddress;
        incomingMessageBuilder.expiresInSeconds = expiresInSeconds;
        message = [incomingMessageBuilder build];
        [message anyInsertWithTransaction:transaction];

        if (expireStartedAt > 0) {
            [message markAsReadAtTimestamp:expireStartedAt
                                    thread:thread
                              circumstance:OWSReadCircumstanceReadOnLinkedDevice
                               transaction:transaction];
        } else if (markAsRead) {
            [message markAsReadAtTimestamp:self.now - 1000
                                    thread:thread
                              circumstance:OWSReadCircumstanceReadOnLinkedDevice
                               transaction:transaction];
        }
    }];
    return message;
}

- (TSOutgoingMessage *)outgoingMessageWithBody:(NSString *)body
                              expiresInSeconds:(uint32_t)expiresInSeconds
                               expireStartedAt:(uint64_t)expireStartedAt
{
    __block TSOutgoingMessage *message;
    [self writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        TSThread *thread = [self threadWithTransaction:transaction];

        TSOutgoingMessageBuilder *messageBuilder = [TSOutgoingMessageBuilder outgoingMessageBuilderWithThread:thread
                                                                                                  messageBody:body];
        messageBuilder.expiresInSeconds = expiresInSeconds;
        messageBuilder.expireStartedAt = expireStartedAt;
        message = [messageBuilder build];
        [message anyInsertWithTransaction:transaction];
    }];
    return message;
}

- (void)testExpiredMessages
{
    TSMessage *expiredMessage1 = [self incomingMessageWithBody:@"expiredMessage1"
                                              expiresInSeconds:2
                                               expireStartedAt:self.now - 2001];
    TSMessage *expiredMessage2 = [self incomingMessageWithBody:@"expiredMessage2"
                                              expiresInSeconds:1
                                               expireStartedAt:self.now - 20000];

    __unused TSMessage *notYetExpiredMessage = [self incomingMessageWithBody:@"notYetExpiredMessage"
                                                            expiresInSeconds:20
                                                             expireStartedAt:self.now - 10000];

    __unused TSMessage *unreadExpiringMessage = [self incomingMessageWithBody:@"unreadExpiringMessage"
                                                             expiresInSeconds:10
                                                              expireStartedAt:0];

    __unused TSMessage *unExpiringMessage = [self incomingMessageWithBody:@"unexpiringMessage"
                                                         expiresInSeconds:0
                                                          expireStartedAt:0];

    __unused TSMessage *unExpiringMessage2 = [self incomingMessageWithBody:@"unexpiringMessage2"
                                                          expiresInSeconds:0
                                                           expireStartedAt:0];

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
    TSMessage *expiredIncomingMessage = [self incomingMessageWithBody:@"incoming expiredMessage"
                                                     expiresInSeconds:2
                                                      expireStartedAt:self.now - 2001];
    TSMessage *notYetExpiredIncomingMessage = [self incomingMessageWithBody:@"incoming notYetExpiredMessage"
                                                           expiresInSeconds:20
                                                            expireStartedAt:self.now - 10000];
    TSMessage *unreadExpiringIncomingMessage = [self incomingMessageWithBody:@"incoming unreadExpiringMessage"
                                                            expiresInSeconds:10
                                                             expireStartedAt:0];
    TSMessage *readExpiringIncomingMessage = [self incomingMessageWithBody:@"incoming readExpiringMessage"
                                                          expiresInSeconds:10
                                                           expireStartedAt:0
                                                                markAsRead:YES];
    TSMessage *unExpiringIncomingMessage = [self incomingMessageWithBody:@"incoming unexpiringMessage"
                                                        expiresInSeconds:0
                                                         expireStartedAt:0];
    TSMessage *unExpiringIncomingMessage2 = [self incomingMessageWithBody:@"incoming unexpiringMessage2"
                                                         expiresInSeconds:0
                                                          expireStartedAt:0];

    TSMessage *expiredOutgoingMessage = [self outgoingMessageWithBody:@"outgoing expiredMessage"
                                                     expiresInSeconds:2
                                                      expireStartedAt:self.now - 2001];
    TSMessage *notYetExpiredOutgoingMessage = [self outgoingMessageWithBody:@"outgoing notYetExpiredMessage"
                                                           expiresInSeconds:20
                                                            expireStartedAt:self.now - 10000];
    TSMessage *expiringUnsentOutgoingMessage = [self outgoingMessageWithBody:@"expiringUnsentOutgoingMessage"
                                                            expiresInSeconds:10
                                                             expireStartedAt:0];
    TSOutgoingMessage *expiringSentOutgoingMessage = [self outgoingMessageWithBody:@"expiringSentOutgoingMessage"
                                                                  expiresInSeconds:10
                                                                   expireStartedAt:0];
    TSOutgoingMessage *expiringDeliveredOutgoingMessage =
        [self outgoingMessageWithBody:@"expiringDeliveredOutgoingMessage" expiresInSeconds:10 expireStartedAt:0];
    TSOutgoingMessage *expiringDeliveredAndReadOutgoingMessage =
        [self outgoingMessageWithBody:@"expiringDeliveredAndReadOutgoingMessage" expiresInSeconds:10 expireStartedAt:0];
    TSMessage *unExpiringOutgoingMessage = [self outgoingMessageWithBody:@"outgoing unexpiringMessage"
                                                        expiresInSeconds:0
                                                         expireStartedAt:0];
    TSMessage *unExpiringOutgoingMessage2 = [self outgoingMessageWithBody:@"outgoing unexpiringMessage2"
                                                         expiresInSeconds:0
                                                          expireStartedAt:0];

    [self writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        // Mark outgoing message as "sent", "delivered" or "delivered and read" using production methods.
        [expiringSentOutgoingMessage updateWithSentRecipient:self.otherAddress wasSentByUD:NO transaction:transaction];
        [expiringDeliveredOutgoingMessage updateWithDeliveredRecipient:self.otherAddress
                                                     deliveryTimestamp:nil
                                                           transaction:transaction];
        uint64_t nowMs = [NSDate ows_millisecondTimeStamp];
        [expiringDeliveredAndReadOutgoingMessage updateWithReadRecipient:self.otherAddress
                                                           readTimestamp:nowMs
                                                             transaction:transaction];
    }];

    NSArray<TSMessage *> *shouldBeExpiringMessages = @[
        expiredIncomingMessage,
        notYetExpiredIncomingMessage,
        readExpiringIncomingMessage,

        expiringSentOutgoingMessage,
        expiringDeliveredOutgoingMessage,
        expiringDeliveredAndReadOutgoingMessage,
        expiredOutgoingMessage,
        notYetExpiredOutgoingMessage,
    ];
    NSArray<TSMessage *> *shouldNotBeExpiringMessages = @[
        unreadExpiringIncomingMessage,
        unExpiringIncomingMessage,
        unExpiringIncomingMessage2,

        expiringUnsentOutgoingMessage,
        unExpiringOutgoingMessage,
        unExpiringOutgoingMessage2,
    ];

    NSMutableSet<NSString *> *actualMessageIds = [NSMutableSet new];
    [self writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        for (TSMessage *oldMessage in shouldBeExpiringMessages) {
            NSString *messageId = oldMessage.uniqueId;
            BOOL shouldBeExpiring = YES;
            TSMessage *_Nullable message = [TSMessage anyFetchMessageWithUniqueId:messageId transaction:transaction];
            XCTAssertNotNil(message);
            if (message == nil) {
                OWSLogVerbose(@"Missing message: %@ %@", messageId, oldMessage.body);
                continue;
            }
            if (shouldBeExpiring != [message shouldStartExpireTimer]) {
                OWSLogVerbose(@"!shouldBeExpiring: %@ %@", messageId, oldMessage.body);
            }
            XCTAssertEqual(shouldBeExpiring, [message shouldStartExpireTimer]);
            XCTAssertEqual(shouldBeExpiring, message.storedShouldStartExpireTimer);
            XCTAssertTrue(message.expiresAt > 0);
        }
        for (TSMessage *oldMessage in shouldNotBeExpiringMessages) {
            NSString *messageId = oldMessage.uniqueId;
            BOOL shouldBeExpiring = NO;
            TSMessage *_Nullable message = [TSMessage anyFetchMessageWithUniqueId:messageId transaction:transaction];
            XCTAssertNotNil(message);
            if (message == nil) {
                OWSLogVerbose(@"Missing message: %@ %@", messageId, oldMessage.body);
                continue;
            }
            XCTAssertEqual(shouldBeExpiring, [message shouldStartExpireTimer]);
            XCTAssertEqual(shouldBeExpiring, message.storedShouldStartExpireTimer);
            XCTAssertEqual(0, message.expiresAt);
        }

        TSThread *thread = [self threadWithTransaction:transaction];

        for (TSMessage *message in
            [self.finder fetchUnstartedExpiringMessagesInThread:thread transaction:transaction]) {
            [actualMessageIds addObject:message.uniqueId];
        }
    }];

    XCTAssertEqualObjects([NSSet set], actualMessageIds);
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

    __unused TSMessage *unExpiringMessage = [self incomingMessageWithBody:@"unexpiringMessage"
                                                         expiresInSeconds:0
                                                          expireStartedAt:0];
    XCTAssertNil(self.nextExpirationTimestamp);
}

- (void)testNextExpirationTimestampNotNilWithUpcomingExpiringMessages
{
    __unused TSMessage *soonToExpireMessage = [self incomingMessageWithBody:@"soonToExpireMessage"
                                                           expiresInSeconds:10
                                                            expireStartedAt:self.now - 9000];

    XCTAssertNotNil(self.nextExpirationTimestamp);
    XCTAssertEqual(self.now + 1000, [self.nextExpirationTimestamp unsignedLongLongValue]);

    // expired message should take precedence
    __unused TSMessage *expiredMessage = [self incomingMessageWithBody:@"expiredMessage"
                                                      expiresInSeconds:10
                                                       expireStartedAt:self.now - 11000];

    XCTAssertNotNil(self.nextExpirationTimestamp);
    XCTAssertEqual(self.now - 1000, [self.nextExpirationTimestamp unsignedLongLongValue]);
}

@end

NS_ASSUME_NONNULL_END
