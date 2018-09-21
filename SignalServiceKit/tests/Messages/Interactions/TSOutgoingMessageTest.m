//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSOutgoingMessage.h"
#import "OWSPrimaryStorage.h"
#import "SSKBaseTest.h"
#import "TSContactThread.h"

NS_ASSUME_NONNULL_BEGIN

@interface TSOutgoingMessageTest : SSKBaseTest

@property (nonatomic) TSContactThread *thread;

@end

@implementation TSOutgoingMessageTest

#ifdef BROKEN_TESTS

- (NSString *)contactId
{
    return @"fake-thread-id";
}

- (void)setUp
{
    [super setUp];
    self.thread = [[TSContactThread alloc] initWithUniqueId:self.contactId];
}

- (void)testShouldNotStartExpireTimerWithMessageThatDoesNotExpire
{
    TSOutgoingMessage *message =
        [[TSOutgoingMessage alloc] initOutgoingMessageWithTimestamp:100
                                                           inThread:self.thread
                                                        messageBody:nil
                                                      attachmentIds:[NSMutableArray new]
                                                   expiresInSeconds:0
                                                    expireStartedAt:0
                                                     isVoiceMessage:NO
                                                   groupMetaMessage:TSGroupMetaMessageUnspecified
                                                      quotedMessage:nil
                                                       contactShare:nil];
    [self readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        XCTAssertFalse([message shouldStartExpireTimerWithTransaction:transaction]);
    }];
}

- (void)testShouldStartExpireTimerWithSentMessage
{
    TSOutgoingMessage *message =
        [[TSOutgoingMessage alloc] initOutgoingMessageWithTimestamp:100
                                                           inThread:self.thread
                                                        messageBody:nil
                                                      attachmentIds:[NSMutableArray new]
                                                   expiresInSeconds:10
                                                    expireStartedAt:0
                                                     isVoiceMessage:NO
                                                   groupMetaMessage:TSGroupMetaMessageUnspecified
                                                      quotedMessage:nil
                                                       contactShare:nil];
    [self readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [message updateWithSentRecipient:self.contactId transaction:transaction];
        XCTAssertTrue([message shouldStartExpireTimerWithTransaction:transaction]);
    }];
}

- (void)testShouldNotStartExpireTimerWithUnsentMessage
{
    TSOutgoingMessage *message =
        [[TSOutgoingMessage alloc] initOutgoingMessageWithTimestamp:100
                                                           inThread:self.thread
                                                        messageBody:nil
                                                      attachmentIds:[NSMutableArray new]
                                                   expiresInSeconds:10
                                                    expireStartedAt:0
                                                     isVoiceMessage:NO
                                                   groupMetaMessage:TSGroupMetaMessageUnspecified
                                                      quotedMessage:nil
                                                       contactShare:nil];
    [self readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        XCTAssertFalse([message shouldStartExpireTimerWithTransaction:transaction]);
    }];
}

- (void)testShouldNotStartExpireTimerWithAttemptingOutMessage
{
    TSOutgoingMessage *message =
        [[TSOutgoingMessage alloc] initOutgoingMessageWithTimestamp:100
                                                           inThread:self.thread
                                                        messageBody:nil
                                                      attachmentIds:[NSMutableArray new]
                                                   expiresInSeconds:10
                                                    expireStartedAt:0
                                                     isVoiceMessage:NO
                                                   groupMetaMessage:TSGroupMetaMessageUnspecified
                                                      quotedMessage:nil
                                                       contactShare:nil];
    [self readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [message updateWithMarkingAllUnsentRecipientsAsSendingWithTransaction:transaction];
        XCTAssertFalse([message shouldStartExpireTimerWithTransaction:transaction]);
    }];
}

#endif

@end

NS_ASSUME_NONNULL_END
