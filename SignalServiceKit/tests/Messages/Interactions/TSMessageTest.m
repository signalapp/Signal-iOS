//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSMessage.h"
#import "NSDate+OWS.h"
#import "SSKBaseTest.h"
#import "TSAttachmentStream.h"
#import "TSContactThread.h"

NS_ASSUME_NONNULL_BEGIN

@interface TSMessageTest : SSKBaseTest

@property TSThread *thread;

@end

@implementation TSMessageTest

- (void)setUp {
    [super setUp];
    self.thread = [TSContactThread getOrCreateThreadWithContactId:@"fake-thread-id"];
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (void)testExpiresAtWithoutStartedTimer
{
    TSMessage *message = [[TSMessage alloc] initMessageWithTimestamp:1
                                                            inThread:self.thread
                                                         messageBody:@"foo"
                                                       attachmentIds:@[]
                                                    expiresInSeconds:100
                                                     expireStartedAt:0
                                                       quotedMessage:nil
                                                        contactShare:nil];

    XCTAssertEqual(0, message.expiresAt);
}

- (void)testExpiresAtWithStartedTimer
{
    uint64_t now = [NSDate ows_millisecondTimeStamp];
    const uint32_t expirationSeconds = 10;
    const uint32_t expirationMs = expirationSeconds * 1000;
    TSMessage *message = [[TSMessage alloc] initMessageWithTimestamp:1
                                                            inThread:self.thread
                                                         messageBody:@"foo"
                                                       attachmentIds:@[]
                                                    expiresInSeconds:expirationSeconds
                                                     expireStartedAt:now
                                                       quotedMessage:nil
                                                        contactShare:nil];
    XCTAssertEqual(now + expirationMs, message.expiresAt);
}

@end

NS_ASSUME_NONNULL_END
