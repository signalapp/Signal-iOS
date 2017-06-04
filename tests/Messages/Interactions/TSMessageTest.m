//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "NSDate+millisecondTimeStamp.h"
#import "TSAttachmentStream.h"
#import "TSMessage.h"
#import "TSThread.h"

#import <XCTest/XCTest.h>

NS_ASSUME_NONNULL_BEGIN

@interface TSMessageTest : XCTestCase

@property TSThread *thread;

@end

@implementation TSMessageTest

- (void)setUp {
    [super setUp];
    self.thread = [[TSThread alloc] init];
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (void)testExpiresAtWithoutStartedTimer
{
    TSMessage *message = [[TSMessage alloc] initWithTimestamp:1
                                                     inThread:self.thread
                                                  messageBody:@"foo"
                                                attachmentIds:@[]
                                             expiresInSeconds:100];
    XCTAssertEqual(0, message.expiresAt);
}

- (void)testExpiresAtWithStartedTimer
{
    uint64_t now = [NSDate ows_millisecondTimeStamp];
    TSMessage *message = [[TSMessage alloc] initWithTimestamp:1
                                                     inThread:self.thread
                                                  messageBody:@"foo"
                                                attachmentIds:@[]
                                             expiresInSeconds:10
                                              expireStartedAt:now];
    XCTAssertEqual(now + 10000, message.expiresAt);
}

- (void)testDescription
{
    TSMessage *message = [[TSMessage alloc] initWithTimestamp:1 inThread:self.thread messageBody:@"My message body"];
    XCTAssertEqualObjects(@"My message body", [message description]);
}

- (void)testDescriptionWithBogusAttachmentId
{
    TSMessage *message = [[TSMessage alloc] initWithTimestamp:1
                                                     inThread:self.thread
                                                  messageBody:@"My message body"
                                                attachmentIds:@[ @"fake-attachment-id" ]];
    NSString *actualDescription = [message description];
    XCTAssertEqualObjects(@"UNKNOWN_ATTACHMENT_LABEL", actualDescription);
}

- (void)testDescriptionWithEmptyAttachments
{
    TSMessage *message =
        [[TSMessage alloc] initWithTimestamp:1 inThread:self.thread messageBody:@"My message body" attachmentIds:@[]];
    NSString *actualDescription = [message description];
    XCTAssertEqualObjects(@"My message body", actualDescription);
}

- (void)testDescriptionWithPhotoAttachmentId
{
    TSAttachment *attachment = [[TSAttachmentStream alloc] initWithContentType:@"image/jpeg" sourceFilename:nil];
    [attachment save];

    TSMessage *message = [[TSMessage alloc] initWithTimestamp:1
                                                     inThread:self.thread
                                                  messageBody:@"My message body"
                                                attachmentIds:@[ attachment.uniqueId ]];
    NSString *actualDescription = [message description];
    XCTAssertEqualObjects(@"📷 ATTACHMENT", actualDescription);
}


- (void)testDescriptionWithVideoAttachmentId
{
    TSAttachment *attachment = [[TSAttachmentStream alloc] initWithContentType:@"video/mp4" sourceFilename:nil];
    [attachment save];

    TSMessage *message = [[TSMessage alloc] initWithTimestamp:1
                                                     inThread:self.thread
                                                  messageBody:@"My message body"
                                                attachmentIds:@[ attachment.uniqueId ]];
    NSString *actualDescription = [message description];
    XCTAssertEqualObjects(@"📽 ATTACHMENT", actualDescription);
}


- (void)testDescriptionWithAudioAttachmentId
{
    TSAttachment *attachment = [[TSAttachmentStream alloc] initWithContentType:@"audio/mp3" sourceFilename:nil];
    [attachment save];

    TSMessage *message = [[TSMessage alloc] initWithTimestamp:1
                                                     inThread:self.thread
                                                  messageBody:@"My message body"
                                                attachmentIds:@[ attachment.uniqueId ]];
    NSString *actualDescription = [message description];
    XCTAssertEqualObjects(@"📻 ATTACHMENT", actualDescription);
}

- (void)testDescriptionWithUnkownAudioContentType
{
    TSAttachment *attachment = [[TSAttachmentStream alloc] initWithContentType:@"non/sense" sourceFilename:nil];
    [attachment save];

    TSMessage *message = [[TSMessage alloc] initWithTimestamp:1
                                                     inThread:self.thread
                                                  messageBody:@"My message body"
                                                attachmentIds:@[ attachment.uniqueId ]];
    NSString *actualDescription = [message description];
    XCTAssertEqualObjects(@"ATTACHMENT", actualDescription);
}

@end

NS_ASSUME_NONNULL_END
