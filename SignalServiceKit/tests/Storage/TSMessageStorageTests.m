//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "Cryptography.h"
#import "OWSPrimaryStorage.h"
#import "SSKBaseTest.h"
#import "TSContactThread.h"
#import "TSGroupThread.h"
#import "TSIncomingMessage.h"
#import "TSMessage.h"
#import "TSOutgoingMessage.h"
#import "TSThread.h"

@interface TSMessageStorageTests : SSKBaseTest

@property TSContactThread *thread;

@end

@implementation TSMessageStorageTests

- (void)setUp
{
    [super setUp];

    [[OWSPrimaryStorage sharedManager].dbReadWriteConnection
        readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            self.thread = [TSContactThread getOrCreateThreadWithContactId:@"aStupidId" transaction:transaction];

            [self.thread saveWithTransaction:transaction];
        }];

    OWSPrimaryStorage *manager = [OWSPrimaryStorage sharedManager];
    [manager purgeCollection:[TSMessage collection]];
}

- (void)tearDown
{
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (void)testIncrementalMessageNumbers
{
    __block NSInteger messageInt;
    NSString *body = @"I don't see myself as a hero because what I'm doing is self-interested: I don't want to live in a world where there's no privacy and therefore no room for intellectual exploration and creativity.";
    [[OWSPrimaryStorage sharedManager].newDatabaseConnection readWriteWithBlock:^(
        YapDatabaseReadWriteTransaction *transaction) {
        NSString* messageId;
        
        for (uint64_t i = 0; i<50; i++) {
            TSOutgoingMessage *newMessage =
                [[TSOutgoingMessage alloc] initWithTimestamp:i inThread:self.thread messageBody:body];
            [newMessage saveWithTransaction:transaction];
            if (i == 0) {
                messageId = newMessage.uniqueId;
            }
        }
        
        messageInt = [messageId integerValue];
        
        for (NSInteger i = messageInt; i < messageInt+50; i++) {
            TSOutgoingMessage *message =
                [TSOutgoingMessage fetchObjectWithUniqueID:[@(i) stringValue] transaction:transaction];
            XCTAssert(message != nil);
            XCTAssert(message.body == body);
        }
    }];

    [[OWSPrimaryStorage sharedManager].newDatabaseConnection
        readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            TSOutgoingMessage *deletedmessage =
                [TSOutgoingMessage fetchObjectWithUniqueID:[@(messageInt + 49) stringValue]];
            [deletedmessage removeWithTransaction:transaction];

            uint64_t uniqueNewTimestamp = 985439854983;
            TSOutgoingMessage *newMessage =
                [[TSOutgoingMessage alloc] initWithTimestamp:uniqueNewTimestamp inThread:self.thread messageBody:body];
            [newMessage saveWithTransaction:transaction];

            TSOutgoingMessage *retrieved =
                [TSOutgoingMessage fetchObjectWithUniqueID:[@(messageInt + 50) stringValue] transaction:transaction];
            XCTAssertEqual(uniqueNewTimestamp, retrieved.timestamp);
        }];
}

- (void)testStoreIncomingMessage
{
    __block NSString *messageId;
    uint64_t timestamp = 666;
    
    NSString *body = @"A child born today will grow up with no conception of privacy at all. They’ll never know what it means to have a private moment to themselves an unrecorded, unanalyzed thought. And that’s a problem because privacy matters; privacy is what allows us to determine who we are and who we want to be.";

    TSIncomingMessage *newMessage = [[TSIncomingMessage alloc] initWithTimestamp:timestamp
                                                                        inThread:self.thread
                                                                        authorId:[self.thread contactIdentifier]
                                                                  sourceDeviceId:1
                                                                     messageBody:body];
    [[OWSPrimaryStorage sharedManager].newDatabaseConnection
        readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            [newMessage saveWithTransaction:transaction];
            messageId = newMessage.uniqueId;
        }];

    TSIncomingMessage *fetchedMessage = [TSIncomingMessage fetchObjectWithUniqueID:messageId];

    XCTAssertEqualObjects(body, fetchedMessage.body);
    XCTAssertFalse(fetchedMessage.hasAttachments);
    XCTAssertEqual(timestamp, fetchedMessage.timestamp);
    XCTAssertFalse(fetchedMessage.wasRead);
    XCTAssertEqualObjects(self.thread.uniqueId, fetchedMessage.uniqueThreadId);
}

- (void)testMessagesDeletedOnThreadDeletion
{
    NSString *body = @"A child born today will grow up with no conception of privacy at all. They’ll never know what it means to have a private moment to themselves an unrecorded, unanalyzed thought. And that’s a problem because privacy matters; privacy is what allows us to determine who we are and who we want to be.";

    NSMutableArray<TSIncomingMessage *> *messages = [NSMutableArray new];
    for (int i = 0; i < 10; i++) {
        TSIncomingMessage *newMessage = [[TSIncomingMessage alloc] initWithTimestamp:i
                                                                            inThread:self.thread
                                                                            authorId:[self.thread contactIdentifier]
                                                                      sourceDeviceId:1
                                                                         messageBody:body];
        [messages addObject:newMessage];
        [newMessage save];
    }

    for (TSIncomingMessage *message in messages) {
        TSIncomingMessage *fetchedMessage = [TSIncomingMessage fetchObjectWithUniqueID:message.uniqueId];

        XCTAssertEqualObjects(fetchedMessage.body, body, @"Body of incoming message recovered");
        XCTAssertEqual(0, fetchedMessage.attachmentIds.count, @"attachments are nil");
        XCTAssertEqualObjects(fetchedMessage.uniqueId, message.uniqueId, @"Unique identifier is accurate");
        XCTAssertFalse(fetchedMessage.wasRead, @"Message should originally be unread");
        XCTAssertEqualObjects(
            fetchedMessage.uniqueThreadId, self.thread.uniqueId, @"Isn't stored in the right thread!");
    }

    [self.thread remove];

    for (TSIncomingMessage *message in messages) {
        TSIncomingMessage *fetchedMessage = [TSIncomingMessage fetchObjectWithUniqueID:message.uniqueId];
        XCTAssertNil(fetchedMessage, @"Message should be deleted!");
    }
}


- (void)testGroupMessagesDeletedOnThreadDeletion
{
    NSString *body = @"A child born today will grow up with no conception of privacy at all. They’ll never know what it means to have a private moment to themselves an unrecorded, unanalyzed thought. And that’s a problem because privacy matters; privacy is what allows us to determine who we are and who we want to be.";

    __block TSGroupThread *thread;
    [[OWSPrimaryStorage sharedManager].dbReadWriteConnection readWriteWithBlock:^(
        YapDatabaseReadWriteTransaction *transaction) {
        thread = [TSGroupThread getOrCreateThreadWithGroupModel:[[TSGroupModel alloc] initWithTitle:@"fdsfsd"
                                                                                          memberIds:[@[] mutableCopy]
                                                                                              image:nil
                                                                                            groupId:[NSData data]]
                                                    transaction:transaction];

        [thread saveWithTransaction:transaction];
    }];

    OWSPrimaryStorage *manager = [OWSPrimaryStorage sharedManager];
    [manager purgeCollection:[TSMessage collection]];

    NSMutableArray<TSIncomingMessage *> *messages = [NSMutableArray new];
    for (uint64_t i = 0; i < 10; i++) {
        TSIncomingMessage *newMessage = [[TSIncomingMessage alloc] initWithTimestamp:i
                                                                            inThread:thread
                                                                            authorId:@"Ed"
                                                                      sourceDeviceId:1
                                                                         messageBody:body];
        [newMessage save];
        [messages addObject:newMessage];
    }

    for (TSIncomingMessage *message in messages) {
        TSIncomingMessage *fetchedMessage = [TSIncomingMessage fetchObjectWithUniqueID:message.uniqueId];
        XCTAssertNotNil(fetchedMessage);
        XCTAssertEqualObjects(fetchedMessage.body, body, @"Body of incoming message recovered");
        XCTAssertEqual(0, fetchedMessage.attachmentIds.count, @"attachments are empty");
        XCTAssertEqualObjects(fetchedMessage.uniqueId, message.uniqueId, @"Unique identifier is accurate");
        XCTAssertFalse(fetchedMessage.wasRead, @"Message should originally be unread");
        XCTAssertEqualObjects(fetchedMessage.uniqueThreadId, thread.uniqueId, @"Isn't stored in the right thread!");
    }

    [thread remove];

    for (TSIncomingMessage *message in messages) {
        TSIncomingMessage *fetchedMessage = [TSIncomingMessage fetchObjectWithUniqueID:message.uniqueId];
        XCTAssertNil(fetchedMessage, @"Message should be deleted!");
    }
}

@end
