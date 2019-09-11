//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSDisappearingMessagesJob.h"
#import "OWSDisappearingMessagesConfiguration.h"
#import "OWSDisappearingMessagesFinder.h"
#import "SSKBaseTestObjC.h"
#import "TSContactThread.h"
#import "TSMessage.h"
#import <SignalCoreKit/NSDate+OWS.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef BROKEN_TESTS

@interface OWSDisappearingMessagesJob (Testing)

- (NSUInteger)runLoop;

@end

@interface OWSDisappearingMessagesJobTest : SSKBaseTestObjC

@property TSThread *thread;

@end

@implementation OWSDisappearingMessagesJobTest

- (void)setUp
{
    [super setUp];

    // NOTE: Certain parts of the codebase assert that contact ids are valid e164
    // phone numbers.
    self.thread = [TSContactThread getOrCreateThreadWithContactId:@"+19999999999"];
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
                                          contactShare:nil
                                           linkPreview:nil];
}

#ifdef BROKEN_TESTS

- (void)testRemoveAnyExpiredMessage
{
    uint64_t now = [NSDate ows_millisecondTimeStamp];
    TSMessage *expiredMessage1 =
        [self messageWithBody:@"expiredMessage1" expiresInSeconds:1 expireStartedAt:now - 20000];
    [expiredMessage1 save];

    TSMessage *expiredMessage2 =
        [self messageWithBody:@"expiredMessage2" expiresInSeconds:2 expireStartedAt:now - 2001];
    [expiredMessage2 save];

    TSMessage *notYetExpiredMessage =
        [self messageWithBody:@"notYetExpiredMessage" expiresInSeconds:20 expireStartedAt:now - 10000];
    [notYetExpiredMessage save];

    TSMessage *unExpiringMessage = [self messageWithBody:@"unexpiringMessage" expiresInSeconds:0 expireStartedAt:0];
    [unExpiringMessage save];

    
    OWSDisappearingMessagesJob *job = [OWSDisappearingMessagesJob sharedJob];

    // Sanity Check.
    XCTAssertEqual(4, [TSMessage numberOfKeysInCollection]);
    [job runLoop];

    //FIXME remove sleep hack in favor of expiringMessage completion handler
    sleep(4);
    XCTAssertEqual(2, [TSMessage numberOfKeysInCollection]);
}

#endif

- (void)testBecomeConsistentWithMessageConfiguration
{
    OWSDisappearingMessagesJob *job = [OWSDisappearingMessagesJob sharedJob];

    [self readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        OWSDisappearingMessagesConfiguration *configuration;
        configuration = [self.thread disappearingMessagesConfigurationWithTransaction:transaction.asAnyRead];
        [configuration anyRemoveWithTransaction:transaction.asAnyWrite];
    }];

    TSMessage *expiringMessage = [self messageWithBody:@"notYetExpiredMessage" expiresInSeconds:20 expireStartedAt:0];
    [expiringMessage save];

    [self
        readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            [job becomeConsistentWithConfigurationForMessage:expiringMessage
                                             contactsManager:[OWSFakeContactsManager new]
                                                 transaction:transaction];

            OWSDisappearingMessagesConfiguration *configuration;
            configuration = [self.thread disappearingMessagesConfigurationWithTransaction:transaction.asAnyRead];
            XCTAssertNotNil(configuration);
        }];

    XCTAssert(configuration.isEnabled);
    XCTAssertEqual(20, configuration.durationSeconds);
}

- (void)testBecomeConsistentWithUnexpiringMessageConfiguration
{
    OWSDisappearingMessagesJob *job = [OWSDisappearingMessagesJob sharedJob];

    [self readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        OWSDisappearingMessagesConfiguration *configuration;
        configuration = [self.thread disappearingMessagesConfigurationWithTransaction:transaction.asAnyRead];
        [configuration anyRemoveWithTransaction:transaction.asAnyWrite];
    }];

    TSMessage *unExpiringMessage = [self messageWithBody:@"unexpiringMessage" expiresInSeconds:0 expireStartedAt:0];
    [unExpiringMessage save];
    [self readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [job becomeConsistentWithConfigurationForMessage:unExpiringMessage
                                         contactsManager:[OWSFakeContactsManager new]
                                             transaction:transaction];
    }];

    [self readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        XCTAssertNil([self.thread disappearingMessagesConfigurationWithTransaction:transaction.asAnyRead]);
    }];
}

@end

#endif

NS_ASSUME_NONNULL_END
