//
//  TSMessageStorageTests.m
//  TextSecureKit
//
//  Created by Frederic Jacobs on 16/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <XCTest/XCTest.h>

#import "Cryptography.h"
#import "TSThread.h"
#import "TSContactThread.h"
#import "TSGroupThread.h"

#import "TSStorageManager.h"

#import "TSMessage.h"
#import "TSIncomingMessage.h"


@interface TSMessageStorageTests : XCTestCase

@property TSContactThread *thread;

@end

@implementation TSMessageStorageTests

- (void)setUp
{
    [super setUp];
    
    [[TSStorageManager sharedManager].dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        self.thread = [TSContactThread getOrCreateThreadWithContactId:@"aStupidId" transaction:transaction];
        
        [self.thread saveWithTransaction:transaction];
    }];
    
    TSStorageManager *manager = [TSStorageManager sharedManager];
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
    [[TSStorageManager sharedManager].newDatabaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        
        NSString* messageId;
        
        for (uint64_t i = 0; i<50; i++) {
            TSIncomingMessage *newMessage =
                [[TSIncomingMessage alloc] initWithTimestamp:i inThread:self.thread messageBody:body attachmentIds:nil];
            [newMessage saveWithTransaction:transaction];
            if (i == 0) {
                messageId = newMessage.uniqueId;
             }
        }
        
        messageInt = [messageId integerValue];
        
        for (NSInteger i = messageInt; i < messageInt+50; i++) {
            TSIncomingMessage *message = [TSIncomingMessage fetchObjectWithUniqueID:[@(i) stringValue] transaction:transaction];
            XCTAssert(message != nil);
            XCTAssert(message.body == body);
        }
    }];
    
    [[TSStorageManager sharedManager].newDatabaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        TSIncomingMessage *deletedmessage = [TSIncomingMessage fetchObjectWithUniqueID:[@(messageInt+49) stringValue]];
        [deletedmessage removeWithTransaction:transaction];
        
        uint64_t uniqueNewTimestamp = 985439854983;
        TSIncomingMessage *newMessage = [[TSIncomingMessage alloc] initWithTimestamp:uniqueNewTimestamp
                                                                            inThread:self.thread
                                                                         messageBody:body
                                                                       attachmentIds:nil];
        [newMessage saveWithTransaction:transaction];
        
        TSIncomingMessage *retrieved = [TSIncomingMessage fetchObjectWithUniqueID:[@(messageInt+50) stringValue] transaction:transaction];
        XCTAssert(retrieved.timestamp == uniqueNewTimestamp);
    }];
}

- (void)testStoreIncomingMessage
{
    __block NSString *messageId;
    uint64_t timestamp = 666;
    
    NSString *body = @"A child born today will grow up with no conception of privacy at all. They’ll never know what it means to have a private moment to themselves an unrecorded, unanalyzed thought. And that’s a problem because privacy matters; privacy is what allows us to determine who we are and who we want to be.";

    TSIncomingMessage *newMessage =
        [[TSIncomingMessage alloc] initWithTimestamp:timestamp inThread:self.thread messageBody:body attachmentIds:nil];
    [[TSStorageManager sharedManager].newDatabaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [newMessage saveWithTransaction:transaction];
        messageId = newMessage.uniqueId;
    }];
    
    TSIncomingMessage *fetchedMessage = [TSIncomingMessage fetchObjectWithUniqueID:messageId];
    
    NSAssert([fetchedMessage.body isEqualToString:body], @"Body of incoming message recovered");
    NSAssert(fetchedMessage.attachmentIds == nil, @"attachments are nil");
    NSAssert(fetchedMessage.timestamp == timestamp, @"Unique identifier is accurate");
    NSAssert(fetchedMessage.wasRead == false, @"Message should originally be unread");
    NSAssert([fetchedMessage.uniqueThreadId isEqualToString:self.thread.uniqueId], @"Isn't stored in the right thread!");
}

- (void)testMessagesDeletedOnThreadDeletion
{
    uint64_t timestamp = 666;
    NSString *body = @"A child born today will grow up with no conception of privacy at all. They’ll never know what it means to have a private moment to themselves an unrecorded, unanalyzed thought. And that’s a problem because privacy matters; privacy is what allows us to determine who we are and who we want to be.";
    
    for (uint64_t i = timestamp; i<100; i++) {
        TSIncomingMessage *newMessage =
            [[TSIncomingMessage alloc] initWithTimestamp:i inThread:self.thread messageBody:body attachmentIds:nil];
        [newMessage save];
    }
    
    
    
    [[TSStorageManager sharedManager].dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        for (uint64_t i = timestamp; i<100; i++) {
            TSIncomingMessage *fetchedMessage = [TSIncomingMessage fetchObjectWithUniqueID:[TSInteraction stringFromTimeStamp:timestamp] transaction:transaction];
            
            NSAssert([fetchedMessage.body isEqualToString:body], @"Body of incoming message recovered");
            NSAssert(fetchedMessage.attachmentIds == nil, @"attachments are nil");
            NSAssert([fetchedMessage.uniqueId isEqualToString:[TSInteraction stringFromTimeStamp:timestamp]], @"Unique identifier is accurate");
            NSAssert(fetchedMessage.wasRead == false, @"Message should originally be unread");
            NSAssert([fetchedMessage.uniqueThreadId isEqualToString:self.thread.uniqueId], @"Isn't stored in the right thread!");
        }
    }];
    
    
    [self.thread remove];
    
    [[TSStorageManager sharedManager].dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        for (uint64_t i = timestamp; i<100; i++) {
            TSIncomingMessage *fetchedMessage = [TSIncomingMessage fetchObjectWithUniqueID:[TSInteraction stringFromTimeStamp:timestamp] transaction:transaction];
            NSAssert(fetchedMessage == nil, @"Message should be deleted!");
        }
    }];
}


- (void)testGroupMessagesDeletedOnThreadDeletion
{
    uint64_t timestamp = 666;
    NSString *body = @"A child born today will grow up with no conception of privacy at all. They’ll never know what it means to have a private moment to themselves an unrecorded, unanalyzed thought. And that’s a problem because privacy matters; privacy is what allows us to determine who we are and who we want to be.";
    
    
    TSAttachmentStream *pointer = [[TSAttachmentStream alloc] initWithIdentifier:@"helloid" data:[Cryptography generateRandomBytes:16] key:[Cryptography generateRandomBytes:16] contentType:@"data/random"];

    __block TSGroupThread *thread;
    [[TSStorageManager sharedManager].dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        thread = [TSGroupThread getOrCreateThreadWithGroupModel:[[TSGroupModel alloc] initWithTitle:@"fdsfsd" memberIds:[@[] mutableCopy] image:nil groupId:[NSData data] associatedAttachmentId:pointer.uniqueId] transaction:transaction];
        
        [thread saveWithTransaction:transaction];
        [pointer saveWithTransaction:transaction];

    }];
    
    TSStorageManager *manager         = [TSStorageManager sharedManager];
    [manager purgeCollection:[TSMessage collection]];
    
    for (uint64_t i = timestamp; i<100; i++) {
        TSIncomingMessage *newMessage = [[TSIncomingMessage alloc] initWithTimestamp:i
                                                                            inThread:thread
                                                                            authorId:@"Ed"
                                                                         messageBody:body
                                                                       attachmentIds:nil];

        [newMessage save];
    }
    
    
    
    [[TSStorageManager sharedManager].dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        for (uint64_t i = timestamp; i<100; i++) {
            TSIncomingMessage *fetchedMessage = [TSIncomingMessage fetchObjectWithUniqueID:[TSInteraction stringFromTimeStamp:timestamp] transaction:transaction];
            TSAttachmentStream *fetchedPointer = [TSAttachmentStream fetchObjectWithUniqueID:pointer.uniqueId];
            NSAssert([fetchedPointer.image isEqual:pointer.image], @"attachment pointers not equal");
            
            
            NSAssert([fetchedMessage.body isEqualToString:body], @"Body of incoming message recovered");
            NSAssert(fetchedMessage.attachmentIds == nil, @"attachments are nil");
            NSAssert([fetchedMessage.uniqueId isEqualToString:[TSInteraction stringFromTimeStamp:timestamp]], @"Unique identifier is accurate");
            NSAssert(fetchedMessage.wasRead == false, @"Message should originally be unread");
            NSAssert([fetchedMessage.uniqueThreadId isEqualToString:self.thread.uniqueId], @"Isn't stored in the right thread!");
        }
    }];
    
    
    [self.thread remove];
    
    [[TSStorageManager sharedManager].dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        for (uint64_t i = timestamp; i<100; i++) {
            TSIncomingMessage *fetchedMessage = [TSIncomingMessage fetchObjectWithUniqueID:[TSInteraction stringFromTimeStamp:timestamp] transaction:transaction];
            TSAttachmentStream *fetchedPointer = [TSAttachmentStream fetchObjectWithUniqueID:pointer.uniqueId];
            NSAssert(fetchedPointer == nil, @"Attachment pointer should be deleted");
            NSAssert(fetchedMessage == nil, @"Message should be deleted!");
        }
    }];
}

@end
