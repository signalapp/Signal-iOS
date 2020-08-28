//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "ConversationViewItem.h"
#import "SignalBaseTest.h"
#import <MobileCoreServices/MobileCoreServices.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/MIMETypeUtil.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSAccountManager.h>
#import <SignalServiceKit/TSAttachmentStream.h>
#import <SignalServiceKit/TSContactThread.h>
#import <SignalServiceKit/TSOutgoingMessage.h>

@interface ConversationViewItemTest : SignalBaseTest

@property TSThread *thread;
@property OutgoingMessageFactory *messageFactory;
@property ConversationStyle *conversationStyle;

@end

#pragma mark -

@implementation ConversationViewItemTest

- (void)setUp
{
    [super setUp];

    [[TSAccountManager sharedInstance] registerForTestsWithLocalNumber:@"+13231231234" uuid:[NSUUID new]];

    __block TSThread *thread;
    [self writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        thread = [[ContactThreadFactory new] createWithTransaction:transaction];
    }];
    self.thread = thread;

    self.messageFactory = [OutgoingMessageFactory new];
    self.messageFactory.threadCreator = ^TSThread *(SDSAnyWriteTransaction *transaction) {
        return thread;
    };
    self.messageFactory.messageBodyBuilder = ^NSString * _Nonnull{
        return @"abc";
    };

    self.conversationStyle = [[ConversationStyle alloc] initWithThread:self.thread];
}

- (void)tearDown
{
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (ConversationInteractionViewItem *)textViewItem
{
    __block ConversationInteractionViewItem *viewItem = nil;
    [self writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        TSOutgoingMessage *message = [self.messageFactory createWithTransaction:transaction];
        TSThread *thread = [message threadWithTransaction:transaction];

        viewItem = [[ConversationInteractionViewItem alloc] initWithInteraction:message
                                                                         thread:thread
                                                                    transaction:transaction
                                                              conversationStyle:self.conversationStyle];
    }];

    return viewItem;
}

- (ConversationInteractionViewItem *)viewItemWithAttachmentMimetype:(NSString *)mimeType filename:(NSString *)filename
{
    OWSAssertDebug(filename.length > 0);

    NSString *resourcePath = [[NSBundle bundleForClass:[self class]] resourcePath];
    NSString *filePath = [resourcePath stringByAppendingPathComponent:filename];

    OWSAssertDebug([[NSFileManager defaultManager] fileExistsAtPath:filePath]);

    NSError *error;
    id<DataSource> dataSource = [DataSourcePath dataSourceWithFilePath:filePath
                                            shouldDeleteOnDeallocation:NO
                                                                 error:&error];
    OWSAssertDebug(error == nil);
    dataSource.sourceFilename = filename;

    __block ConversationInteractionViewItem *viewItem = nil;
    [self writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        TSAttachmentStream *attachment =
            [AttachmentStreamFactory createWithContentType:mimeType dataSource:dataSource transaction:transaction];
        self.messageFactory.attachmentIdsBuilder = ^NSMutableArray * _Nonnull(void){
            return [@[ attachment.uniqueId ] mutableCopy];
        };

        TSOutgoingMessage *message = [self.messageFactory createWithTransaction:transaction];
        TSThread *thread = [message threadWithTransaction:transaction];

        viewItem = [[ConversationInteractionViewItem alloc] initWithInteraction:message
                                                                         thread:thread
                                                                    transaction:transaction
                                                              conversationStyle:self.conversationStyle];
    }];

    return viewItem;
}

- (ConversationInteractionViewItem *)stillImageViewItem
{
    return [self viewItemWithAttachmentMimetype:OWSMimeTypeImageJpeg filename:@"test-jpg.jpg"];
}

- (ConversationInteractionViewItem *)animatedImageViewItem
{
    return [self viewItemWithAttachmentMimetype:OWSMimeTypeImageGif filename:@"test-gif.gif"];
}

- (ConversationInteractionViewItem *)videoViewItem
{
    return [self viewItemWithAttachmentMimetype:@"video/mp4" filename:@"test-mp4.mp4"];
}

- (ConversationInteractionViewItem *)audioViewItem
{
    return [self viewItemWithAttachmentMimetype:@"audio/mp3" filename:@"test-mp3.mp3"];
}

// This method passes on the execution and wait for it to come back for 10 seconds
// so that the previous call to a method that involves async execution on the same queue
// can run and return the execution back to the test.
//
// Note that it may be better for the `deleteAction` method to have a completion block
// so the expectation can be fulfulled in there. Maybe revisit later.
- (void)waitForPreviousAsyncMethodCompletion
{
    XCTestExpectation *expectation =
        [[XCTestExpectation alloc] initWithDescription:@"Allow the async method to be dispatched before the test ends"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [expectation fulfill];
    });
    [self waitForExpectations:@[ expectation ] timeout:10.0];
}

// Test Delete

- (void)testPerformDeleteEditingActionWithNonMediaMessage
{
    ConversationInteractionViewItem *viewItem = self.textViewItem;

    XCTAssertNotNil([self fetchMessageWithUniqueId:viewItem.interaction.uniqueId]);
    [viewItem deleteAction];
    [self waitForPreviousAsyncMethodCompletion];
    XCTAssertNil([self fetchMessageWithUniqueId:viewItem.interaction.uniqueId]);
}

- (void)testPerformDeleteActionWithPhotoMessage
{
    ConversationInteractionViewItem *viewItem = self.stillImageViewItem;

    XCTAssertEqual((NSUInteger)1, ((TSMessage *)viewItem.interaction).attachmentIds.count);
    NSString *_Nullable attachmentId = ((TSMessage *)viewItem.interaction).attachmentIds.firstObject;
    XCTAssertNotNil(attachmentId);
    TSAttachment *_Nullable attachment = [self fetchAttachmentWithUniqueId:attachmentId];
    XCTAssertTrue([attachment isKindOfClass:[TSAttachmentStream class]]);
    TSAttachmentStream *_Nullable attachmentStream = (TSAttachmentStream *)attachment;
    NSString *_Nullable filePath = attachmentStream.originalFilePath;
    XCTAssertNotNil(filePath);

    XCTAssertNotNil([self fetchMessageWithUniqueId:viewItem.interaction.uniqueId]);
    XCTAssertNotNil([self fetchAttachmentWithUniqueId:attachmentId]);
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:filePath]);
    [viewItem deleteAction];
    [self waitForPreviousAsyncMethodCompletion];
    XCTAssertNil([self fetchMessageWithUniqueId:viewItem.interaction.uniqueId]);
    XCTAssertNil([self fetchAttachmentWithUniqueId:attachmentId]);
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:filePath]);
}

- (void)testPerformDeleteEditingActionWithAnimatedMessage
{
    ConversationInteractionViewItem *viewItem = self.animatedImageViewItem;

    XCTAssertEqual((NSUInteger)1, ((TSMessage *)viewItem.interaction).attachmentIds.count);
    NSString *_Nullable attachmentId = ((TSMessage *)viewItem.interaction).attachmentIds.firstObject;
    XCTAssertNotNil(attachmentId);
    TSAttachment *_Nullable attachment = [self fetchAttachmentWithUniqueId:attachmentId];
    XCTAssertTrue([attachment isKindOfClass:[TSAttachmentStream class]]);
    TSAttachmentStream *_Nullable attachmentStream = (TSAttachmentStream *)attachment;
    NSString *_Nullable filePath = attachmentStream.originalFilePath;
    XCTAssertNotNil(filePath);

    XCTAssertNotNil([self fetchMessageWithUniqueId:viewItem.interaction.uniqueId]);
    XCTAssertNotNil([self fetchAttachmentWithUniqueId:attachmentId]);
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:filePath]);
    [viewItem deleteAction];
    [self waitForPreviousAsyncMethodCompletion];
    XCTAssertNil([self fetchMessageWithUniqueId:viewItem.interaction.uniqueId]);
    XCTAssertNil([self fetchAttachmentWithUniqueId:attachmentId]);
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:filePath]);
}

- (void)testPerformDeleteEditingActionWithVideoMessage
{
    ConversationInteractionViewItem *viewItem = self.videoViewItem;

    XCTAssertEqual((NSUInteger)1, ((TSMessage *)viewItem.interaction).attachmentIds.count);
    NSString *_Nullable attachmentId = ((TSMessage *)viewItem.interaction).attachmentIds.firstObject;
    XCTAssertNotNil(attachmentId);
    TSAttachment *_Nullable attachment = [self fetchAttachmentWithUniqueId:attachmentId];
    XCTAssertTrue([attachment isKindOfClass:[TSAttachmentStream class]]);
    TSAttachmentStream *_Nullable attachmentStream = (TSAttachmentStream *)attachment;
    NSString *_Nullable filePath = attachmentStream.originalFilePath;
    XCTAssertNotNil(filePath);

    XCTAssertNotNil([self fetchMessageWithUniqueId:viewItem.interaction.uniqueId]);
    XCTAssertNotNil([self fetchAttachmentWithUniqueId:attachmentId]);
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:filePath]);
    [viewItem deleteAction];
    [self waitForPreviousAsyncMethodCompletion];
    XCTAssertNil([self fetchMessageWithUniqueId:viewItem.interaction.uniqueId]);
    XCTAssertNil([self fetchAttachmentWithUniqueId:attachmentId]);
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:filePath]);
}

- (void)testPerformDeleteEditingActionWithAudioMessage
{
    ConversationInteractionViewItem *viewItem = self.audioViewItem;

    XCTAssertEqual((NSUInteger)1, ((TSMessage *)viewItem.interaction).attachmentIds.count);
    NSString *_Nullable attachmentId = ((TSMessage *)viewItem.interaction).attachmentIds.firstObject;
    XCTAssertNotNil(attachmentId);
    TSAttachment *_Nullable attachment = [self fetchAttachmentWithUniqueId:attachmentId];
    XCTAssertTrue([attachment isKindOfClass:[TSAttachmentStream class]]);
    TSAttachmentStream *_Nullable attachmentStream = (TSAttachmentStream *)attachment;
    NSString *_Nullable filePath = attachmentStream.originalFilePath;
    XCTAssertNotNil(filePath);

    XCTAssertNotNil([self fetchMessageWithUniqueId:viewItem.interaction.uniqueId]);
    XCTAssertNotNil([self fetchAttachmentWithUniqueId:attachmentId]);
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:filePath]);
    [viewItem deleteAction];
    [self waitForPreviousAsyncMethodCompletion];
    XCTAssertNil([self fetchMessageWithUniqueId:viewItem.interaction.uniqueId]);
    XCTAssertNil([self fetchAttachmentWithUniqueId:attachmentId]);
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:filePath]);
}

// Test Copy

- (void)testPerformCopyEditingActionWithNonMediaMessage
{
    // Reset the pasteboard.
    UIPasteboard.generalPasteboard.items = @[];
    XCTAssertNil(UIPasteboard.generalPasteboard.string);

    ConversationInteractionViewItem *viewItem = self.textViewItem;
    [viewItem copyTextAction];
    XCTAssertEqualObjects(@"abc", UIPasteboard.generalPasteboard.string);
}

- (void)unknownAction:(id)sender
{
    // It's easier to create this stub method than to suppress the "unknown selector" build warnings.
}

#pragma mark - Helpers

- (nullable TSMessage *)fetchMessageWithUniqueId:(NSString *)uniqueId
{
    __block TSMessage *_Nullable instance;
    [self readWithBlock:^(SDSAnyReadTransaction *transaction) {
        instance = [TSMessage anyFetchMessageWithUniqueId:uniqueId transaction:transaction];
    }];
    return instance;
}

- (nullable TSAttachment *)fetchAttachmentWithUniqueId:(NSString *)uniqueId
{
    __block TSAttachment *_Nullable instance;
    [self readWithBlock:^(SDSAnyReadTransaction *transaction) {
        instance = [TSAttachment anyFetchWithUniqueId:uniqueId transaction:transaction];
    }];
    return instance;
}

@end
