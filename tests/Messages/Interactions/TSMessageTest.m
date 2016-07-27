//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "TSMessage.h"
#import "TSThread.h"
#import "TSAttachment.h"

#import <XCTest/XCTest.h>

@interface TSMessageTest : XCTestCase

@end

@implementation TSMessageTest

- (void)setUp {
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (void)testDescription {
    TSThread *thread = [[TSThread alloc] init];
    TSMessage *message = [[TSMessage alloc] initWithTimestamp:1 inThread:thread messageBody:@"My message body" attachments:nil];
    XCTAssertEqualObjects(@"My message body", [message description]);
}

- (void)testDescriptionWithBogusAttachmentId {
    TSThread *thread = [[TSThread alloc] init];
    TSMessage *message = [[TSMessage alloc] initWithTimestamp:1 inThread:thread messageBody:@"My message body" attachments:@[@"fake-attachment-id"]];
    NSString *actualDescription = [message description];
    XCTAssertEqualObjects(@"UNKNOWN_ATTACHMENT_LABEL", actualDescription);
}

- (void)testDescriptionWithEmptyAttachments {
    TSThread *thread = [[TSThread alloc] init];
    TSMessage *message = [[TSMessage alloc] initWithTimestamp:1 inThread:thread messageBody:@"My message body" attachments:@[]];
    NSString *actualDescription = [message description];
    XCTAssertEqualObjects(@"My message body", actualDescription);
}

- (void)testDescriptionWithPhotoAttachmentId {
    TSThread *thread = [[TSThread alloc] init];
    TSAttachment *attachment = [[TSAttachment alloc] initWithIdentifier:@"fake-photo-attachment-id"
                                                        encryptionKey:[[NSData alloc] init]
                                                            contentType:@"image/jpeg"];
    [attachment save];

    TSMessage *message = [[TSMessage alloc] initWithTimestamp:1 inThread:thread messageBody:@"My message body" attachments:@[@"fake-photo-attachment-id"]];
    NSString *actualDescription = [message description];
    XCTAssertEqualObjects(@"📷 ATTACHMENT", actualDescription);
}


- (void)testDescriptionWithVideoAttachmentId {
    TSThread *thread = [[TSThread alloc] init];
    TSAttachment *attachment = [[TSAttachment alloc] initWithIdentifier:@"fake-video-attachment-id"
                                                          encryptionKey:[[NSData alloc] init]
                                                            contentType:@"video/mp4"];
    [attachment save];

    TSMessage *message = [[TSMessage alloc] initWithTimestamp:1 inThread:thread messageBody:@"My message body" attachments:@[@"fake-video-attachment-id"]];
    NSString *actualDescription = [message description];
    XCTAssertEqualObjects(@"📽 ATTACHMENT", actualDescription);
}


- (void)testDescriptionWithAudioAttachmentId {
    TSThread *thread = [[TSThread alloc] init];
    TSAttachment *attachment = [[TSAttachment alloc] initWithIdentifier:@"fake-audio-attachment-id"
                                                          encryptionKey:[[NSData alloc] init]
                                                            contentType:@"audio/mp3"];
    [attachment save];

    TSMessage *message = [[TSMessage alloc] initWithTimestamp:1 inThread:thread messageBody:@"My message body" attachments:@[@"fake-audio-attachment-id"]];
    NSString *actualDescription = [message description];
    XCTAssertEqualObjects(@"📻 ATTACHMENT", actualDescription);
}

- (void)testDescriptionWithUnkownAudioContentType {
    TSThread *thread = [[TSThread alloc] init];
    TSAttachment *attachment = [[TSAttachment alloc] initWithIdentifier:@"fake-nonsense-attachment-id"
                                                          encryptionKey:[[NSData alloc] init]
                                                            contentType:@"non/sense"];
    [attachment save];

    TSMessage *message = [[TSMessage alloc] initWithTimestamp:1 inThread:thread messageBody:@"My message body" attachments:@[@"fake-nonsense-attachment-id"]];
    NSString *actualDescription = [message description];
    XCTAssertEqualObjects(@"ATTACHMENT", actualDescription);
}

@end
