//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "MIMETypeUtil.h"
#import "OWSDevice.h"
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

- (void)setUp
{
    [super setUp];
}

- (void)tearDown
{
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (void)testDeletingThreadDeletesInteractions
{
    TSContactThread *thread = [[TSContactThread alloc]
        initWithContactAddress:[[SignalServiceAddress alloc] initWithPhoneNumber:@"+13334445555"]];
    [self writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [thread anyInsertWithTransaction:transaction];
    }];

    [self readWithBlock:^(SDSAnyReadTransaction *transaction) {
        XCTAssertEqual(0, [thread numberOfInteractionsWithTransaction:transaction]);
    }];

    TSIncomingMessage *incomingMessage = [[TSIncomingMessage alloc]
        initIncomingMessageWithTimestamp:10000
                                inThread:thread
                           authorAddress:[[SignalServiceAddress alloc] initWithPhoneNumber:@"+12223334444"]
                          sourceDeviceId:OWSDevicePrimaryDeviceId
                             messageBody:@"Incoming message body"
                           attachmentIds:@[]
                        expiresInSeconds:0
                           quotedMessage:nil
                            contactShare:nil
                             linkPreview:nil
                          messageSticker:nil
                         serverTimestamp:nil
                         wasReceivedByUD:NO
                       isViewOnceMessage:NO];
    [self writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [incomingMessage anyInsertWithTransaction:transaction];
    }];

    TSOutgoingMessage *outgoingMessage =
        [[TSOutgoingMessage alloc] initOutgoingMessageWithTimestamp:20000
                                                           inThread:thread
                                                        messageBody:@"outgoing message body"
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
    [self writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [outgoingMessage anyInsertWithTransaction:transaction];
    }];

    [self readWithBlock:^(SDSAnyReadTransaction *transaction) {
        XCTAssertEqual(2, [thread numberOfInteractionsWithTransaction:transaction]);
    }];

    [self writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [thread anyRemoveWithTransaction:transaction];
    }];
    [self readWithBlock:^(SDSAnyReadTransaction *transaction) {
        XCTAssertEqual(0, [thread numberOfInteractionsWithTransaction:transaction]);
        XCTAssertEqual(0, [TSInteraction anyCountWithTransaction:transaction]);
    }];
}

- (void)testDeletingThreadDeletesAttachmentFiles
{
    TSContactThread *thread = [[TSContactThread alloc]
        initWithContactAddress:[[SignalServiceAddress alloc] initWithPhoneNumber:@"+13334445555"]];
    [self writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [thread anyInsertWithTransaction:transaction];
    }];

    // Sanity check
    [self readWithBlock:^(SDSAnyReadTransaction *transaction) {
        XCTAssertEqual(0, [thread numberOfInteractionsWithTransaction:transaction]);
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

    TSIncomingMessage *incomingMessage = [[TSIncomingMessage alloc]
        initIncomingMessageWithTimestamp:10000
                                inThread:thread
                           authorAddress:[[SignalServiceAddress alloc] initWithPhoneNumber:@"+12223334444"]
                          sourceDeviceId:OWSDevicePrimaryDeviceId
                             messageBody:@"incoming message body"
                           attachmentIds:@[ incomingAttachment.uniqueId ]
                        expiresInSeconds:0
                           quotedMessage:nil
                            contactShare:nil
                             linkPreview:nil
                          messageSticker:nil
                         serverTimestamp:nil
                         wasReceivedByUD:NO
                       isViewOnceMessage:NO];
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

    TSOutgoingMessage *outgoingMessage =
        [[TSOutgoingMessage alloc] initOutgoingMessageWithTimestamp:10000
                                                           inThread:thread
                                                        messageBody:@"outgoing message body"
                                                      attachmentIds:[@[ outgoingAttachment.uniqueId ] mutableCopy]
                                                   expiresInSeconds:0
                                                    expireStartedAt:0
                                                     isVoiceMessage:NO
                                                   groupMetaMessage:TSGroupMetaMessageUnspecified
                                                      quotedMessage:nil
                                                       contactShare:nil
                                                        linkPreview:nil
                                                     messageSticker:nil
                                                  isViewOnceMessage:NO];
    [self writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [outgoingMessage anyInsertWithTransaction:transaction];
    }];

    // Sanity check
    [self readWithBlock:^(SDSAnyReadTransaction *transaction) {
        XCTAssertEqual(2, [thread numberOfInteractionsWithTransaction:transaction]);
    }];

    // Actual Test Follows
    [self writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [thread anyRemoveWithTransaction:transaction];
    }];

    [self readWithBlock:^(SDSAnyReadTransaction *transaction) {
        XCTAssertEqual(0, [thread numberOfInteractionsWithTransaction:transaction]);
    }];

    BOOL incomingFileStillExists =
        [[NSFileManager defaultManager] fileExistsAtPath:[incomingAttachment originalFilePath]];
    XCTAssertFalse(incomingFileStillExists);

    BOOL outgoingFileStillExists =
        [[NSFileManager defaultManager] fileExistsAtPath:[outgoingAttachment originalFilePath]];
    XCTAssertFalse(outgoingFileStillExists);
}

@end
