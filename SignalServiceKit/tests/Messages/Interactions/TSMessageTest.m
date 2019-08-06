//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "SSKBaseTestObjC.h"
#import "TSAttachmentStream.h"
#import "TSContactThread.h"
#import "TSMessage.h"
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface TSMessageTest : SSKBaseTestObjC

@property TSThread *thread;

@end

@implementation TSMessageTest

- (void)setUp {
    [super setUp];
    self.thread = [TSContactThread
        getOrCreateThreadWithContactAddress:[[SignalServiceAddress alloc] initWithPhoneNumber:@"fake-thread-id"]];
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
                                                        contactShare:nil
                                                         linkPreview:nil
                                                      messageSticker:nil
                                                   isViewOnceMessage:NO];

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
                                                        contactShare:nil
                                                         linkPreview:nil
                                                      messageSticker:nil
                                                   isViewOnceMessage:NO];
    XCTAssertEqual(now + expirationMs, message.expiresAt);
}

@end

NS_ASSUME_NONNULL_END
