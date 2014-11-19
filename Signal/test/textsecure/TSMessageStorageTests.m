//
//  TSMessageStorageTests.m
//  TextSecureKit
//
//  Created by Frederic Jacobs on 16/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <XCTest/XCTest.h>

#import "TSThread.h"
#import "TSContactThread.h"
#import "TSGroupThread.h"

#import "TSStorageManager.h"

#import "TSMessage.h"
#import "TSErrorMessage.h"
#import "TSInfoMessage.h"
#import "TSIncomingMessage.h"
#import "TSCall.h"
#import "TSOutgoingMessage.h"


@interface TSMessageStorageTests : XCTestCase

@property TSContactThread *thread;

@end

@implementation TSMessageStorageTests

- (void)setUp {
    [super setUp];
    
    self.thread = [TSContactThread threadWithContactId:@"aStupidId"];
    
    [self.thread save];
    
    TSStorageManager *manager = [TSStorageManager sharedManager];
    [manager purgeCollection:[TSMessage collection]];
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (void)testStoreIncomingMessage {
    uint64_t timestamp = 666;
    
    NSString *body = @"A child born today will grow up with no conception of privacy at all. They’ll never know what it means to have a private moment to themselves an unrecorded, unanalyzed thought. And that’s a problem because privacy matters; privacy is what allows us to determine who we are and who we want to be.";
    
    TSIncomingMessage *newMessage = [[TSIncomingMessage alloc] initWithTimestamp:timestamp
                                                                        inThread:self.thread
                                                                     messageBody:body
                                                                    attachements:nil];
    [newMessage save];
    
    
    TSIncomingMessage *fetchedMessage = [TSIncomingMessage fetchObjectWithUniqueID:[TSInteraction stringFromTimeStamp:timestamp]];
    
    NSAssert([fetchedMessage.body isEqualToString:body], @"Body of incoming message recovered");
    NSAssert(fetchedMessage.attachements == nil, @"Attachements are nil");
    NSAssert([fetchedMessage.uniqueId isEqualToString:[TSInteraction stringFromTimeStamp:timestamp]], @"Unique identifier is accurate");
    NSAssert(fetchedMessage.wasRead == false, @"Message should originally be unread");
    NSAssert([fetchedMessage.uniqueThreadId isEqualToString:self.thread.uniqueId], @"Isn't stored in the right thread!");
}

- (void)testMessagesDeletedOnThreadDeletion {
    uint64_t timestamp = 666;
    NSString *body = @"A child born today will grow up with no conception of privacy at all. They’ll never know what it means to have a private moment to themselves an unrecorded, unanalyzed thought. And that’s a problem because privacy matters; privacy is what allows us to determine who we are and who we want to be.";
    
    for (uint64_t i = timestamp; i<100; i++) {
        TSIncomingMessage *newMessage = [[TSIncomingMessage alloc] initWithTimestamp:i
                                                                            inThread:self.thread
                                                                         messageBody:body
                                                                        attachements:nil];
        [newMessage save];
    }
    
    
    
    [[TSStorageManager sharedManager].databaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        for (uint64_t i = timestamp; i<100; i++) {
            TSIncomingMessage *fetchedMessage = [TSIncomingMessage fetchObjectWithUniqueID:[TSInteraction stringFromTimeStamp:timestamp] transaction:transaction];
            
            NSAssert([fetchedMessage.body isEqualToString:body], @"Body of incoming message recovered");
            NSAssert(fetchedMessage.attachements == nil, @"Attachements are nil");
            NSAssert([fetchedMessage.uniqueId isEqualToString:[TSInteraction stringFromTimeStamp:timestamp]], @"Unique identifier is accurate");
            NSAssert(fetchedMessage.wasRead == false, @"Message should originally be unread");
            NSAssert([fetchedMessage.uniqueThreadId isEqualToString:self.thread.uniqueId], @"Isn't stored in the right thread!");
        }
    }];
    
    
    [self.thread remove];
    
    [[TSStorageManager sharedManager].databaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        for (uint64_t i = timestamp; i<1000; i++) {
            TSIncomingMessage *fetchedMessage = [TSIncomingMessage fetchObjectWithUniqueID:[TSInteraction stringFromTimeStamp:timestamp] transaction:transaction];
            NSAssert(fetchedMessage == nil, @"Message should be deleted!");
        }
    }];
}

@end
