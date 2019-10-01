//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
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
        TSOutgoingMessage *message =
        [[TSOutgoingMessage alloc] initOutgoingMessageWithTimestamp:100
                                                           inThread:thread
                                                        messageBody:nil
                                                      attachmentIds:[NSMutableArray new]
                                                   expiresInSeconds:0
                                                    expireStartedAt:0
                                                     isVoiceMessage:NO
                                                   groupMetaMessage:TSGroupMetaMessageUnspecified
                                                      quotedMessage:nil
                                                       contactShare:nil
                                                        linkPreview:nil
                                                     messageSticker:nil
                                                  isViewOnceMessage:NO];
        
        XCTAssertFalse([message shouldStartExpireTimer]);
    }];
}

- (void)testShouldStartExpireTimerWithSentMessage
{
    [self writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        SignalServiceAddress *otherAddress = [[SignalServiceAddress alloc] initWithPhoneNumber:@"+12223334444"];
        TSContactThread *thread = [TSContactThread getOrCreateThreadWithContactAddress:otherAddress
                                                                           transaction:transaction];
    TSOutgoingMessage *message =
        [[TSOutgoingMessage alloc] initOutgoingMessageWithTimestamp:100
                                                           inThread:thread
                                                        messageBody:nil
                                                      attachmentIds:[NSMutableArray new]
                                                   expiresInSeconds:10
                                                    expireStartedAt:0
                                                     isVoiceMessage:NO
                                                   groupMetaMessage:TSGroupMetaMessageUnspecified
                                                      quotedMessage:nil
                                                       contactShare:nil
                                                        linkPreview:nil
                                                     messageSticker:nil
                                                  isViewOnceMessage:NO];
        
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
    TSOutgoingMessage *message =
        [[TSOutgoingMessage alloc] initOutgoingMessageWithTimestamp:100
                                                           inThread:thread
                                                        messageBody:nil
                                                      attachmentIds:[NSMutableArray new]
                                                   expiresInSeconds:10
                                                    expireStartedAt:0
                                                     isVoiceMessage:NO
                                                   groupMetaMessage:TSGroupMetaMessageUnspecified
                                                      quotedMessage:nil
                                                       contactShare:nil
                                                        linkPreview:nil
                                                     messageSticker:nil
                                                  isViewOnceMessage:NO];

        XCTAssertFalse([message shouldStartExpireTimer]);
    }];
}

- (void)testShouldNotStartExpireTimerWithAttemptingOutMessage
{
    [self writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        SignalServiceAddress *otherAddress = [[SignalServiceAddress alloc] initWithPhoneNumber:@"+12223334444"];
        TSContactThread *thread = [TSContactThread getOrCreateThreadWithContactAddress:otherAddress
                                                                           transaction:transaction];
    TSOutgoingMessage *message =
        [[TSOutgoingMessage alloc] initOutgoingMessageWithTimestamp:100
                                                           inThread:thread
                                                        messageBody:nil
                                                      attachmentIds:[NSMutableArray new]
                                                   expiresInSeconds:10
                                                    expireStartedAt:0
                                                     isVoiceMessage:NO
                                                   groupMetaMessage:TSGroupMetaMessageUnspecified
                                                      quotedMessage:nil
                                                       contactShare:nil
                                                        linkPreview:nil
                                                     messageSticker:nil
                                                  isViewOnceMessage:NO];

        [message updateAllUnsentRecipientsAsSendingWithTransaction:transaction];

        XCTAssertFalse([message shouldStartExpireTimer]);
    }];
}

@end

NS_ASSUME_NONNULL_END
