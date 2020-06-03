//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
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
    TSOutgoingMessageBuilder *outgoingMessageBuilder =
        [TSOutgoingMessageBuilder outgoingMessageBuilderWithThread:self.thread messageBody:@"foo"];
    outgoingMessageBuilder.timestamp = 1;
    outgoingMessageBuilder.expiresInSeconds = 100;
    TSMessage *message = [outgoingMessageBuilder build];

    XCTAssertEqual(0, message.expiresAt);
}

- (void)testExpiresAtWithStartedTimer
{
    uint64_t now = [NSDate ows_millisecondTimeStamp];
    const uint32_t expirationSeconds = 10;
    const uint32_t expirationMs = expirationSeconds * 1000;
    TSOutgoingMessageBuilder *outgoingMessageBuilder =
        [TSOutgoingMessageBuilder outgoingMessageBuilderWithThread:self.thread messageBody:@"foo"];
    outgoingMessageBuilder.timestamp = 1;
    outgoingMessageBuilder.expiresInSeconds = expirationSeconds;
    outgoingMessageBuilder.expireStartedAt = now;
    TSMessage *message = [outgoingMessageBuilder build];
    XCTAssertEqual(now + expirationMs, message.expiresAt);
}

@end

NS_ASSUME_NONNULL_END
