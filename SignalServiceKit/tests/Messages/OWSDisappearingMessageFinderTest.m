//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "NSDate+OWS.h"
#import "OWSDisappearingMessagesFinder.h"
#import "OWSPrimaryStorage.h"
#import "TSContactThread.h"
#import "TSMessage.h"
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
@property OWSPrimaryStorage *storageManager;
@property TSThread *thread;
@property uint64_t now;

@end

@implementation OWSDisappearingMessageFinderTest

- (void)setUp
{
    [super setUp];
    [TSMessage removeAllObjectsInCollection];

    self.storageManager = [OWSPrimaryStorage sharedManager];
    self.dbConnection = self.storageManager.newDatabaseConnection;
    self.thread = [TSContactThread getOrCreateThreadWithContactId:@"fake-thread-id"];

    self.now = [NSDate ows_millisecondTimeStamp];

    // Test subject
    self.finder = [OWSDisappearingMessagesFinder new];
    [OWSDisappearingMessagesFinder blockingRegisterDatabaseExtensions:self.storageManager];
}

- (TSMessage *)messageWithBody:(NSString *)body
              expiresInSeconds:(uint32_t)expiresInSeconds
               expireStartedAt:(uint64_t)expireStartedAt
{
    return [[TSMessage alloc] initMessageWithTimestamp:1
                                              inThread:self.thread
                                           messageBody:body
                                         attachmentIds:@[]
                                      expiresInSeconds:expiresInSeconds
                                       expireStartedAt:expireStartedAt
                                         quotedMessage:nil
                                          contactShare:nil];
}

- (void)testExpiredMessages
{


    TSMessage *expiredMessage1 =
        [self messageWithBody:@"expiredMessage1" expiresInSeconds:1 expireStartedAt:self.now - 20000];
    [expiredMessage1 save];

    TSMessage *expiredMessage2 =
        [self messageWithBody:@"expiredMessage2" expiresInSeconds:2 expireStartedAt:self.now - 2001];
    [expiredMessage2 save];

    TSMessage *notYetExpiredMessage =
        [self messageWithBody:@"notYetExpiredMessage" expiresInSeconds:20 expireStartedAt:self.now - 10000];
    [notYetExpiredMessage save];

    TSMessage *unreadExpiringMessage =
        [self messageWithBody:@"unereadExpiringMessage" expiresInSeconds:10 expireStartedAt:0];
    [unreadExpiringMessage save];

    TSMessage *unExpiringMessage = [self messageWithBody:@"unexpiringMessage" expiresInSeconds:0 expireStartedAt:0];
    [unExpiringMessage save];

    TSMessage *unExpiringMessage2 = [self messageWithBody:@"unexpiringMessage2" expiresInSeconds:0 expireStartedAt:0];
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
    TSMessage *expiredMessage =
        [self messageWithBody:@"expiredMessage2" expiresInSeconds:2 expireStartedAt:self.now - 2001];
    [expiredMessage save];

    TSMessage *notYetExpiredMessage =
        [self messageWithBody:@"notYetExpiredMessage" expiresInSeconds:20 expireStartedAt:self.now - 10000];
    [notYetExpiredMessage save];

    TSMessage *unreadExpiringMessage =
        [self messageWithBody:@"unereadExpiringMessage" expiresInSeconds:10 expireStartedAt:0];
    [unreadExpiringMessage save];

    TSMessage *unExpiringMessage = [self messageWithBody:@"unexpiringMessage" expiresInSeconds:0 expireStartedAt:0];
    [unExpiringMessage save];

    TSMessage *unExpiringMessage2 = [self messageWithBody:@"unexpiringMessage2" expiresInSeconds:0 expireStartedAt:0];
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

    TSMessage *unExpiringMessage = [self messageWithBody:@"unexpiringMessage" expiresInSeconds:0 expireStartedAt:0];
    [unExpiringMessage save];
    XCTAssertNil(self.nextExpirationTimestamp);
}

- (void)testNextExpirationTimestampNotNilWithUpcomingExpiringMessages
{
    TSMessage *soonToExpireMessage =
        [self messageWithBody:@"soonToExpireMessage" expiresInSeconds:10 expireStartedAt:self.now - 9000];
    [soonToExpireMessage save];

    XCTAssertNotNil(self.nextExpirationTimestamp);
    XCTAssertEqual(self.now + 1000, [self.nextExpirationTimestamp unsignedLongLongValue]);

    // expired message should take precedence
    TSMessage *expiredMessage =
        [self messageWithBody:@"expiredMessage" expiresInSeconds:10 expireStartedAt:self.now - 11000];
    [expiredMessage save];

    XCTAssertNotNil(self.nextExpirationTimestamp);
    XCTAssertEqual(self.now - 1000, [self.nextExpirationTimestamp unsignedLongLongValue]);
}

@end

NS_ASSUME_NONNULL_END
