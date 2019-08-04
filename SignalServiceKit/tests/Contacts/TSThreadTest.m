//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "MIMETypeUtil.h"
#import "OWSDevice.h"
#import "OWSPrimaryStorage.h"
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
    TSContactThread *thread =
        [[TSContactThread alloc] initWithUniqueId:[TSContactThread threadIdFromContactId:@"+13334445555"]];
    [thread save];

    [self readWithBlock:^(SDSAnyReadTransaction *_Nonnull transaction) {
        XCTAssertEqual(0, [thread numberOfInteractionsWithTransaction:transaction]);
    }];

    TSIncomingMessage *incomingMessage =
        [[TSIncomingMessage alloc] initIncomingMessageWithTimestamp:10000
                                                           inThread:thread
                                                           authorId:@"+12223334444"
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
                                perMessageExpirationDurationSeconds:0];
    [incomingMessage save];

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
                                perMessageExpirationDurationSeconds:0];
    [outgoingMessage save];

    [self yapReadWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
        XCTAssertEqual(2, [thread numberOfInteractionsWithTransaction:transaction.asAnyRead]);
    }];

    [thread remove];
    [self yapReadWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
        XCTAssertEqual(0, [thread numberOfInteractionsWithTransaction:transaction.asAnyRead]);
    }];
    XCTAssertEqual(0, [TSInteraction numberOfKeysInCollection]);
}

- (void)testDeletingThreadDeletesAttachmentFiles
{
    TSContactThread *thread =
        [[TSContactThread alloc] initWithUniqueId:[TSContactThread threadIdFromContactId:@"+13334445555"]];
    [thread save];

    // Sanity check
    [self yapReadWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
        XCTAssertEqual(0, [thread numberOfInteractionsWithTransaction:transaction.asAnyRead]);
    }];

    __block TSAttachmentStream *incomingAttachment;
    [self yapWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        incomingAttachment = [AttachmentStreamFactory createWithContentType:OWSMimeTypeImageJpeg
                                                                 dataSource:DataSourceValue.emptyDataSource
                                                                transaction:transaction.asAnyWrite];
    }];

    // Sanity check
    BOOL incomingFileWasCreated =
        [[NSFileManager defaultManager] fileExistsAtPath:[incomingAttachment originalFilePath]];
    XCTAssert(incomingFileWasCreated);

    TSIncomingMessage *incomingMessage =
        [[TSIncomingMessage alloc] initIncomingMessageWithTimestamp:10000
                                                           inThread:thread
                                                           authorId:@"+12223334444"
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
                                perMessageExpirationDurationSeconds:0];
    [incomingMessage save];

    __block TSAttachmentStream *outgoingAttachment;
    [self yapWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        outgoingAttachment = [AttachmentStreamFactory createWithContentType:OWSMimeTypeImageJpeg
                                                                 dataSource:DataSourceValue.emptyDataSource
                                                                transaction:transaction.asAnyWrite];
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
                                perMessageExpirationDurationSeconds:0];
    [outgoingMessage save];

    // Sanity check
    [self yapReadWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
        XCTAssertEqual(2, [thread numberOfInteractionsWithTransaction:transaction.asAnyRead]);
    }];

    // Actual Test Follows
    [thread remove];
    [self yapReadWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
        XCTAssertEqual(0, [thread numberOfInteractionsWithTransaction:transaction.asAnyRead]);
    }];

    BOOL incomingFileStillExists =
        [[NSFileManager defaultManager] fileExistsAtPath:[incomingAttachment originalFilePath]];
    XCTAssertFalse(incomingFileStillExists);

    BOOL outgoingFileStillExists =
        [[NSFileManager defaultManager] fileExistsAtPath:[outgoingAttachment originalFilePath]];
    XCTAssertFalse(outgoingFileStillExists);
}

@end
