//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSDevice.h"
#import "OWSPrimaryStorage.h"
#import "SSKBaseTest.h"
#import "TSAttachmentStream.h"
#import "TSContactThread.h"
#import "TSIncomingMessage.h"
#import "TSOutgoingMessage.h"
#import "TestAppContext.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

@interface TSThreadTest : SSKBaseTest

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

    XCTAssertEqual(0, [thread numberOfInteractions]);

    TSIncomingMessage *incomingMessage =
        [[TSIncomingMessage alloc] initIncomingMessageWithTimestamp:10000
                                                           inThread:thread
                                                           authorId:@"+12223334444"
                                                     sourceDeviceId:OWSDevicePrimaryDeviceId
                                                        messageBody:@"Incoming message body"
                                                      attachmentIds:@[]
                                                   expiresInSeconds:0
                                                      quotedMessage:nil
                                                       contactShare:nil];
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
                                                       contactShare:nil];
    [outgoingMessage save];

    XCTAssertEqual(2, [thread numberOfInteractions]);

    [thread remove];
    XCTAssertEqual(0, [thread numberOfInteractions]);
    XCTAssertEqual(0, [TSInteraction numberOfKeysInCollection]);
}

- (void)testDeletingThreadDeletesAttachmentFiles
{
    TSContactThread *thread =
        [[TSContactThread alloc] initWithUniqueId:[TSContactThread threadIdFromContactId:@"+13334445555"]];
    [thread save];

    // Sanity check
    XCTAssertEqual(0, [thread numberOfInteractions]);

    NSError *error;
    TSAttachmentStream *incomingAttachment =
        [[TSAttachmentStream alloc] initWithContentType:@"image/jpeg" byteCount:0 sourceFilename:nil];
    [incomingAttachment writeData:[NSData new] error:&error];
    [incomingAttachment save];

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
                                                       contactShare:nil];
    [incomingMessage save];

    TSAttachmentStream *outgoingAttachment =
        [[TSAttachmentStream alloc] initWithContentType:@"image/jpeg" byteCount:0 sourceFilename:nil];
    [outgoingAttachment writeData:[NSData new] error:&error];
    [outgoingAttachment save];

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
                                                       contactShare:nil];
    [outgoingMessage save];

    // Sanity check
    XCTAssertEqual(2, [thread numberOfInteractions]);

    // Actual Test Follows
    [thread remove];
    XCTAssertEqual(0, [thread numberOfInteractions]);

    BOOL incomingFileStillExists =
        [[NSFileManager defaultManager] fileExistsAtPath:[incomingAttachment originalFilePath]];
    XCTAssertFalse(incomingFileStillExists);

    BOOL outgoingFileStillExists =
        [[NSFileManager defaultManager] fileExistsAtPath:[outgoingAttachment originalFilePath]];
    XCTAssertFalse(outgoingFileStillExists);
}

@end
