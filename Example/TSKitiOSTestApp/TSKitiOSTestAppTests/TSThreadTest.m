//  Copyright © 2016 Open Whisper Systems. All rights reserved.

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
                                                                          messageBody:@"incoming message body"];
    [incomingMessage save];

    TSOutgoingMessage *outgoingMessage = [[TSOutgoingMessage alloc] initWithTimestamp:20000
                                                                             inThread:thread
                                                                          messageBody:@"outgoing message body"];
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

    TSAttachmentStream *attachment = [[TSAttachmentStream alloc] initWithIdentifier:@"fake-photo-attachment-id"
                                                                               data:[[NSData alloc] init]
                                                                                key:[[NSData alloc] init]
                                                                        contentType:@"image/jpeg"];
    [attachment save];

    BOOL fileWasCreated = [[NSFileManager defaultManager] fileExistsAtPath:[attachment filePath]];
    XCTAssert(fileWasCreated);

    TSIncomingMessage *incomingMessage = [[TSIncomingMessage alloc] initWithTimestamp:10000
                                                                             inThread:thread
                                                                          messageBody:@"incoming message body"
                                                                        attachmentIds:@[ attachment.uniqueId ]];
    [incomingMessage save];

    // Sanity check
    XCTAssertEqual(1, [thread numberOfInteractions]);

    [thread remove];
    XCTAssertEqual(0, [thread numberOfInteractions]);

    BOOL fileStillExists = [[NSFileManager defaultManager] fileExistsAtPath:[attachment filePath]];
    XCTAssertFalse(fileStillExists);
}

@end
