//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSDevice.h"
#import "TSAttachmentStream.h"
#import "TSContactThread.h"
#import "TSIncomingMessage.h"
#import "TSOutgoingMessage.h"
#import "TSStorageManager.h"
#import <XCTest/XCTest.h>

@interface TSThreadTest : XCTestCase

@end

@implementation TSThreadTest

- (void)setUp
{
    [super setUp];

    // Register views, etc.
    [[TSStorageManager sharedManager] setupDatabase];
}

- (void)tearDown
{
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (void)testDeletingThreadDeletesInteractions
{
    TSContactThread *thread = [[TSContactThread alloc] initWithUniqueId:@"fake-test-thread"];
    [thread save];

    [TSInteraction removeAllObjectsInCollection];
    XCTAssertEqual(0, [thread numberOfInteractions]);

    TSIncomingMessage *incomingMessage = [[TSIncomingMessage alloc] initWithTimestamp:10000
                                                                             inThread:thread
                                                                             authorId:@"fake-author-id"
                                                                       sourceDeviceId:OWSDevicePrimaryDeviceId
                                                                          messageBody:@"Incoming message body"];
    [incomingMessage save];

    TSOutgoingMessage *outgoingMessage =
        [[TSOutgoingMessage alloc] initWithTimestamp:20000 inThread:thread messageBody:@"outgoing message body"];
    [outgoingMessage save];

    XCTAssertEqual(2, [thread numberOfInteractions]);

    [thread remove];
    XCTAssertEqual(0, [thread numberOfInteractions]);
    XCTAssertEqual(0, [TSInteraction numberOfKeysInCollection]);
}

- (void)testDeletingThreadDeletesAttachmentFiles
{
    TSContactThread *thread = [[TSContactThread alloc] initWithUniqueId:@"fake-test-thread"];
    [thread save];

    // Sanity check
    [TSInteraction removeAllObjectsInCollection];
    XCTAssertEqual(0, [thread numberOfInteractions]);

    NSError *error;
    TSAttachmentStream *incomingAttachment = [[TSAttachmentStream alloc] initWithContentType:@"image/jpeg"
                                                                              sourceFilename:nil];
    [incomingAttachment writeData:[NSData new] error:&error];
    [incomingAttachment save];

    // Sanity check
    BOOL incomingFileWasCreated = [[NSFileManager defaultManager] fileExistsAtPath:[incomingAttachment filePath]];
    XCTAssert(incomingFileWasCreated);

    TSIncomingMessage *incomingMessage = [[TSIncomingMessage alloc] initWithTimestamp:10000
                                                                             inThread:thread
                                                                             authorId:@"fake-author-id"
                                                                       sourceDeviceId:OWSDevicePrimaryDeviceId
                                                                          messageBody:@"incoming message body"
                                                                        attachmentIds:@[ incomingAttachment.uniqueId ]
                                                                     expiresInSeconds:0];
    [incomingMessage save];

    TSAttachmentStream *outgoingAttachment = [[TSAttachmentStream alloc] initWithContentType:@"image/jpeg"
                                                                              sourceFilename:nil];
    [outgoingAttachment writeData:[NSData new] error:&error];
    [outgoingAttachment save];

    // Sanity check
    BOOL outgoingFileWasCreated = [[NSFileManager defaultManager] fileExistsAtPath:[outgoingAttachment filePath]];
    XCTAssert(outgoingFileWasCreated);

    TSOutgoingMessage *outgoingMessage = [[TSOutgoingMessage alloc] initWithTimestamp:10000
                                                                             inThread:thread
                                                                          messageBody:@"outgoing message body"
                                                                        attachmentIds:[@[ outgoingAttachment.uniqueId ] mutableCopy]];
    [outgoingMessage save];

    // Sanity check
    XCTAssertEqual(2, [thread numberOfInteractions]);

    // Actual Test Follows
    [thread remove];
    XCTAssertEqual(0, [thread numberOfInteractions]);

    BOOL incomingFileStillExists = [[NSFileManager defaultManager] fileExistsAtPath:[incomingAttachment filePath]];
    XCTAssertFalse(incomingFileStillExists);

    BOOL outgoingFileStillExists = [[NSFileManager defaultManager] fileExistsAtPath:[outgoingAttachment filePath]];
    XCTAssertFalse(outgoingFileStillExists);
}

@end
