//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSDevice.h"
#import "OWSIncomingMessageFinder.h"
#import "TSContactThread.h"
#import "TSIncomingMessage.h"
#import <XCTest/XCTest.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSIncomingMessageFinder (Testing)

- (void)registerExtension;

@end

@interface OWSIncomingMessageFinderTest : XCTestCase

@property (nonatomic) NSString *sourceId;
@property (nonatomic) TSThread *thread;
@property (nonatomic) OWSIncomingMessageFinder *finder;

@end

@implementation OWSIncomingMessageFinderTest

- (void)setUp
{
    [super setUp];
    self.sourceId = @"some-source-id";
    self.thread = [TSContactThread getOrCreateThreadWithContactId:self.sourceId];
    self.finder = [OWSIncomingMessageFinder new];
    [self.finder registerExtension];
}

- (void)tearDown
{
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (void)testExistingMessages
{

    uint64_t timestamp = 1234;
    BOOL result = [self.finder existsMessageWithTimestamp:timestamp
                                                 sourceId:self.sourceId
                                           sourceDeviceId:OWSDevicePrimaryDeviceId];

    // Sanity check.
    XCTAssertFalse(result);

    // Different timestamp
    [[[TSIncomingMessage alloc] initWithTimestamp:timestamp + 1
                                         inThread:self.thread
                                         authorId:self.sourceId
                                   sourceDeviceId:OWSDevicePrimaryDeviceId
                                      messageBody:@"foo"] save];
    result = [self.finder existsMessageWithTimestamp:timestamp
                                            sourceId:self.sourceId
                                      sourceDeviceId:OWSDevicePrimaryDeviceId];
    XCTAssertFalse(result);

    // Different authorId
    [[[TSIncomingMessage alloc] initWithTimestamp:timestamp
                                         inThread:self.thread
                                         authorId:@"some-other-author-id"
                                   sourceDeviceId:OWSDevicePrimaryDeviceId
                                      messageBody:@"foo"] save];

    result = [self.finder existsMessageWithTimestamp:timestamp
                                            sourceId:self.sourceId
                                      sourceDeviceId:OWSDevicePrimaryDeviceId];
    XCTAssertFalse(result);

    // Different device
    [[[TSIncomingMessage alloc] initWithTimestamp:timestamp
                                         inThread:self.thread
                                         authorId:self.sourceId
                                   sourceDeviceId:OWSDevicePrimaryDeviceId + 1
                                      messageBody:@"foo"] save];

    result = [self.finder existsMessageWithTimestamp:timestamp
                                            sourceId:self.sourceId
                                      sourceDeviceId:OWSDevicePrimaryDeviceId];
    XCTAssertFalse(result);

    // The real deal...
    [[[TSIncomingMessage alloc] initWithTimestamp:timestamp
                                         inThread:self.thread
                                         authorId:self.sourceId
                                   sourceDeviceId:OWSDevicePrimaryDeviceId
                                      messageBody:@"foo"] save];

    result = [self.finder existsMessageWithTimestamp:timestamp
                                            sourceId:self.sourceId
                                      sourceDeviceId:OWSDevicePrimaryDeviceId];
    XCTAssertTrue(result);
}

@end

NS_ASSUME_NONNULL_END
