//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

#import "SignalBaseTest.h"
#import <SignalMessaging/OWSOrphanDataCleaner.h>
#import <SignalServiceKit/OWSDevice.h>
#import <SignalServiceKit/TSAttachmentStream.h>
#import <SignalServiceKit/TSContactThread.h>
#import <SignalServiceKit/TSIncomingMessage.h>

@interface OWSOrphanDataCleaner (Test)

+ (nullable NSSet<NSString *> *)filePathsInDirectorySafe:(NSString *)dirPath;

@end

#pragma mark -


@interface OWSOrphanDataCleanerTest : SignalBaseTest

@end

#pragma mark -

@implementation OWSOrphanDataCleanerTest

#ifdef BROKEN_TESTS

- (void)setUp
{
    [super setUp];

    // Set up initial conditions & Sanity check
    XCTAssertEqual(0, [self numberOfItemsInAttachmentsFolder]);
    XCTAssertEqual(0, [TSAttachmentStream numberOfKeysInCollection]);
    XCTAssertEqual(0, [TSIncomingMessage numberOfKeysInCollection]);
    XCTAssertEqual(0, [TSThread numberOfKeysInCollection]);
}

- (int)numberOfItemsInAttachmentsFolder
{
    NSString *legacyAttachmentsDirPath = TSAttachmentStream.legacyAttachmentsDirPath;
    NSSet<NSString *> *_Nullable legacyAttachmentFilePaths =
        [OWSOrphanDataCleaner filePathsInDirectorySafe:legacyAttachmentsDirPath];

    NSString *sharedDataAttachmentsDirPath = TSAttachmentStream.sharedDataAttachmentsDirPath;
    NSSet<NSString *> *_Nullable sharedDataAttachmentFilePaths =
        [OWSOrphanDataCleaner filePathsInDirectorySafe:sharedDataAttachmentsDirPath];

    NSMutableSet<NSString *> *attachmentFilePaths = [NSMutableSet new];
    if (legacyAttachmentFilePaths) {
        [attachmentFilePaths unionSet:legacyAttachmentFilePaths];
    }
    if (sharedDataAttachmentFilePaths) {
        [attachmentFilePaths unionSet:sharedDataAttachmentFilePaths];
    }

    return (int)attachmentFilePaths.count;
}

- (TSIncomingMessage *)createIncomingMessageWithThread:(TSThread *)thread
                                         attachmentIds:(NSArray<NSString *> *)attachmentIds
{
    TSIncomingMessageBuilder *incomingMessageBuilder =
        [TSIncomingMessageBuilder incomingMessageBuilderWithThread:thread messageBody:@"Test body"];
    incomingMessageBuilder.authorAddress = [[SignalServiceAddress alloc] initWithPhoneNumber:@"fake-author-id"];
    incomingMessageBuilder.timestamp = 1;
    incomingMessageBuilder.attachmentIds = attachmentIds;
    TSIncomingMessage *incomingMessage = [incomingMessageBuilder build];
    [incomingMessage save];

    return incomingMessage;
}

- (TSAttachmentStream *)createAttachmentStream
{
    NSError *error;
    TSAttachmentStream *attachmentStream =
        [[TSAttachmentStream alloc] initWithContentType:OWSMimeTypeImageJpeg byteCount:12 sourceFilename:nil];
    [attachmentStream writeData:[NSData new] error:&error];

    XCTAssertNil(error);

    [attachmentStream save];

    return attachmentStream;
}

- (void)testInteractionsWithoutThreadAreDeleted
{
    // This thread is intentionally not saved. It's meant to recreate a situation we've seen where interactions exist
    // that reference the id of a thread that no longer exists. Presumably this is the result of a deleted thread not
    // properly deleting it's interactions.
    TSContactThread *unsavedThread = [[TSContactThread alloc] initWithUniqueId:@"this-thread-does-not-exist"];

    __unused TSIncomingMessage *incomingMessage =
        [self createIncomingMessageWithThread:unsavedThread attachmentIds:@[]];

    XCTAssertEqual(1, [TSIncomingMessage numberOfKeysInCollection]);

    XCTestExpectation *expectation = [self expectationWithDescription:@"Cleanup"];
    [OWSOrphanDataCleaner auditAndCleanup:YES
                               completion:^{
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

    __unused TSIncomingMessage *incomingMessage = [self createIncomingMessageWithThread:savedThread attachmentIds:@[]];

    XCTAssertEqual(1, [TSIncomingMessage numberOfKeysInCollection]);

    XCTestExpectation *expectation = [self expectationWithDescription:@"Cleanup"];
    [OWSOrphanDataCleaner auditAndCleanup:YES
                               completion:^{
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

    TSAttachmentStream *attachmentStream = [self createAttachmentStream];

    NSString *orphanFilePath = [attachmentStream originalFilePath];
    BOOL fileExists = [[NSFileManager defaultManager] fileExistsAtPath:orphanFilePath];
    XCTAssert(fileExists);
    XCTAssertEqual(1, [self numberOfItemsInAttachmentsFolder]);

    // Do multiple cleanup passes.
    for (int i = 0; i < 2; i++) {
        XCTestExpectation *expectation = [self expectationWithDescription:@"Cleanup"];
        [OWSOrphanDataCleaner auditAndCleanup:YES
                                   completion:^{
                                       [expectation fulfill];
                                   }];
        [self waitForExpectationsWithTimeout:5.0
                                     handler:^(NSError *error) {
                                         if (error) {
                                             XCTFail(@"Expectation Failed with error: %@", error);
                                         }
                                     }];
    }

    fileExists = [[NSFileManager defaultManager] fileExistsAtPath:orphanFilePath];
    XCTAssertFalse(fileExists);
    XCTAssertEqual(0, [self numberOfItemsInAttachmentsFolder]);
}

- (void)testFilesWithInteractionsAreNotDeleted
{
    TSContactThread *savedThread = [[TSContactThread alloc] initWithUniqueId:@"this-thread-exists"];
    [savedThread save];

    TSAttachmentStream *attachmentStream = [self createAttachmentStream];

    __unused TSIncomingMessage *incomingMessage =
        [self createIncomingMessageWithThread:savedThread attachmentIds:@[ attachmentStream.uniqueId ]];

    NSString *attachmentFilePath = [attachmentStream originalFilePath];
    BOOL fileExists = [[NSFileManager defaultManager] fileExistsAtPath:attachmentFilePath];
    XCTAssert(fileExists);
    XCTAssertEqual(1, [self numberOfItemsInAttachmentsFolder]);

    XCTestExpectation *expectation = [self expectationWithDescription:@"Cleanup"];
    [OWSOrphanDataCleaner auditAndCleanup:YES
                               completion:^{
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
    TSAttachmentStream *attachmentStream =
        [[TSAttachmentStream alloc] initWithContentType:OWSMimeTypeImageJpeg byteCount:0 sourceFilename:nil];
    [attachmentStream writeData:[NSData new] error:&error];
    // Intentionally not saved, because we want a lingering file.

    NSString *orphanFilePath = [attachmentStream originalFilePath];
    BOOL fileExists = [[NSFileManager defaultManager] fileExistsAtPath:orphanFilePath];
    XCTAssert(fileExists);
    XCTAssertEqual(1, [self numberOfItemsInAttachmentsFolder]);

    XCTestExpectation *expectation = [self expectationWithDescription:@"Cleanup"];
    [OWSOrphanDataCleaner auditAndCleanup:YES
                               completion:^{
                                   [expectation fulfill];
                               }];
    [self waitForExpectationsWithTimeout:5.0
                                 handler:^(NSError *error) {
                                     if (error) {
                                         XCTFail(@"Expectation Failed with error: %@", error);
                                     }
                                 }];

    fileExists = [[NSFileManager defaultManager] fileExistsAtPath:orphanFilePath];
    XCTAssertFalse(fileExists);
    XCTAssertEqual(0, [self numberOfItemsInAttachmentsFolder]);
}

#endif

@end
