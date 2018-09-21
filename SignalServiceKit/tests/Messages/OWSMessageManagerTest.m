//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageManager.h"
#import "ContactsManagerProtocol.h"
#import "ContactsUpdater.h"
#import "Cryptography.h"
#import "MockSSKEnvironment.h"
#import "OWSFakeCallMessageHandler.h"
#import "OWSFakeContactsManager.h"
#import "OWSFakeMessageSender.h"
#import "OWSFakeNetworkManager.h"
#import "OWSIdentityManager.h"
#import "OWSMessageSender.h"
#import "OWSPrimaryStorage.h"
#import "SSKBaseTest.h"
#import "TSGroupThread.h"
#import "TSNetworkManager.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSMessageManager (Testing)

// Private init for stubbing dependencies

- (instancetype)initWithNetworkManager:(TSNetworkManager *)networkManager
                        storageManager:(OWSPrimaryStorage *)storageManager
                    callMessageHandler:(id<OWSCallMessageHandler>)callMessageHandler
                       contactsManager:(id<ContactsManagerProtocol>)contactsManager
                       contactsUpdater:(ContactsUpdater *)contactsUpdater
                       identityManager:(OWSIdentityManager *)identityManager
                         messageSender:(OWSMessageSender *)messageSender;

// private method we are testing
- (void)handleIncomingEnvelope:(SSKProtoEnvelope *)messageEnvelope withSyncMessage:(SSKProtoSyncMessage *)syncMessage;

- (void)handleIncomingEnvelope:(SSKProtoEnvelope *)messageEnvelope withDataMessage:(SSKProtoDataMessage *)dataMessage;

@end

#pragma mark -

@interface OWSMessageManagerTest : SSKBaseTest

@end

#pragma mark -

@implementation OWSMessageManagerTest

- (void)setUp
{
    [super setUp];
}

#ifdef BROKEN_TESTS

- (void)testIncomingSyncContactMessage
{
    XCTestExpectation *messageWasSent = [self expectationWithDescription:@"message was sent"];

    OWSAssert([SSKEnvironment.shared.messageSender isKindOfClass:[OWSFakeMessageSender class]]);
    OWSFakeMessageSender *fakeMessageSender = (OWSFakeMessageSender *)SSKEnvironment.shared.messageSender;
    fakeMessageSender.enqueueTemporaryAttachmentBlock = ^{
        [messageWasSent fulfill];
    };

    OWSMessageManager *messagesManager = OWSMessageManager.sharedManager;

    SSKProtoSyncMessageRequestBuilder *requestBuilder = [SSKProtoSyncMessageRequestBuilder new];
    [requestBuilder setType:SSKProtoSyncMessageRequestTypeGroups];

    SSKProtoSyncMessageBuilder *messageBuilder = [SSKProtoSyncMessageBuilder new];
    [messageBuilder setRequest:[requestBuilder buildIgnoringErrors]];

    SSKProtoEnvelopeBuilder *envelopeBuilder = [SSKProtoEnvelopeBuilder new];
    [envelopeBuilder setType:SSKProtoEnvelopeTypeCiphertext];
    [envelopeBuilder setSource:@"+13213214321"];
    [envelopeBuilder setSourceDevice:1];
    [envelopeBuilder setTimestamp:12345];

    [messagesManager handleIncomingEnvelope:[envelopeBuilder buildIgnoringErrors]
                            withSyncMessage:[messageBuilder buildIgnoringErrors]];

    [self waitForExpectationsWithTimeout:5
                                 handler:^(NSError *error) {
                                     NSLog(@"No message submitted.");
                                 }];
}

- (void)testGroupUpdate
{
    NSData *groupIdData = [Cryptography generateRandomBytes:32];
    NSString *groupThreadId = [TSGroupThread threadIdFromGroupId:groupIdData];
    TSGroupThread *groupThread = [TSGroupThread fetchObjectWithUniqueID:groupThreadId];
    XCTAssertNil(groupThread);

    OWSMessageManager *messagesManager = SSKEnvironment.shared.messageManager;

    SSKProtoEnvelopeBuilder *envelopeBuilder = [SSKProtoEnvelopeBuilder new];

    SSKProtoGroupContextBuilder *groupContextBuilder = [SSKProtoGroupContextBuilder new];
    groupContextBuilder.name = @"Newly created Group Name";
    groupContextBuilder.id = groupIdData;
    groupContextBuilder.type = SSKProtoGroupContextTypeUpdate;

    SSKProtoDataMessageBuilder *messageBuilder = [SSKProtoDataMessageBuilder new];
    messageBuilder.group = [groupContextBuilder buildIgnoringErrors];

    [messagesManager handleIncomingEnvelope:[envelopeBuilder buildIgnoringErrors]
                            withDataMessage:[messageBuilder buildIgnoringErrors]];

    groupThread = [TSGroupThread fetchObjectWithUniqueID:groupThreadId];
    XCTAssertNotNil(groupThread);
    XCTAssertEqualObjects(@"Newly created Group Name", groupThread.name);
}

- (void)testGroupUpdateWithAvatar
{
    NSData *groupIdData = [Cryptography generateRandomBytes:32];
    NSString *groupThreadId = [TSGroupThread threadIdFromGroupId:groupIdData];
    TSGroupThread *groupThread = [TSGroupThread fetchObjectWithUniqueID:groupThreadId];
    XCTAssertNil(groupThread);

    OWSMessageManager *messagesManager = SSKEnvironment.shared.messageManager;

    SSKProtoEnvelopeBuilder *envelopeBuilder = [SSKProtoEnvelopeBuilder new];

    SSKProtoGroupContextBuilder *groupContextBuilder = [SSKProtoGroupContextBuilder new];
    groupContextBuilder.name = @"Newly created Group with Avatar Name";
    groupContextBuilder.id = groupIdData;
    groupContextBuilder.type = SSKProtoGroupContextTypeUpdate;

    SSKProtoAttachmentPointerBuilder *attachmentBuilder = [SSKProtoAttachmentPointerBuilder new];
    attachmentBuilder.id = 1234;
    attachmentBuilder.contentType = @"image/png";
    attachmentBuilder.key = [NSData new];
    attachmentBuilder.size = 123;
    groupContextBuilder.avatar = [attachmentBuilder buildIgnoringErrors];

    SSKProtoDataMessageBuilder *messageBuilder = [SSKProtoDataMessageBuilder new];
    messageBuilder.group = [groupContextBuilder buildIgnoringErrors];

    [messagesManager handleIncomingEnvelope:[envelopeBuilder buildIgnoringErrors]
                            withDataMessage:[messageBuilder buildIgnoringErrors]];

    groupThread = [TSGroupThread fetchObjectWithUniqueID:groupThreadId];
    XCTAssertNotNil(groupThread);
    XCTAssertEqualObjects(@"Newly created Group with Avatar Name", groupThread.name);
}

- (void)testUnknownGroupMessageIsIgnored
{
    NSData *groupIdData = [Cryptography generateRandomBytes:32];
    TSGroupThread *groupThread = [TSGroupThread getOrCreateThreadWithGroupId:groupIdData];

    // Sanity check
    XCTAssertEqual(0, groupThread.numberOfInteractions);

    OWSMessageManager *messagesManager = SSKEnvironment.shared.messageManager;

    SSKProtoEnvelopeBuilder *envelopeBuilder = [SSKProtoEnvelopeBuilder new];

    SSKProtoGroupContextBuilder *groupContextBuilder = [SSKProtoGroupContextBuilder new];
    groupContextBuilder.name = @"Newly created Group with Avatar Name";
    groupContextBuilder.id = groupIdData;

    // e.g. some future feature sent from another device that we don't yet support.
    groupContextBuilder.type = 666;

    SSKProtoDataMessageBuilder *messageBuilder = [SSKProtoDataMessageBuilder new];
    messageBuilder.group = [groupContextBuilder buildIgnoringErrors];

    [messagesManager handleIncomingEnvelope:[envelopeBuilder buildIgnoringErrors]
                            withDataMessage:[messageBuilder buildIgnoringErrors]];

    XCTAssertEqual(0, groupThread.numberOfInteractions);
}

#endif

@end

NS_ASSUME_NONNULL_END
