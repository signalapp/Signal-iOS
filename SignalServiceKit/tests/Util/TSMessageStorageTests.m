//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "SSKBaseTestObjC.h"
#import "TSContactThread.h"
#import "TSGroupThread.h"
#import "TSIncomingMessage.h"
#import "TSMessage.h"
#import "TSOutgoingMessage.h"
#import "TSThread.h"
#import <SignalCoreKit/Cryptography.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

@interface TSMessageStorageTests : SSKBaseTestObjC

@property TSContactThread *thread;

@end

#pragma mark -

@implementation TSMessageStorageTests

- (SignalServiceAddress *)localAddress
{
    return [[SignalServiceAddress alloc] initWithPhoneNumber:@"+13334445555"];
}

- (SignalServiceAddress *)otherAddress
{
    return [[SignalServiceAddress alloc] initWithPhoneNumber:@"+12223334444"];
}

- (void)setUp
{
    [super setUp];

    [self writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        self.thread = [TSContactThread getOrCreateThreadWithContactAddress:self.otherAddress transaction:transaction];
    }];
}

- (void)tearDown
{
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (void)testStoreIncomingMessage
{
    __block NSString *messageId;
    uint64_t timestamp = 666;

    NSString *body
        = @"A child born today will grow up with no conception of privacy at all. They’ll never know what it means to "
          @"have a private moment to themselves an unrecorded, unanalyzed thought. And that’s a problem because "
          @"privacy matters; privacy is what allows us to determine who we are and who we want to be.";

    [self writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        TSIncomingMessage *newMessage = [[TSIncomingMessage alloc] initIncomingMessageWithTimestamp:timestamp
                                                                                           inThread:self.thread
                                                                                      authorAddress:self.otherAddress
                                                                                     sourceDeviceId:1
                                                                                        messageBody:body
                                                                                      attachmentIds:@[]
                                                                                   expiresInSeconds:0
                                                                                      quotedMessage:nil
                                                                                       contactShare:nil
                                                                                        linkPreview:nil
                                                                                     messageSticker:nil
                                                                                    serverTimestamp:nil
                                                                                    wasReceivedByUD:NO
                                                                                  isViewOnceMessage:NO];

        [newMessage anyInsertWithTransaction:transaction];
        messageId = newMessage.uniqueId;

        TSIncomingMessage *_Nullable fetchedMessage =
            [TSIncomingMessage anyFetchIncomingMessageWithUniqueId:messageId transaction:transaction];

        XCTAssertEqualObjects(body, fetchedMessage.body);
        XCTAssertFalse(fetchedMessage.hasAttachments);
        XCTAssertEqual(timestamp, fetchedMessage.timestamp);
        XCTAssertFalse(fetchedMessage.wasRead);
        XCTAssertEqualObjects(self.thread.uniqueId, fetchedMessage.uniqueThreadId);
    }];
}

- (void)testMessagesDeletedOnThreadDeletion
{
    NSString *body
        = @"A child born today will grow up with no conception of privacy at all. They’ll never know what it means to "
          @"have a private moment to themselves an unrecorded, unanalyzed thought. And that’s a problem because "
          @"privacy matters; privacy is what allows us to determine who we are and who we want to be.";

    [self writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        NSMutableArray<TSIncomingMessage *> *messages = [NSMutableArray new];
        for (int i = 0; i < 10; i++) {
            TSIncomingMessage *newMessage =
                [[TSIncomingMessage alloc] initIncomingMessageWithTimestamp:i + 1
                                                                   inThread:self.thread
                                                              authorAddress:self.otherAddress
                                                             sourceDeviceId:1
                                                                messageBody:body
                                                              attachmentIds:@[]
                                                           expiresInSeconds:0
                                                              quotedMessage:nil
                                                               contactShare:nil
                                                                linkPreview:nil
                                                             messageSticker:nil
                                                            serverTimestamp:nil
                                                            wasReceivedByUD:NO
                                                          isViewOnceMessage:NO];

            [messages addObject:newMessage];
            [newMessage anyInsertWithTransaction:transaction];
        }

        for (TSIncomingMessage *message in messages) {
            TSIncomingMessage *_Nullable fetchedMessage =
                [TSIncomingMessage anyFetchIncomingMessageWithUniqueId:message.uniqueId transaction:transaction];

            XCTAssertEqualObjects(fetchedMessage.body, body, @"Body of incoming message recovered");
            XCTAssertEqual(0, fetchedMessage.attachmentIds.count, @"attachments are nil");
            XCTAssertEqualObjects(fetchedMessage.uniqueId, message.uniqueId, @"Unique identifier is accurate");
            XCTAssertFalse(fetchedMessage.wasRead, @"Message should originally be unread");
            XCTAssertEqualObjects(
                fetchedMessage.uniqueThreadId, self.thread.uniqueId, @"Isn't stored in the right thread!");
        }

        [self.thread anyRemoveWithTransaction:transaction];

        for (TSIncomingMessage *message in messages) {
            TSIncomingMessage *_Nullable fetchedMessage =
                [TSIncomingMessage anyFetchIncomingMessageWithUniqueId:message.uniqueId transaction:transaction];
            XCTAssertNil(fetchedMessage, @"Message should be deleted!");
        }
    }];
}

- (void)testGroupMessagesDeletedOnThreadDeletion
{
    NSString *body
        = @"A child born today will grow up with no conception of privacy at all. They’ll never know what it means to "
          @"have a private moment to themselves an unrecorded, unanalyzed thought. And that’s a problem because "
          @"privacy matters; privacy is what allows us to determine who we are and who we want to be.";

    [self writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        TSGroupThread *thread = [GroupManager createGroupForTestsObjcWithMembers:@[
            self.localAddress,
            self.otherAddress,
        ]
                                                                            name:@"fdsfsd"
                                                                      avatarData:nil
                                                                     transaction:transaction];

        NSMutableArray<TSIncomingMessage *> *messages = [NSMutableArray new];
        for (uint64_t i = 0; i < 10; i++) {
            SignalServiceAddress *authorAddress = [[SignalServiceAddress alloc] initWithPhoneNumber:@"+fakephone"];
            TSIncomingMessage *newMessage = [[TSIncomingMessage alloc] initIncomingMessageWithTimestamp:i + 1
                                                                                               inThread:thread
                                                                                          authorAddress:authorAddress
                                                                                         sourceDeviceId:1
                                                                                            messageBody:body
                                                                                          attachmentIds:@[]
                                                                                       expiresInSeconds:0
                                                                                          quotedMessage:nil
                                                                                           contactShare:nil
                                                                                            linkPreview:nil
                                                                                         messageSticker:nil
                                                                                        serverTimestamp:nil
                                                                                        wasReceivedByUD:NO
                                                                                      isViewOnceMessage:NO];
            [newMessage anyInsertWithTransaction:transaction];
            [messages addObject:newMessage];
        }

        for (TSIncomingMessage *message in messages) {
            TSIncomingMessage *_Nullable fetchedMessage =
                [TSIncomingMessage anyFetchIncomingMessageWithUniqueId:message.uniqueId transaction:transaction];
            XCTAssertNotNil(fetchedMessage);
            XCTAssertEqualObjects(fetchedMessage.body, body, @"Body of incoming message recovered");
            XCTAssertEqual(0, fetchedMessage.attachmentIds.count, @"attachments are empty");
            XCTAssertEqualObjects(fetchedMessage.uniqueId, message.uniqueId, @"Unique identifier is accurate");
            XCTAssertFalse(fetchedMessage.wasRead, @"Message should originally be unread");
            XCTAssertEqualObjects(fetchedMessage.uniqueThreadId, thread.uniqueId, @"Isn't stored in the right thread!");
        }

        [thread anyRemoveWithTransaction:transaction];

        for (TSIncomingMessage *message in messages) {
            TSIncomingMessage *_Nullable fetchedMessage =
                [TSIncomingMessage anyFetchIncomingMessageWithUniqueId:message.uniqueId transaction:transaction];
            XCTAssertNil(fetchedMessage, @"Message should be deleted!");
        }
    }];
}

@end
