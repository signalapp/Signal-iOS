//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSDevice.h"
#import "OWSIncomingMessageFinder.h"
#import "OWSPrimaryStorage.h"
#import "SSKBaseTestObjC.h"
#import "TSContactThread.h"
#import "TSIncomingMessage.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSIncomingMessageFinder (Testing)

- (void)registerExtension;

@end

@interface OWSIncomingMessageFinderTest : SSKBaseTestObjC

@property (nonatomic) NSString *sourceId;
@property (nonatomic) TSThread *thread;
@property (nonatomic) OWSIncomingMessageFinder *finder;

@end

@implementation OWSIncomingMessageFinderTest

- (void)setUp
{
    [super setUp];
    self.sourceId = @"+19999999999";
    self.thread = [TSContactThread getOrCreateThreadWithContactId:self.sourceId];
    self.finder = [OWSIncomingMessageFinder new];
}

- (void)tearDown
{
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}


- (void)createIncomingMessageWithTimestamp:(uint64_t)timestamp
                                  authorId:(NSString *)authorId
                            sourceDeviceId:(uint32_t)sourceDeviceId
{
    TSIncomingMessage *incomingMessage = [[TSIncomingMessage alloc] initIncomingMessageWithTimestamp:timestamp
                                                                                            inThread:self.thread
                                                                                            authorId:authorId
                                                                                      sourceDeviceId:sourceDeviceId
                                                                                         messageBody:@"foo"
                                                                                       attachmentIds:@[]
                                                                                    expiresInSeconds:0
                                                                                       quotedMessage:nil
                                                                                        contactShare:nil
                                                                                         linkPreview:nil
                                                                                      messageSticker:nil
                                                                                     serverTimestamp:nil
                                                                                     wasReceivedByUD:NO
                                                                 perMessageExpirationDurationSeconds:0];
    [incomingMessage save];
}

- (void)testExistingMessages
{

    uint64_t timestamp = 1234;
    __block BOOL result;

    [self yapReadWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
        result = [self.finder existsMessageWithTimestamp:timestamp
                                                sourceId:self.sourceId
                                          sourceDeviceId:OWSDevicePrimaryDeviceId
                                             transaction:transaction];
    }];


    // Sanity check.
    XCTAssertFalse(result);

    // Different timestamp
    [self createIncomingMessageWithTimestamp:timestamp + 1
                                    authorId:self.sourceId
                              sourceDeviceId:OWSDevicePrimaryDeviceId];

    [self yapReadWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
        result = [self.finder existsMessageWithTimestamp:timestamp
                                                sourceId:self.sourceId
                                          sourceDeviceId:OWSDevicePrimaryDeviceId
                                             transaction:transaction];
    }];

    XCTAssertFalse(result);

    // Different authorId
    [self createIncomingMessageWithTimestamp:timestamp
                                    authorId:@"some-other-author-id"
                              sourceDeviceId:OWSDevicePrimaryDeviceId];

    [self yapReadWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
        result = [self.finder existsMessageWithTimestamp:timestamp
                                                sourceId:self.sourceId
                                          sourceDeviceId:OWSDevicePrimaryDeviceId
                                             transaction:transaction];
    }];
    XCTAssertFalse(result);

    // Different device
    [self createIncomingMessageWithTimestamp:timestamp
                                    authorId:self.sourceId
                              sourceDeviceId:OWSDevicePrimaryDeviceId + 1];

    [self yapReadWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
        result = [self.finder existsMessageWithTimestamp:timestamp
                                                sourceId:self.sourceId
                                          sourceDeviceId:OWSDevicePrimaryDeviceId
                                             transaction:transaction];
    }];
    XCTAssertFalse(result);

    // The real deal...
    [self createIncomingMessageWithTimestamp:timestamp authorId:self.sourceId sourceDeviceId:OWSDevicePrimaryDeviceId];

    [self yapReadWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
        result = [self.finder existsMessageWithTimestamp:timestamp
                                                sourceId:self.sourceId
                                          sourceDeviceId:OWSDevicePrimaryDeviceId
                                             transaction:transaction];
    }];

    XCTAssertTrue(result);
}

@end

NS_ASSUME_NONNULL_END
