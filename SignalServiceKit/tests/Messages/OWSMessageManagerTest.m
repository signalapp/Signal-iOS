//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageManager.h"
#import "ContactsManagerProtocol.h"
#import "HTTPUtils.h"
#import "MessageSender.h"
#import "MockSSKEnvironment.h"
#import "OWSFakeCallMessageHandler.h"
#import "OWSFakeMessageSender.h"
#import "OWSIdentityManager.h"
#import "OWSSyncGroupsMessage.h"
#import "SSKBaseTestObjC.h"
#import "TSAccountManager.h"
#import "TSGroupThread.h"
#import <SignalCoreKit/Cryptography.h>
#import <SignalCoreKit/OWSAsserts.h>
#import <SignalCoreKit/OWSLogs.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const kAliceRecipientId = @"+13213214321";

@interface OWSMessageManager (Testing)

// private method we are testing
- (void)throws_handleIncomingEnvelope:(SSKProtoEnvelope *)envelope
                      withSyncMessage:(SSKProtoSyncMessage *)syncMessage
                        plaintextData:(NSData *)plaintextData
                      wasReceivedByUD:(BOOL)wasReceivedByUD
              serverDeliveryTimestamp:(uint64_t)serverDeliveryTimestamp
                          transaction:(SDSAnyWriteTransaction *)transaction;

- (void)handleIncomingEnvelope:(SSKProtoEnvelope *)envelope
               withDataMessage:(SSKProtoDataMessage *)dataMessage
                 plaintextData:(NSData *)plaintextData
               wasReceivedByUD:(BOOL)wasReceivedByUD
       serverDeliveryTimestamp:(uint64_t)serverDeliveryTimestamp
  shouldDiscardVisibleMessages:(BOOL)shouldDiscardVisibleMessages
                   transaction:(SDSAnyWriteTransaction *)transaction;

@end

#pragma mark -

@interface OWSMessageManagerTest : SSKBaseTestObjC

@end

#pragma mark -

@implementation OWSMessageManagerTest

- (void)setUp
{
    [super setUp];
    [self.tsAccountManager registerForTestsWithLocalNumber:kAliceRecipientId uuid:[NSUUID new]];
    [self.messageSenderJobQueue setup];
}

#pragma mark -

- (void)test_IncomingSyncGroupsMessage
{
    XCTestExpectation *messageWasSent = [self expectationWithDescription:@"message was sent"];

    OWSAssertDebug([((NSObject *) SSKEnvironment.shared.syncManager) isKindOfClass:[OWSMockSyncManager class]]);
    OWSMockSyncManager *mockSyncManager = (OWSMockSyncManager *)SSKEnvironment.shared.syncManager;
    mockSyncManager.syncGroupsHook = ^{
        [messageWasSent fulfill];
    };

    SSKProtoSyncMessageRequestBuilder *requestBuilder =
        [SSKProtoSyncMessageRequest builder];
    [requestBuilder setType:SSKProtoSyncMessageRequestTypeGroups];
    
    SSKProtoSyncMessageBuilder *messageBuilder = [SSKProtoSyncMessage builder];
    [messageBuilder setRequest:[requestBuilder buildIgnoringErrors]];

    SSKProtoEnvelopeBuilder *envelopeBuilder =
        [SSKProtoEnvelope builderWithTimestamp:12345];
    [envelopeBuilder setType:SSKProtoEnvelopeTypeCiphertext];
    [envelopeBuilder setSourceE164:kAliceRecipientId];
    [envelopeBuilder setSourceDevice:1];

    [self writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [self.messageManager throws_handleIncomingEnvelope:[envelopeBuilder buildIgnoringErrors]
                                           withSyncMessage:[messageBuilder buildIgnoringErrors]
                                             plaintextData:nil
                                           wasReceivedByUD:NO
                                   serverDeliveryTimestamp:0
                                               transaction:transaction];
    }];

    [self waitForExpectationsWithTimeout:5
                                 handler:^(NSError *error) {
                                     OWSLogInfo(@"No message submitted.");
                                 }];
}

- (void)test_GroupUpdate
{
    // GroupsV2 TODO: Handle v2 groups.
    NSData *groupId = [TSGroupModel generateRandomV1GroupId];
    [self readWithBlock:^(SDSAnyReadTransaction *transaction) {
        TSGroupThread *_Nullable thread = [TSGroupThread fetchWithGroupId:groupId transaction:transaction];
        XCTAssertNil(thread);
    }];

    SSKProtoEnvelopeBuilder *envelopeBuilder =
        [SSKProtoEnvelope builderWithTimestamp:12345];
    [envelopeBuilder setSourceE164:@"+13213214321"];
    [envelopeBuilder setSourceUuid:NSUUID.UUID.UUIDString];
    [envelopeBuilder setType:SSKProtoEnvelopeTypeCiphertext];

    SSKProtoGroupContextBuilder *groupContextBuilder =
        [SSKProtoGroupContext builderWithId:groupId];
    [groupContextBuilder setType:SSKProtoGroupContextTypeUpdate];
    [groupContextBuilder setName:@"Newly created Group Name"];

    SSKProtoDataMessageBuilder *messageBuilder = [SSKProtoDataMessage builder];
    messageBuilder.group = [groupContextBuilder buildIgnoringErrors];

    [self writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [self.messageManager handleIncomingEnvelope:[envelopeBuilder buildIgnoringErrors]
                                    withDataMessage:[messageBuilder buildIgnoringErrors]
                                      plaintextData:nil
                                    wasReceivedByUD:NO
                            serverDeliveryTimestamp:0
                       shouldDiscardVisibleMessages:NO
                                        transaction:transaction];
    }];

    [self readWithBlock:^(SDSAnyReadTransaction *transaction) {
        TSGroupThread *_Nullable thread = [TSGroupThread fetchWithGroupId:groupId transaction:transaction];
        XCTAssertNotNil(thread);
        XCTAssertEqualObjects(@"Newly created Group Name", thread.groupNameOrDefault);
    }];
}

- (void)test_GroupUpdateWithAvatar
{
    // GroupsV2 TODO: Handle v2 groups.
    NSData *groupId = [TSGroupModel generateRandomV1GroupId];
    [self readWithBlock:^(SDSAnyReadTransaction *transaction) {
        TSGroupThread *_Nullable thread = [TSGroupThread fetchWithGroupId:groupId transaction:transaction];
        XCTAssertNil(thread);
    }];

    SSKProtoEnvelopeBuilder *envelopeBuilder =
        [SSKProtoEnvelope builderWithTimestamp:12345];
    [envelopeBuilder setSourceE164:@"+13213214321"];
    [envelopeBuilder setSourceUuid:NSUUID.UUID.UUIDString];
    [envelopeBuilder setType:SSKProtoEnvelopeTypeCiphertext];

    SSKProtoGroupContextBuilder *groupContextBuilder =
        [SSKProtoGroupContext builderWithId:groupId];
    [groupContextBuilder setType:SSKProtoGroupContextTypeUpdate];
    [groupContextBuilder setName:@"Newly created Group Name"];

    SSKProtoAttachmentPointerBuilder *attachmentBuilder = [SSKProtoAttachmentPointer builder];
    attachmentBuilder.cdnID = 1234;
    [attachmentBuilder setContentType:@"image/png"];
    [attachmentBuilder setKey:[Cryptography generateRandomBytes:32]];
    [attachmentBuilder setSize:123];
    [groupContextBuilder setAvatar:[attachmentBuilder buildIgnoringErrors]];

    SSKProtoDataMessageBuilder *messageBuilder = [SSKProtoDataMessage builder];
    messageBuilder.group = [groupContextBuilder buildIgnoringErrors];

    [self writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [self.messageManager handleIncomingEnvelope:[envelopeBuilder buildIgnoringErrors]
                                    withDataMessage:[messageBuilder buildIgnoringErrors]
                                      plaintextData:nil
                                    wasReceivedByUD:NO
                            serverDeliveryTimestamp:0
                       shouldDiscardVisibleMessages:NO
                                        transaction:transaction];
    }];

    [self readWithBlock:^(SDSAnyReadTransaction *transaction) {
        TSGroupThread *_Nullable thread = [TSGroupThread fetchWithGroupId:groupId transaction:transaction];
        XCTAssertNotNil(thread);
        XCTAssertEqualObjects(@"Newly created Group Name", thread.groupNameOrDefault);
    }];
}

@end

NS_ASSUME_NONNULL_END
