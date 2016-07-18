//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "TSAttachmentStream.h"
#import "TSContentAdapters.h"
#import "TSInteraction.h"
#import <MobileCoreServices/MobileCoreServices.h>
#import <XCTest/XCTest.h>

static NSString * const kTestingInteractionId = @"some-fake-testing-id";

@interface TSMessageAdapter (Testing)

// expose some private setters for ease of testing setup
@property (nonatomic, retain) NSString *messageBody;
@property JSQMediaItem *mediaItem;

@end

@interface TSMessageAdapterTest : XCTestCase

@property TSMessageAdapter *messageAdapter;
@property TSInteraction *interaction;
@property (readonly) NSData *fakeAudioData;

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

- (void)setUp
{
    [super setUp];

    self.messageAdapter = [[TSMessageAdapter alloc] init];

    self.interaction = [[TSInteraction alloc] initWithUniqueId:kTestingInteractionId];
    [self.interaction save];
    self.messageAdapter.interaction = self.interaction;
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
    TSAttachmentStream *videoAttachment = [[TSAttachmentStream alloc] initWithIdentifier:@"fake-video-message" encryptionKey:nil contentType:@"video/mp4"];
    self.messageAdapter.mediaItem = [[TSVideoAttachmentAdapter alloc] initWithAttachment:videoAttachment incoming:NO];

    XCTAssertTrue([self.messageAdapter canPerformEditingAction:@selector(delete:)]);
    XCTAssertTrue([self.messageAdapter canPerformEditingAction:@selector(copy:)]);
    XCTAssertTrue([self.messageAdapter canPerformEditingAction:NSSelectorFromString(@"save:")]);

    // e.g. any other unsupported action
    XCTAssertFalse([self.messageAdapter canPerformEditingAction:@selector(paste:)]);
}

- (void)testCanPerformEditingActionWithAudioMessage
{
    TSAttachmentStream *audioAttachment = [[TSAttachmentStream alloc] initWithIdentifier:@"fake-audio-message" encryptionKey:nil contentType:@"audio/mp3"];
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
    XCTAssertNotNil([TSInteraction fetchObjectWithUniqueID:kTestingInteractionId]);
    [self.messageAdapter performEditingAction:@selector(delete:)];
    XCTAssertNil([TSInteraction fetchObjectWithUniqueID:kTestingInteractionId]);
}

- (void)testPerformDeleteActionWithPhotoMessage
{
    XCTAssertNotNil([TSInteraction fetchObjectWithUniqueID:kTestingInteractionId]);

    self.messageAdapter.mediaItem = [[TSPhotoAdapter alloc] init];
    [self.messageAdapter performEditingAction:@selector(delete:)];
    XCTAssertNil([TSInteraction fetchObjectWithUniqueID:kTestingInteractionId]);
    // TODO assert files are deleted
}

- (void)testPerformDeleteEditingActionWithAnimatedMessage
{
    XCTAssertNotNil([TSInteraction fetchObjectWithUniqueID:kTestingInteractionId]);

    self.messageAdapter.mediaItem = [[TSAnimatedAdapter alloc] init];
    [self.messageAdapter performEditingAction:@selector(delete:)];
    XCTAssertNil([TSInteraction fetchObjectWithUniqueID:kTestingInteractionId]);
    // TODO assert files are deleted
}

- (void)testPerformDeleteEditingActionWithVideoMessage
{
    XCTAssertNotNil([TSInteraction fetchObjectWithUniqueID:kTestingInteractionId]);

    TSAttachmentStream *videoAttachment = [[TSAttachmentStream alloc] initWithIdentifier:@"fake-video-message" encryptionKey:nil contentType:@"video/mp4"];
    self.messageAdapter.mediaItem = [[TSVideoAttachmentAdapter alloc] initWithAttachment:videoAttachment incoming:NO];

    [self.messageAdapter performEditingAction:@selector(delete:)];
    XCTAssertNil([TSInteraction fetchObjectWithUniqueID:kTestingInteractionId]);
    // TODO assert files are deleted
}

- (void)testPerformDeleteEditingActionWithAudioMessage
{
    XCTAssertNotNil([TSInteraction fetchObjectWithUniqueID:kTestingInteractionId]);

    TSAttachmentStream *audioAttachment = [[TSAttachmentStream alloc] initWithIdentifier:@"fake-audio-message" encryptionKey:nil contentType:@"audio/mp3"];
    self.messageAdapter.mediaItem = [[TSVideoAttachmentAdapter alloc] initWithAttachment:audioAttachment incoming:NO];

    [self.messageAdapter performEditingAction:@selector(delete:)];
    XCTAssertNil([TSInteraction fetchObjectWithUniqueID:kTestingInteractionId]);
    // TODO assert files are deleted
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

    // Grab some random existing image
    UIImage *image = [UIImage imageNamed:@"savephoto"];
    TSPhotoAdapter *photoAdapter = [[TSPhotoAdapter alloc] initWithImage:image];
    self.messageAdapter.mediaItem = photoAdapter;
    [self.messageAdapter performEditingAction:@selector(copy:)];

    XCTAssertNotNil(UIPasteboard.generalPasteboard.image);
}

- (void)testPerformCopyEditingActionWithVideoMessage
{
    // reset the paste board for clean slate test
    UIPasteboard.generalPasteboard.items = @[];
    TSAttachmentStream *videoAttachment = [[TSAttachmentStream alloc] initWithIdentifier:@"fake-video" data:self.fakeVideoData key:nil contentType:@"video/mp4"];
    self.messageAdapter.mediaItem = [[TSVideoAttachmentAdapter alloc] initWithAttachment:videoAttachment incoming:YES];

    [self.messageAdapter performEditingAction:@selector(copy:)];

    NSData *copiedData = [UIPasteboard.generalPasteboard dataForPasteboardType:(NSString *)kUTTypeMPEG4];
    XCTAssertEqualObjects(self.fakeVideoData, copiedData);
}

- (void)testPerformCopyEditingActionWithMp3AudioMessage
{
    UIPasteboard.generalPasteboard.items = @[];
    XCTAssertNil([UIPasteboard.generalPasteboard dataForPasteboardType:(NSString *)kUTTypeMP3]);

    TSAttachmentStream *audioAttachment = [[TSAttachmentStream alloc] initWithIdentifier:@"fake-audio-message" data:self.fakeAudioData key:nil contentType:@"audio/mp3"];
    self.messageAdapter.mediaItem = [[TSVideoAttachmentAdapter alloc] initWithAttachment:audioAttachment incoming:NO];

    [self.messageAdapter performEditingAction:@selector(copy:)];
    XCTAssertEqualObjects(self.fakeAudioData, [UIPasteboard.generalPasteboard dataForPasteboardType:(NSString *)kUTTypeMP3]);
}

- (void)testPerformCopyEditingActionWithM4aAudioMessage
{
    UIPasteboard.generalPasteboard.items = @[];
    XCTAssertNil([UIPasteboard.generalPasteboard dataForPasteboardType:(NSString *)kUTTypeMPEG4Audio]);

    TSAttachmentStream *audioAttachment = [[TSAttachmentStream alloc] initWithIdentifier:@"fake-audio-message" data:self.fakeAudioData key:nil contentType:@"audio/x-m4a"];
    self.messageAdapter.mediaItem = [[TSVideoAttachmentAdapter alloc] initWithAttachment:audioAttachment incoming:NO];

    [self.messageAdapter performEditingAction:@selector(copy:)];
    XCTAssertEqualObjects(self.fakeAudioData, [UIPasteboard.generalPasteboard dataForPasteboardType:(NSString *)kUTTypeMPEG4Audio]);
}

- (void)testPerformCopyEditingActionWithGenericAudioMessage
{
    UIPasteboard.generalPasteboard.items = @[];
    XCTAssertNil([UIPasteboard.generalPasteboard dataForPasteboardType:(NSString *)kUTTypeAudio]);

    TSAttachmentStream *audioAttachment = [[TSAttachmentStream alloc] initWithIdentifier:@"fake-audio-message" data:self.fakeAudioData key:nil contentType:@"audio/wav"];
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
