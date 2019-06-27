//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSIncomingMessageFinder.h"
#import "OWSDevice.h"
#import "OWSPrimaryStorage.h"
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
                                                                 perMessageExpirationDurationSeconds:0];
    [incomingMessage save];
}

- (void)testExistingMessages
{

    uint64_t timestamp = 1234;
    __block BOOL result;

    [self yapReadWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
        result = [self.finder existsMessageWithTimestamp:timestamp
                                                sourceId:self.sourceAddress.transitional_phoneNumber
                                          sourceDeviceId:OWSDevicePrimaryDeviceId
                                             transaction:transaction];
    }];


    // Sanity check.
    XCTAssertFalse(result);

    // Different timestamp
    [self createIncomingMessageWithTimestamp:timestamp + 1
                               authorAddress:self.sourceAddress
                              sourceDeviceId:OWSDevicePrimaryDeviceId];

    [self yapReadWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
        result = [self.finder existsMessageWithTimestamp:timestamp
                                                sourceId:self.sourceAddress.transitional_phoneNumber
                                          sourceDeviceId:OWSDevicePrimaryDeviceId
                                             transaction:transaction];
    }];

    XCTAssertFalse(result);

    // Different authorId
    [self createIncomingMessageWithTimestamp:timestamp
                               authorAddress:self.sourceAddress
                              sourceDeviceId:OWSDevicePrimaryDeviceId];

    [self yapReadWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
        result = [self.finder existsMessageWithTimestamp:timestamp
                                                sourceId:self.sourceAddress.transitional_phoneNumber
                                          sourceDeviceId:OWSDevicePrimaryDeviceId
                                             transaction:transaction];
    }];
    XCTAssertFalse(result);

    // Different device
    [self createIncomingMessageWithTimestamp:timestamp
                               authorAddress:self.sourceAddress
                              sourceDeviceId:OWSDevicePrimaryDeviceId + 1];

    [self yapReadWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
        result = [self.finder existsMessageWithTimestamp:timestamp
                                                sourceId:self.sourceAddress.transitional_phoneNumber
                                          sourceDeviceId:OWSDevicePrimaryDeviceId
                                             transaction:transaction];
    }];
    XCTAssertFalse(result);

    // The real deal...
    [self createIncomingMessageWithTimestamp:timestamp
                               authorAddress:self.sourceAddress
                              sourceDeviceId:OWSDevicePrimaryDeviceId];

    [self yapReadWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
        result = [self.finder existsMessageWithTimestamp:timestamp
                                                sourceId:self.sourceAddress.transitional_phoneNumber
                                          sourceDeviceId:OWSDevicePrimaryDeviceId
                                             transaction:transaction];
    }];

    XCTAssertTrue(result);
}

@end

NS_ASSUME_NONNULL_END
