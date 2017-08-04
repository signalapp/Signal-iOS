//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "NSDate+millisecondTimeStamp.h"
#import "OWSDisappearingMessagesFinder.h"
#import "TSContactThread.h"
#import "TSMessage.h"
#import "TSStorageManager.h"
#import <XCTest/XCTest.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSDisappearingMessagesFinder (Testing)

- (NSArray<TSMessage *> *)fetchExpiredMessagesWithTransaction:(YapDatabaseReadTransaction *)transaction;
- (NSArray<TSMessage *> *)fetchUnstartedExpiringMessagesInThread:(TSThread *)thread
                                                     transaction:(YapDatabaseReadTransaction *)transaction;

@end


@interface OWSDisappearingMessageFinderTest : XCTestCase

@property YapDatabaseConnection *dbConnection;
@property OWSDisappearingMessagesFinder *finder;
@property TSStorageManager *storageManager;
@property TSThread *thread;
@property uint64_t now;

@end

@implementation OWSDisappearingMessageFinderTest

- (void)setUp
{
    [super setUp];
    [TSMessage removeAllObjectsInCollection];

    self.storageManager = [TSStorageManager sharedManager];
    self.dbConnection = self.storageManager.newDatabaseConnection;
    self.thread = [TSContactThread getOrCreateThreadWithContactId:@"fake-thread-id"];

    self.now = [NSDate ows_millisecondTimeStamp];

    // Test subject
    self.finder = [OWSDisappearingMessagesFinder new];
    [OWSDisappearingMessagesFinder blockingRegisterDatabaseExtensions:self.storageManager];
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

    __block NSArray<TSMessage *> *actualMessages;
    [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
        actualMessages = [self.finder fetchExpiredMessagesWithTransaction:transaction];
    }];
    
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

    __block NSArray<TSMessage *> *actualMessages;
    [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
        actualMessages = [self.finder fetchUnstartedExpiringMessagesInThread:self.thread
                                                                 transaction:transaction];
    }];
    
    NSArray<TSMessage *> *expectedMessages = @[ unreadExpiringMessage ];
    XCTAssertEqualObjects(expectedMessages, actualMessages);
}

- (NSNumber *)nextExpirationTimestamp
{
    __block NSNumber *nextExpirationTimestamp;
    
    [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
        XCTAssertNotNil(self.finder);
        nextExpirationTimestamp = [self.finder nextExpirationTimestampWithTransaction:transaction];
    }];
        
    return nextExpirationTimestamp;
}

- (void)testNextExpirationTimestampNilWhenNoExpiringMessages
{
    // Sanity check.

    XCTAssertNil(self.nextExpirationTimestamp);

    TSMessage *unExpiringMessage = [[TSMessage alloc] initWithTimestamp:1
                                                               inThread:self.thread
                                                            messageBody:@"unexpiringMessage"
                                                          attachmentIds:@[]
                                                       expiresInSeconds:0
                                                        expireStartedAt:0];
    [unExpiringMessage save];
    XCTAssertNil(self.nextExpirationTimestamp);
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

    XCTAssertNotNil(self.nextExpirationTimestamp);
    XCTAssertEqual(self.now + 1000, [self.nextExpirationTimestamp unsignedLongLongValue]);

    // expired message should take precedence
    TSMessage *expiredMessage = [[TSMessage alloc] initWithTimestamp:1
                                                            inThread:self.thread
                                                         messageBody:@"expiredMessage"
                                                       attachmentIds:@[]
                                                    expiresInSeconds:10
                                                     expireStartedAt:self.now - 11000];
    [expiredMessage save];

    //FIXME remove sleep hack in favor of expiringMessage completion handler
//    sleep(2);
    XCTAssertNotNil(self.nextExpirationTimestamp);
    XCTAssertEqual(self.now - 1000, [self.nextExpirationTimestamp unsignedLongLongValue]);
}

@end

NS_ASSUME_NONNULL_END
