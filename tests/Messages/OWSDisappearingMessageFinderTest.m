//  Created by Michael Kirk on 9/23/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "NSDate+millisecondTimeStamp.h"
#import "OWSDisappearingMessagesFinder.h"
#import "TSMessage.h"
#import "TSStorageManager.h"
#import "TSThread.h"
#import <XCTest/XCTest.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSDisappearingMessagesFinder (Testing)

- (NSArray<TSMessage *> *)fetchExpiredMessages;
- (NSArray<TSMessage *> *)fetchUnstartedExpiringMessagesInThread:(TSThread *)thread;

@end


@interface OWSDisappearingMessageFinderTest : XCTestCase

@property TSStorageManager *storageManager;
@property OWSDisappearingMessagesFinder *finder;
@property TSThread *thread;
@property uint64_t now;

@end

@implementation OWSDisappearingMessageFinderTest

- (void)setUp
{
    [super setUp];
    [TSMessage removeAllObjectsInCollection];

    self.storageManager = [TSStorageManager sharedManager];
    self.thread = [TSThread new];
    [self.thread save];
    self.now = [NSDate ows_millisecondTimeStamp];

    // Test subject
    self.finder = [[OWSDisappearingMessagesFinder alloc] initWithStorageManager:self.storageManager];
    [self.finder blockingRegisterDatabaseExtensions];
}

- (void)testExpiredMessages
{
    TSMessage *expiredMessage1 = [[TSMessage alloc] initWithTimestamp:1
                                                             inThread:self.thread
                                                          messageBody:@"expiredMessage1"
                                                        attachmentIds:@[]
                                                     expiresInSeconds:1
                                                      expireStartedAt:self.now - 20000];
    [expiredMessage1 save];

    TSMessage *expiredMessage2 = [[TSMessage alloc] initWithTimestamp:1
                                                             inThread:self.thread
                                                          messageBody:@"expiredMessage2"
                                                        attachmentIds:@[]
                                                     expiresInSeconds:2
                                                      expireStartedAt:self.now - 2001];
    [expiredMessage2 save];

    TSMessage *notYetExpiredMessage = [[TSMessage alloc] initWithTimestamp:1
                                                                  inThread:self.thread
                                                               messageBody:@"notYetExpiredMessage"
                                                             attachmentIds:@[]
                                                          expiresInSeconds:20
                                                           expireStartedAt:self.now - 10000];
    [notYetExpiredMessage save];

    TSMessage *unreadExpiringMessage = [[TSMessage alloc] initWithTimestamp:1
                                                                   inThread:self.thread
                                                                messageBody:@"unereadExpiringMessage"
                                                              attachmentIds:@[]
                                                           expiresInSeconds:10
                                                            expireStartedAt:0];
    [unreadExpiringMessage save];

    TSMessage *unExpiringMessage = [[TSMessage alloc] initWithTimestamp:1
                                                               inThread:self.thread
                                                            messageBody:@"unexpiringMessage"
                                                          attachmentIds:@[]
                                                       expiresInSeconds:0
                                                        expireStartedAt:0];
    [unExpiringMessage save];

    TSMessage *unExpiringMessage2 =
        [[TSMessage alloc] initWithTimestamp:1 inThread:self.thread messageBody:@"unexpiringMessage2"];
    [unExpiringMessage2 save];

    NSArray<TSMessage *> *actualMessages = [self.finder fetchExpiredMessages];
    NSArray<TSMessage *> *expectedMessages = @[ expiredMessage1, expiredMessage2 ];
    XCTAssertEqualObjects(expectedMessages, actualMessages);
}

- (void)testUnstartedExpiredMessagesForThread
{
    TSMessage *expiredMessage = [[TSMessage alloc] initWithTimestamp:1
                                                            inThread:self.thread
                                                         messageBody:@"expiredMessage2"
                                                       attachmentIds:@[]
                                                    expiresInSeconds:2
                                                     expireStartedAt:self.now - 2001];
    [expiredMessage save];

    TSMessage *notYetExpiredMessage = [[TSMessage alloc] initWithTimestamp:1
                                                                  inThread:self.thread
                                                               messageBody:@"notYetExpiredMessage"
                                                             attachmentIds:@[]
                                                          expiresInSeconds:20
                                                           expireStartedAt:self.now - 10000];
    [notYetExpiredMessage save];

    TSMessage *unreadExpiringMessage = [[TSMessage alloc] initWithTimestamp:1
                                                                   inThread:self.thread
                                                                messageBody:@"unereadExpiringMessage"
                                                              attachmentIds:@[]
                                                           expiresInSeconds:10
                                                            expireStartedAt:0];
    [unreadExpiringMessage save];

    TSMessage *unExpiringMessage = [[TSMessage alloc] initWithTimestamp:1
                                                               inThread:self.thread
                                                            messageBody:@"unexpiringMessage"
                                                          attachmentIds:@[]
                                                       expiresInSeconds:0
                                                        expireStartedAt:0];
    [unExpiringMessage save];

    TSMessage *unExpiringMessage2 =
        [[TSMessage alloc] initWithTimestamp:1 inThread:self.thread messageBody:@"unexpiringMessage2"];
    [unExpiringMessage2 save];

    NSArray<TSMessage *> *actualMessages = [self.finder fetchUnstartedExpiringMessagesInThread:self.thread];
    NSArray<TSMessage *> *expectedMessages = @[ unreadExpiringMessage ];
    XCTAssertEqualObjects(expectedMessages, actualMessages);
}

- (void)testNextExpirationTimestampNilWhenNoExpiringMessages
{
    // Sanity check.
    XCTAssertNil(self.finder.nextExpirationTimestamp);

    TSMessage *unExpiringMessage = [[TSMessage alloc] initWithTimestamp:1
                                                               inThread:self.thread
                                                            messageBody:@"unexpiringMessage"
                                                          attachmentIds:@[]
                                                       expiresInSeconds:0
                                                        expireStartedAt:0];
    [unExpiringMessage save];
    XCTAssertNil(self.finder.nextExpirationTimestamp);
}

- (void)testNextExpirationTimestampNotNilWithUpcomingExpiringMessages
{
    TSMessage *soonToExpireMessage = [[TSMessage alloc] initWithTimestamp:1
                                                                 inThread:self.thread
                                                              messageBody:@"soonToExpireMessage"
                                                            attachmentIds:@[]
                                                         expiresInSeconds:10
                                                          expireStartedAt:self.now - 9000];
    [soonToExpireMessage save];

    XCTAssertNotNil(self.finder.nextExpirationTimestamp);
    XCTAssertEqual(self.now + 1000, [self.finder.nextExpirationTimestamp unsignedLongLongValue]);

    // expired message should take precedence
    TSMessage *expiredMessage = [[TSMessage alloc] initWithTimestamp:1
                                                            inThread:self.thread
                                                         messageBody:@"expiredMessage"
                                                       attachmentIds:@[]
                                                    expiresInSeconds:10
                                                     expireStartedAt:self.now - 11000];
    [expiredMessage save];

    XCTAssertNotNil(self.finder.nextExpirationTimestamp);
    XCTAssertEqual(self.now - 1000, [self.finder.nextExpirationTimestamp unsignedLongLongValue]);
}

@end

NS_ASSUME_NONNULL_END
