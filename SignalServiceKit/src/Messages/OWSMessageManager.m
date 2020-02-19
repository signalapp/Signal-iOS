//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageManager.h"
#import "AppContext.h"
#import "AppReadiness.h"
#import "ContactsManagerProtocol.h"
#import "MimeTypeUtil.h"
#import "NSNotificationCenter+OWS.h"
#import "NSString+SSK.h"
#import "NotificationsProtocol.h"
#import "OWSAttachmentDownloads.h"
#import "OWSBlockingManager.h"
#import "OWSCallMessageHandler.h"
#import "OWSContact.h"
#import "OWSDevice.h"
#import "OWSDevicesService.h"
#import "OWSDisappearingConfigurationUpdateInfoMessage.h"
#import "OWSDisappearingMessagesConfiguration.h"
#import "OWSDisappearingMessagesJob.h"
#import "LKEphemeralMessage.h"
#import "LKSessionRequestMessage.h"
#import "LKDeviceLinkMessage.h"
#import "OWSIdentityManager.h"
#import "OWSIncomingMessageFinder.h"
#import "OWSIncomingSentMessageTranscript.h"
#import "OWSMessageSender.h"
#import "OWSMessageUtils.h"
#import "OWSOutgoingReceiptManager.h"
#import "OWSPrimaryStorage+SessionStore.h"
#import "OWSPrimaryStorage+Loki.h"
#import "OWSPrimaryStorage.h"
#import "OWSReadReceiptManager.h"
#import "OWSRecordTranscriptJob.h"
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
#import <SignalCoreKit/Cryptography.h>
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalMetadataKit/SignalMetadataKit-Swift.h>
#import <SignalServiceKit/NSObject+Casting.h>
#import <SignalServiceKit/SignalRecipient.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <YapDatabase/YapDatabase.h>
#import "OWSDispatch.h"
#import "OWSBatchMessageProcessor.h"
#import "OWSQueues.h"

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

    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

#pragma mark - Dependencies

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

- (SSKMessageSenderJobQueue *)messageSenderJobQueue
{
    return SSKEnvironment.shared.messageSenderJobQueue;
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

- (OWSOutgoingReceiptManager *)outgoingReceiptManager
{
    OWSAssertDebug(SSKEnvironment.shared.outgoingReceiptManager);

    return SSKEnvironment.shared.outgoingReceiptManager;
}

- (id<OWSSyncManagerProtocol>)syncManager
{
    OWSAssertDebug(SSKEnvironment.shared.syncManager);

    return SSKEnvironment.shared.syncManager;
}

- (TSAccountManager *)tsAccountManager
{
    OWSAssertDebug(SSKEnvironment.shared.tsAccountManager);

    return SSKEnvironment.shared.tsAccountManager;
}

- (id<ProfileManagerProtocol>)profileManager
{
    return SSKEnvironment.shared.profileManager;
}

- (id<OWSTypingIndicators>)typingIndicators
{
    return SSKEnvironment.shared.typingIndicators;
}

- (OWSAttachmentDownloads *)attachmentDownloads
{
    return SSKEnvironment.shared.attachmentDownloads;
}

#pragma mark -

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
            [AppReadiness runNowOrWhenAppDidBecomeReady:^{
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

- (void)throws_processEnvelope:(SSKProtoEnvelope *)envelope
                 plaintextData:(NSData *_Nullable)plaintextData
               wasReceivedByUD:(BOOL)wasReceivedByUD
                   transaction:(YapDatabaseReadWriteTransaction *)transaction
                      serverID:(uint64_t)serverID
{
    if (!envelope) {
        OWSFailDebug(@"Missing envelope.");
        return;
    }
    if (!transaction) {
        OWSFail(@"Missing transaction.");
        return;
    }
    if (!self.tsAccountManager.isRegistered) {
        OWSFailDebug(@"Not registered.");
        return;
    }
    if (!CurrentAppContext().isMainApp) {
        OWSFail(@"Not the main app.");
        return;
    }

    OWSLogInfo(@"Handling decrypted envelope: %@.", [self descriptionForEnvelope:envelope]);

    if (!wasReceivedByUD) {
        if (!envelope.hasSource || envelope.source.length < 1) {
            OWSFailDebug(@"Incoming envelope with invalid source.");
            return;
        }
        if (!envelope.hasSourceDevice || envelope.sourceDevice < 1) {
            OWSFailDebug(@"Incoming envelope with invalid source device.");
            return;
        }
    }

    OWSAssertDebug(![self isEnvelopeSenderBlocked:envelope]);

    // Loki: Ignore any friend requests from before restoration
    // The envelope type is set during UD decryption.
    uint64_t restorationTime = [NSNumber numberWithDouble:[OWSPrimaryStorage.sharedManager getRestorationTime]].unsignedLongLongValue;
    if (envelope.type == SSKProtoEnvelopeTypeFriendRequest && envelope.timestamp < restorationTime * 1000) {
        [LKLogger print:@"[Loki] Ignoring friend request received before restoration."];
        return;
    }
    
    [self checkForUnknownLinkedDevice:envelope transaction:transaction];

    switch (envelope.type) {
        case SSKProtoEnvelopeTypeFriendRequest:
        case SSKProtoEnvelopeTypeCiphertext:
        case SSKProtoEnvelopeTypePrekeyBundle:
        case SSKProtoEnvelopeTypeUnidentifiedSender:
            if (!plaintextData) {
                OWSFailDebug(@"missing decrypted data for envelope: %@", [self descriptionForEnvelope:envelope]);
                return;
            }
            [self throws_handleEnvelope:envelope
                          plaintextData:plaintextData
                        wasReceivedByUD:wasReceivedByUD
                            transaction:transaction
                               serverID:serverID];
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

- (void)throws_handleEnvelope:(SSKProtoEnvelope *)envelope
                plaintextData:(NSData *)plaintextData
              wasReceivedByUD:(BOOL)wasReceivedByUD
                  transaction:(YapDatabaseReadWriteTransaction *)transaction
                     serverID:(uint64_t)serverID
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
        OWSFailDebug(@"Invalid source device.");
        return;
    }

    BOOL duplicateEnvelope = [self.incomingMessageFinder existsMessageWithTimestamp:envelope.timestamp
                                                                           sourceId:envelope.source
                                                                     sourceDeviceId:envelope.sourceDevice
                                                                        transaction:transaction];
    if (duplicateEnvelope) {
        OWSLogInfo(@"Ignoring previously received envelope from: %@ with timestamp: %llu.",
            envelopeAddress(envelope),
            envelope.timestamp);
        return;
    }
    
    // Loki: Handle friend request acceptance if needed
    // The envelope type is set during UD decryption.
    [self handleFriendRequestAcceptanceIfNeededWithEnvelope:envelope transaction:transaction];
    
    if (envelope.content != nil) {
        NSError *error;
        SSKProtoContent *_Nullable contentProto = [SSKProtoContent parseData:plaintextData error:&error];
        if (error || !contentProto) {
            OWSFailDebug(@"Could not parse proto due to error: %@.", error);
            return;
        }
        OWSLogInfo(@"Handling content: <Content: %@>.", [self descriptionForContent:contentProto]);
        
        // Loki: Workaround for duplicate sync transcript issue
        if (contentProto.syncMessage != nil && contentProto.syncMessage.sent != nil) {
            BOOL isDuplicate = [LKAPI isDuplicateSyncMessage:contentProto.syncMessage.sent from:envelope.source];
            if (isDuplicate) { return; }
        }

        // Loki: Handle pre key bundle message if needed
        if (contentProto.prekeyBundleMessage != nil) {
            OWSLogInfo(@"[Loki] Received a pre key bundle message from: %@.", envelope.source);
            PreKeyBundle *_Nullable bundle = [contentProto.prekeyBundleMessage getPreKeyBundleWithTransaction:transaction];
            if (bundle == nil) {
                OWSFailDebug(@"Failed to create a pre key bundle.");
                return;
            }
            [self.primaryStorage setPreKeyBundle:bundle forContact:envelope.source transaction:transaction];
            
            // Loki: If we received a friend request, but we were already friends with this user, reset the session
            // The envelope type is set during UD decryption.
            if (envelope.type == SSKProtoEnvelopeTypeFriendRequest) {
                TSContactThread *thread = [TSContactThread getThreadWithContactId:envelope.source transaction:transaction];
                if (thread && thread.isContactFriend) {
                    [self resetSessionWithContact:envelope.source transaction:transaction];
                    // Let our other devices know that we have reset the session
                    [SSKEnvironment.shared.syncManager syncContact:envelope.source transaction:transaction];
                }
            }
        }
        
        // Loki: Handle address message if needed
        if (contentProto.lokiAddressMessage) {
            NSString *address = contentProto.lokiAddressMessage.ptpAddress;
            uint32_t port = contentProto.lokiAddressMessage.ptpPort;
            [LKP2PAPI didReceiveLokiAddressMessageForContact:envelope.source address:address port:port receivedThroughP2P:envelope.isPtpMessage];
        }

        // Loki: Handle device linking message if needed
        if (contentProto.lokiDeviceLinkMessage != nil) {
            NSString *masterHexEncodedPublicKey = contentProto.lokiDeviceLinkMessage.masterHexEncodedPublicKey;
            NSString *slaveHexEncodedPublicKey = contentProto.lokiDeviceLinkMessage.slaveHexEncodedPublicKey;
            NSData *masterSignature = contentProto.lokiDeviceLinkMessage.masterSignature;
            NSData *slaveSignature = contentProto.lokiDeviceLinkMessage.slaveSignature;
            if (masterSignature != nil) { // Authorization
                OWSLogInfo(@"[Loki] Received a device linking authorization from: %@", envelope.source); // Not masterHexEncodedPublicKey
                [LKDeviceLinkingSession.current processLinkingAuthorizationFrom:masterHexEncodedPublicKey for:slaveHexEncodedPublicKey masterSignature:masterSignature slaveSignature:slaveSignature];
                // Set any profile info
                if (contentProto.dataMessage) {
                    SSKProtoDataMessage *dataMessage = contentProto.dataMessage;
                    [self handleProfileNameUpdateIfNeeded:dataMessage recipientId:masterHexEncodedPublicKey transaction:transaction];
                    [self handleProfileKeyUpdateIfNeeded:dataMessage recipientId:masterHexEncodedPublicKey];
                }
            } else if (slaveSignature != nil) { // Request
                OWSLogInfo(@"[Loki] Received a device linking request from: %@", envelope.source); // Not slaveHexEncodedPublicKey
                [LKDeviceLinkingSession.current processLinkingRequestFrom:slaveHexEncodedPublicKey to:masterHexEncodedPublicKey with:slaveSignature];
            }
        } else if (contentProto.syncMessage) {
            [self throws_handleIncomingEnvelope:envelope
                                withSyncMessage:contentProto.syncMessage
                                    transaction:transaction
                                       serverID:serverID];

            [[OWSDeviceManager sharedManager] setHasReceivedSyncMessage];
        } else if (contentProto.dataMessage) {
            [self handleIncomingEnvelope:envelope
                         withDataMessage:contentProto.dataMessage
                         wasReceivedByUD:wasReceivedByUD
                             transaction:transaction];
        } else if (contentProto.callMessage) {
            [self handleIncomingEnvelope:envelope withCallMessage:contentProto.callMessage];
        } else if (contentProto.typingMessage) {
            [self handleIncomingEnvelope:envelope withTypingMessage:contentProto.typingMessage transaction:transaction];
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

        [self handleIncomingEnvelope:envelope
                     withDataMessage:dataMessageProto
                     wasReceivedByUD:wasReceivedByUD
                         transaction:transaction];
    } else {
        OWSProdInfoWEnvelope([OWSAnalyticsEvents messageManagerErrorEnvelopeNoActionablePayload], envelope);
    }
}

- (void)handleIncomingEnvelope:(SSKProtoEnvelope *)envelope
               withDataMessage:(SSKProtoDataMessage *)dataMessage
               wasReceivedByUD:(BOOL)wasReceivedByUD
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
    
    // Loki: Don't process session request messages any further
    if ((dataMessage.flags & SSKProtoDataMessageFlagsSessionRequest) != 0) { return; }
    // Loki: Don't process session restore messages any further
    if ((dataMessage.flags & SSKProtoDataMessageFlagsSessionRestore) != 0) { return; }
    
    if ([self isDataMessageBlocked:dataMessage envelope:envelope]) {
        NSString *logMessage = [NSString stringWithFormat:@"Ignoring blocked message from sender: %@.", envelope.source];
        if (dataMessage.group) {
            logMessage = [logMessage stringByAppendingFormat:@" in group: %@", dataMessage.group.id];
        }
        OWSLogError(@"%@", logMessage);
        return;
    }

    if (dataMessage.hasTimestamp) {
        if (dataMessage.timestamp <= 0) {
            OWSFailDebug(@"Ignoring data message with invalid timestamp: %@.", envelope.source);
            return;
        }
        // This prevents replay attacks by the service.
        if (dataMessage.timestamp != envelope.timestamp) {
            OWSFailDebug(@"Ignoring data message with non-matching timestamp: %@.", envelope.source);
            return;
        }
    }
    
    [self handleProfileKeyUpdateIfNeeded:dataMessage recipientId:envelope.source];

    if (dataMessage.group) {
        TSGroupThread *_Nullable groupThread =
            [TSGroupThread threadWithGroupId:dataMessage.group.id transaction:transaction];

        if (groupThread) {
            if (dataMessage.group.type != SSKProtoGroupContextTypeUpdate) {
                if (![groupThread isLocalUserInGroupWithTransaction:transaction]) {
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
                OWSLogInfo(@"Ignoring group message for unknown group from: %@.", envelope.source);
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
    } else if ((dataMessage.flags & SSKProtoDataMessageFlagsUnlinkDevice) != 0) {
        [self handleUnlinkDeviceMessageWithEnvelope:envelope dataMessage:dataMessage transaction:transaction];
    } else if (dataMessage.attachments.count > 0) {
        [self handleReceivedMediaWithEnvelope:envelope
                                  dataMessage:dataMessage
                              wasReceivedByUD:wasReceivedByUD
                                  transaction:transaction];
    } else {
        [self handleReceivedTextMessageWithEnvelope:envelope
                                        dataMessage:dataMessage
                                    wasReceivedByUD:wasReceivedByUD
                                        transaction:transaction];

        if ([self isDataMessageGroupAvatarUpdate:dataMessage]) {
            OWSLogVerbose(@"Data message had group avatar attachment");
            [self handleReceivedGroupAvatarUpdateWithEnvelope:envelope dataMessage:dataMessage transaction:transaction];
        }
    }

    // Send delivery receipts for "valid data" messages received via UD.
    if (wasReceivedByUD) {
        [self.outgoingReceiptManager enqueueDeliveryReceiptForEnvelope:envelope];
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

    [self.messageSenderJobQueue addMessage:syncGroupsRequestMessage transaction:transaction];
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

- (void)handleIncomingEnvelope:(SSKProtoEnvelope *)envelope
             withTypingMessage:(SSKProtoTypingMessage *)typingMessage
                   transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssertDebug(transaction);

    if (!envelope) {
        OWSFailDebug(@"Missing envelope.");
        return;
    }
    if (!typingMessage) {
        OWSFailDebug(@"Missing typingMessage.");
        return;
    }
    if (typingMessage.timestamp != envelope.timestamp) {
        OWSFailDebug(@"typingMessage has invalid timestamp.");
        return;
    }
    NSString *localNumber = self.tsAccountManager.localNumber;
    if ([localNumber isEqualToString:envelope.source]) {
        OWSLogVerbose(@"Ignoring typing indicators from self or linked device.");
        return;
    } else if ([self.blockingManager isRecipientIdBlocked:envelope.source]
        || (typingMessage.hasGroupID && [self.blockingManager isGroupIdBlocked:typingMessage.groupID])) {
        NSString *logMessage = [NSString stringWithFormat:@"Ignoring blocked message from sender: %@", envelope.source];
        if (typingMessage.hasGroupID) {
            logMessage = [logMessage stringByAppendingFormat:@" in group: %@", typingMessage.groupID];
        }
        OWSLogError(@"%@", logMessage);
        return;
    }

    TSThread *_Nullable thread;
    if (typingMessage.hasGroupID) {
        TSGroupThread *groupThread = [TSGroupThread threadWithGroupId:typingMessage.groupID transaction:transaction];

        if (![groupThread isLocalUserInGroupWithTransaction:transaction]) {
            OWSLogInfo(@"Ignoring messages for left group.");
            return;
        }

        thread = groupThread;
    } else {
        thread = [TSContactThread getThreadWithContactId:envelope.source transaction:transaction];
    }

    if (!thread) {
        // This isn't neccesarily an error.  We might not yet know about the thread,
        // in which case we don't need to display the typing indicators.
        OWSLogWarn(@"Could not locate thread for typingMessage.");
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        switch (typingMessage.action) {
            case SSKProtoTypingMessageActionStarted:
                [self.typingIndicators didReceiveTypingStartedMessageInThread:thread
                                                                  recipientId:envelope.source
                                                                     deviceId:envelope.sourceDevice];
                break;
            case SSKProtoTypingMessageActionStopped:
                [self.typingIndicators didReceiveTypingStoppedMessageInThread:thread
                                                                  recipientId:envelope.source
                                                                     deviceId:envelope.sourceDevice];
                break;
            default:
                OWSFailDebug(@"Typing message has unexpected action.");
                break;
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

    TSAttachmentPointer *_Nullable avatarPointer =
        [TSAttachmentPointer attachmentPointerFromProto:dataMessage.group.avatar albumMessage:nil];

    if (!avatarPointer) {
        OWSLogWarn(@"received unsupported group avatar envelope");
        return;
    }
    [self.attachmentDownloads downloadAttachmentPointer:avatarPointer
        success:^(NSArray<TSAttachmentStream *> *attachmentStreams) {
            OWSAssertDebug(attachmentStreams.count == 1);
            TSAttachmentStream *attachmentStream = attachmentStreams.firstObject;
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
                        wasReceivedByUD:(BOOL)wasReceivedByUD
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
        OWSFailDebug(@"Ignoring media message for unknown group.");
        return;
    }

    TSIncomingMessage *_Nullable message = [self handleReceivedEnvelope:envelope
                                                        withDataMessage:dataMessage
                                                        wasReceivedByUD:wasReceivedByUD
                                                            transaction:transaction];

    if (!message) {
        return;
    }

    [message saveWithTransaction:transaction];

    OWSLogDebug(@"Incoming attachment message: %@.", message.debugDescription);

    [self.attachmentDownloads downloadAttachmentsForMessage:message
        transaction:transaction
        success:^(NSArray<TSAttachmentStream *> *attachmentStreams) {
            OWSLogDebug(@"Successfully fetched attachments: %lu for message: %@.",
                (unsigned long)attachmentStreams.count,
                message);
        }
        failure:^(NSError *error) {
            OWSLogError(@"Failed to fetch attachments for message: %@ with error: %@.", message, error);
        }];
}

- (void)throws_handleIncomingEnvelope:(SSKProtoEnvelope *)envelope
                      withSyncMessage:(SSKProtoSyncMessage *)syncMessage
                          transaction:(YapDatabaseReadWriteTransaction *)transaction
                             serverID:(uint64_t)serverID
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

    NSString *userHexEncodedPublicKey = OWSIdentityManager.sharedManager.identityKeyPair.hexEncodedPublicKey;
    NSSet<NSString *> *linkedDeviceHexEncodedPublicKeys = [LKDatabaseUtilities getLinkedDeviceHexEncodedPublicKeysFor:userHexEncodedPublicKey in:transaction];
    if (![linkedDeviceHexEncodedPublicKeys contains:^BOOL(NSString *hexEncodedPublicKey) {
        return [hexEncodedPublicKey isEqual:envelope.source];
    }]) {
        OWSProdErrorWEnvelope([OWSAnalyticsEvents messageManagerErrorSyncMessageFromUnknownSource], envelope);
        return;
    }
    
    NSString *masterHexEncodedPublicKey = [LKDatabaseUtilities getMasterHexEncodedPublicKeyFor:userHexEncodedPublicKey in:transaction];
    BOOL wasSentByMasterDevice = [masterHexEncodedPublicKey isEqual:envelope.source];
    if (syncMessage.sent) {

        OWSIncomingSentMessageTranscript *transcript =
        [[OWSIncomingSentMessageTranscript alloc] initWithProto:syncMessage.sent transaction:transaction];
        
        SSKProtoDataMessage *_Nullable dataMessage = syncMessage.sent.message;
        if (!dataMessage) {
            OWSFailDebug(@"Missing dataMessage.");
            return;
        }
        
        // Loki: Try to update using the provided profile
       if (wasSentByMasterDevice) {
           [self handleProfileNameUpdateIfNeeded:dataMessage recipientId:masterHexEncodedPublicKey transaction:transaction];
           [self handleProfileKeyUpdateIfNeeded:dataMessage recipientId:masterHexEncodedPublicKey];
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
        
        if ([self isDataMessageGroupAvatarUpdate:syncMessage.sent.message] && !syncMessage.sent.isRecipientUpdate) {
            [OWSRecordTranscriptJob
             processIncomingSentMessageTranscript:transcript
             serverID:0
             attachmentHandler:^(NSArray<TSAttachmentStream *> *attachmentStreams) {
                OWSAssertDebug(attachmentStreams.count == 1);
                TSAttachmentStream *attachmentStream = attachmentStreams.firstObject;
                [self.dbConnection readWriteWithBlock:^(
                                                        YapDatabaseReadWriteTransaction *transaction) {
                    TSGroupThread *_Nullable groupThread =
                    [TSGroupThread threadWithGroupId:dataMessage.group.id
                                         transaction:transaction];
                    if (!groupThread) {
                        OWSFailDebug(@"ignoring sync group avatar update for unknown group.");
                        return;
                    }
                    
                    [groupThread updateAvatarWithAttachmentStream:attachmentStream
                                                      transaction:transaction];
                }];
            }
             transaction:transaction];
        } else {
            if (transcript.isGroupUpdate) {
                // TODO: This code is pretty much a duplicate of the code in OWSRecordTranscriptJob
                TSGroupThread *newGroupThread = [TSGroupThread getOrCreateThreadWithGroupId:transcript.dataMessage.group.id groupType:closedGroup transaction:transaction];
                TSGroupModel *newGroupModel = [[TSGroupModel alloc] initWithTitle:transcript.dataMessage.group.name
                                                                        memberIds:transcript.dataMessage.group.members
                                                                            image:nil
                                                                          groupId:transcript.dataMessage.group.id
                                                                        groupType:closedGroup
                                                                         adminIds:transcript.dataMessage.group.admins];
                NSString *updateMessage = [newGroupThread.groupModel getInfoStringAboutUpdateTo:newGroupModel contactsManager:self.contactsManager];
                newGroupThread.groupModel = newGroupModel;
                [newGroupThread saveWithTransaction:transaction];
                // Loki: Try to establish sessions with all members when a group is created or updated
                [self establishSessionsWithMembersIfNeeded: transcript.dataMessage.group.members forThread:newGroupThread transaction:transaction];
                [[OWSDisappearingMessagesJob sharedJob] becomeConsistentWithDisappearingDuration:transcript.dataMessage.expireTimer
                                                                                          thread:newGroupThread
                                                                      createdByRemoteRecipientId:nil
                                                                          createdInExistingGroup:YES
                                                                                     transaction:transaction];
                TSInfoMessage *infoMessage = [[TSInfoMessage alloc] initWithTimestamp:NSDate.ows_millisecondTimeStamp
                                                                             inThread:newGroupThread
                                                                          messageType:TSInfoMessageTypeGroupUpdate
                                                                        customMessage:updateMessage];
                [infoMessage saveWithTransaction:transaction];
            } else {
                [OWSRecordTranscriptJob
                 processIncomingSentMessageTranscript:transcript
                 serverID:(serverID ?: 0)
                 attachmentHandler:^(NSArray<TSAttachmentStream *> *attachmentStreams) {
                    OWSLogDebug(@"successfully fetched transcript attachments: %lu",
                                (unsigned long)attachmentStreams.count);
                }
                 transaction:transaction];
            }
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
                [[self.syncManager syncAllContacts] retainUntilComplete];
            });
        } else if (syncMessage.request.type == SSKProtoSyncMessageRequestTypeGroups) {
            OWSSyncGroupsMessage *syncGroupsMessage = [[OWSSyncGroupsMessage alloc] init];
            NSData *_Nullable syncData = [syncGroupsMessage buildPlainTextAttachmentDataWithTransaction:transaction];
            if (!syncData) {
                OWSFailDebug(@"Failed to serialize groups sync message.");
                return;
            }
            DataSource *dataSource = [DataSourceValue dataSourceWithSyncMessageData:syncData];
            [self.messageSenderJobQueue addMediaMessage:syncGroupsMessage
                                             dataSource:dataSource
                                            contentType:OWSMimeTypeApplicationOctetStream
                                         sourceFilename:nil
                                                caption:nil
                                         albumMessageId:nil
                                  isTemporaryAttachment:YES];
        } else if (syncMessage.request.type == SSKProtoSyncMessageRequestTypeBlocked) {
            OWSLogInfo(@"Received request for block list");
            [self.blockingManager syncBlockList];
        } else if (syncMessage.request.type == SSKProtoSyncMessageRequestTypeConfiguration) {
            [SSKEnvironment.shared.syncManager sendConfigurationSyncMessage];
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
        [self.identityManager throws_processIncomingSyncMessage:syncMessage.verified transaction:transaction];
    } else if (syncMessage.contacts != nil) {
        if (wasSentByMasterDevice && syncMessage.contacts.data.length > 0) {
            NSLog(@"[Loki] Received contact sync message.");
            NSData *data = syncMessage.contacts.data;
            ContactParser *parser = [[ContactParser alloc] initWithData:data];
            NSArray<NSString *> *hexEncodedPublicKeys = [parser parseHexEncodedPublicKeys];
            // Try to establish sessions
            for (NSString *hexEncodedPublicKey in hexEncodedPublicKeys) {
                TSContactThread *thread = [TSContactThread getOrCreateThreadWithContactId:hexEncodedPublicKey transaction:transaction];
                LKThreadFriendRequestStatus friendRequestStatus = thread.friendRequestStatus;
                switch (friendRequestStatus) {
                    case LKThreadFriendRequestStatusNone: {
                        OWSMessageSender *messageSender = SSKEnvironment.shared.messageSender;
                        OWSMessageSend *automatedFriendRequestMessage = [messageSender getMultiDeviceFriendRequestMessageForHexEncodedPublicKey:hexEncodedPublicKey];
                        dispatch_async(OWSDispatch.sendingQueue, ^{
                            [messageSender sendMessage:automatedFriendRequestMessage];
                        });
                        break;
                    }
                    case LKThreadFriendRequestStatusRequestReceived: {
                        [thread saveFriendRequestStatus:LKThreadFriendRequestStatusFriends withTransaction:transaction];
                        // The two lines below are equivalent to calling [ThreadUtil enqueueFriendRequestAcceptanceMessageInThread:thread]
                        LKEphemeralMessage *backgroundMessage = [[LKEphemeralMessage alloc] initInThread:thread];
                        [self.messageSenderJobQueue addMessage:backgroundMessage transaction:transaction];
                        break;
                    }
                    default: break; // Do nothing
                }
            }
        }
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

    [self resetSessionWithContact:envelope.source transaction:transaction];
}

- (void)resetSessionWithContact:(NSString *)hexEncodedPublicKey
                    transaction:(YapDatabaseReadWriteTransaction *)transaction {
    TSContactThread *thread = [TSContactThread getOrCreateThreadWithContactId:hexEncodedPublicKey transaction:transaction];

    // MJK TODO - safe to remove senderTimestamp
    [[[TSInfoMessage alloc] initWithTimestamp:NSDate.ows_millisecondTimeStamp
                                     inThread:thread
                                  messageType:TSInfoMessageTypeLokiSessionResetInProgress] saveWithTransaction:transaction];

    // Loki: Archive all our sessions
    // Ref: SignalServiceKit/Loki/Docs/SessionReset.md
    [self.primaryStorage archiveAllSessionsForContact:hexEncodedPublicKey protocolContext:transaction];
    
    // Loki: Set our session reset state
    thread.sessionResetStatus = LKSessionResetStatusRequestReceived;
    [thread saveWithTransaction:transaction];
    
    // Loki: Send an empty message to trigger the session reset code for both parties
    LKEphemeralMessage *emptyMessage = [[LKEphemeralMessage alloc] initInThread:thread];
    [self.messageSenderJobQueue addMessage:emptyMessage transaction:transaction];

    NSLog(@"[Loki] Session reset received from %@.", hexEncodedPublicKey);
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
    NSString *name = [dataMessage.profile displayName] ?: [self.contactsManager displayNameForPhoneIdentifier:envelope.source transaction:transaction];

    // MJK TODO - safe to remove senderTimestamp
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
        OWSFailDebug(@"received profile key of unexpected length: %lu, from: %@",
            (unsigned long)profileKey.length,
            envelopeAddress(envelope));
        return;
    }
    
    if (dataMessage.profile == nil) {
        OWSFailDebug(@"received profile key message without loki profile attached from: %@", envelopeAddress(envelope));
        return;
    }

    id<ProfileManagerProtocol> profileManager = SSKEnvironment.shared.profileManager;
    [profileManager setProfileKeyData:profileKey forRecipientId:recipientId avatarURL:dataMessage.profile.profilePicture];
}

- (void)handleUnlinkDeviceMessageWithEnvelope:(SSKProtoEnvelope *)envelope dataMessage:(SSKProtoDataMessage *)dataMessage transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    NSString *senderHexEncodedPublicKey = envelope.source;
    NSString *userHexEncodedPublicKey = OWSIdentityManager.sharedManager.identityKeyPair.hexEncodedPublicKey;
    NSString *masterHexEncodedPublicKey = [LKDatabaseUtilities getMasterHexEncodedPublicKeyFor:userHexEncodedPublicKey in:transaction];
    if (![masterHexEncodedPublicKey isEqual:senderHexEncodedPublicKey]) { return; }
    NSSet<LKDeviceLink *> *deviceLinks = [LKDatabaseUtilities getDeviceLinksFor:senderHexEncodedPublicKey in:transaction];
    if (![deviceLinks contains:^BOOL(LKDeviceLink *deviceLink) {
        return [deviceLink.master.hexEncodedPublicKey isEqual:senderHexEncodedPublicKey] && [deviceLink.slave.hexEncodedPublicKey isEqual:userHexEncodedPublicKey];
    }]) {
        return;
    }
    [LKFileServerAPI getDeviceLinksAssociatedWith:userHexEncodedPublicKey].thenOn(dispatch_get_main_queue(), ^(NSSet<LKDeviceLink *> *deviceLinks) {
        if ([deviceLinks contains:^BOOL(LKDeviceLink *deviceLink) {
            return [deviceLink.master.hexEncodedPublicKey isEqual:senderHexEncodedPublicKey] && [deviceLink.slave.hexEncodedPublicKey isEqual:userHexEncodedPublicKey];
        }]) {
            [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"wasUnlinked"];
            [NSNotificationCenter.defaultCenter postNotificationName:NSNotification.dataNukeRequested object:nil];
        }
    });
}

- (void)handleReceivedTextMessageWithEnvelope:(SSKProtoEnvelope *)envelope
                                  dataMessage:(SSKProtoDataMessage *)dataMessage
                              wasReceivedByUD:(BOOL)wasReceivedByUD
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

    [self handleReceivedEnvelope:envelope
                 withDataMessage:dataMessage
                 wasReceivedByUD:wasReceivedByUD
                     transaction:transaction];
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
    if (![gThread isLocalUserInGroupWithTransaction:transaction]) {
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

    if (gThread.groupModel.groupImage) {
        NSData *_Nullable data = UIImagePNGRepresentation(gThread.groupModel.groupImage);
        OWSAssertDebug(data);
        if (data) {
            DataSource *_Nullable dataSource = [DataSourceValue dataSourceWithData:data fileExtension:@"png"];
            [self.messageSenderJobQueue addMediaMessage:message
                                             dataSource:dataSource
                                            contentType:OWSMimeTypeImagePng
                                         sourceFilename:nil
                                                caption:nil
                                         albumMessageId:nil
                                  isTemporaryAttachment:YES];
        }
    } else {
        [self.messageSenderJobQueue addMessage:message transaction:transaction];
    }
}

- (TSIncomingMessage *_Nullable)handleReceivedEnvelope:(SSKProtoEnvelope *)envelope
                                       withDataMessage:(SSKProtoDataMessage *)dataMessage
                                       wasReceivedByUD:(BOOL)wasReceivedByUD
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
    NSNumber *_Nullable serverTimestamp = (envelope.hasServerTimestamp ? @(envelope.serverTimestamp) : nil);

    if (dataMessage.group.type == SSKProtoGroupContextTypeRequestInfo) {
        [self handleGroupInfoRequest:envelope dataMessage:dataMessage transaction:transaction];
        return nil;
    }

    // The envelope source is set during UD decryption.

    if ([ECKeyPair isValidHexEncodedPublicKeyWithCandidate:envelope.source] && dataMessage.publicChatInfo == nil) { // Handled in LokiPublicChatPoller for open group messages
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
        [[LKAPI getDestinationsFor:envelope.source inTransaction:transaction].ensureOn(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^() {
            dispatch_semaphore_signal(semaphore);
        }).catchOn(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(NSError *error) {
            dispatch_semaphore_signal(semaphore);
        }) retainUntilComplete];
        dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 4 * NSEC_PER_SEC));
    }

    if (groupId.length > 0) {
        NSMutableSet *newMemberIds = [NSMutableSet setWithArray:dataMessage.group.members];
        NSMutableSet *removedMemberIds = [NSMutableSet new];
        for (NSString *recipientId in newMemberIds) {
            if (![ECKeyPair isValidHexEncodedPublicKeyWithCandidate:recipientId]) {
                OWSLogVerbose(
                    @"incoming group update has invalid group member: %@", [self descriptionForEnvelope:envelope]);
                OWSFailDebug(@"incoming group update has invalid group member");
                return nil;
            }
        }
        
        NSString *hexEncodedPublicKey = ([LKDatabaseUtilities getMasterHexEncodedPublicKeyFor:envelope.source in:transaction] ?: envelope.source);

        // Group messages create the group if it doesn't already exist.
        //
        // We distinguish between the old group state (if any) and the new group state.
        TSGroupThread *_Nullable oldGroupThread = [TSGroupThread threadWithGroupId:groupId transaction:transaction];
        if (oldGroupThread) {
            // Loki: Determine removed members
            removedMemberIds = [NSMutableSet setWithArray:oldGroupThread.groupModel.groupMemberIds];
            [removedMemberIds minusSet:newMemberIds];
            [removedMemberIds removeObject:hexEncodedPublicKey];
        }

        // Only set the display name here, the logic for updating profile pictures is handled when we're setting profile key
        [self handleProfileNameUpdateIfNeeded:dataMessage recipientId:hexEncodedPublicKey transaction:transaction];

        switch (dataMessage.group.type) {
            case SSKProtoGroupContextTypeUpdate: {
                if (oldGroupThread && ![oldGroupThread.groupModel.groupAdminIds containsObject:hexEncodedPublicKey]) {
                    [LKLogger print:[NSString stringWithFormat:@"[Loki] Received a group update from a non-admin user for %@; ignoring.", [LKGroupUtilities getEncodedGroupID:groupId]]];
                    return nil;
                }
                // Ensures that the thread exists but doesn't update it.
                TSGroupThread *newGroupThread =
                [TSGroupThread getOrCreateThreadWithGroupId:groupId groupType:oldGroupThread.groupModel.groupType transaction:transaction];

                TSGroupModel *newGroupModel = [[TSGroupModel alloc] initWithTitle:dataMessage.group.name
                                                                        memberIds:newMemberIds.allObjects
                                                                            image:oldGroupThread.groupModel.groupImage
                                                                          groupId:dataMessage.group.id
                                                                        groupType:oldGroupThread.groupModel.groupType
                                                                         adminIds:dataMessage.group.admins];
                newGroupModel.removedMembers = removedMemberIds;
                NSString *updateGroupInfo = [newGroupThread.groupModel getInfoStringAboutUpdateTo:newGroupModel
                                                                                  contactsManager:self.contactsManager];
                newGroupThread.groupModel = newGroupModel;
                [newGroupThread saveWithTransaction:transaction];
                
                // Loki: Try to establish sessions with all members when a group is created or updated
                [self establishSessionsWithMembersIfNeeded: newMemberIds.allObjects forThread:newGroupThread transaction:transaction];

                [[OWSDisappearingMessagesJob sharedJob] becomeConsistentWithDisappearingDuration:dataMessage.expireTimer
                                                                                          thread:newGroupThread
                                                                      createdByRemoteRecipientId:nil
                                                                          createdInExistingGroup:YES
                                                                                     transaction:transaction];

                // MJK TODO - should be safe to remove senderTimestamp
                TSInfoMessage *infoMessage = [[TSInfoMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                                             inThread:newGroupThread
                                                                          messageType:TSInfoMessageTypeGroupUpdate
                                                                        customMessage:updateGroupInfo];
                [infoMessage saveWithTransaction:transaction];

                return nil;
            }
            case SSKProtoGroupContextTypeQuit: {
                if (!oldGroupThread) {
                    OWSLogWarn(@"ignoring quit group message from unknown group.");
                    return nil;
                }
                newMemberIds = [NSMutableSet setWithArray:oldGroupThread.groupModel.groupMemberIds];
                [newMemberIds removeObject:hexEncodedPublicKey];
                oldGroupThread.groupModel.groupMemberIds = [newMemberIds.allObjects mutableCopy];
                [oldGroupThread saveWithTransaction:transaction];

                NSString *nameString =
                    [self.contactsManager displayNameForPhoneIdentifier:hexEncodedPublicKey transaction:transaction];
                NSString *updateGroupInfo =
                    [NSString stringWithFormat:NSLocalizedString(@"GROUP_MEMBER_LEFT", @""), nameString];
                // MJK TODO - should be safe to remove senderTimestamp
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

                [[OWSDisappearingMessagesJob sharedJob] becomeConsistentWithDisappearingDuration:dataMessage.expireTimer
                                                                                          thread:oldGroupThread
                                                                      createdByRemoteRecipientId:hexEncodedPublicKey
                                                                          createdInExistingGroup:NO
                                                                                     transaction:transaction];

                TSQuotedMessage *_Nullable quotedMessage = [TSQuotedMessage quotedMessageForDataMessage:dataMessage
                                                                                                 thread:oldGroupThread
                                                                                            transaction:transaction];

                NSError *linkPreviewError;
                OWSLinkPreview *_Nullable linkPreview =
                    [OWSLinkPreview buildValidatedLinkPreviewWithDataMessage:dataMessage
                                                                        body:body
                                                                 transaction:transaction
                                                                       error:&linkPreviewError];
                if (linkPreviewError && ![OWSLinkPreview isNoPreviewError:linkPreviewError]) {
                    OWSLogError(@"linkPreviewError: %@", linkPreviewError);
                }

                OWSLogDebug(@"incoming message from: %@ for group: %@ with timestamp: %lu",
                    envelopeAddress(envelope),
                    groupId,
                    (unsigned long)timestamp);
                
                // Legit usage of senderTimestamp when creating an incoming group message record
                TSIncomingMessage *incomingMessage =
                    [[TSIncomingMessage alloc] initIncomingMessageWithTimestamp:timestamp
                                                                       inThread:oldGroupThread
                                                                       authorId:hexEncodedPublicKey
                                                                 sourceDeviceId:envelope.sourceDevice
                                                                    messageBody:body
                                                                  attachmentIds:@[]
                                                               expiresInSeconds:dataMessage.expireTimer
                                                                  quotedMessage:quotedMessage
                                                                   contactShare:contact
                                                                    linkPreview:linkPreview
                                                                serverTimestamp:serverTimestamp
                                                                wasReceivedByUD:wasReceivedByUD];
                
                // Loki: Parse Loki specific properties if needed
                if (envelope.isPtpMessage) { incomingMessage.isP2P = YES; }
                if (dataMessage.publicChatInfo != nil && dataMessage.publicChatInfo.hasServerID) { incomingMessage.groupChatServerID = dataMessage.publicChatInfo.serverID; }

                NSArray<TSAttachmentPointer *> *attachmentPointers =
                    [TSAttachmentPointer attachmentPointersFromProtos:dataMessage.attachments
                                                         albumMessage:incomingMessage];
                for (TSAttachmentPointer *pointer in attachmentPointers) {
                    [pointer saveWithTransaction:transaction];
                    [incomingMessage.attachmentIds addObject:pointer.uniqueId];
                }
                
                // Loki: Don't process friend requests in group chats
                if (body.length == 0 && attachmentPointers.count < 1 && !contact) {
                    OWSLogWarn(@"Ignoring empty incoming message from: %@ for group: %@ with timestamp: %lu.",
                        hexEncodedPublicKey,
                        groupId,
                        (unsigned long)timestamp);
                    return nil;
                }
                
                // Loki: Cache the user hex encoded public key (for mentions)
                dispatch_async(dispatch_get_main_queue(), ^{
                    [OWSPrimaryStorage.sharedManager.dbReadConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
                        [LKAPI populateUserHexEncodedPublicKeyCacheIfNeededFor:oldGroupThread.uniqueId in:transaction];
                        [LKAPI cache:incomingMessage.authorId for:oldGroupThread.uniqueId];
                    }];
                });
                
                [self finalizeIncomingMessage:incomingMessage
                                       thread:oldGroupThread
                                 masterThread:oldGroupThread
                                     envelope:envelope
                                  transaction:transaction];
                
                // Loki: Map the message ID to the message server ID if needed
                if (dataMessage.publicChatInfo != nil && dataMessage.publicChatInfo.hasServerID) {
                    [self.primaryStorage setIDForMessageWithServerID:dataMessage.publicChatInfo.serverID to:incomingMessage.uniqueId in:transaction];
                }

                return incomingMessage;
            }
            default: {
                OWSLogWarn(@"Ignoring unknown group message type: %d.", (int)dataMessage.group.type);
                return nil;
            }
        }
    } else {
        
        // Loki: A message from a slave device should appear as if it came from the master device; the underlying
        // friend request logic, however, should still be specific to the slave device.
        
        // Loki: Get the master hex encoded public key and thread
        NSString *hexEncodedPublicKey = envelope.source;
        NSString *masterHexEncodedPublicKey = ([LKDatabaseUtilities getMasterHexEncodedPublicKeyFor:envelope.source in:transaction] ?: envelope.source);
        TSContactThread *thread = [TSContactThread getOrCreateThreadWithContactId:hexEncodedPublicKey transaction:transaction];
        TSContactThread *masterThread = [TSContactThread getOrCreateThreadWithContactId:masterHexEncodedPublicKey transaction:transaction];

        OWSLogDebug(@"Incoming message from: %@ with timestamp: %lu.", hexEncodedPublicKey, (unsigned long)timestamp);
        
        [[OWSDisappearingMessagesJob sharedJob] becomeConsistentWithDisappearingDuration:dataMessage.expireTimer
                                                                                  thread:masterThread
                                                              createdByRemoteRecipientId:hexEncodedPublicKey
                                                                  createdInExistingGroup:NO
                                                                             transaction:transaction];

        TSQuotedMessage *_Nullable quotedMessage = [TSQuotedMessage quotedMessageForDataMessage:dataMessage
                                                                                         thread:masterThread
                                                                                    transaction:transaction];

        NSError *linkPreviewError;
        OWSLinkPreview *_Nullable linkPreview =
            [OWSLinkPreview buildValidatedLinkPreviewWithDataMessage:dataMessage
                                                                body:body
                                                         transaction:transaction
                                                               error:&linkPreviewError];
        if (linkPreviewError && ![OWSLinkPreview isNoPreviewError:linkPreviewError]) {
            OWSLogError(@"linkPreviewError: %@", linkPreviewError);
        }

        // Legit usage of senderTimestamp when creating incoming message from received envelope
        TSIncomingMessage *incomingMessage =
            [[TSIncomingMessage alloc] initIncomingMessageWithTimestamp:timestamp
                                                               inThread:masterThread
                                                               authorId:masterThread.contactIdentifier
                                                         sourceDeviceId:envelope.sourceDevice
                                                            messageBody:body
                                                          attachmentIds:@[]
                                                       expiresInSeconds:dataMessage.expireTimer
                                                          quotedMessage:quotedMessage
                                                           contactShare:contact
                                                            linkPreview:linkPreview
                                                        serverTimestamp:serverTimestamp
                                                        wasReceivedByUD:wasReceivedByUD];
        
        NSString *rawDisplayName = dataMessage.profile.displayName;
        NSString *displayName = nil;
        if (rawDisplayName != nil && rawDisplayName.length > 0) {
            displayName = [NSString stringWithFormat:@"%@ (...%@)", rawDisplayName, [incomingMessage.authorId substringFromIndex:incomingMessage.authorId.length - 8]];
        }
        [self.profileManager updateProfileForContactWithID:thread.contactIdentifier displayName:displayName with:transaction];
        [self handleProfileKeyUpdateIfNeeded:dataMessage recipientId:thread.contactIdentifier];

        // Loki: Parse Loki specific properties if needed
        if (envelope.isPtpMessage) { incomingMessage.isP2P = YES; }
        
        NSArray<TSAttachmentPointer *> *attachmentPointers =
            [TSAttachmentPointer attachmentPointersFromProtos:dataMessage.attachments albumMessage:incomingMessage];
        for (TSAttachmentPointer *pointer in attachmentPointers) {
            [pointer saveWithTransaction:transaction];
            [incomingMessage.attachmentIds addObject:pointer.uniqueId];
        }

        // Loki: Do this before the check below
        [self handleFriendRequestMessageIfNeededWithEnvelope:envelope data:dataMessage message:incomingMessage thread:thread transaction:transaction];
        
        if (body.length == 0 && attachmentPointers.count < 1 && !contact) {
            OWSLogWarn(@"Ignoring empty incoming message from: %@ with timestamp: %lu.",
                hexEncodedPublicKey,
                (unsigned long)timestamp);
            return nil;
        }
        
        // Loki: If we received a message from a contact in the last 2 minutes that wasn't P2P, then we need to ping them.
        // We assume this occurred because they don't have our P2P details.
        if (!envelope.isPtpMessage && hexEncodedPublicKey != nil) {
            uint64_t timestamp = envelope.timestamp;
            uint64_t now = NSDate.ows_millisecondTimeStamp;
            uint64_t ageInSeconds = (now - timestamp) / 1000;
            if (ageInSeconds <= 120) { [LKP2PAPI pingContact:hexEncodedPublicKey]; }
        }

        [self finalizeIncomingMessage:incomingMessage
                               thread:thread
                         masterThread:thread
                             envelope:envelope
                          transaction:transaction];
        
        return incomingMessage;
    }
}

- (void)handleProfileNameUpdateIfNeeded:(SSKProtoDataMessage *)dataMessage recipientId:(NSString *)recipientId transaction:(YapDatabaseReadWriteTransaction *)transaction {
    if (dataMessage != nil && dataMessage.profile != nil) {
        [self.profileManager updateProfileForContactWithID:recipientId displayName:dataMessage.profile.displayName with:transaction];
    }
}

- (void)handleProfileKeyUpdateIfNeeded:(SSKProtoDataMessage *)dataMessage recipientId:(NSString *)recipientId {
    if (dataMessage != nil && [dataMessage hasProfileKey]) {
        NSData *profileKey = [dataMessage profileKey];
        NSString *url = dataMessage.profile != nil ? dataMessage.profile.profilePicture : nil;
        if (profileKey.length == kAES256_KeyByteLength) {
            [self.profileManager setProfileKeyData:profileKey forRecipientId:recipientId avatarURL:url];
        } else {
            OWSFailDebug(@"Unexpected profile key length:%lu on message from:%@", (unsigned long)profileKey.length, recipientId);
        }
    }
}

- (void)establishSessionsWithMembersIfNeeded:(NSArray *)members forThread:(TSGroupThread *)thread transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    NSString *userHexEncodedPublicKey = OWSIdentityManager.sharedManager.identityKeyPair.hexEncodedPublicKey;
    for (NSString *member in members) {
        if ([member isEqualToString:userHexEncodedPublicKey] ) { continue; }
        BOOL hasSession = [self.primaryStorage containsSession:member deviceId:1 protocolContext:transaction];
        if (hasSession) { continue; }
        TSContactThread *contactThread = [TSContactThread getOrCreateThreadWithContactId:member transaction:transaction];
        LKSessionRequestMessage *message = [[LKSessionRequestMessage alloc] initWithThread:contactThread];
        [self.messageSenderJobQueue addMessage:message transaction:transaction];
    }
}

- (BOOL)canFriendRequestBeAutoAcceptedForThread:(TSContactThread *)thread transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    NSString *senderHexEncodedPublicKey = thread.contactIdentifier;
    if (thread.hasCurrentUserSentFriendRequest) {
        // This can happen if Alice sent Bob a friend request, Bob declined, but then Bob changed his
        // mind and sent a friend request to Alice. In this case we want Alice to auto-accept the request
        // and send a friend request accepted message back to Bob. We don't check that sending the
        // friend request accepted message succeeded. Even if it doesn't, the thread's current friend
        // request status will be set to LKThreadFriendRequestStatusFriends for Alice making it possible
        // for Alice to send messages to Bob. When Bob receives a message, his thread's friend request status
        // will then be set to LKThreadFriendRequestStatusFriends. If we do check for a successful send
        // before updating Alice's thread's friend request status to LKThreadFriendRequestStatusFriends,
        // we can end up in a deadlock where both users' threads' friend request statuses are
        // LKThreadFriendRequestStatusRequestSent.
        return YES;
    }
    NSString *userHexEncodedPublicKey = OWSIdentityManager.sharedManager.identityKeyPair.hexEncodedPublicKey;
    NSSet<NSString *> *userLinkedDeviceHexEncodedPublicKeys = [LKDatabaseUtilities getLinkedDeviceHexEncodedPublicKeysFor:userHexEncodedPublicKey in:transaction];
    if ([userLinkedDeviceHexEncodedPublicKeys containsObject:senderHexEncodedPublicKey]) {
        // Auto-accept any friend requests from the user's own linked devices
        return YES;
    }
    NSSet<TSContactThread *> *senderLinkedDeviceThreads = [LKDatabaseUtilities getLinkedDeviceThreadsFor:senderHexEncodedPublicKey in:transaction];
    if ([senderLinkedDeviceThreads contains:^BOOL(TSContactThread *thread) {
        return thread.isContactFriend;
    }]) {
        // Auto-accept if the user is friends with any of the sender's linked devices.
        return YES;
    }
    return NO;
}

- (void)handleFriendRequestMessageIfNeededWithEnvelope:(SSKProtoEnvelope *)envelope data:(SSKProtoDataMessage *)data message:(TSIncomingMessage *)message thread:(TSContactThread *)thread transaction:(YapDatabaseReadWriteTransaction *)transaction {
    if (envelope.isGroupChatMessage) {
        return NSLog(@"[Loki] Ignoring friend request in group chat.", @"");
    }
    // The envelope type is set during UD decryption.
    if (envelope.type != SSKProtoEnvelopeTypeFriendRequest) {
        return NSLog(@"[Loki] Ignoring friend request logic for non friend request type envelope.");
    }
    if ([self canFriendRequestBeAutoAcceptedForThread:thread transaction:transaction]) {
        [thread saveFriendRequestStatus:LKThreadFriendRequestStatusFriends withTransaction:transaction];
        __block TSOutgoingMessage *existingFriendRequestMessage;
        [thread enumerateInteractionsWithTransaction:transaction usingBlock:^(TSInteraction *interaction, YapDatabaseReadTransaction *transaction) {
            if ([interaction isKindOfClass:TSOutgoingMessage.class] && ((TSOutgoingMessage *)interaction).isFriendRequest) {
                existingFriendRequestMessage = (TSOutgoingMessage *)interaction;
            }
        }];
        if (existingFriendRequestMessage != nil) {
            [existingFriendRequestMessage saveFriendRequestStatus:LKMessageFriendRequestStatusAccepted withTransaction:transaction];
        }
        // The two lines below are equivalent to calling [ThreadUtil enqueueFriendRequestAcceptanceMessageInThread:thread]
        LKEphemeralMessage *backgroundMessage = [[LKEphemeralMessage alloc] initInThread:thread];
        [self.messageSenderJobQueue addMessage:backgroundMessage transaction:transaction];
    } else if (!thread.isContactFriend) {
        // Checking that the sender of the message isn't already a friend is necessary because otherwise
        // the following situation can occur: Alice and Bob are friends. Bob loses his database and his
        // friend request status is reset to LKThreadFriendRequestStatusNone. Bob now sends Alice a friend
        // request. Alice's thread's friend request status is reset to
        // LKThreadFriendRequestStatusRequestReceived.
        [thread saveFriendRequestStatus:LKThreadFriendRequestStatusRequestReceived withTransaction:transaction];
        // Except for the message.friendRequestStatus = LKMessageFriendRequestStatusPending line below, all of this is to ensure that
        // there's only ever one message with status LKMessageFriendRequestStatusPending in a thread (where a thread is the combination
        // of all threads belonging to the linked devices of a user).
        NSString *senderID = ((TSIncomingMessage *)message).authorId;
        NSSet<TSContactThread *> *linkedDeviceThreads = [LKDatabaseUtilities getLinkedDeviceThreadsFor:senderID in:transaction];
        for (TSContactThread *thread in linkedDeviceThreads) {
            [thread enumerateInteractionsWithTransaction:transaction usingBlock:^(TSInteraction *interaction, YapDatabaseReadTransaction *transaction) {
                if (![interaction isKindOfClass:TSIncomingMessage.class]) { return; }
                TSIncomingMessage *message = (TSIncomingMessage *)interaction;
                if (message.friendRequestStatus != LKMessageFriendRequestStatusNone) {
                    [message saveFriendRequestStatus:LKMessageFriendRequestStatusNone withTransaction:transaction];
                }
            }];
        }
        message.friendRequestStatus = LKMessageFriendRequestStatusPending; // Don't save yet. This is done in finalizeIncomingMessage:thread:masterThread:envelope:transaction.
    }
}

- (void)handleFriendRequestAcceptanceIfNeededWithEnvelope:(SSKProtoEnvelope *)envelope transaction:(YapDatabaseReadWriteTransaction *)transaction {
    // If we get an envelope that isn't a friend request, then we can infer that we had to use
    // Signal cipher decryption and thus that we have a session with the other person.
    // The envelope type is set during UD decryption.
    if (envelope.isGroupChatMessage || envelope.type == SSKProtoEnvelopeTypeFriendRequest) return;
    // Currently this uses `envelope.source` but with sync messages we'll need to use the message sender ID
    TSContactThread *thread = [TSContactThread getOrCreateThreadWithContactId:envelope.source transaction:transaction];
    // We shouldn't be able to skip from none to friends under normal circumstances
    if (thread.friendRequestStatus == LKThreadFriendRequestStatusNone) { return; }
    // Become happy friends and go on great adventures
    [thread saveFriendRequestStatus:LKThreadFriendRequestStatusFriends withTransaction:transaction];
    TSOutgoingMessage *existingFriendRequestMessage = [[thread getLastInteractionWithTransaction:transaction] as:TSOutgoingMessage.class];
    if (existingFriendRequestMessage != nil && existingFriendRequestMessage.isFriendRequest) {
        [existingFriendRequestMessage saveFriendRequestStatus:LKMessageFriendRequestStatusAccepted withTransaction:transaction];
    }
    // Send our P2P details
    LKAddressMessage *_Nullable onlineMessage = [LKP2PAPI onlineBroadcastMessageForThread:thread];
    if (onlineMessage != nil) {
        [self.messageSenderJobQueue addMessage:onlineMessage transaction:transaction];
    }
}

- (void)finalizeIncomingMessage:(TSIncomingMessage *)incomingMessage
                         thread:(TSThread *)thread
                   masterThread:(TSThread *)masterThread
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
    
    // Loki: Remove any old incoming messages
    if (incomingMessage.isFriendRequest) {
        [thread removeOldIncomingFriendRequestMessagesIfNeededWithTransaction:transaction];
    }

    // Any messages sent from the current user - from this device or another - should be automatically marked as read.
    if ([(masterThread.contactIdentifier ?: envelope.source) isEqualToString:self.tsAccountManager.localNumber]) {
        // Don't send a read receipt for messages sent by ourselves.
        [incomingMessage markAsReadAtTimestamp:envelope.timestamp sendReadReceipt:NO transaction:transaction];
    }

    // Download the "non-message body" attachments.
    NSMutableArray<NSString *> *otherAttachmentIds = [incomingMessage.allAttachmentIds mutableCopy];
    if (incomingMessage.attachmentIds) {
        [otherAttachmentIds removeObjectsInArray:incomingMessage.attachmentIds];
    }
    for (NSString *attachmentId in otherAttachmentIds) {
        TSAttachment *_Nullable attachment =
            [TSAttachment fetchObjectWithUniqueID:attachmentId transaction:transaction];
        if (![attachment isKindOfClass:[TSAttachmentPointer class]]) {
            OWSLogInfo(@"Skipping attachment stream.");
            continue;
        }
        TSAttachmentPointer *_Nullable attachmentPointer = (TSAttachmentPointer *)attachment;

        OWSLogDebug(@"Downloading attachment for message: %lu", (unsigned long)incomingMessage.timestamp);

        // Use a separate download for each attachment so that:
        //
        // * We update the message as each comes in.
        // * Failures don't interfere with successes.
        [self.attachmentDownloads downloadAttachmentPointer:attachmentPointer
            success:^(NSArray<TSAttachmentStream *> *attachmentStreams) {
                [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                    TSAttachmentStream *_Nullable attachmentStream = attachmentStreams.firstObject;
                    OWSAssertDebug(attachmentStream);
                    if (attachmentStream && incomingMessage.quotedMessage.thumbnailAttachmentPointerId.length > 0 &&
                        [attachmentStream.uniqueId
                            isEqualToString:incomingMessage.quotedMessage.thumbnailAttachmentPointerId]) {
                        [incomingMessage setQuotedMessageThumbnailAttachmentStream:attachmentStream];
                        [incomingMessage saveWithTransaction:transaction];
                    } else {
                        // We touch the message to trigger redraw of any views displaying it,
                        // since the attachment might be a contact avatar, etc.
                        [incomingMessage touchWithTransaction:transaction];
                    }
                }];
            }
            failure:^(NSError *error) {
                OWSLogWarn(@"Failed to download attachment for message: %lu with error: %@.",
                    (unsigned long)incomingMessage.timestamp,
                    error);
            }];
    }

    // In case we already have a read receipt for this new message (this happens sometimes).
    [OWSReadReceiptManager.sharedManager applyEarlyReadReceiptsForIncomingMessage:incomingMessage
                                                                      transaction:transaction];

    // Update thread preview in inbox
    [masterThread touchWithTransaction:transaction];

    [SSKEnvironment.shared.notificationsManager notifyUserForIncomingMessage:incomingMessage
                                                                    inThread:masterThread
                                                                 transaction:transaction];

    dispatch_async(dispatch_get_main_queue(), ^{
        [self.typingIndicators didReceiveIncomingMessageInThread:masterThread
                                                     recipientId:(masterThread.contactIdentifier ?: envelope.source)
                                                        deviceId:envelope.sourceDevice];
    });
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

#pragma mark -

- (void)checkForUnknownLinkedDevice:(SSKProtoEnvelope *)envelope
                        transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssertDebug(envelope);
    OWSAssertDebug(transaction);

    NSString *localNumber = self.tsAccountManager.localNumber;
    if (![localNumber isEqualToString:envelope.source]) {
        return;
    }

    // Consult the device list cache we use for message sending
    // whether or not we know about this linked device.
    SignalRecipient *_Nullable recipient =
        [SignalRecipient registeredRecipientForRecipientId:localNumber mustHaveDevices:NO transaction:transaction];
    if (!recipient) {
//        OWSFailDebug(@"No local SignalRecipient.");
    } else {
        BOOL isRecipientDevice = [recipient.devices containsObject:@(envelope.sourceDevice)];
        if (!isRecipientDevice) {
            OWSLogInfo(@"Message received from unknown linked device; adding to local SignalRecipient: %lu.",
                       (unsigned long) envelope.sourceDevice);

            [recipient updateRegisteredRecipientWithDevicesToAdd:@[ @(envelope.sourceDevice) ]
                                                 devicesToRemove:nil
                                                     transaction:transaction];
        }
    }

    // Consult the device list cache we use for the "linked device" UI
    // whether or not we know about this linked device.
    NSMutableSet<NSNumber *> *deviceIdSet = [NSMutableSet new];
    for (OWSDevice *device in [OWSDevice currentDevicesWithTransaction:transaction]) {
        [deviceIdSet addObject:@(device.deviceId)];
    }
    BOOL isInDeviceList = [deviceIdSet containsObject:@(envelope.sourceDevice)];
    if (!isInDeviceList) {
        OWSLogInfo(@"Message received from unknown linked device; refreshing device list: %lu.",
                   (unsigned long) envelope.sourceDevice);

        [OWSDevicesService refreshDevices];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.profileManager fetchLocalUsersProfile];
        });
    }
}

@end

NS_ASSUME_NONNULL_END
