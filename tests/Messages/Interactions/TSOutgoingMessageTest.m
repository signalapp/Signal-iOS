//  Created by Michael Kirk on 10/7/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "TSContactThread.h"
#import "TSOutgoingMessage.h"
#import <XCTest/XCTest.h>

NS_ASSUME_NONNULL_BEGIN

@interface TSOutgoingMessageTest : XCTestCase

@property (nonatomic) TSContactThread *thread;

@end

@implementation TSOutgoingMessageTest

- (void)setUp
{
    [super setUp];
    self.thread = [[TSContactThread alloc] initWithUniqueId:@"fake-thread-id"];
}

- (void)testShouldNotStartExpireTimerWithMessageThatDoesNotExpire
{
    TSOutgoingMessage *message = [[TSOutgoingMessage alloc] initWithTimestamp:100 inThread:self.thread messageBody:nil];
    XCTAssertFalse(message.shouldStartExpireTimer);
}

- (void)testShouldStartExpireTimerWithSentMessage
{
    TSOutgoingMessage *message = [[TSOutgoingMessage alloc] initWithTimestamp:100
                                                                     inThread:self.thread
                                                                  messageBody:nil
                                                                attachmentIds:[NSMutableArray new]
                                                             expiresInSeconds:10];
    message.messageState = TSOutgoingMessageStateSent;
    XCTAssert(message.shouldStartExpireTimer);
}

- (void)testShouldStartExpireTimerWithDeliveredMessage
{
    TSOutgoingMessage *message = [[TSOutgoingMessage alloc] initWithTimestamp:100
                                                                     inThread:self.thread
                                                                  messageBody:nil
                                                                attachmentIds:[NSMutableArray new]
                                                             expiresInSeconds:10];
    message.messageState = TSOutgoingMessageStateDelivered;
    XCTAssert(message.shouldStartExpireTimer);
}

- (void)testShouldNotStartExpireTimerWithUnsentMessage
{
    TSOutgoingMessage *message = [[TSOutgoingMessage alloc] initWithTimestamp:100
                                                                     inThread:self.thread
                                                                  messageBody:nil
                                                                attachmentIds:[NSMutableArray new]
                                                             expiresInSeconds:10];
    message.messageState = TSOutgoingMessageStateUnsent;
    XCTAssertFalse(message.shouldStartExpireTimer);
}

- (void)testShouldNotStartExpireTimerWithAttemptingOutMessage
{
    TSOutgoingMessage *message = [[TSOutgoingMessage alloc] initWithTimestamp:100
                                                                     inThread:self.thread
                                                                  messageBody:nil
                                                                attachmentIds:[NSMutableArray new]
                                                             expiresInSeconds:10];
    message.messageState = TSOutgoingMessageStateAttemptingOut;
    XCTAssertFalse(message.shouldStartExpireTimer);
}


@end

NS_ASSUME_NONNULL_END
