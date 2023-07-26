//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "SSKBaseTestObjC.h"
#import "TSAccountManager.h"
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

- (UntypedServiceIdObjC *)localAci
{
    return [[UntypedServiceIdObjC alloc] initWithUuidString:@"00000000-0000-4000-8000-000000000000"];
}

- (SignalServiceAddress *)localAddress
{
    return [[SignalServiceAddress alloc] initWithUntypedServiceIdObjC:[self localAci]];
}

- (UntypedServiceIdObjC *)otherAci
{
    return [[UntypedServiceIdObjC alloc] initWithUuidString:@"00000000-0000-4000-8000-000000000001"];
}

- (SignalServiceAddress *)otherAddress
{
    return [[SignalServiceAddress alloc] initWithUntypedServiceIdObjC:[self otherAci]];
}

- (void)setUp
{
    [super setUp];

    // ensure local client has necessary "registered" state
    NSString *localE164Identifier = @"+13235551234";
    NSUUID *localUUID = NSUUID.UUID;
    [self.tsAccountManager registerForTestsWithLocalNumber:localE164Identifier uuid:localUUID];

    [self writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        self.thread = [TSContactThread getOrCreateThreadWithContactAddress:self.otherAddress transaction:transaction];
    }];
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
        TSIncomingMessageBuilder *incomingMessageBuilder =
            [TSIncomingMessageBuilder incomingMessageBuilderWithThread:self.thread messageBody:body];
        incomingMessageBuilder.timestamp = timestamp;
        incomingMessageBuilder.authorAci = [self otherAci];
        incomingMessageBuilder.sourceDeviceId = 1;
        TSIncomingMessage *newMessage = [incomingMessageBuilder build];

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
        for (uint64_t i = 0; i < 10; i++) {
            TSIncomingMessageBuilder *incomingMessageBuilder =
                [TSIncomingMessageBuilder incomingMessageBuilderWithThread:self.thread messageBody:body];
            incomingMessageBuilder.timestamp = i + 1;
            incomingMessageBuilder.authorAci = [self otherAci];
            incomingMessageBuilder.sourceDeviceId = 1;
            TSIncomingMessage *newMessage = [incomingMessageBuilder build];

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

        [self.thread softDeleteThreadWithTransaction:transaction];

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
            NSUInteger memberIdx = (i % thread.groupModel.groupMembers.count);
            SignalServiceAddress *authorAddress = thread.groupModel.groupMembers[memberIdx];
            TSIncomingMessageBuilder *incomingMessageBuilder =
                [TSIncomingMessageBuilder incomingMessageBuilderWithThread:thread messageBody:body];
            incomingMessageBuilder.timestamp = i + 1;
            incomingMessageBuilder.authorAci = authorAddress.untypedServiceIdObjC;
            incomingMessageBuilder.sourceDeviceId = 1;
            TSIncomingMessage *newMessage = [incomingMessageBuilder build];
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

        [thread softDeleteThreadWithTransaction:transaction];

        for (TSIncomingMessage *message in messages) {
            TSIncomingMessage *_Nullable fetchedMessage =
                [TSIncomingMessage anyFetchIncomingMessageWithUniqueId:message.uniqueId transaction:transaction];
            XCTAssertNil(fetchedMessage, @"Message should be deleted!");
        }
    }];
}

@end
