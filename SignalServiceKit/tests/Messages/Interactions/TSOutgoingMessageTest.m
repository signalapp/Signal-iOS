//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "TSOutgoingMessage.h"
#import "OWSPrimaryStorage.h"
#import "SSKBaseTestObjC.h"
#import "TSContactThread.h"

NS_ASSUME_NONNULL_BEGIN

@interface TSOutgoingMessageTest : SSKBaseTestObjC

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
                                                       contactShare:nil
                                                        linkPreview:nil];
    [self yapWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
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
                                                       contactShare:nil
                                                        linkPreview:nil];
    [self yapWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [message updateWithSentRecipient:self.contactId wasSentByUD:NO transaction:transaction];
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
                                                       contactShare:nil
                                                        linkPreview:nil];
    [self yapWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
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
                                                       contactShare:nil
                                                        linkPreview:nil];
    [self yapWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [message updateWithMarkingAllUnsentRecipientsAsSendingWithTransaction:transaction];
        XCTAssertFalse([message shouldStartExpireTimerWithTransaction:transaction]);
    }];
}

#endif

@end

NS_ASSUME_NONNULL_END
