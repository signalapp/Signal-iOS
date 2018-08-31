//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSDisappearingMessagesJob.h"
#import "NSDate+OWS.h"
#import "OWSDisappearingMessagesConfiguration.h"
#import "OWSDisappearingMessagesFinder.h"
#import "OWSFakeContactsManager.h"
#import "TSContactThread.h"
#import "TSMessage.h"
#import <XCTest/XCTest.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSDisappearingMessagesJob (Testing)

- (void)run;
- (void)becomeConsistentWithConfigurationForMessage:(TSMessage *)message
                                    contactsManager:(id<ContactsManagerProtocol>)contactsManager;
@end

@interface OWSDisappearingMessagesJobTest : XCTestCase

@property TSThread *thread;

@end

@implementation OWSDisappearingMessagesJobTest

- (void)setUp
{
    [super setUp];
    [TSMessage removeAllObjectsInCollection];
    self.thread = [TSContactThread getOrCreateThreadWithContactId:@"fake-thread-id"];
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
    [job run];
    
    //FIXME remove sleep hack in favor of expiringMessage completion handler
    sleep(4);
    XCTAssertEqual(2, [TSMessage numberOfKeysInCollection]);
}

- (void)testBecomeConsistentWithMessageConfiguration
{
    OWSDisappearingMessagesJob *job = [OWSDisappearingMessagesJob sharedJob];

    OWSDisappearingMessagesConfiguration *configuration =
        [OWSDisappearingMessagesConfiguration fetchObjectWithUniqueID:self.thread.uniqueId];
    [configuration remove];

    TSMessage *expiringMessage = [self messageWithBody:@"notYetExpiredMessage" expiresInSeconds:20 expireStartedAt:0];
    [expiringMessage save];

    [job becomeConsistentWithConfigurationForMessage:expiringMessage contactsManager:[OWSFakeContactsManager new]];
    configuration = [OWSDisappearingMessagesConfiguration fetchObjectWithUniqueID:self.thread.uniqueId];

    XCTAssertNotNil(configuration);
    XCTAssert(configuration.isEnabled);
    XCTAssertEqual(20, configuration.durationSeconds);
}

- (void)testBecomeConsistentWithUnexpiringMessageConfiguration
{
    OWSDisappearingMessagesConfiguration *configuration =
        [OWSDisappearingMessagesConfiguration fetchObjectWithUniqueID:self.thread.uniqueId];
    [configuration remove];

    TSMessage *unExpiringMessage = [self messageWithBody:@"unexpiringMessage" expiresInSeconds:0 expireStartedAt:0];
    [unExpiringMessage save];
    [OWSDisappearingMessagesJob.sharedJob becomeConsistentWithConfigurationForMessage:unExpiringMessage
                                                                      contactsManager:[OWSFakeContactsManager new]];

    XCTAssertNil([OWSDisappearingMessagesConfiguration fetchObjectWithUniqueID:self.thread.uniqueId]);
}

@end

NS_ASSUME_NONNULL_END
