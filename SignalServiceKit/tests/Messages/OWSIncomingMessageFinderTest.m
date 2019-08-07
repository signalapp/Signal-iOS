//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSDevice.h"
#import "OWSIncomingMessageFinder.h"
#import "SSKBaseTestObjC.h"
#import "TSContactThread.h"
#import "TSIncomingMessage.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSIncomingMessageFinder (Testing)

- (void)registerExtension;

@end

@interface OWSIncomingMessageFinderTest : SSKBaseTestObjC

@property (nonatomic) SignalServiceAddress *sourceAddress;
@property (nonatomic) TSThread *thread;
@property (nonatomic) OWSIncomingMessageFinder *finder;

@end

@implementation OWSIncomingMessageFinderTest

- (void)setUp
{
    [super setUp];
    self.sourceAddress = [[SignalServiceAddress alloc] initWithPhoneNumber:@"+19999999999"];
    self.thread = [TSContactThread getOrCreateThreadWithContactAddress:self.sourceAddress];
    self.finder = [OWSIncomingMessageFinder new];
}

- (void)tearDown
{
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}


- (void)createIncomingMessageWithTimestamp:(uint64_t)timestamp
                             authorAddress:(SignalServiceAddress *)authorAddress
                            sourceDeviceId:(uint32_t)sourceDeviceId
{
    TSIncomingMessage *incomingMessage = [[TSIncomingMessage alloc] initIncomingMessageWithTimestamp:timestamp
                                                                                            inThread:self.thread
                                                                                       authorAddress:authorAddress
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
                                                                                   isViewOnceMessage:NO];
    [self writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [incomingMessage anyInsertWithTransaction:transaction];
    }];
}

- (void)testExistingMessages
{

    uint64_t timestamp = 1234;
    __block BOOL result;

    [self readWithBlock:^(SDSAnyReadTransaction *transaction) {
        result = [InteractionFinder existsIncomingMessageWithTimestamp:timestamp
                                                               address:self.sourceAddress
                                                        sourceDeviceId:OWSDevicePrimaryDeviceId
                                                           transaction:transaction];
    }];


    // Sanity check.
    XCTAssertFalse(result);

    // Different timestamp
    [self createIncomingMessageWithTimestamp:timestamp + 1
                               authorAddress:self.sourceAddress
                              sourceDeviceId:OWSDevicePrimaryDeviceId];

    [self readWithBlock:^(SDSAnyReadTransaction *transaction) {
        result = [InteractionFinder existsIncomingMessageWithTimestamp:timestamp
                                                               address:self.sourceAddress
                                                        sourceDeviceId:OWSDevicePrimaryDeviceId
                                                           transaction:transaction];
    }];

    XCTAssertFalse(result);

    // Different authorId
    [self createIncomingMessageWithTimestamp:timestamp
                               authorAddress:[[SignalServiceAddress alloc] initWithPhoneNumber:@"some-other-address"]
                              sourceDeviceId:OWSDevicePrimaryDeviceId];

    [self readWithBlock:^(SDSAnyReadTransaction *transaction) {
        result = [InteractionFinder existsIncomingMessageWithTimestamp:timestamp
                                                               address:self.sourceAddress
                                                        sourceDeviceId:OWSDevicePrimaryDeviceId
                                                           transaction:transaction];
    }];
    XCTAssertFalse(result);

    // Different device
    [self createIncomingMessageWithTimestamp:timestamp
                               authorAddress:self.sourceAddress
                              sourceDeviceId:OWSDevicePrimaryDeviceId + 1];

    [self readWithBlock:^(SDSAnyReadTransaction *transaction) {
        result = [InteractionFinder existsIncomingMessageWithTimestamp:timestamp
                                                               address:self.sourceAddress
                                                        sourceDeviceId:OWSDevicePrimaryDeviceId
                                                           transaction:transaction];
    }];
    XCTAssertFalse(result);

    // The real deal...
    [self createIncomingMessageWithTimestamp:timestamp
                               authorAddress:self.sourceAddress
                              sourceDeviceId:OWSDevicePrimaryDeviceId];

    [self readWithBlock:^(SDSAnyReadTransaction *transaction) {
        result = [InteractionFinder existsIncomingMessageWithTimestamp:timestamp
                                                               address:self.sourceAddress
                                                        sourceDeviceId:OWSDevicePrimaryDeviceId
                                                           transaction:transaction];
    }];

    XCTAssertTrue(result);
}

@end

NS_ASSUME_NONNULL_END
