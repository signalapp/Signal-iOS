//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "ConversationViewItem.h"
#import <MobileCoreServices/MobileCoreServices.h>
#import <SignalServiceKit/SecurityUtils.h>
#import <SignalServiceKit/TSAttachmentStream.h>
#import <SignalServiceKit/TSOutgoingMessage.h>
#import <XCTest/XCTest.h>
#import <YapDatabase/YapDatabaseConnection.h>

@interface ConversationViewItem (Testing)

- (SEL)copyActionSelector;
- (SEL)saveActionSelector;
- (SEL)shareActionSelector;
- (SEL)deleteActionSelector;
- (SEL)metadataActionSelector;

@end

@interface ConversationViewItemTest : XCTestCase

@end

@implementation ConversationViewItemTest

- (void)setUp
{
    [super setUp];
}

- (void)tearDown
{
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

// Test canPerformAction

- (NSString *)fakeTextMessageText
{
    return @"abc";
}

- (ConversationViewItem *)textViewItem
{
    TSOutgoingMessage *message =
        [[TSOutgoingMessage alloc] initWithTimestamp:1 inThread:nil messageBody:self.fakeTextMessageText];
    [message save];
    __block ConversationViewItem *viewItem = nil;
    [TSYapDatabaseObject.dbReadConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        viewItem = [[ConversationViewItem alloc] initWithInteraction:message isGroupThread:NO transaction:transaction];
    }];
    return viewItem;
}

- (ConversationViewItem *)viewItemWithAttachmentMimetype:(NSString *)mimeType filename:(NSString *)filename
{
    OWSAssert(filename.length > 0);

    NSString *resourcePath = [[NSBundle bundleForClass:[self class]] resourcePath];
    NSString *filePath = [resourcePath stringByAppendingPathComponent:filename];

    OWSAssert([[NSFileManager defaultManager] fileExistsAtPath:filePath]);

    DataSource *dataSource = [DataSourcePath dataSourceWithFilePath:filePath];
    TSAttachmentStream *attachment = [[TSAttachmentStream alloc] initWithContentType:mimeType
                                                                           byteCount:(UInt32)dataSource.dataLength
                                                                      sourceFilename:nil];
    BOOL success = [attachment writeDataSource:dataSource];
    OWSAssert(success);
    [attachment save];
    NSMutableArray<NSString *> *attachmentIds = [@[
        attachment.uniqueId,
    ] mutableCopy];
    TSOutgoingMessage *message =
        [[TSOutgoingMessage alloc] initWithTimestamp:1 inThread:nil messageBody:nil attachmentIds:attachmentIds];
    [message save];

    __block ConversationViewItem *viewItem = nil;
    [TSYapDatabaseObject.dbReadConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        viewItem = [[ConversationViewItem alloc] initWithInteraction:message isGroupThread:NO transaction:transaction];
    }];

    return viewItem;
}

- (ConversationViewItem *)stillImageViewItem
{
    return [self viewItemWithAttachmentMimetype:@"image/jpeg" filename:@"test-jpg.jpg"];
}

- (ConversationViewItem *)animatedImageViewItem
{
    return [self viewItemWithAttachmentMimetype:@"image/gif" filename:@"test-gif.gif"];
}

- (ConversationViewItem *)videoViewItem
{
    return [self viewItemWithAttachmentMimetype:@"video/mp4" filename:@"test-mp4.mp4"];
}

- (ConversationViewItem *)audioViewItem
{
    return [self viewItemWithAttachmentMimetype:@"audio/mp3" filename:@"test-mp3.mp3"];
}

- (void)testCanPerformEditingActionWithNonMediaMessage
{
    ConversationViewItem *viewItem = self.textViewItem;

    XCTAssertTrue([viewItem canPerformAction:viewItem.copyActionSelector]);
    XCTAssertFalse([viewItem canPerformAction:viewItem.saveActionSelector]);
    XCTAssertTrue([viewItem canPerformAction:viewItem.shareActionSelector]);
    XCTAssertTrue([viewItem canPerformAction:viewItem.deleteActionSelector]);
    XCTAssertTrue([viewItem canPerformAction:viewItem.metadataActionSelector]);
    XCTAssertFalse([viewItem canPerformAction:@selector(unknownAction:)]);
}

- (void)testCanPerformEditingActionWithPhotoMessage
{
    ConversationViewItem *viewItem = self.stillImageViewItem;

    XCTAssertTrue([viewItem canPerformAction:viewItem.copyActionSelector]);
    XCTAssertTrue([viewItem canPerformAction:viewItem.saveActionSelector]);
    XCTAssertTrue([viewItem canPerformAction:viewItem.shareActionSelector]);
    XCTAssertTrue([viewItem canPerformAction:viewItem.deleteActionSelector]);
    XCTAssertTrue([viewItem canPerformAction:viewItem.metadataActionSelector]);
    XCTAssertFalse([viewItem canPerformAction:@selector(unknownAction:)]);
}

- (void)testCanPerformEditingActionWithAnimatedMessage
{
    ConversationViewItem *viewItem = self.animatedImageViewItem;

    XCTAssertTrue([viewItem canPerformAction:viewItem.copyActionSelector]);
    XCTAssertTrue([viewItem canPerformAction:viewItem.saveActionSelector]);
    XCTAssertTrue([viewItem canPerformAction:viewItem.shareActionSelector]);
    XCTAssertTrue([viewItem canPerformAction:viewItem.deleteActionSelector]);
    XCTAssertTrue([viewItem canPerformAction:viewItem.metadataActionSelector]);
    XCTAssertFalse([viewItem canPerformAction:@selector(unknownAction:)]);
}

- (void)testCanPerformEditingActionWithVideoMessage
{
    ConversationViewItem *viewItem = self.videoViewItem;

    XCTAssertTrue([viewItem canPerformAction:viewItem.copyActionSelector]);
    XCTAssertTrue([viewItem canPerformAction:viewItem.saveActionSelector]);
    XCTAssertTrue([viewItem canPerformAction:viewItem.shareActionSelector]);
    XCTAssertTrue([viewItem canPerformAction:viewItem.deleteActionSelector]);
    XCTAssertTrue([viewItem canPerformAction:viewItem.metadataActionSelector]);
    XCTAssertFalse([viewItem canPerformAction:@selector(unknownAction:)]);
}

- (void)testCanPerformEditingActionWithAudioMessage
{
    ConversationViewItem *viewItem = self.audioViewItem;

    XCTAssertTrue([viewItem canPerformAction:viewItem.copyActionSelector]);
    XCTAssertFalse([viewItem canPerformAction:viewItem.saveActionSelector]);
    XCTAssertTrue([viewItem canPerformAction:viewItem.shareActionSelector]);
    XCTAssertTrue([viewItem canPerformAction:viewItem.deleteActionSelector]);
    XCTAssertTrue([viewItem canPerformAction:viewItem.metadataActionSelector]);
    XCTAssertFalse([viewItem canPerformAction:@selector(unknownAction:)]);
}

// Test Delete

- (void)testPerformDeleteEditingActionWithNonMediaMessage
{
    ConversationViewItem *viewItem = self.textViewItem;

    XCTAssertNotNil([TSMessage fetchObjectWithUniqueID:viewItem.interaction.uniqueId]);
    [viewItem deleteAction];
    XCTAssertNil([TSMessage fetchObjectWithUniqueID:viewItem.interaction.uniqueId]);
}

- (void)testPerformDeleteActionWithPhotoMessage
{
    ConversationViewItem *viewItem = self.stillImageViewItem;

    XCTAssertEqual((NSUInteger)1, ((TSMessage *)viewItem.interaction).attachmentIds.count);
    NSString *_Nullable attachmentId = ((TSMessage *)viewItem.interaction).attachmentIds.firstObject;
    XCTAssertNotNil(attachmentId);
    TSAttachment *_Nullable attachment = [TSAttachment fetchObjectWithUniqueID:attachmentId];
    XCTAssertTrue([attachment isKindOfClass:[TSAttachmentStream class]]);
    TSAttachmentStream *_Nullable attachmentStream = (TSAttachmentStream *)attachment;
    NSString *_Nullable filePath = attachmentStream.filePath;
    XCTAssertNotNil(filePath);

    XCTAssertNotNil([TSMessage fetchObjectWithUniqueID:viewItem.interaction.uniqueId]);
    XCTAssertNotNil([TSAttachment fetchObjectWithUniqueID:attachmentId]);
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:filePath]);
    [viewItem deleteAction];
    XCTAssertNil([TSMessage fetchObjectWithUniqueID:viewItem.interaction.uniqueId]);
    XCTAssertNil([TSAttachment fetchObjectWithUniqueID:attachmentId]);
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:filePath]);
}

- (void)testPerformDeleteEditingActionWithAnimatedMessage
{
    ConversationViewItem *viewItem = self.animatedImageViewItem;

    XCTAssertEqual((NSUInteger)1, ((TSMessage *)viewItem.interaction).attachmentIds.count);
    NSString *_Nullable attachmentId = ((TSMessage *)viewItem.interaction).attachmentIds.firstObject;
    XCTAssertNotNil(attachmentId);
    TSAttachment *_Nullable attachment = [TSAttachment fetchObjectWithUniqueID:attachmentId];
    XCTAssertTrue([attachment isKindOfClass:[TSAttachmentStream class]]);
    TSAttachmentStream *_Nullable attachmentStream = (TSAttachmentStream *)attachment;
    NSString *_Nullable filePath = attachmentStream.filePath;
    XCTAssertNotNil(filePath);

    XCTAssertNotNil([TSMessage fetchObjectWithUniqueID:viewItem.interaction.uniqueId]);
    XCTAssertNotNil([TSAttachment fetchObjectWithUniqueID:attachmentId]);
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:filePath]);
    [viewItem deleteAction];
    XCTAssertNil([TSMessage fetchObjectWithUniqueID:viewItem.interaction.uniqueId]);
    XCTAssertNil([TSAttachment fetchObjectWithUniqueID:attachmentId]);
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:filePath]);
}

- (void)testPerformDeleteEditingActionWithVideoMessage
{
    ConversationViewItem *viewItem = self.videoViewItem;

    XCTAssertEqual((NSUInteger)1, ((TSMessage *)viewItem.interaction).attachmentIds.count);
    NSString *_Nullable attachmentId = ((TSMessage *)viewItem.interaction).attachmentIds.firstObject;
    XCTAssertNotNil(attachmentId);
    TSAttachment *_Nullable attachment = [TSAttachment fetchObjectWithUniqueID:attachmentId];
    XCTAssertTrue([attachment isKindOfClass:[TSAttachmentStream class]]);
    TSAttachmentStream *_Nullable attachmentStream = (TSAttachmentStream *)attachment;
    NSString *_Nullable filePath = attachmentStream.filePath;
    XCTAssertNotNil(filePath);

    XCTAssertNotNil([TSMessage fetchObjectWithUniqueID:viewItem.interaction.uniqueId]);
    XCTAssertNotNil([TSAttachment fetchObjectWithUniqueID:attachmentId]);
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:filePath]);
    [viewItem deleteAction];
    XCTAssertNil([TSMessage fetchObjectWithUniqueID:viewItem.interaction.uniqueId]);
    XCTAssertNil([TSAttachment fetchObjectWithUniqueID:attachmentId]);
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:filePath]);
}

- (void)testPerformDeleteEditingActionWithAudioMessage
{
    ConversationViewItem *viewItem = self.audioViewItem;

    XCTAssertEqual((NSUInteger)1, ((TSMessage *)viewItem.interaction).attachmentIds.count);
    NSString *_Nullable attachmentId = ((TSMessage *)viewItem.interaction).attachmentIds.firstObject;
    XCTAssertNotNil(attachmentId);
    TSAttachment *_Nullable attachment = [TSAttachment fetchObjectWithUniqueID:attachmentId];
    XCTAssertTrue([attachment isKindOfClass:[TSAttachmentStream class]]);
    TSAttachmentStream *_Nullable attachmentStream = (TSAttachmentStream *)attachment;
    NSString *_Nullable filePath = attachmentStream.filePath;
    XCTAssertNotNil(filePath);

    XCTAssertNotNil([TSMessage fetchObjectWithUniqueID:viewItem.interaction.uniqueId]);
    XCTAssertNotNil([TSAttachment fetchObjectWithUniqueID:attachmentId]);
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:filePath]);
    [viewItem deleteAction];
    XCTAssertNil([TSMessage fetchObjectWithUniqueID:viewItem.interaction.uniqueId]);
    XCTAssertNil([TSAttachment fetchObjectWithUniqueID:attachmentId]);
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:filePath]);
}

// Test Copy

- (void)testPerformCopyEditingActionWithNonMediaMessage
{
    // Reset the pasteboard.
    UIPasteboard.generalPasteboard.items = @[];
    XCTAssertNil(UIPasteboard.generalPasteboard.string);

    ConversationViewItem *viewItem = self.textViewItem;
    [viewItem copyTextAction];
    XCTAssertEqualObjects(self.fakeTextMessageText, UIPasteboard.generalPasteboard.string);
}

- (void)testPerformCopyEditingActionWithStillImageMessage
{
    // Reset the pasteboard.
    UIPasteboard.generalPasteboard.items = @[];
    XCTAssertNil(UIPasteboard.generalPasteboard.image);
    XCTAssertNil([UIPasteboard.generalPasteboard dataForPasteboardType:(NSString *)kUTTypeJPEG]);

    ConversationViewItem *viewItem = self.stillImageViewItem;
    [viewItem copyMediaAction];
    NSData *_Nullable copiedData = [UIPasteboard.generalPasteboard dataForPasteboardType:(NSString *)kUTTypeJPEG];
    XCTAssertTrue(copiedData.length > 0);
}

- (void)testPerformCopyEditingActionWithAnimatedImageMessage
{
    // Reset the pasteboard.
    UIPasteboard.generalPasteboard.items = @[];
    XCTAssertNil(UIPasteboard.generalPasteboard.image);
    XCTAssertNil([UIPasteboard.generalPasteboard dataForPasteboardType:(NSString *)kUTTypeGIF]);

    ConversationViewItem *viewItem = self.animatedImageViewItem;
    [viewItem copyMediaAction];
    NSData *_Nullable copiedData = [UIPasteboard.generalPasteboard dataForPasteboardType:(NSString *)kUTTypeGIF];
    XCTAssertTrue(copiedData.length > 0);
}

- (void)testPerformCopyEditingActionWithVideoMessage
{
    // Reset the pasteboard.
    UIPasteboard.generalPasteboard.items = @[];
    XCTAssertNil([UIPasteboard.generalPasteboard dataForPasteboardType:(NSString *)kUTTypeMPEG4]);

    ConversationViewItem *viewItem = self.videoViewItem;
    [viewItem copyMediaAction];
    NSData *_Nullable copiedData = [UIPasteboard.generalPasteboard dataForPasteboardType:(NSString *)kUTTypeMPEG4];
    XCTAssertTrue(copiedData.length > 0);
}

- (void)testPerformCopyEditingActionWithMp3AudioMessage
{
    // Reset the pasteboard.
    UIPasteboard.generalPasteboard.items = @[];
    XCTAssertNil([UIPasteboard.generalPasteboard dataForPasteboardType:(NSString *)kUTTypeMP3]);

    ConversationViewItem *viewItem = self.audioViewItem;
    [viewItem copyMediaAction];
    NSData *_Nullable copiedData = [UIPasteboard.generalPasteboard dataForPasteboardType:(NSString *)kUTTypeMP3];
    XCTAssertTrue(copiedData.length > 0);
}

- (void)unknownAction:(id)sender
{
    // It's easier to create this stub method than to suppress the "unknown selector" build warnings.
}

@end
