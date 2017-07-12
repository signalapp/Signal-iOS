//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "TSAttachmentStream.h"
#import "TSContentAdapters.h"
#import "TSOutgoingMessage.h"
#import <MobileCoreServices/MobileCoreServices.h>
#import <XCTest/XCTest.h>

@interface TSMessageAdapter (Testing)

// expose some private setters for ease of testing setup
@property (nonatomic, retain) NSString *messageBody;
@property JSQMediaItem *mediaItem;

@end

@interface TSMessageAdapterTest : XCTestCase

@property TSMessageAdapter *messageAdapter;
@property TSOutgoingMessage *message;
@property (readonly) NSData *fakeAudioData;
@property (readonly) NSData *fakeImageData;

@end

@implementation TSMessageAdapterTest

- (NSData *)fakeAudioData
{
    NSString *fakeAudioString = @"QmxhY2tiaXJkIFJhdW0gRG90IE1QMw==";
    return [[NSData alloc] initWithBase64EncodedString:fakeAudioString options:0];
}

- (NSData *)fakeVideoData
{
    NSString *fakeVideoString = @"RmFrZSBWaWRlbyBEYXRh";
    return [[NSData alloc] initWithBase64EncodedString:fakeVideoString options:0];
}

- (NSData *)fakeImageData
{
    NSString *fakeString = @"RmFrZUltYWdlRGF0YQ==";
    return [[NSData alloc] initWithBase64EncodedString:fakeString options:0];
}

- (void)setUp
{
    [super setUp];

    self.message = [[TSOutgoingMessage alloc] initWithTimestamp:1 inThread:nil messageBody:nil];
    [self.message save];

    self.messageAdapter = [TSMessageAdapter new];
    self.messageAdapter.interaction = self.message;
}

- (void)tearDown
{
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

// Test canPerformAction

- (void)testCanPerformEditingActionWithNonMediaMessage
{
    XCTAssertTrue([self.messageAdapter canPerformEditingAction:@selector(delete:)]);
    XCTAssertTrue([self.messageAdapter canPerformEditingAction:@selector(copy:)]);

    XCTAssertFalse([self.messageAdapter canPerformEditingAction:NSSelectorFromString(@"save:")]);

    //e.g. any other unsupported action
    XCTAssertFalse([self.messageAdapter canPerformEditingAction:@selector(paste:)]);
}

- (void)testCanPerformEditingActionWithPhotoMessage
{
    self.messageAdapter.mediaItem = [[TSPhotoAdapter alloc] init];

    XCTAssertTrue([self.messageAdapter canPerformEditingAction:@selector(delete:)]);
    XCTAssertTrue([self.messageAdapter canPerformEditingAction:@selector(copy:)]);
    XCTAssertTrue([self.messageAdapter canPerformEditingAction:NSSelectorFromString(@"save:")]);

    // e.g. any other unsupported action
    XCTAssertFalse([self.messageAdapter canPerformEditingAction:@selector(paste:)]);
}

- (void)testCanPerformEditingActionWithAnimatedMessage
{
    self.messageAdapter.mediaItem = [[TSAnimatedAdapter alloc] init];

    XCTAssertTrue([self.messageAdapter canPerformEditingAction:@selector(delete:)]);
    XCTAssertTrue([self.messageAdapter canPerformEditingAction:@selector(copy:)]);
    XCTAssertTrue([self.messageAdapter canPerformEditingAction:NSSelectorFromString(@"save:")]);

    // e.g. any other unsupported action
    XCTAssertFalse([self.messageAdapter canPerformEditingAction:@selector(paste:)]);
}

- (void)testCanPerformEditingActionWithVideoMessage
{
    TSAttachmentStream *videoAttachment =
    [[TSAttachmentStream alloc] initWithContentType:@"video/mp4" sourceFilename:nil];
    [videoAttachment save];
    self.messageAdapter.mediaItem = [[TSVideoAttachmentAdapter alloc] initWithAttachment:videoAttachment incoming:NO];

    XCTAssertTrue([self.messageAdapter canPerformEditingAction:@selector(delete:)]);
    XCTAssertTrue([self.messageAdapter canPerformEditingAction:@selector(copy:)]);
    XCTAssertTrue([self.messageAdapter canPerformEditingAction:NSSelectorFromString(@"save:")]);

    // e.g. any other unsupported action
    XCTAssertFalse([self.messageAdapter canPerformEditingAction:@selector(paste:)]);
}

- (void)testCanPerformEditingActionWithAudioMessage
{
    TSAttachmentStream *audioAttachment =
        [[TSAttachmentStream alloc] initWithContentType:@"audio/mp3" sourceFilename:nil];
    [audioAttachment save];
    self.messageAdapter.mediaItem = [[TSVideoAttachmentAdapter alloc] initWithAttachment:audioAttachment incoming:NO];

    XCTAssertTrue([self.messageAdapter canPerformEditingAction:@selector(delete:)]);
    XCTAssertTrue([self.messageAdapter canPerformEditingAction:@selector(copy:)]);

    //e.g. Can't save an audio attachment at this time.
    XCTAssertFalse([self.messageAdapter canPerformEditingAction:NSSelectorFromString(@"save:")]);

    //e.g. any other unsupported action
    XCTAssertFalse([self.messageAdapter canPerformEditingAction:@selector(paste:)]);
}

// Test Delete

- (void)testPerformDeleteEditingActionWithNonMediaMessage
{
    XCTAssertNotNil([TSMessage fetchObjectWithUniqueID:self.message.uniqueId]);
    [self.messageAdapter performEditingAction:@selector(delete:)];
    XCTAssertNil([TSMessage fetchObjectWithUniqueID:self.message.uniqueId]);
}

- (void)testPerformDeleteActionWithPhotoMessage
{
    XCTAssertNotNil([TSMessage fetchObjectWithUniqueID:self.message.uniqueId]);

    self.messageAdapter.mediaItem = [[TSPhotoAdapter alloc] init];
    [self.messageAdapter performEditingAction:@selector(delete:)];
    XCTAssertNil([TSMessage fetchObjectWithUniqueID:self.message.uniqueId]);
    // TODO assert files are deleted
}

- (void)testPerformDeleteEditingActionWithAnimatedMessage
{
    XCTAssertNotNil([TSMessage fetchObjectWithUniqueID:self.message.uniqueId]);

    self.messageAdapter.mediaItem = [[TSAnimatedAdapter alloc] init];
    [self.messageAdapter performEditingAction:@selector(delete:)];
    XCTAssertNil([TSMessage fetchObjectWithUniqueID:self.message.uniqueId]);
    // TODO assert files are deleted
}

- (void)testPerformDeleteEditingActionWithVideoMessage
{
    XCTAssertNotNil([TSMessage fetchObjectWithUniqueID:self.message.uniqueId]);

    NSError *error;
    TSAttachmentStream *videoAttachment =
        [[TSAttachmentStream alloc] initWithContentType:@"video/mp4" sourceFilename:nil];
    [videoAttachment writeData:[NSData new] error:&error];
    [videoAttachment save];

    [self.message.attachmentIds addObject:videoAttachment.uniqueId];
    [self.message save];

    self.messageAdapter.mediaItem = [[TSVideoAttachmentAdapter alloc] initWithAttachment:videoAttachment incoming:NO];

    // Sanity Check
    XCTAssert([[NSFileManager defaultManager] fileExistsAtPath:videoAttachment.filePath]);

    [self.messageAdapter performEditingAction:@selector(delete:)];
    XCTAssertNil([TSMessage fetchObjectWithUniqueID:self.message.uniqueId]);
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:videoAttachment.filePath]);
}

- (void)testPerformDeleteEditingActionWithAudioMessage
{
    XCTAssertNotNil([TSMessage fetchObjectWithUniqueID:self.message.uniqueId]);

    NSError *error;
    TSAttachmentStream *audioAttachment =
        [[TSAttachmentStream alloc] initWithContentType:@"audio/mp3" sourceFilename:nil];
    [audioAttachment writeData:[NSData new] error:&error];
    [audioAttachment save];

    [self.message.attachmentIds addObject:audioAttachment.uniqueId];
    [self.message save];

    // Sanity Check
    XCTAssertNil(error);
    XCTAssert([[NSFileManager defaultManager] fileExistsAtPath:audioAttachment.filePath]);

    self.messageAdapter.mediaItem = [[TSVideoAttachmentAdapter alloc] initWithAttachment:audioAttachment incoming:NO];

    [self.messageAdapter performEditingAction:@selector(delete:)];
    XCTAssertNil([TSMessage fetchObjectWithUniqueID:self.message.uniqueId]);
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:audioAttachment.filePath]);
}

// Test Copy

- (void)testPerformCopyEditingActionWithNonMediaMessage
{
    self.messageAdapter.messageBody = @"My message text";
    [self.messageAdapter performEditingAction:@selector(copy:)];
    XCTAssertEqualObjects(@"My message text", UIPasteboard.generalPasteboard.string);
}

- (void)testPerformCopyEditingActionWithPhotoMessage
{
    // reset the paste board for clean slate test
    UIPasteboard.generalPasteboard.items = @[];
    XCTAssertNil(UIPasteboard.generalPasteboard.image);

    NSError *error;
    TSAttachmentStream *attachment = [[TSAttachmentStream alloc] initWithContentType:@"image/jpeg" sourceFilename:nil];
    [attachment writeData:self.fakeAudioData error:&error];
    [attachment save];

    // Sanity Check
    XCTAssertNil(error);
    XCTAssert([[NSFileManager defaultManager] fileExistsAtPath:attachment.filePath]);

    [self.message.attachmentIds addObject:attachment.uniqueId];
    [self.message save];

    TSPhotoAdapter *photoAdapter = [[TSPhotoAdapter alloc] initWithAttachment:attachment incoming:NO];
    // assign random image, since photoAdapter expects an image.
    photoAdapter.image = [UIImage imageNamed:@"savephoto"];
    self.messageAdapter.mediaItem = photoAdapter;

    [self.messageAdapter performEditingAction:@selector(copy:)];

    NSData *copiedData = [UIPasteboard.generalPasteboard dataForPasteboardType:(NSString *)kUTTypeJPEG];
    XCTAssertEqualObjects(self.fakeAudioData, copiedData);
}

- (void)testPerformCopyEditingActionWithVideoMessage
{
    // reset the paste board for clean slate test
    UIPasteboard.generalPasteboard.items = @[];

    NSError *error;
    TSAttachmentStream *videoAttachment =
        [[TSAttachmentStream alloc] initWithContentType:@"video/mp4" sourceFilename:nil];
    [videoAttachment writeData:self.fakeVideoData error:&error];
    [videoAttachment save];
    self.messageAdapter.mediaItem = [[TSVideoAttachmentAdapter alloc] initWithAttachment:videoAttachment incoming:YES];

    [self.messageAdapter performEditingAction:@selector(copy:)];

    NSData *copiedData = [UIPasteboard.generalPasteboard dataForPasteboardType:(NSString *)kUTTypeMPEG4];
    XCTAssertEqualObjects(self.fakeVideoData, copiedData);
}

- (void)testPerformCopyEditingActionWithMp3AudioMessage
{
    UIPasteboard.generalPasteboard.items = @[];
    XCTAssertNil([UIPasteboard.generalPasteboard dataForPasteboardType:(NSString *)kUTTypeMP3]);

    NSError *error;
    TSAttachmentStream *audioAttachment =
        [[TSAttachmentStream alloc] initWithContentType:@"audio/mp3" sourceFilename:nil];
    [audioAttachment writeData:self.fakeAudioData error:&error];
    [audioAttachment save];
    self.messageAdapter.mediaItem = [[TSVideoAttachmentAdapter alloc] initWithAttachment:audioAttachment incoming:NO];

    [self.messageAdapter performEditingAction:@selector(copy:)];
    XCTAssertEqualObjects(self.fakeAudioData, [UIPasteboard.generalPasteboard dataForPasteboardType:(NSString *)kUTTypeMP3]);
}

- (void)testPerformCopyEditingActionWithM4aAudioMessage
{
    UIPasteboard.generalPasteboard.items = @[];
    XCTAssertNil([UIPasteboard.generalPasteboard dataForPasteboardType:(NSString *)kUTTypeMPEG4Audio]);

    NSError *error;
    TSAttachmentStream *audioAttachment =
        [[TSAttachmentStream alloc] initWithContentType:@"audio/x-m4a" sourceFilename:nil];
    [audioAttachment writeData:self.fakeAudioData error:&error];
    [audioAttachment save];
    self.messageAdapter.mediaItem = [[TSVideoAttachmentAdapter alloc] initWithAttachment:audioAttachment incoming:NO];

    [self.messageAdapter performEditingAction:@selector(copy:)];
    XCTAssertEqualObjects(self.fakeAudioData, [UIPasteboard.generalPasteboard dataForPasteboardType:(NSString *)kUTTypeMPEG4Audio]);
}

- (void)testPerformCopyEditingActionWithGenericAudioMessage
{
    UIPasteboard.generalPasteboard.items = @[];
    XCTAssertNil([UIPasteboard.generalPasteboard dataForPasteboardType:(NSString *)kUTTypeAudio]);

    NSError *error;
    TSAttachmentStream *audioAttachment =
        [[TSAttachmentStream alloc] initWithContentType:@"audio/wav" sourceFilename:nil];
    [audioAttachment writeData:self.fakeAudioData error:&error];
    [audioAttachment save];
    self.messageAdapter.mediaItem = [[TSVideoAttachmentAdapter alloc] initWithAttachment:audioAttachment incoming:NO];

    [self.messageAdapter performEditingAction:@selector(copy:)];
    XCTAssertEqualObjects(self.fakeAudioData, [UIPasteboard.generalPasteboard dataForPasteboardType:(NSString *)kUTTypeAudio]);
}

//  TODO - We don't currenlty have a good way of testing "copy of an animated message attachment"
//         We need an attachment with some NSData, which requires getting into the crypto layer,
//         which is outside of my realm.
//
//   Since you can't currently PASTE images into our version of JSQMessageViewController, I tested this by pasting
//   into native Messages client, and verifying the result was animated.
//
//- (void)testPerformCopyActionWithAnimatedMessage
//{
//    // reset the paste board for clean slate test
//    UIPasteboard.generalPasteboard.items = @[];
//    XCTAssertNil(UIPasteboard.generalPasteboard.image);
//
//    // "some-animated-gif" doesn't exist yet
//    NSData *imageData = [[NSData alloc] initWithContentsOfFile:@"some-animated-gif"];
//    //TODO build attachment with imageData
//    TSAttachmentStream animatedAttachement = [[TSAttachmentStream alloc] initWithIdentifier:@"test-animated-attachment-id" data:imageDatq key:@"TODO" contentType:@"image/gif"];
//    TSAnimatedAdapter *animatedAdapter = [[TSAnimatedAdapter alloc] initWithAttachment:animatedAttachment];
//    animatedAdapter.image = image;
//    self.messageAdapter.mediaItem = animatedAdapter;
//    [self.messageAdapter performEditingAction:@selector(copy:)];
//
//    // TODO XCTAssert that image is copied as a GIF (e.g. not convereted to a PNG, etc.)
//    // We want to be sure that we can copy/paste an animated GIF from
//    // one thread to the other, and ensure it's still animated.
//}

@end
