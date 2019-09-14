//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "ContactsManagerProtocol.h"
#import "ContactsUpdater.h"
#import "MockSSKEnvironment.h"
#import "OWSFakeCallMessageHandler.h"
#import "OWSFakeMessageSender.h"
#import "OWSFakeNetworkManager.h"
#import "OWSIdentityManager.h"
#import "OWSMessageManager.h"
#import "OWSMessageSender.h"
#import "OWSSyncGroupsMessage.h"
#import "SSKBaseTestObjC.h"
#import "TSAccountManager.h"
#import "TSGroupThread.h"
#import "TSNetworkManager.h"
#import <SignalCoreKit/Cryptography.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const kAliceRecipientId = @"+13213214321";

@interface OWSMessageManager (Testing)

// private method we are testing
- (void)throws_handleIncomingEnvelope:(SSKProtoEnvelope *)envelope
                      withSyncMessage:(SSKProtoSyncMessage *)syncMessage
                          transaction:(SDSAnyWriteTransaction *)transaction;

- (void)handleIncomingEnvelope:(SSKProtoEnvelope *)envelope
               withDataMessage:(SSKProtoDataMessage *)dataMessage
               wasReceivedByUD:(BOOL)wasReceivedByUD
                   transaction:(SDSAnyWriteTransaction *)transaction;

@end

#pragma mark -

@interface OWSMessageManagerTest : SSKBaseTestObjC

@end

#pragma mark -

@implementation OWSMessageManagerTest

#pragma mark - Dependencies

- (OWSMessageManager *)messagesManager
{
    return SSKEnvironment.shared.messageManager;
}

- (TSAccountManager *)tsAccountManager
{
    return SSKEnvironment.shared.tsAccountManager;
}

- (MessageSenderJobQueue *)messageSenderJobQueue
{
    return SSKEnvironment.shared.messageSenderJobQueue;
}

#pragma mark -

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

    OWSAssertDebug([SSKEnvironment.shared.syncManager isKindOfClass:[OWSMockSyncManager class]]);
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
        [self.messagesManager throws_handleIncomingEnvelope:[envelopeBuilder buildIgnoringErrors]
                                            withSyncMessage:[messageBuilder buildIgnoringErrors]
                                                transaction:transaction];
    }];

    [self waitForExpectationsWithTimeout:5
                                 handler:^(NSError *error) {
                                     OWSLogInfo(@"No message submitted.");
                                 }];
}

- (void)test_GroupUpdate
{
    NSData *groupIdData = [Cryptography generateRandomBytes:kGroupIdLength];
    NSString *groupThreadId = [TSGroupThread threadIdFromGroupId:groupIdData];
    [self readWithBlock:^(SDSAnyReadTransaction *transaction) {
        TSGroupThread *groupThread
            = (TSGroupThread *)[TSGroupThread anyFetchWithUniqueId:groupThreadId transaction:transaction];
        XCTAssertNil(groupThread);
    }];

    SSKProtoEnvelopeBuilder *envelopeBuilder =
        [SSKProtoEnvelope builderWithTimestamp:12345];
    [envelopeBuilder setType:SSKProtoEnvelopeTypeCiphertext];

    SSKProtoGroupContextBuilder *groupContextBuilder =
        [SSKProtoGroupContext builderWithId:groupIdData];
    [groupContextBuilder setType:SSKProtoGroupContextTypeUpdate];
    [groupContextBuilder setName:@"Newly created Group Name"];

    SSKProtoDataMessageBuilder *messageBuilder = [SSKProtoDataMessage builder];
    messageBuilder.group = [groupContextBuilder buildIgnoringErrors];

    [self writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [self.messagesManager handleIncomingEnvelope:[envelopeBuilder buildIgnoringErrors]
                                     withDataMessage:[messageBuilder buildIgnoringErrors]
                                     wasReceivedByUD:NO
                                         transaction:transaction];
    }];

    [self readWithBlock:^(SDSAnyReadTransaction *transaction) {
        TSGroupThread *groupThread
            = (TSGroupThread *)[TSGroupThread anyFetchWithUniqueId:groupThreadId transaction:transaction];
        XCTAssertNotNil(groupThread);
        XCTAssertEqualObjects(@"Newly created Group Name", groupThread.groupNameOrDefault);
    }];
}


- (void)test_GroupUpdateWithAvatar
{
    NSData *groupIdData = [Cryptography generateRandomBytes:kGroupIdLength];
    NSString *groupThreadId = [TSGroupThread threadIdFromGroupId:groupIdData];
    [self readWithBlock:^(SDSAnyReadTransaction *transaction) {
        TSGroupThread *groupThread
            = (TSGroupThread *)[TSGroupThread anyFetchWithUniqueId:groupThreadId transaction:transaction];
        XCTAssertNil(groupThread);
    }];

    SSKProtoEnvelopeBuilder *envelopeBuilder =
        [SSKProtoEnvelope builderWithTimestamp:12345];
    [envelopeBuilder setType:SSKProtoEnvelopeTypeCiphertext];

    SSKProtoGroupContextBuilder *groupContextBuilder =
        [SSKProtoGroupContext builderWithId:groupIdData];
    [groupContextBuilder setType:SSKProtoGroupContextTypeUpdate];
    [groupContextBuilder setName:@"Newly created Group Name"];

    SSKProtoAttachmentPointerBuilder *attachmentBuilder = [SSKProtoAttachmentPointer builderWithId:1234];
    [attachmentBuilder setContentType:@"image/png"];
    [attachmentBuilder setKey:[Cryptography generateRandomBytes:32]];
    [attachmentBuilder setSize:123];
    [groupContextBuilder setAvatar:[attachmentBuilder buildIgnoringErrors]];

    SSKProtoDataMessageBuilder *messageBuilder = [SSKProtoDataMessage builder];
    messageBuilder.group = [groupContextBuilder buildIgnoringErrors];

    [self writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [self.messagesManager handleIncomingEnvelope:[envelopeBuilder buildIgnoringErrors]
                                     withDataMessage:[messageBuilder buildIgnoringErrors]
                                     wasReceivedByUD:NO
                                         transaction:transaction];
    }];

    [self readWithBlock:^(SDSAnyReadTransaction *transaction) {
        TSGroupThread *groupThread
            = (TSGroupThread *)[TSGroupThread anyFetchWithUniqueId:groupThreadId transaction:transaction];
        XCTAssertNotNil(groupThread);
        XCTAssertEqualObjects(@"Newly created Group Name", groupThread.groupNameOrDefault);
    }];
}

@end

NS_ASSUME_NONNULL_END
