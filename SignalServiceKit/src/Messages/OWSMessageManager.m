//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageManager.h"
#import "AppContext.h"
#import "AppReadiness.h"
#import "ContactsManagerProtocol.h"
#import "Cryptography.h"
#import "MimeTypeUtil.h"
#import "NSDate+OWS.h"
#import "NSString+SSK.h"
#import "NotificationsProtocol.h"
#import "OWSAttachmentsProcessor.h"
#import "OWSBlockingManager.h"
#import "OWSCallMessageHandler.h"
#import "OWSContact.h"
#import "OWSDevice.h"
#import "OWSDisappearingConfigurationUpdateInfoMessage.h"
#import "OWSDisappearingMessagesConfiguration.h"
#import "OWSDisappearingMessagesJob.h"
#import "OWSIdentityManager.h"
#import "OWSIncomingMessageFinder.h"
#import "OWSIncomingSentMessageTranscript.h"
#import "OWSMessageSender.h"
#import "OWSMessageUtils.h"
#import "OWSPrimaryStorage+SessionStore.h"
#import "OWSPrimaryStorage.h"
#import "OWSReadReceiptManager.h"
#import "OWSRecordTranscriptJob.h"
#import "OWSSyncConfigurationMessage.h"
#import "OWSSyncContactsMessage.h"
#import "OWSSyncGroupsMessage.h"
#import "OWSSyncGroupsRequestMessage.h"
#import "ProfileManagerProtocol.h"
#import "SSKEnvironment.h"
#import "TSAccountManager.h"
#import "TSAttachment.h"
#import "TSAttachmentPointer.h"
#import "TSAttachmentStream.h"
#import "TSContactThread.h"
#import "TSDatabaseView.h"
#import "TSGroupModel.h"
#import "TSGroupThread.h"
#import "TSIncomingMessage.h"
#import "TSInfoMessage.h"
#import "TSNetworkManager.h"
#import "TSOutgoingMessage.h"
#import "TSQuotedMessage.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <YapDatabase/YapDatabase.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSMessageManager ()

@property (nonatomic, readonly) OWSPrimaryStorage *primaryStorage;
@property (nonatomic, readonly) YapDatabaseConnection *dbConnection;
@property (nonatomic, readonly) OWSIncomingMessageFinder *incomingMessageFinder;

@end

#pragma mark -

@implementation OWSMessageManager

+ (instancetype)sharedManager
{
    OWSAssertDebug(SSKEnvironment.shared.messageManager);

    return SSKEnvironment.shared.messageManager;
}

- (instancetype)initWithPrimaryStorage:(OWSPrimaryStorage *)primaryStorage
{
    self = [super init];

    if (!self) {
        return self;
    }

    _primaryStorage = primaryStorage;
    _dbConnection = primaryStorage.newDatabaseConnection;
    _incomingMessageFinder = [[OWSIncomingMessageFinder alloc] initWithPrimaryStorage:primaryStorage];

    OWSSingletonAssert();
    OWSAssertDebug(CurrentAppContext().isMainApp);

    return self;
}

- (id<OWSCallMessageHandler>)callMessageHandler
{
    OWSAssertDebug(SSKEnvironment.shared.callMessageHandler);

    return SSKEnvironment.shared.callMessageHandler;
}

- (id<ContactsManagerProtocol>)contactsManager
{
    OWSAssertDebug(SSKEnvironment.shared.contactsManager);

    return SSKEnvironment.shared.contactsManager;
}

- (OWSMessageSender *)messageSender
{
    OWSAssertDebug(SSKEnvironment.shared.messageSender);

    return SSKEnvironment.shared.messageSender;
}

- (OWSBlockingManager *)blockingManager
{
    OWSAssertDebug(SSKEnvironment.shared.blockingManager);

    return SSKEnvironment.shared.blockingManager;
}

- (OWSIdentityManager *)identityManager
{
    OWSAssertDebug(SSKEnvironment.shared.identityManager);

    return SSKEnvironment.shared.identityManager;
}

- (TSNetworkManager *)networkManager
{
    OWSAssertDebug(SSKEnvironment.shared.networkManager);

    return SSKEnvironment.shared.networkManager;
}

- (void)startObserving
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(yapDatabaseModified:)
                                                 name:YapDatabaseModifiedNotification
                                               object:OWSPrimaryStorage.sharedManager.dbNotificationObject];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(yapDatabaseModified:)
                                                 name:YapDatabaseModifiedExternallyNotification
                                               object:nil];
}

- (void)yapDatabaseModified:(NSNotification *)notification
{
    if (AppReadiness.isAppReady) {
        [OWSMessageUtils.sharedManager updateApplicationBadgeCount];
    } else {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            [AppReadiness runNowOrWhenAppIsReady:^{
                [OWSMessageUtils.sharedManager updateApplicationBadgeCount];
            }];
        });
    }
}

#pragma mark - Blocking

- (BOOL)isEnvelopeSenderBlocked:(SSKProtoEnvelope *)envelope
{
    OWSAssertDebug(envelope);

    return [self.blockingManager isRecipientIdBlocked:envelope.source];
}

- (BOOL)isDataMessageBlocked:(SSKProtoDataMessage *)dataMessage envelope:(SSKProtoEnvelope *)envelope
{
    OWSAssertDebug(dataMessage);
    OWSAssertDebug(envelope);

    if (dataMessage.group) {
        return [self.blockingManager isGroupIdBlocked:dataMessage.group.id];
    } else {
        BOOL senderBlocked = [self isEnvelopeSenderBlocked:envelope];

        // If the envelopeSender was blocked, we never should have gotten as far as decrypting the dataMessage.
        OWSAssertDebug(!senderBlocked);

        return senderBlocked;
    }
}

#pragma mark - message handling

- (void)processEnvelope:(SSKProtoEnvelope *)envelope
          plaintextData:(NSData *_Nullable)plaintextData
            transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    if (!envelope) {
        OWSFailDebug(@"Missing envelope.");
        return;
    }
    if (!transaction) {
        OWSFail(@"Missing transaction.");
        return;
    }
    if (!TSAccountManager.isRegistered) {
        OWSFailDebug(@"Not registered.");
        return;
    }
    if (!CurrentAppContext().isMainApp) {
        OWSFail(@"Not main app.");
        return;
    }

    OWSLogInfo(@"handling decrypted envelope: %@", [self descriptionForEnvelope:envelope]);

    if (!envelope.source.isValidE164) {
        OWSFailDebug(@"incoming envelope has invalid source");
        return;
    }

    OWSAssertDebug(envelope.source.length > 0);
    OWSAssertDebug(![self isEnvelopeSenderBlocked:envelope]);

    switch (envelope.type) {
        case SSKProtoEnvelopeTypeCiphertext:
        case SSKProtoEnvelopeTypePrekeyBundle:
            if (!plaintextData) {
                OWSFailDebug(@"missing decrypted data for envelope: %@", [self descriptionForEnvelope:envelope]);
                return;
            }
            [self handleEnvelope:envelope plaintextData:plaintextData transaction:transaction];
            break;
        case SSKProtoEnvelopeTypeReceipt:
            OWSAssertDebug(!plaintextData);
            [self handleDeliveryReceipt:envelope transaction:transaction];
            break;
            // Other messages are just dismissed for now.
        case SSKProtoEnvelopeTypeKeyExchange:
            OWSLogWarn(@"Received Key Exchange Message, not supported");
            break;
        case SSKProtoEnvelopeTypeUnknown:
            OWSLogWarn(@"Received an unknown message type");
            break;
        default:
            OWSLogWarn(@"Received unhandled envelope type: %d", (int)envelope.type);
            break;
    }
}

- (void)handleDeliveryReceipt:(SSKProtoEnvelope *)envelope transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    if (!envelope) {
        OWSFailDebug(@"Missing envelope.");
        return;
    }
    if (!transaction) {
        OWSFail(@"Missing transaction.");
        return;
    }

    // Old-style delivery notices don't include a "delivery timestamp".
    [self processDeliveryReceiptsFromRecipientId:envelope.source
                                  sentTimestamps:@[
                                      @(envelope.timestamp),
                                  ]
                               deliveryTimestamp:nil
                                     transaction:transaction];
}

// deliveryTimestamp is an optional parameter, since legacy
// delivery receipts don't have a "delivery timestamp".  Those
// messages repurpose the "timestamp" field to indicate when the
// corresponding message was originally sent.
- (void)processDeliveryReceiptsFromRecipientId:(NSString *)recipientId
                                sentTimestamps:(NSArray<NSNumber *> *)sentTimestamps
                             deliveryTimestamp:(NSNumber *_Nullable)deliveryTimestamp
                                   transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    if (recipientId.length < 1) {
        OWSFailDebug(@"Empty recipientId.");
        return;
    }
    if (sentTimestamps.count < 1) {
        OWSFailDebug(@"Missing sentTimestamps.");
        return;
    }
    if (!transaction) {
        OWSFail(@"Missing transaction.");
        return;
    }

    for (NSNumber *nsTimestamp in sentTimestamps) {
        uint64_t timestamp = [nsTimestamp unsignedLongLongValue];

        NSArray<TSOutgoingMessage *> *messages
            = (NSArray<TSOutgoingMessage *> *)[TSInteraction interactionsWithTimestamp:timestamp
                                                                               ofClass:[TSOutgoingMessage class]
                                                                       withTransaction:transaction];
        if (messages.count < 1) {
            // The service sends delivery receipts for "unpersisted" messages
            // like group updates, so these errors are expected to a certain extent.
            //
            // TODO: persist "early" delivery receipts.
            OWSLogInfo(@"Missing message for delivery receipt: %llu", timestamp);
        } else {
            if (messages.count > 1) {
                OWSLogInfo(@"More than one message (%lu) for delivery receipt: %llu",
                    (unsigned long)messages.count,
                    timestamp);
            }
            for (TSOutgoingMessage *outgoingMessage in messages) {
                [outgoingMessage updateWithDeliveredRecipient:recipientId
                                            deliveryTimestamp:deliveryTimestamp
                                                  transaction:transaction];
            }
        }
    }
}

- (void)handleEnvelope:(SSKProtoEnvelope *)envelope
         plaintextData:(NSData *)plaintextData
           transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    if (!envelope) {
        OWSFailDebug(@"Missing envelope.");
        return;
    }
    if (!plaintextData) {
        OWSFailDebug(@"Missing plaintextData.");
        return;
    }
    if (!transaction) {
        OWSFail(@"Missing transaction.");
        return;
    }
    if (envelope.timestamp < 1) {
        OWSFailDebug(@"Invalid timestamp.");
        return;
    }
    if (envelope.source.length < 1) {
        OWSFailDebug(@"Missing source.");
        return;
    }
    if (envelope.sourceDevice < 1) {
        OWSFailDebug(@"Invaid source device.");
        return;
    }

    BOOL duplicateEnvelope = [self.incomingMessageFinder existsMessageWithTimestamp:envelope.timestamp
                                                                           sourceId:envelope.source
                                                                     sourceDeviceId:envelope.sourceDevice
                                                                        transaction:transaction];
    if (duplicateEnvelope) {
        OWSLogInfo(@"Ignoring previously received envelope from %@ with timestamp: %llu",
            envelopeAddress(envelope),
            envelope.timestamp);
        return;
    }

    if (envelope.content != nil) {
        NSError *error;
        SSKProtoContent *_Nullable contentProto = [SSKProtoContent parseData:plaintextData error:&error];
        if (error || !contentProto) {
            OWSFailDebug(@"could not parse proto: %@", error);
            return;
        }
        OWSLogInfo(@"handling content: <Content: %@>", [self descriptionForContent:contentProto]);

        if (contentProto.syncMessage) {
            [self handleIncomingEnvelope:envelope withSyncMessage:contentProto.syncMessage transaction:transaction];

            [[OWSDeviceManager sharedManager] setHasReceivedSyncMessage];
        } else if (contentProto.dataMessage) {
            [self handleIncomingEnvelope:envelope withDataMessage:contentProto.dataMessage transaction:transaction];
        } else if (contentProto.callMessage) {
            [self handleIncomingEnvelope:envelope withCallMessage:contentProto.callMessage];
        } else if (contentProto.nullMessage) {
            OWSLogInfo(@"Received null message.");
        } else if (contentProto.receiptMessage) {
            [self handleIncomingEnvelope:envelope
                      withReceiptMessage:contentProto.receiptMessage
                             transaction:transaction];
        } else {
            OWSLogWarn(@"Ignoring envelope. Content with no known payload");
        }
    } else if (envelope.legacyMessage != nil) { // DEPRECATED - Remove after all clients have been upgraded.
        NSError *error;
        SSKProtoDataMessage *_Nullable dataMessageProto = [SSKProtoDataMessage parseData:plaintextData error:&error];
        if (error || !dataMessageProto) {
            OWSFailDebug(@"could not parse proto: %@", error);
            return;
        }
        OWSLogInfo(@"handling message: <DataMessage: %@ />", [self descriptionForDataMessage:dataMessageProto]);

        [self handleIncomingEnvelope:envelope withDataMessage:dataMessageProto transaction:transaction];
    } else {
        OWSProdInfoWEnvelope([OWSAnalyticsEvents messageManagerErrorEnvelopeNoActionablePayload], envelope);
    }
}

- (void)handleIncomingEnvelope:(SSKProtoEnvelope *)envelope
               withDataMessage:(SSKProtoDataMessage *)dataMessage
                   transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    if (!envelope) {
        OWSFailDebug(@"Missing envelope.");
        return;
    }
    if (!dataMessage) {
        OWSFailDebug(@"Missing dataMessage.");
        return;
    }
    if (!transaction) {
        OWSFail(@"Missing transaction.");
        return;
    }

    if ([self isDataMessageBlocked:dataMessage envelope:envelope]) {
        NSString *logMessage = [NSString stringWithFormat:@"Ignoring blocked message from sender: %@", envelope.source];
        if (dataMessage.group) {
            logMessage =
                [logMessage stringByAppendingString:[NSString stringWithFormat:@" in group: %@", dataMessage.group.id]];
        }
        OWSLogError(@"%@", logMessage);
        return;
    }

    if (dataMessage.hasTimestamp) {
        if (dataMessage.timestamp <= 0) {
            OWSFailDebug(@"Ignoring message with invalid data message timestamp: %@", envelope.source);
            // TODO: Add analytics.
            return;
        }
        // This prevents replay attacks by the service.
        if (dataMessage.timestamp != envelope.timestamp) {
            OWSFailDebug(@"Ignoring message with non-matching data message timestamp: %@", envelope.source);
            // TODO: Add analytics.
            return;
        }
    }

    if ([dataMessage hasProfileKey]) {
        NSData *profileKey = [dataMessage profileKey];
        NSString *recipientId = envelope.source;
        if (profileKey.length == kAES256_KeyByteLength) {
            [self.profileManager setProfileKeyData:profileKey forRecipientId:recipientId];
        } else {
            OWSFailDebug(
                @"Unexpected profile key length:%lu on message from:%@", (unsigned long)profileKey.length, recipientId);
        }
    }

    if (dataMessage.group) {
        TSGroupThread *_Nullable groupThread =
            [TSGroupThread threadWithGroupId:dataMessage.group.id transaction:transaction];

        if (groupThread) {
            if (dataMessage.group.type != SSKProtoGroupContextTypeUpdate) {
                if (![groupThread.groupModel.groupMemberIds containsObject:[TSAccountManager localNumber]]) {
                    OWSLogInfo(@"Ignoring messages for left group.");
                    return;
                }
            }
        } else {
            // Unknown group.
            if (dataMessage.group.type == SSKProtoGroupContextTypeUpdate) {
                // Accept group updates for unknown groups.
            } else if (dataMessage.group.type == SSKProtoGroupContextTypeDeliver) {
                [self sendGroupInfoRequest:dataMessage.group.id envelope:envelope transaction:transaction];
                return;
            } else {
                OWSLogInfo(@"Ignoring group message for unknown group from: %@", envelope.source);
                return;
            }
        }
    }

    if ((dataMessage.flags & SSKProtoDataMessageFlagsEndSession) != 0) {
        [self handleEndSessionMessageWithEnvelope:envelope dataMessage:dataMessage transaction:transaction];
    } else if ((dataMessage.flags & SSKProtoDataMessageFlagsExpirationTimerUpdate) != 0) {
        [self handleExpirationTimerUpdateMessageWithEnvelope:envelope dataMessage:dataMessage transaction:transaction];
    } else if ((dataMessage.flags & SSKProtoDataMessageFlagsProfileKeyUpdate) != 0) {
        [self handleProfileKeyMessageWithEnvelope:envelope dataMessage:dataMessage];
    } else if (dataMessage.attachments.count > 0) {
        [self handleReceivedMediaWithEnvelope:envelope dataMessage:dataMessage transaction:transaction];
    } else {
        [self handleReceivedTextMessageWithEnvelope:envelope dataMessage:dataMessage transaction:transaction];

        if ([self isDataMessageGroupAvatarUpdate:dataMessage]) {
            OWSLogVerbose(@"Data message had group avatar attachment");
            [self handleReceivedGroupAvatarUpdateWithEnvelope:envelope dataMessage:dataMessage transaction:transaction];
        }
    }
}

- (void)sendGroupInfoRequest:(NSData *)groupId
                    envelope:(SSKProtoEnvelope *)envelope
                 transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    if (!envelope) {
        OWSFailDebug(@"Missing envelope.");
        return;
    }
    if (!transaction) {
        OWSFail(@"Missing transaction.");
        return;
    }
    if (groupId.length < 1) {
        OWSFailDebug(@"Invalid groupId.");
        return;
    }

    // FIXME: https://github.com/signalapp/Signal-iOS/issues/1340
    OWSLogInfo(@"Sending group info request: %@", envelopeAddress(envelope));

    NSString *recipientId = envelope.source;

    TSThread *thread = [TSContactThread getOrCreateThreadWithContactId:recipientId transaction:transaction];

    OWSSyncGroupsRequestMessage *syncGroupsRequestMessage =
        [[OWSSyncGroupsRequestMessage alloc] initWithThread:thread groupId:groupId];
    [self.messageSender enqueueMessage:syncGroupsRequestMessage
        success:^{
            OWSLogWarn(@"Successfully sent Request Group Info message.");
        }
        failure:^(NSError *error) {
            OWSLogError(@"Failed to send Request Group Info message with error: %@", error);
        }];
}

- (id<ProfileManagerProtocol>)profileManager
{
    return SSKEnvironment.shared.profileManager;
}

- (void)handleIncomingEnvelope:(SSKProtoEnvelope *)envelope
            withReceiptMessage:(SSKProtoReceiptMessage *)receiptMessage
                   transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    if (!envelope) {
        OWSFailDebug(@"Missing envelope.");
        return;
    }
    if (!receiptMessage) {
        OWSFailDebug(@"Missing receiptMessage.");
        return;
    }
    if (!transaction) {
        OWSFail(@"Missing transaction.");
        return;
    }

    NSArray<NSNumber *> *sentTimestamps = receiptMessage.timestamp;

    switch (receiptMessage.type) {
        case SSKProtoReceiptMessageTypeDelivery:
            OWSLogVerbose(@"Processing receipt message with delivery receipts.");
            [self processDeliveryReceiptsFromRecipientId:envelope.source
                                          sentTimestamps:sentTimestamps
                                       deliveryTimestamp:@(envelope.timestamp)
                                             transaction:transaction];
            return;
        case SSKProtoReceiptMessageTypeRead:
            OWSLogVerbose(@"Processing receipt message with read receipts.");
            [OWSReadReceiptManager.sharedManager processReadReceiptsFromRecipientId:envelope.source
                                                                     sentTimestamps:sentTimestamps
                                                                      readTimestamp:envelope.timestamp];
            break;
        default:
            OWSLogInfo(@"Ignoring receipt message of unknown type: %d.", (int)receiptMessage.type);
            return;
    }
}

- (void)handleIncomingEnvelope:(SSKProtoEnvelope *)envelope
               withCallMessage:(SSKProtoCallMessage *)callMessage
{
    if (!envelope) {
        OWSFailDebug(@"Missing envelope.");
        return;
    }
    if (!callMessage) {
        OWSFailDebug(@"Missing callMessage.");
        return;
    }

    if ([callMessage hasProfileKey]) {
        NSData *profileKey = [callMessage profileKey];
        NSString *recipientId = envelope.source;
        [self.profileManager setProfileKeyData:profileKey forRecipientId:recipientId];
    }

    // By dispatching async, we introduce the possibility that these messages might be lost
    // if the app exits before this block is executed.  This is fine, since the call by
    // definition will end if the app exits.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (callMessage.offer) {
            [self.callMessageHandler receivedOffer:callMessage.offer fromCallerId:envelope.source];
        } else if (callMessage.answer) {
            [self.callMessageHandler receivedAnswer:callMessage.answer fromCallerId:envelope.source];
        } else if (callMessage.iceUpdate.count > 0) {
            for (SSKProtoCallMessageIceUpdate *iceUpdate in callMessage.iceUpdate) {
                [self.callMessageHandler receivedIceUpdate:iceUpdate fromCallerId:envelope.source];
            }
        } else if (callMessage.hangup) {
            OWSLogVerbose(@"Received CallMessage with Hangup.");
            [self.callMessageHandler receivedHangup:callMessage.hangup fromCallerId:envelope.source];
        } else if (callMessage.busy) {
            [self.callMessageHandler receivedBusy:callMessage.busy fromCallerId:envelope.source];
        } else {
            OWSProdInfoWEnvelope([OWSAnalyticsEvents messageManagerErrorCallMessageNoActionablePayload], envelope);
        }
    });
}

- (void)handleReceivedGroupAvatarUpdateWithEnvelope:(SSKProtoEnvelope *)envelope
                                        dataMessage:(SSKProtoDataMessage *)dataMessage
                                        transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    if (!envelope) {
        OWSFailDebug(@"Missing envelope.");
        return;
    }
    if (!dataMessage) {
        OWSFailDebug(@"Missing dataMessage.");
        return;
    }
    if (!transaction) {
        OWSFail(@"Missing transaction.");
        return;
    }

    TSGroupThread *_Nullable groupThread =
        [TSGroupThread threadWithGroupId:dataMessage.group.id transaction:transaction];
    if (!groupThread) {
        OWSFailDebug(@"Missing group for group avatar update");
        return;
    }

    OWSAttachmentsProcessor *attachmentsProcessor =
        [[OWSAttachmentsProcessor alloc] initWithAttachmentProtos:@[ dataMessage.group.avatar ]
                                                   networkManager:self.networkManager
                                                      transaction:transaction];

    if (!attachmentsProcessor.hasSupportedAttachments) {
        OWSLogWarn(@"received unsupported group avatar envelope");
        return;
    }
    [attachmentsProcessor fetchAttachmentsForMessage:nil
        transaction:transaction
        success:^(TSAttachmentStream *attachmentStream) {
            [groupThread updateAvatarWithAttachmentStream:attachmentStream];
        }
        failure:^(NSError *error) {
            OWSLogError(@"failed to fetch attachments for group avatar sent at: %llu. with error: %@",
                envelope.timestamp,
                error);
        }];
}

- (void)handleReceivedMediaWithEnvelope:(SSKProtoEnvelope *)envelope
                            dataMessage:(SSKProtoDataMessage *)dataMessage
                            transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    if (!envelope) {
        OWSFailDebug(@"Missing envelope.");
        return;
    }
    if (!dataMessage) {
        OWSFailDebug(@"Missing dataMessage.");
        return;
    }
    if (!transaction) {
        OWSFail(@"Missing transaction.");
        return;
    }

    TSThread *_Nullable thread = [self threadForEnvelope:envelope dataMessage:dataMessage transaction:transaction];
    if (!thread) {
        OWSFailDebug(@"ignoring media message for unknown group.");
        return;
    }

    OWSAttachmentsProcessor *attachmentsProcessor =
        [[OWSAttachmentsProcessor alloc] initWithAttachmentProtos:dataMessage.attachments
                                                   networkManager:self.networkManager
                                                      transaction:transaction];
    if (!attachmentsProcessor.hasSupportedAttachments) {
        OWSLogWarn(@"received unsupported media envelope");
        return;
    }

    TSIncomingMessage *_Nullable createdMessage = [self handleReceivedEnvelope:envelope
                                                               withDataMessage:dataMessage
                                                                 attachmentIds:attachmentsProcessor.attachmentIds
                                                                   transaction:transaction];

    if (!createdMessage) {
        return;
    }

    OWSLogDebug(@"incoming attachment message: %@", createdMessage.debugDescription);

    [attachmentsProcessor fetchAttachmentsForMessage:createdMessage
        transaction:transaction
        success:^(TSAttachmentStream *attachmentStream) {
            OWSLogDebug(@"successfully fetched attachment: %@ for message: %@", attachmentStream, createdMessage);
        }
        failure:^(NSError *error) {
            OWSLogError(@"failed to fetch attachments for message: %@ with error: %@", createdMessage, error);
        }];
}

- (void)handleIncomingEnvelope:(SSKProtoEnvelope *)envelope
               withSyncMessage:(SSKProtoSyncMessage *)syncMessage
                   transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    if (!envelope) {
        OWSFailDebug(@"Missing envelope.");
        return;
    }
    if (!syncMessage) {
        OWSFailDebug(@"Missing syncMessage.");
        return;
    }
    if (!transaction) {
        OWSFail(@"Missing transaction.");
        return;
    }

    NSString *localNumber = [TSAccountManager localNumber];
    if (![localNumber isEqualToString:envelope.source]) {
        // Sync messages should only come from linked devices.
        OWSProdErrorWEnvelope([OWSAnalyticsEvents messageManagerErrorSyncMessageFromUnknownSource], envelope);
        return;
    }

    if (syncMessage.sent) {
        OWSIncomingSentMessageTranscript *transcript =
            [[OWSIncomingSentMessageTranscript alloc] initWithProto:syncMessage.sent
                                                        transaction:transaction];

        OWSRecordTranscriptJob *recordJob =
            [[OWSRecordTranscriptJob alloc] initWithIncomingSentMessageTranscript:transcript];

        SSKProtoDataMessage *_Nullable dataMessage = syncMessage.sent.message;
        if (!dataMessage) {
            OWSFailDebug(@"Missing dataMessage.");
            return;
        }
        NSString *destination = syncMessage.sent.destination;
        if (dataMessage && destination.length > 0 && dataMessage.hasProfileKey) {
            // If we observe a linked device sending our profile key to another
            // user, we can infer that that user belongs in our profile whitelist.
            if (dataMessage.group) {
                [self.profileManager addGroupIdToProfileWhitelist:dataMessage.group.id];
            } else {
                [self.profileManager addUserToProfileWhitelist:destination];
            }
        }

        if ([self isDataMessageGroupAvatarUpdate:syncMessage.sent.message]) {
            [recordJob runWithAttachmentHandler:^(TSAttachmentStream *attachmentStream) {
                [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                    TSGroupThread *_Nullable groupThread =
                        [TSGroupThread threadWithGroupId:dataMessage.group.id transaction:transaction];
                    if (!groupThread) {
                        OWSFailDebug(@"ignoring sync group avatar update for unknown group.");
                        return;
                    }

                    [groupThread updateAvatarWithAttachmentStream:attachmentStream transaction:transaction];
                }];
            }
                                    transaction:transaction];
        } else {
            [recordJob
                runWithAttachmentHandler:^(TSAttachmentStream *attachmentStream) {
                    OWSLogDebug(@"successfully fetched transcript attachment: %@", attachmentStream);
                }
                             transaction:transaction];
        }
    } else if (syncMessage.request) {
        if (syncMessage.request.type == SSKProtoSyncMessageRequestTypeContacts) {
            // We respond asynchronously because populating the sync message will
            // create transactions and it's not practical (due to locking in the OWSIdentityManager)
            // to plumb our transaction through.
            //
            // In rare cases this means we won't respond to the sync request, but that's
            // acceptable.
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                OWSSyncContactsMessage *syncContactsMessage =
                    [[OWSSyncContactsMessage alloc] initWithSignalAccounts:self.contactsManager.signalAccounts
                                                           identityManager:self.identityManager
                                                            profileManager:self.profileManager];
                __block NSData *_Nullable syncData;
                [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
                    syncData = [syncContactsMessage buildPlainTextAttachmentDataWithTransaction:transaction];
                }];
                if (!syncData) {
                    OWSFailDebug(@"Failed to serialize contacts sync message.");
                    return;
                }
                DataSource *dataSource = [DataSourceValue dataSourceWithSyncMessageData:syncData];
                [self.messageSender enqueueTemporaryAttachment:dataSource
                    contentType:OWSMimeTypeApplicationOctetStream
                    inMessage:syncContactsMessage
                    success:^{
                        OWSLogInfo(@"Successfully sent Contacts response syncMessage.");
                    }
                    failure:^(NSError *error) {
                        OWSLogError(@"Failed to send Contacts response syncMessage with error: %@", error);
                    }];
            });
        } else if (syncMessage.request.type == SSKProtoSyncMessageRequestTypeGroups) {
            OWSSyncGroupsMessage *syncGroupsMessage = [[OWSSyncGroupsMessage alloc] init];
            NSData *_Nullable syncData = [syncGroupsMessage buildPlainTextAttachmentDataWithTransaction:transaction];
            if (!syncData) {
                OWSFailDebug(@"Failed to serialize groups sync message.");
                return;
            }
            DataSource *dataSource = [DataSourceValue dataSourceWithSyncMessageData:syncData];
            [self.messageSender enqueueTemporaryAttachment:dataSource
                contentType:OWSMimeTypeApplicationOctetStream
                inMessage:syncGroupsMessage
                success:^{
                    OWSLogInfo(@"Successfully sent Groups response syncMessage.");
                }
                failure:^(NSError *error) {
                    OWSLogError(@"Failed to send Groups response syncMessage with error: %@", error);
                }];
        } else if (syncMessage.request.type == SSKProtoSyncMessageRequestTypeBlocked) {
            OWSLogInfo(@"Received request for block list");
            [self.blockingManager syncBlockList];
        } else if (syncMessage.request.type == SSKProtoSyncMessageRequestTypeConfiguration) {
            BOOL areReadReceiptsEnabled =
                [[OWSReadReceiptManager sharedManager] areReadReceiptsEnabledWithTransaction:transaction];
            OWSSyncConfigurationMessage *syncConfigurationMessage =
                [[OWSSyncConfigurationMessage alloc] initWithReadReceiptsEnabled:areReadReceiptsEnabled];
            [self.messageSender enqueueMessage:syncConfigurationMessage
                success:^{
                    OWSLogInfo(@"Successfully sent Configuration response syncMessage.");
                }
                failure:^(NSError *error) {
                    OWSLogError(@"Failed to send Configuration response syncMessage with error: %@", error);
                }];
        } else {
            OWSLogWarn(@"ignoring unsupported sync request message");
        }
    } else if (syncMessage.blocked) {
        NSArray<NSString *> *blockedPhoneNumbers = [syncMessage.blocked.numbers copy];
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self.blockingManager setBlockedPhoneNumbers:blockedPhoneNumbers sendSyncMessage:NO];
        });
    } else if (syncMessage.read.count > 0) {
        OWSLogInfo(@"Received %lu read receipt(s)", (unsigned long)syncMessage.read.count);
        [OWSReadReceiptManager.sharedManager processReadReceiptsFromLinkedDevice:syncMessage.read
                                                                   readTimestamp:envelope.timestamp
                                                                     transaction:transaction];
    } else if (syncMessage.verified) {
        OWSLogInfo(@"Received verification state for %@", syncMessage.verified.destination);
        [self.identityManager processIncomingSyncMessage:syncMessage.verified transaction:transaction];
    } else {
        OWSLogWarn(@"Ignoring unsupported sync message.");
    }
}

- (void)handleEndSessionMessageWithEnvelope:(SSKProtoEnvelope *)envelope
                                dataMessage:(SSKProtoDataMessage *)dataMessage
                                transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    if (!envelope) {
        OWSFailDebug(@"Missing envelope.");
        return;
    }
    if (!dataMessage) {
        OWSFailDebug(@"Missing dataMessage.");
        return;
    }
    if (!transaction) {
        OWSFail(@"Missing transaction.");
        return;
    }

    TSContactThread *thread = [TSContactThread getOrCreateThreadWithContactId:envelope.source transaction:transaction];

    [[[TSInfoMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                     inThread:thread
                                  messageType:TSInfoMessageTypeSessionDidEnd] saveWithTransaction:transaction];

    [self.primaryStorage deleteAllSessionsForContact:envelope.source protocolContext:transaction];
}

- (void)handleExpirationTimerUpdateMessageWithEnvelope:(SSKProtoEnvelope *)envelope
                                           dataMessage:(SSKProtoDataMessage *)dataMessage
                                           transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    if (!envelope) {
        OWSFailDebug(@"Missing envelope.");
        return;
    }
    if (!dataMessage) {
        OWSFailDebug(@"Missing dataMessage.");
        return;
    }
    if (!transaction) {
        OWSFail(@"Missing transaction.");
        return;
    }

    TSThread *_Nullable thread = [self threadForEnvelope:envelope dataMessage:dataMessage transaction:transaction];
    if (!thread) {
        OWSFailDebug(@"ignoring expiring messages update for unknown group.");
        return;
    }

    OWSDisappearingMessagesConfiguration *disappearingMessagesConfiguration;
    if (dataMessage.hasExpireTimer && dataMessage.expireTimer > 0) {
        OWSLogInfo(
            @"Expiring messages duration turned to %u for thread %@", (unsigned int)dataMessage.expireTimer, thread);
        disappearingMessagesConfiguration =
            [[OWSDisappearingMessagesConfiguration alloc] initWithThreadId:thread.uniqueId
                                                                   enabled:YES
                                                           durationSeconds:dataMessage.expireTimer];
    } else {
        OWSLogInfo(@"Expiring messages have been turned off for thread %@", thread);
        disappearingMessagesConfiguration = [[OWSDisappearingMessagesConfiguration alloc]
            initWithThreadId:thread.uniqueId
                     enabled:NO
             durationSeconds:OWSDisappearingMessagesConfigurationDefaultExpirationDuration];
    }
    OWSAssertDebug(disappearingMessagesConfiguration);
    [disappearingMessagesConfiguration saveWithTransaction:transaction];
    NSString *name = [self.contactsManager displayNameForPhoneIdentifier:envelope.source];
    OWSDisappearingConfigurationUpdateInfoMessage *message =
        [[OWSDisappearingConfigurationUpdateInfoMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                                          thread:thread
                                                                   configuration:disappearingMessagesConfiguration
                                                             createdByRemoteName:name
                                                          createdInExistingGroup:NO];
    [message saveWithTransaction:transaction];
}

- (void)handleProfileKeyMessageWithEnvelope:(SSKProtoEnvelope *)envelope
                                dataMessage:(SSKProtoDataMessage *)dataMessage
{
    if (!envelope) {
        OWSFailDebug(@"Missing envelope.");
        return;
    }
    if (!dataMessage) {
        OWSFailDebug(@"Missing dataMessage.");
        return;
    }

    NSString *recipientId = envelope.source;
    if (!dataMessage.hasProfileKey) {
        OWSFailDebug(@"received profile key message without profile key from: %@", envelopeAddress(envelope));
        return;
    }
    NSData *profileKey = dataMessage.profileKey;
    if (profileKey.length != kAES256_KeyByteLength) {
        OWSFailDebug(@"received profile key of unexpected length:%lu from:%@",
            (unsigned long)profileKey.length,
            envelopeAddress(envelope));
        return;
    }

    id<ProfileManagerProtocol> profileManager = SSKEnvironment.shared.profileManager;
    [profileManager setProfileKeyData:profileKey forRecipientId:recipientId];
}

- (void)handleReceivedTextMessageWithEnvelope:(SSKProtoEnvelope *)envelope
                                  dataMessage:(SSKProtoDataMessage *)dataMessage
                                  transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    if (!envelope) {
        OWSFailDebug(@"Missing envelope.");
        return;
    }
    if (!dataMessage) {
        OWSFailDebug(@"Missing dataMessage.");
        return;
    }
    if (!transaction) {
        OWSFail(@"Missing transaction.");
        return;
    }

    [self handleReceivedEnvelope:envelope withDataMessage:dataMessage attachmentIds:@[] transaction:transaction];
}

- (void)sendGroupUpdateForThread:(TSGroupThread *)gThread message:(TSOutgoingMessage *)message
{
    if (!gThread) {
        OWSFailDebug(@"Missing gThread.");
        return;
    }
    if (!gThread.groupModel) {
        OWSFailDebug(@"Missing gThread.groupModel.");
        return;
    }
    if (!message) {
        OWSFailDebug(@"Missing message.");
        return;
    }

    if (gThread.groupModel.groupImage) {
        NSData *data = UIImagePNGRepresentation(gThread.groupModel.groupImage);
        DataSource *_Nullable dataSource = [DataSourceValue dataSourceWithData:data fileExtension:@"png"];
        [self.messageSender enqueueTemporaryAttachment:dataSource
            contentType:OWSMimeTypeImagePng
            inMessage:message
            success:^{
                OWSLogDebug(@"Successfully sent group update with avatar");
            }
            failure:^(NSError *error) {
                OWSLogError(@"Failed to send group avatar update with error: %@", error);
            }];
    } else {
        [self.messageSender enqueueMessage:message
            success:^{
                OWSLogDebug(@"Successfully sent group update");
            }
            failure:^(NSError *error) {
                OWSLogError(@"Failed to send group update with error: %@", error);
            }];
    }
}

- (void)handleGroupInfoRequest:(SSKProtoEnvelope *)envelope
                   dataMessage:(SSKProtoDataMessage *)dataMessage
                   transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    if (!envelope) {
        OWSFailDebug(@"Missing envelope.");
        return;
    }
    if (!dataMessage) {
        OWSFailDebug(@"Missing dataMessage.");
        return;
    }
    if (!transaction) {
        OWSFail(@"Missing transaction.");
        return;
    }
    if (dataMessage.group.type != SSKProtoGroupContextTypeRequestInfo) {
        OWSFailDebug(@"Unexpected group message type.");
        return;
    }

    NSData *groupId = dataMessage.group ? dataMessage.group.id : nil;
    if (!groupId) {
        OWSFailDebug(@"Group info request is missing group id.");
        return;
    }

    OWSLogInfo(@"Received 'Request Group Info' message for group: %@ from: %@", groupId, envelope.source);

    TSGroupThread *_Nullable gThread = [TSGroupThread threadWithGroupId:dataMessage.group.id transaction:transaction];
    if (!gThread) {
        OWSLogWarn(@"Unknown group: %@", groupId);
        return;
    }

    // Ensure sender is in the group.
    if (![gThread.groupModel.groupMemberIds containsObject:envelope.source]) {
        OWSLogWarn(@"Ignoring 'Request Group Info' message for non-member of group. %@ not in %@",
            envelope.source,
            gThread.groupModel.groupMemberIds);
        return;
    }

    // Ensure we are in the group.
    NSString *localNumber = [TSAccountManager localNumber];
    if (![gThread.groupModel.groupMemberIds containsObject:localNumber]) {
        OWSLogWarn(@"Ignoring 'Request Group Info' message for group we no longer belong to.");
        return;
    }

    NSString *updateGroupInfo =
        [gThread.groupModel getInfoStringAboutUpdateTo:gThread.groupModel contactsManager:self.contactsManager];

    uint32_t expiresInSeconds = [gThread disappearingMessagesDurationWithTransaction:transaction];
    TSOutgoingMessage *message = [TSOutgoingMessage outgoingMessageInThread:gThread
                                                           groupMetaMessage:TSGroupMetaMessageUpdate
                                                           expiresInSeconds:expiresInSeconds];

    [message updateWithCustomMessage:updateGroupInfo transaction:transaction];
    // Only send this group update to the requester.
    [message updateWithSendingToSingleGroupRecipient:envelope.source transaction:transaction];

    [self sendGroupUpdateForThread:gThread message:message];
}

- (TSIncomingMessage *_Nullable)handleReceivedEnvelope:(SSKProtoEnvelope *)envelope
                                       withDataMessage:(SSKProtoDataMessage *)dataMessage
                                         attachmentIds:(NSArray<NSString *> *)attachmentIds
                                           transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    if (!envelope) {
        OWSFailDebug(@"Missing envelope.");
        return nil;
    }
    if (!dataMessage) {
        OWSFailDebug(@"Missing dataMessage.");
        return nil;
    }
    if (!transaction) {
        OWSFail(@"Missing transaction.");
        return nil;
    }

    uint64_t timestamp = envelope.timestamp;
    NSString *body = dataMessage.body;
    NSData *groupId = dataMessage.group ? dataMessage.group.id : nil;
    OWSContact *_Nullable contact = [OWSContacts contactForDataMessage:dataMessage transaction:transaction];

    if (dataMessage.group.type == SSKProtoGroupContextTypeRequestInfo) {
        [self handleGroupInfoRequest:envelope dataMessage:dataMessage transaction:transaction];
        return nil;
    }

    if (groupId.length > 0) {
        NSMutableSet *newMemberIds = [NSMutableSet setWithArray:dataMessage.group.members];
        for (NSString *recipientId in newMemberIds) {
            if (!recipientId.isValidE164) {
                OWSLogVerbose(
                    @"incoming group update has invalid group member: %@", [self descriptionForEnvelope:envelope]);
                OWSFailDebug(@"incoming group update has invalid group member");
                return nil;
            }
        }

        // Group messages create the group if it doesn't already exist.
        //
        // We distinguish between the old group state (if any) and the new group state.
        TSGroupThread *_Nullable oldGroupThread = [TSGroupThread threadWithGroupId:groupId transaction:transaction];
        if (oldGroupThread) {
            // Don't trust other clients; ensure all known group members remain in the
            // group unless it is a "quit" message in which case we should only remove
            // the quiting member below.
            [newMemberIds addObjectsFromArray:oldGroupThread.groupModel.groupMemberIds];
        }

        switch (dataMessage.group.type) {
            case SSKProtoGroupContextTypeUpdate: {
                // Ensures that the thread exists but doesn't update it.
                TSGroupThread *newGroupThread =
                    [TSGroupThread getOrCreateThreadWithGroupId:groupId transaction:transaction];


                uint64_t now = [NSDate ows_millisecondTimeStamp];
                TSGroupModel *newGroupModel = [[TSGroupModel alloc] initWithTitle:dataMessage.group.name
                                                                        memberIds:newMemberIds.allObjects
                                                                            image:oldGroupThread.groupModel.groupImage
                                                                          groupId:dataMessage.group.id];
                NSString *updateGroupInfo = [newGroupThread.groupModel getInfoStringAboutUpdateTo:newGroupModel
                                                                                  contactsManager:self.contactsManager];
                newGroupThread.groupModel = newGroupModel;
                [newGroupThread saveWithTransaction:transaction];

                TSInfoMessage *infoMessage = [[TSInfoMessage alloc] initWithTimestamp:now
                                                                             inThread:newGroupThread
                                                                          messageType:TSInfoMessageTypeGroupUpdate
                                                                        customMessage:updateGroupInfo];
                [infoMessage saveWithTransaction:transaction];

                if (dataMessage.hasExpireTimer && dataMessage.expireTimer > 0) {
                    [[OWSDisappearingMessagesJob sharedJob]
                        becomeConsistentWithDisappearingDuration:dataMessage.expireTimer
                                                          thread:newGroupThread
                                           appearBeforeTimestamp:now
                                      createdByRemoteContactName:nil
                                          createdInExistingGroup:YES
                                                     transaction:transaction];
                }

                return nil;
            }
            case SSKProtoGroupContextTypeQuit: {
                if (!oldGroupThread) {
                    OWSLogWarn(@"ignoring quit group message from unknown group.");
                    return nil;
                }
                [newMemberIds removeObject:envelope.source];
                oldGroupThread.groupModel.groupMemberIds = [newMemberIds.allObjects mutableCopy];
                [oldGroupThread saveWithTransaction:transaction];

                NSString *nameString = [self.contactsManager displayNameForPhoneIdentifier:envelope.source];
                NSString *updateGroupInfo =
                    [NSString stringWithFormat:NSLocalizedString(@"GROUP_MEMBER_LEFT", @""), nameString];
                [[[TSInfoMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                 inThread:oldGroupThread
                                              messageType:TSInfoMessageTypeGroupUpdate
                                            customMessage:updateGroupInfo] saveWithTransaction:transaction];
                return nil;
            }
            case SSKProtoGroupContextTypeDeliver: {
                if (!oldGroupThread) {
                    OWSFailDebug(@"ignoring deliver group message from unknown group.");
                    return nil;
                }

                if (body.length == 0 && attachmentIds.count < 1 && !contact) {
                    OWSLogWarn(@"ignoring empty incoming message from: %@ for group: %@ with timestamp: %lu",
                        envelopeAddress(envelope),
                        groupId,
                        (unsigned long)timestamp);
                    return nil;
                }

                TSQuotedMessage *_Nullable quotedMessage = [TSQuotedMessage quotedMessageForDataMessage:dataMessage
                                                                                                 thread:oldGroupThread
                                                                                            transaction:transaction];

                OWSLogDebug(@"incoming message from: %@ for group: %@ with timestamp: %lu",
                    envelopeAddress(envelope),
                    groupId,
                    (unsigned long)timestamp);

                TSIncomingMessage *incomingMessage =
                    [[TSIncomingMessage alloc] initIncomingMessageWithTimestamp:timestamp
                                                                       inThread:oldGroupThread
                                                                       authorId:envelope.source
                                                                 sourceDeviceId:envelope.sourceDevice
                                                                    messageBody:body
                                                                  attachmentIds:attachmentIds
                                                               expiresInSeconds:dataMessage.expireTimer
                                                                  quotedMessage:quotedMessage
                                                                   contactShare:contact];

                [self finalizeIncomingMessage:incomingMessage
                                       thread:oldGroupThread
                                     envelope:envelope
                                  transaction:transaction];
                return incomingMessage;
            }
            default: {
                OWSLogWarn(@"Ignoring unknown group message type: %d", (int)dataMessage.group.type);
                return nil;
            }
        }
    } else {
        if (body.length == 0 && attachmentIds.count < 1 && !contact) {
            OWSLogWarn(@"ignoring empty incoming message from: %@ with timestamp: %lu",
                envelopeAddress(envelope),
                (unsigned long)timestamp);
            return nil;
        }

        OWSLogDebug(
            @"incoming message from: %@ with timestamp: %lu", envelopeAddress(envelope), (unsigned long)timestamp);
        TSContactThread *thread =
            [TSContactThread getOrCreateThreadWithContactId:envelope.source transaction:transaction];

        TSQuotedMessage *_Nullable quotedMessage = [TSQuotedMessage quotedMessageForDataMessage:dataMessage
                                                                                         thread:thread
                                                                                    transaction:transaction];

        TSIncomingMessage *incomingMessage =
            [[TSIncomingMessage alloc] initIncomingMessageWithTimestamp:timestamp
                                                               inThread:thread
                                                               authorId:[thread contactIdentifier]
                                                         sourceDeviceId:envelope.sourceDevice
                                                            messageBody:body
                                                          attachmentIds:attachmentIds
                                                       expiresInSeconds:dataMessage.expireTimer
                                                          quotedMessage:quotedMessage
                                                           contactShare:contact];

        [self finalizeIncomingMessage:incomingMessage
                               thread:thread
                             envelope:envelope
                          transaction:transaction];
        return incomingMessage;
    }
}

- (void)finalizeIncomingMessage:(TSIncomingMessage *)incomingMessage
                         thread:(TSThread *)thread
                       envelope:(SSKProtoEnvelope *)envelope
                    transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    if (!envelope) {
        OWSFailDebug(@"Missing envelope.");
        return;
    }
    if (!thread) {
        OWSFailDebug(@"Missing thread.");
        return;
    }
    if (!incomingMessage) {
        OWSFailDebug(@"Missing incomingMessage.");
        return;
    }
    if (!transaction) {
        OWSFail(@"Missing transaction.");
        return;
    }

    [incomingMessage saveWithTransaction:transaction];

    // Any messages sent from the current user - from this device or another - should be automatically marked as read.
    if ([envelope.source isEqualToString:TSAccountManager.localNumber]) {
        // Don't send a read receipt for messages sent by ourselves.
        [incomingMessage markAsReadAtTimestamp:envelope.timestamp sendReadReceipt:NO transaction:transaction];
    }

    TSQuotedMessage *_Nullable quotedMessage = incomingMessage.quotedMessage;
    if (quotedMessage && quotedMessage.thumbnailAttachmentPointerId) {
        // We weren't able to derive a local thumbnail, so we'll fetch the referenced attachment.
        TSAttachmentPointer *attachmentPointer =
            [TSAttachmentPointer fetchObjectWithUniqueID:quotedMessage.thumbnailAttachmentPointerId
                                             transaction:transaction];

        if ([attachmentPointer isKindOfClass:[TSAttachmentPointer class]]) {
            OWSAttachmentsProcessor *attachmentProcessor =
                [[OWSAttachmentsProcessor alloc] initWithAttachmentPointer:attachmentPointer
                                                            networkManager:self.networkManager];

            OWSLogDebug(@"downloading thumbnail for message: %lu", (unsigned long)incomingMessage.timestamp);
            [attachmentProcessor fetchAttachmentsForMessage:incomingMessage
                transaction:transaction
                success:^(TSAttachmentStream *attachmentStream) {
                    [self.dbConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                        [incomingMessage setQuotedMessageThumbnailAttachmentStream:attachmentStream];
                        [incomingMessage saveWithTransaction:transaction];
                    }];
                }
                failure:^(NSError *error) {
                    OWSLogWarn(@"failed to fetch thumbnail for message: %lu with error: %@",
                        (unsigned long)incomingMessage.timestamp,
                        error);
                }];
        }
    }

    OWSContact *_Nullable contact = incomingMessage.contactShare;
    if (contact && contact.avatarAttachmentId) {
        TSAttachmentPointer *attachmentPointer =
            [TSAttachmentPointer fetchObjectWithUniqueID:contact.avatarAttachmentId transaction:transaction];

        if (![attachmentPointer isKindOfClass:[TSAttachmentPointer class]]) {
            OWSFailDebug(@"avatar attachmentPointer was unexpectedly nil");
        } else {
            OWSAttachmentsProcessor *attachmentProcessor =
                [[OWSAttachmentsProcessor alloc] initWithAttachmentPointer:attachmentPointer
                                                            networkManager:self.networkManager];

            OWSLogDebug(@"downloading contact avatar for message: %lu", (unsigned long)incomingMessage.timestamp);
            [attachmentProcessor fetchAttachmentsForMessage:incomingMessage
                transaction:transaction
                success:^(TSAttachmentStream *attachmentStream) {
                    [self.dbConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                        [incomingMessage touchWithTransaction:transaction];
                    }];
                }
                failure:^(NSError *error) {
                    OWSLogWarn(@"failed to fetch contact avatar for message: %lu with error: %@",
                        (unsigned long)incomingMessage.timestamp,
                        error);
                }];
        }
    }
    // In case we already have a read receipt for this new message (this happens sometimes).
    [OWSReadReceiptManager.sharedManager applyEarlyReadReceiptsForIncomingMessage:incomingMessage
                                                                      transaction:transaction];

    [[OWSDisappearingMessagesJob sharedJob] becomeConsistentWithConfigurationForMessage:incomingMessage
                                                                        contactsManager:self.contactsManager
                                                                            transaction:transaction];

    // Update thread preview in inbox
    [thread touchWithTransaction:transaction];

    [SSKEnvironment.shared.notificationsManager notifyUserForIncomingMessage:incomingMessage
                                                                    inThread:thread
                                                             contactsManager:self.contactsManager
                                                                 transaction:transaction];
}

#pragma mark - helpers

- (BOOL)isDataMessageGroupAvatarUpdate:(SSKProtoDataMessage *)dataMessage
{
    if (!dataMessage) {
        OWSFailDebug(@"Missing dataMessage.");
        return NO;
    }

    return (dataMessage.group != nil && dataMessage.group.type == SSKProtoGroupContextTypeUpdate
        && dataMessage.group.avatar != nil);
}

/**
 * @returns
 *   Group or Contact thread for message, creating a new contact thread if necessary,
 *   but never creating a new group thread.
 */
- (nullable TSThread *)threadForEnvelope:(SSKProtoEnvelope *)envelope
                             dataMessage:(SSKProtoDataMessage *)dataMessage
                             transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    if (!envelope) {
        OWSFailDebug(@"Missing envelope.");
        return nil;
    }
    if (!dataMessage) {
        OWSFailDebug(@"Missing dataMessage.");
        return nil;
    }
    if (!transaction) {
        OWSFail(@"Missing transaction.");
        return nil;
    }

    if (dataMessage.group) {
        NSData *groupId = dataMessage.group.id;
        OWSAssertDebug(groupId.length > 0);
        TSGroupThread *_Nullable groupThread = [TSGroupThread threadWithGroupId:groupId transaction:transaction];
        // This method should only be called from a code path that has already verified
        // that this is a "known" group.
        OWSAssertDebug(groupThread);
        return groupThread;
    } else {
        return [TSContactThread getOrCreateThreadWithContactId:envelope.source transaction:transaction];
    }
}

@end

NS_ASSUME_NONNULL_END
