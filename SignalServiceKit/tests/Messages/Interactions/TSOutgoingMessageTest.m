//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "SSKBaseTestObjC.h"
#import "TSContactThread.h"
#import "TSOutgoingMessage.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface TSOutgoingMessageTest : SSKBaseTestObjC

@end

#pragma mark -

@implementation TSOutgoingMessageTest

- (void)setUp
{
    [super setUp];
}

- (void)testShouldNotStartExpireTimerWithMessageThatDoesNotExpire
{
    [self writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        SignalServiceAddress *otherAddress = [CommonGenerator address];
        TSContactThread *thread = [TSContactThread getOrCreateThreadWithContactAddress:otherAddress
                                                                           transaction:transaction];
        TSOutgoingMessageBuilder *messageBuilder = [TSOutgoingMessageBuilder outgoingMessageBuilderWithThread:thread
                                                                                                  messageBody:nil];
        messageBuilder.timestamp = 100;
        TSOutgoingMessage *message = [messageBuilder build];

        XCTAssertFalse([message shouldStartExpireTimer]);
    }];
}

- (void)testShouldStartExpireTimerWithSentMessage
{
    [self writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        SignalServiceAddress *otherAddress = [[SignalServiceAddress alloc] initWithPhoneNumber:@"+12223334444"];
        TSContactThread *thread = [TSContactThread getOrCreateThreadWithContactAddress:otherAddress
                                                                           transaction:transaction];
        TSOutgoingMessageBuilder *messageBuilder = [TSOutgoingMessageBuilder outgoingMessageBuilderWithThread:thread
                                                                                                  messageBody:nil];
        messageBuilder.timestamp = 100;
        messageBuilder.expiresInSeconds = 10;
        TSOutgoingMessage *message = [messageBuilder build];

        [message updateWithSentRecipient:otherAddress wasSentByUD:NO transaction:transaction];
        
        XCTAssertTrue([message shouldStartExpireTimer]);
    }];
}

- (void)testShouldNotStartExpireTimerWithUnsentMessage
{
    [self writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        SignalServiceAddress *otherAddress = [[SignalServiceAddress alloc] initWithPhoneNumber:@"+12223334444"];
        TSContactThread *thread = [TSContactThread getOrCreateThreadWithContactAddress:otherAddress
                                                                           transaction:transaction];
        TSOutgoingMessageBuilder *messageBuilder = [TSOutgoingMessageBuilder outgoingMessageBuilderWithThread:thread
                                                                                                  messageBody:nil];
        messageBuilder.timestamp = 100;
        messageBuilder.expiresInSeconds = 10;
        TSOutgoingMessage *message = [messageBuilder build];

        XCTAssertFalse([message shouldStartExpireTimer]);
    }];
}

- (void)testShouldNotStartExpireTimerWithAttemptingOutMessage
{
    [self writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        SignalServiceAddress *otherAddress = [[SignalServiceAddress alloc] initWithPhoneNumber:@"+12223334444"];
        TSContactThread *thread = [TSContactThread getOrCreateThreadWithContactAddress:otherAddress
                                                                           transaction:transaction];
        TSOutgoingMessageBuilder *messageBuilder = [TSOutgoingMessageBuilder outgoingMessageBuilderWithThread:thread
                                                                                                  messageBody:nil];
        messageBuilder.timestamp = 100;
        messageBuilder.expiresInSeconds = 10;
        TSOutgoingMessage *message = [messageBuilder build];

        [message updateAllUnsentRecipientsAsSendingWithTransaction:transaction];

        XCTAssertFalse([message shouldStartExpireTimer]);
    }];
}

@end

NS_ASSUME_NONNULL_END
