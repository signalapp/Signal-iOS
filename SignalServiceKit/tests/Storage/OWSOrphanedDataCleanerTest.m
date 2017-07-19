//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSDevice.h"
#import "OWSOrphanedDataCleaner.h"
#import "TSAttachmentStream.h"
#import "TSContactThread.h"
#import "TSIncomingMessage.h"
#import "TSStorageManager.h"
#import <XCTest/XCTest.h>

@interface OWSOrphanedDataCleanerTest : XCTestCase

@end

#pragma mark -

@implementation OWSOrphanedDataCleanerTest

- (void)setUp
{
    [super setUp];
    // Register views, etc.
    [[TSStorageManager sharedManager] setupDatabaseWithSafeBlockingMigrations:^{}];

    // Set up initial conditions & Sanity check
    [TSAttachmentStream deleteAttachments];
    XCTAssertEqual(0, [self numberOfItemsInAttachmentsFolder]);
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

- (NSUInteger)numberOfItemsInAttachmentsFolder
{
    return [OWSOrphanedDataCleaner filePathsInAttachmentsFolder].count;
}

- (void)testInteractionsWithoutThreadAreDeleted
{
    // This thread is intentionally not saved. It's meant to recreate a situation we've seen where interactions exist
    // that reference the id of a thread that no longer exists. Presumably this is the result of a deleted thread not
    // properly deleting it's interactions.
    TSContactThread *unsavedThread = [[TSContactThread alloc] initWithUniqueId:@"this-thread-does-not-exist"];

    TSIncomingMessage *incomingMessage = [[TSIncomingMessage alloc] initWithTimestamp:1
                                                                             inThread:unsavedThread
                                                                             authorId:@"fake-author-id"
                                                                       sourceDeviceId:OWSDevicePrimaryDeviceId
                                                                          messageBody:@"footch"];
    [incomingMessage save];
    XCTAssertEqual(1, [TSIncomingMessage numberOfKeysInCollection]);

    XCTestExpectation *expectation = [self expectationWithDescription:@"Cleanup"];
    [OWSOrphanedDataCleaner auditAndCleanupAsync:^{
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:5.0
                                 handler:^(NSError *error) {
                                     if (error) {
                                         XCTFail(@"Expectation Failed with error: %@", error);
                                     }
                                 }];

    XCTAssertEqual(0, [TSIncomingMessage numberOfKeysInCollection]);
}

- (void)testInteractionsWithThreadAreNotDeleted
{
    TSContactThread *savedThread = [[TSContactThread alloc] initWithUniqueId:@"this-thread-exists"];
    [savedThread save];

    TSIncomingMessage *incomingMessage = [[TSIncomingMessage alloc] initWithTimestamp:1
                                                                             inThread:savedThread
                                                                             authorId:@"fake-author-id"
                                                                       sourceDeviceId:OWSDevicePrimaryDeviceId
                                                                          messageBody:@"footch"];
    [incomingMessage save];
    XCTAssertEqual(1, [TSIncomingMessage numberOfKeysInCollection]);

    XCTestExpectation *expectation = [self expectationWithDescription:@"Cleanup"];
    [OWSOrphanedDataCleaner auditAndCleanupAsync:^{
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:5.0
                                 handler:^(NSError *error) {
                                     if (error) {
                                         XCTFail(@"Expectation Failed with error: %@", error);
                                     }
                                 }];

    XCTAssertEqual(1, [TSIncomingMessage numberOfKeysInCollection]);
}

- (void)testFilesWithoutInteractionsAreDeleted
{
    // sanity check
    XCTAssertEqual(0, [self numberOfItemsInAttachmentsFolder]);

    NSError *error;
    TSAttachmentStream *attachmentStream = [[TSAttachmentStream alloc] initWithContentType:@"image/jpeg" sourceFilename:nil];
    [attachmentStream writeData:[NSData new] error:&error];
    [attachmentStream save];
    NSString *orphanedFilePath = [attachmentStream filePath];
    BOOL fileExists = [[NSFileManager defaultManager] fileExistsAtPath:orphanedFilePath];
    XCTAssert(fileExists);
    XCTAssertEqual(1, [self numberOfItemsInAttachmentsFolder]);

    // Do multiple cleanup passes.
    for (int i = 0; i < 2; i++) {
        XCTestExpectation *expectation = [self expectationWithDescription:@"Cleanup"];
        [OWSOrphanedDataCleaner auditAndCleanupAsync:^{
            [expectation fulfill];
        }];
        [self waitForExpectationsWithTimeout:5.0
                                     handler:^(NSError *error) {
                                         if (error) {
                                             XCTFail(@"Expectation Failed with error: %@", error);
                                         }
                                     }];
    }

    fileExists = [[NSFileManager defaultManager] fileExistsAtPath:orphanedFilePath];
    XCTAssertFalse(fileExists);
    XCTAssertEqual(0, [self numberOfItemsInAttachmentsFolder]);
}

- (void)testFilesWithInteractionsAreNotDeleted
{
    TSContactThread *savedThread = [[TSContactThread alloc] initWithUniqueId:@"this-thread-exists"];
    [savedThread save];

    NSError *error;
    TSAttachmentStream *attachmentStream = [[TSAttachmentStream alloc] initWithContentType:@"image/jpeg" sourceFilename:nil];
    [attachmentStream writeData:[NSData new] error:&error];
    [attachmentStream save];

    TSIncomingMessage *incomingMessage = [[TSIncomingMessage alloc] initWithTimestamp:1
                                                                             inThread:savedThread
                                                                             authorId:@"fake-author-id"
                                                                       sourceDeviceId:OWSDevicePrimaryDeviceId
                                                                          messageBody:@"footch"
                                                                        attachmentIds:@[ attachmentStream.uniqueId ]
                                                                     expiresInSeconds:0];
    [incomingMessage save];

    NSString *attachmentFilePath = [attachmentStream filePath];
    BOOL fileExists = [[NSFileManager defaultManager] fileExistsAtPath:attachmentFilePath];
    XCTAssert(fileExists);
    XCTAssertEqual(1, [self numberOfItemsInAttachmentsFolder]);

    XCTestExpectation *expectation = [self expectationWithDescription:@"Cleanup"];
    [OWSOrphanedDataCleaner auditAndCleanupAsync:^{
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:5.0
                                 handler:^(NSError *error) {
                                     if (error) {
                                         XCTFail(@"Expectation Failed with error: %@", error);
                                     }
                                 }];

    fileExists = [[NSFileManager defaultManager] fileExistsAtPath:attachmentFilePath];
    XCTAssert(fileExists);
    XCTAssertEqual(1, [self numberOfItemsInAttachmentsFolder]);
}

- (void)testFilesWithoutAttachmentStreamsAreDeleted
{
    NSError *error;
    TSAttachmentStream *attachmentStream = [[TSAttachmentStream alloc] initWithContentType:@"image/jpeg" sourceFilename:nil];
    [attachmentStream writeData:[NSData new] error:&error];
    // Intentionally not saved, because we want a lingering file.

    NSString *orphanedFilePath = [attachmentStream filePath];
    BOOL fileExists = [[NSFileManager defaultManager] fileExistsAtPath:orphanedFilePath];
    XCTAssert(fileExists);
    XCTAssertEqual(1, [self numberOfItemsInAttachmentsFolder]);

    XCTestExpectation *expectation = [self expectationWithDescription:@"Cleanup"];
    [OWSOrphanedDataCleaner auditAndCleanupAsync:^{
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:5.0
                                 handler:^(NSError *error) {
                                     if (error) {
                                         XCTFail(@"Expectation Failed with error: %@", error);
                                     }
                                 }];

    fileExists = [[NSFileManager defaultManager] fileExistsAtPath:orphanedFilePath];
    XCTAssertFalse(fileExists);
    XCTAssertEqual(0, [self numberOfItemsInAttachmentsFolder]);
}

@end
