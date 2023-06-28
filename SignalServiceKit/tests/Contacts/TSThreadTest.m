//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "MIMETypeUtil.h"
#import "SSKBaseTestObjC.h"
#import "TSAttachmentStream.h"
#import "TSContactThread.h"
#import "TSIncomingMessage.h"
#import "TSOutgoingMessage.h"
#import "TestAppContext.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

@interface TSThreadTest : SSKBaseTestObjC

@end

#pragma mark -

@implementation TSThreadTest

- (NSUInteger)numberOfInteractionsInThread:(TSThread *)thread transaction:(SDSAnyReadTransaction *)transaction
{
    InteractionFinder *finder = [[InteractionFinder alloc] initWithThreadUniqueId:thread.uniqueId];
    __block NSUInteger result = 0;
    [finder enumerateInteractionIdsWithTransaction:transaction
                                             error:NULL
                                             block:^(NSString *uniqueId, BOOL *stop) { result += 1; }];
    return result;
}

- (void)testDeletingThreadDeletesInteractions
{
    ServiceIdObjC *aci = [[ServiceIdObjC alloc] initWithUuidString:@"00000000-0000-4000-8000-000000000000"];
    TSContactThread *thread =
        [[TSContactThread alloc] initWithContactAddress:[[SignalServiceAddress alloc] initWithServiceIdObjC:aci]];
    [self writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [thread anyInsertWithTransaction:transaction];
    }];

    [self readWithBlock:^(SDSAnyReadTransaction *transaction) {
        XCTAssertEqual(0, [self numberOfInteractionsInThread:thread transaction:transaction]);
    }];

    TSIncomingMessageBuilder *incomingMessageBuilder =
        [TSIncomingMessageBuilder incomingMessageBuilderWithThread:thread messageBody:@"Incoming message body"];
    incomingMessageBuilder.authorAci = aci;
    incomingMessageBuilder.timestamp = 10000;
    TSIncomingMessage *incomingMessage = [incomingMessageBuilder build];
    [self writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [incomingMessage anyInsertWithTransaction:transaction];
    }];

    TSOutgoingMessageBuilder *messageBuilder =
        [TSOutgoingMessageBuilder outgoingMessageBuilderWithThread:thread messageBody:@"outgoing message body"];
    messageBuilder.timestamp = 20000;
    TSOutgoingMessage *outgoingMessage = [messageBuilder buildWithSneakyTransaction];
    [self writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [outgoingMessage anyInsertWithTransaction:transaction];
    }];

    [self readWithBlock:^(SDSAnyReadTransaction *transaction) {
        XCTAssertEqual(2, [self numberOfInteractionsInThread:thread transaction:transaction]);
    }];

    [self writeWithBlock:^(
        SDSAnyWriteTransaction *transaction) { [thread softDeleteThreadWithTransaction:transaction]; }];
    [self readWithBlock:^(SDSAnyReadTransaction *transaction) {
        XCTAssertEqual(0, [self numberOfInteractionsInThread:thread transaction:transaction]);
        XCTAssertEqual(0, [TSInteraction anyCountWithTransaction:transaction]);
    }];
}

- (void)testDeletingThreadDeletesAttachmentFiles
{
    ServiceIdObjC *aci = [[ServiceIdObjC alloc] initWithUuidString:@"00000000-0000-4000-8000-000000000000"];
    TSContactThread *thread =
        [[TSContactThread alloc] initWithContactAddress:[[SignalServiceAddress alloc] initWithServiceIdObjC:aci]];
    [self writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [thread anyInsertWithTransaction:transaction];
    }];

    // Sanity check
    [self readWithBlock:^(SDSAnyReadTransaction *transaction) {
        XCTAssertEqual(0, [self numberOfInteractionsInThread:thread transaction:transaction]);
    }];

    __block TSAttachmentStream *incomingAttachment;
    [self writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        incomingAttachment = [AttachmentStreamFactory createWithContentType:OWSMimeTypeImageJpeg
                                                                 dataSource:DataSourceValue.emptyDataSource
                                                                transaction:transaction];
    }];

    // Sanity check
    BOOL incomingFileWasCreated =
        [[NSFileManager defaultManager] fileExistsAtPath:[incomingAttachment originalFilePath]];
    XCTAssert(incomingFileWasCreated);

    TSIncomingMessageBuilder *incomingMessageBuilder =
        [TSIncomingMessageBuilder incomingMessageBuilderWithThread:thread messageBody:@"Incoming message body"];
    incomingMessageBuilder.authorAci = aci;
    incomingMessageBuilder.timestamp = 10000;
    incomingMessageBuilder.attachmentIds = [@[ incomingAttachment.uniqueId ] mutableCopy];
    TSIncomingMessage *incomingMessage = [incomingMessageBuilder build];
    [self writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [incomingMessage anyInsertWithTransaction:transaction];
    }];

    __block TSAttachmentStream *outgoingAttachment;
    [self writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        outgoingAttachment = [AttachmentStreamFactory createWithContentType:OWSMimeTypeImageJpeg
                                                                 dataSource:DataSourceValue.emptyDataSource
                                                                transaction:transaction];
    }];

    // Sanity check
    BOOL outgoingFileWasCreated =
        [[NSFileManager defaultManager] fileExistsAtPath:[outgoingAttachment originalFilePath]];
    XCTAssert(outgoingFileWasCreated);

    TSOutgoingMessageBuilder *messageBuilder =
        [TSOutgoingMessageBuilder outgoingMessageBuilderWithThread:thread messageBody:@"outgoing message body"];
    messageBuilder.timestamp = 10000;
    messageBuilder.attachmentIds = [@[ outgoingAttachment.uniqueId ] mutableCopy];
    TSOutgoingMessage *outgoingMessage = [messageBuilder buildWithSneakyTransaction];
    [self writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [outgoingMessage anyInsertWithTransaction:transaction];
    }];

    // Sanity check
    [self readWithBlock:^(SDSAnyReadTransaction *transaction) {
        XCTAssertEqual(2, [self numberOfInteractionsInThread:thread transaction:transaction]);
    }];

    // Actual Test Follows
    [self writeWithBlock:^(
        SDSAnyWriteTransaction *transaction) { [thread softDeleteThreadWithTransaction:transaction]; }];

    [self readWithBlock:^(SDSAnyReadTransaction *transaction) {
        XCTAssertEqual(0, [self numberOfInteractionsInThread:thread transaction:transaction]);
    }];

    BOOL incomingFileStillExists =
        [[NSFileManager defaultManager] fileExistsAtPath:[incomingAttachment originalFilePath]];
    XCTAssertFalse(incomingFileStillExists);

    BOOL outgoingFileStillExists =
        [[NSFileManager defaultManager] fileExistsAtPath:[outgoingAttachment originalFilePath]];
    XCTAssertFalse(outgoingFileStillExists);
}

@end
