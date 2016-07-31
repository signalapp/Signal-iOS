//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSOrphanedDataCleaner.h"
#import "TSAttachmentStream.h"
#import "TSContactThread.h"
#import "TSIncomingMessage.h"
#import "TSStorageManager.h"
#import <XCTest/XCTest.h>

@interface OWSOrphanedDataCleanerTest : XCTestCase

@end

@implementation OWSOrphanedDataCleanerTest

- (void)setUp
{
    [super setUp];
    // Register views, etc.
    [[TSStorageManager sharedManager] setupDatabase];

    // Set up initial conditions & Sanity check
    [TSAttachmentStream deleteAttachments];
    XCTAssertEqual(0, [TSAttachmentStream numberOfItemsInAttachmentsFolder]);
    [TSAttachmentStream removeAllObjectsInCollection];
    XCTAssertEqual(0, [TSAttachmentStream numberOfKeysInCollection]);
    [TSIncomingMessage removeAllObjectsInCollection];
    XCTAssertEqual(0, [TSIncomingMessage numberOfKeysInCollection]);
    [TSThread removeAllObjectsInCollection];
    XCTAssertEqual(0, [TSThread numberOfKeysInCollection]);
}

- (void)tearDown
{
    [super tearDown];
}

- (void)testInteractionsWithoutThreadAreDeleted
{
    // This thread is intentionally not saved. It's meant to recreate a situation we've seen where interactions exist
    // that reference the id of a thread that no longer exists. Presumably this is the result of a deleted thread not
    // properly deleting it's interactions.
    TSContactThread *unsavedThread = [[TSContactThread alloc] initWithUniqueId:@"this-thread-does-not-exist"];

    TSIncomingMessage *incomingMessage =
        [[TSIncomingMessage alloc] initWithTimestamp:1 inThread:unsavedThread messageBody:@"footch" attachmentIds:nil];
    [incomingMessage save];
    XCTAssertEqual(1, [TSIncomingMessage numberOfKeysInCollection]);

    [[OWSOrphanedDataCleaner new] removeOrphanedData];
    XCTAssertEqual(0, [TSIncomingMessage numberOfKeysInCollection]);
}

- (void)testInteractionsWithThreadAreNotDeleted
{
    TSContactThread *savedThread = [[TSContactThread alloc] initWithUniqueId:@"this-thread-exists"];
    [savedThread save];

    TSIncomingMessage *incomingMessage =
        [[TSIncomingMessage alloc] initWithTimestamp:1 inThread:savedThread messageBody:@"footch" attachmentIds:nil];
    [incomingMessage save];
    XCTAssertEqual(1, [TSIncomingMessage numberOfKeysInCollection]);

    [[OWSOrphanedDataCleaner new] removeOrphanedData];
    XCTAssertEqual(1, [TSIncomingMessage numberOfKeysInCollection]);
}

- (void)testFilesWithoutInteractionsAreDeleted
{
    TSAttachmentStream *attachmentStream = [[TSAttachmentStream alloc] initWithIdentifier:@"orphaned-attachment"
                                                                                     data:[NSData new]
                                                                                      key:[NSData new]
                                                                              contentType:@"image/jpeg"];

    [attachmentStream save];
    NSString *orphanedFilePath = [attachmentStream filePath];
    BOOL fileExists = [[NSFileManager defaultManager] fileExistsAtPath:orphanedFilePath];
    XCTAssert(fileExists);
    XCTAssertEqual(1, [TSAttachmentStream numberOfItemsInAttachmentsFolder]);

    [[OWSOrphanedDataCleaner new] removeOrphanedData];
    fileExists = [[NSFileManager defaultManager] fileExistsAtPath:orphanedFilePath];
    XCTAssertFalse(fileExists);
    XCTAssertEqual(0, [TSAttachmentStream numberOfItemsInAttachmentsFolder]);
}

- (void)testFilesWithInteractionsAreNotDeleted
{
    TSContactThread *savedThread = [[TSContactThread alloc] initWithUniqueId:@"this-thread-exists"];
    [savedThread save];

    TSAttachmentStream *attachmentStream = [[TSAttachmentStream alloc] initWithIdentifier:@"legit-attachment"
                                                                                     data:[NSData new]
                                                                                      key:[NSData new]
                                                                              contentType:@"image/jpeg"];
    [attachmentStream save];

    TSIncomingMessage *incomingMessage = [[TSIncomingMessage alloc] initWithTimestamp:1
                                                                             inThread:savedThread
                                                                          messageBody:@"footch"
                                                                        attachmentIds:@[ attachmentStream.uniqueId ]];
    [incomingMessage save];

    NSString *attachmentFilePath = [attachmentStream filePath];
    BOOL fileExists = [[NSFileManager defaultManager] fileExistsAtPath:attachmentFilePath];
    XCTAssert(fileExists);
    XCTAssertEqual(1, [TSAttachmentStream numberOfItemsInAttachmentsFolder]);

    [[OWSOrphanedDataCleaner new] removeOrphanedData];

    fileExists = [[NSFileManager defaultManager] fileExistsAtPath:attachmentFilePath];
    XCTAssert(fileExists);
    XCTAssertEqual(1, [TSAttachmentStream numberOfItemsInAttachmentsFolder]);
}

- (void)testFilesWithoutAttachmentStreamsAreDeleted
{
    TSAttachmentStream *attachmentStream = [[TSAttachmentStream alloc] initWithIdentifier:@"orphaned-attachment"
                                                                                     data:[NSData new]
                                                                                      key:[NSData new]
                                                                              contentType:@"image/jpeg"];

    // Intentionally not saved, because we want a lingering file.
    // This relies on a bug(?) in the current TSAttachmentStream init implementation where the file is created during
    // `init` rather than during `save`. If that bug is fixed, we'll have to update this test to manually create the
    // file to set up the correct initial state.
    NSString *orphanedFilePath = [attachmentStream filePath];
    BOOL fileExists = [[NSFileManager defaultManager] fileExistsAtPath:orphanedFilePath];
    XCTAssert(fileExists);
    XCTAssertEqual(1, [TSAttachmentStream numberOfItemsInAttachmentsFolder]);

    [[OWSOrphanedDataCleaner new] removeOrphanedData];
    fileExists = [[NSFileManager defaultManager] fileExistsAtPath:orphanedFilePath];
    XCTAssertFalse(fileExists);
    XCTAssertEqual(0, [TSAttachmentStream numberOfItemsInAttachmentsFolder]);
}

@end
