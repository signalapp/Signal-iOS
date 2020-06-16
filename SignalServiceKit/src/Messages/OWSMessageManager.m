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
#import <SessionCoreKit/Cryptography.h>
#import <SessionCoreKit/NSDate+OWS.h>
#import <SessionMetadataKit/SessionMetadataKit-Swift.h>
#import <SessionServiceKit/NSObject+Casting.h>
#import <SessionServiceKit/SignalRecipient.h>
#import <SessionServiceKit/SessionServiceKit-Swift.h>
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

    OWSLogInfo(@"Handling decrypted envelope: %@.", [self descriptionForEnvelope:envelope]);

    if (!envelope.hasSource || envelope.source.length < 1) {
        OWSFailDebug(@"Incoming envelope with invalid source.");
        return;
    }
    if (!envelope.hasSourceDevice || envelope.sourceDevice < 1) {
        OWSFailDebug(@"Incoming envelope with invalid source device.");
        return;
    }

    OWSAssertDebug(![self isEnvelopeSenderBlocked:envelope]);
    
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

    OWSPrimaryStorage *storage = OWSPrimaryStorage.sharedManager;
    __block NSSet<NSString *> *linkedDeviceHexEncodedPublicKeys;
    [storage.dbReadConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        linkedDeviceHexEncodedPublicKeys = [LKDatabaseUtilities getLinkedDeviceHexEncodedPublicKeysFor:envelope.source in:transaction];
    }];

    BOOL duplicateEnvelope = NO;
    for (NSString *hexEncodedPublicKey in linkedDeviceHexEncodedPublicKeys) {
        duplicateEnvelope = duplicateEnvelope
            || [self.incomingMessageFinder existsMessageWithTimestamp:envelope.timestamp
                                                             sourceId:hexEncodedPublicKey
                                                       sourceDeviceId:envelope.sourceDevice
                                                          transaction:transaction];
    }

    if (duplicateEnvelope) {
        OWSLogInfo(@"Ignoring previously received envelope from: %@ with timestamp: %llu.",
            envelopeAddress(envelope),
            envelope.timestamp);
        return;
    }

    // Loki: Ignore any friend requests from before restoration
    if ([LKFriendRequestProtocol isFriendRequestFromBeforeRestoration:envelope]) {
        [LKLogger print:@"[Loki] Ignoring friend request from before restoration."];
        return;
    }
    
    if (envelope.content != nil) {
        NSError *error;
        SSKProtoContent *_Nullable contentProto = [SSKProtoContent parseData:plaintextData error:&error];
        if (error || !contentProto) {
            OWSFailDebug(@"Could not parse proto due to error: %@.", error);
            return;
        }
        OWSLogInfo(@"Handling content: <Content: %@>.", [self descriptionForContent:contentProto]);
        
        // Loki: Ignore any duplicate sync transcripts
        if ([LKSyncMessagesProtocol isDuplicateSyncMessage:contentProto fromHexEncodedPublicKey:envelope.source]) { return; }

        // Loki: Handle pre key bundle message if needed
        [LKSessionManagementProtocol handlePreKeyBundleMessageIfNeeded:contentProto wrappedIn:envelope using:transaction];

        // Loki: Handle session request if needed
        if ([LKSessionManagementProtocol isSessionRequestMessage:contentProto.dataMessage]) {
            [LKSessionManagementProtocol handleSessionRequestMessage:contentProto.dataMessage wrappedIn:envelope using:transaction];
            return; // Don't process the message any further
        }

        // Loki: Handle session restoration request if needed
        if ([LKSessionManagementProtocol isSessionRestoreMessage:contentProto.dataMessage]) { return; } // Don't process the message any further

        // Loki: Handle friend request acceptance if needed
        [LKFriendRequestProtocol handleFriendRequestAcceptanceIfNeeded:envelope in:transaction];

        // Loki: Handle device linking message if needed
        if (contentProto.lokiDeviceLinkMessage != nil) {
            [LKMultiDeviceProtocol handleDeviceLinkMessageIfNeeded:contentProto wrappedIn:envelope using:transaction];
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

    if (dataMessage.group) {
        TSGroupThread *_Nullable groupThread =
            [TSGroupThread threadWithGroupId:dataMessage.group.id transaction:transaction];

        if (groupThread) {
            // Loki: Ignore closed group message if needed
            if ([LKClosedGroupsProtocol shouldIgnoreClosedGroupMessage:dataMessage inThread:groupThread wrappedIn:envelope using:transaction]) { return; }

            if (dataMessage.group.type != SSKProtoGroupContextTypeUpdate) {
                if (![groupThread isCurrentUserInGroupWithTransaction:transaction]) {
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
    } else if ([LKMultiDeviceProtocol isUnlinkDeviceMessage:dataMessage]) {
        [LKMultiDeviceProtocol handleUnlinkDeviceMessage:dataMessage wrappedIn:envelope using:transaction];
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

        if (![groupThread isCurrentUserInGroupWithTransaction:transaction]) {
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

    // Loki: Take into account multi device when checking sync message validity
    if (![LKSyncMessagesProtocol isValidSyncMessage:envelope in:transaction]) {
        OWSProdErrorWEnvelope([OWSAnalyticsEvents messageManagerErrorSyncMessageFromUnknownSource], envelope);
        return;
    }

    if (syncMessage.sent) {
        OWSIncomingSentMessageTranscript *transcript =
            [[OWSIncomingSentMessageTranscript alloc] initWithProto:syncMessage.sent transaction:transaction];
        
        SSKProtoDataMessage *_Nullable dataMessage = syncMessage.sent.message;
        if (!dataMessage) {
            OWSFailDebug(@"Missing dataMessage.");
            return;
        }

        // Loki: Update profile if needed (i.e. if the sync message came from the master device)
        [LKSyncMessagesProtocol updateProfileFromSyncMessageIfNeeded:dataMessage wrappedIn:envelope using:transaction];
        
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
                                       [LKStorage writeSyncWithBlock:^(
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
                                       } error:nil];
                                   }
                                         transaction:transaction
             ];
        } else {
            if (transcript.isGroupUpdate) {
                // Loki: Handle closed group updated sync message
                [LKSyncMessagesProtocol handleClosedGroupUpdatedSyncMessageIfNeeded:transcript using:transaction];
            } else if (transcript.isGroupQuit) {
                // Loki: Handle closed group quit sync message
                [LKSyncMessagesProtocol handleClosedGroupQuitSyncMessageIfNeeded:transcript using:transaction];
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
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                [[self.syncManager syncAllGroups] retainUntilComplete];
            });
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
        // Loki: Handle contact sync message
        [LKSyncMessagesProtocol handleContactSyncMessageIfNeeded:syncMessage wrappedIn:envelope using:transaction];
    } else if (syncMessage.groups != nil) {
        // Loki: Handle closed groups sync message
        [LKSyncMessagesProtocol handleClosedGroupSyncMessageIfNeeded:syncMessage wrappedIn:envelope using:transaction];
    } else if (syncMessage.openGroups != nil) {
        // Loki: Handle open groups sync message
        [LKSyncMessagesProtocol handleOpenGroupSyncMessageIfNeeded:syncMessage wrappedIn:envelope using:transaction];
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

    // Loki: Handle session reset
    NSString *hexEncodedPublicKey = envelope.source;
    TSContactThread *thread = [TSContactThread getOrCreateThreadWithContactId:hexEncodedPublicKey transaction:transaction];
    [LKSessionManagementProtocol handleEndSessionMessageReceivedInThread:thread using:transaction];
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
        OWSFailDebug(@"Received a profile key message without a profile key from: %@.", envelopeAddress(envelope));
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
    if (![gThread isUserInGroup:envelope.source transaction:transaction]) {
        OWSLogWarn(@"Ignoring 'Request Group Info' message for non-member of group. %@ not in %@",
            envelope.source,
            gThread.groupModel.groupMemberIds);
        return;
    }

    // Ensure we are in the group.
    if (![gThread isCurrentUserInGroupWithTransaction:transaction]) {
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

    // Loki: Update device links in a blocking way
    // FIXME: This is horrible for performance
    // FIXME: ========
    // The envelope source is set during UD decryption
    if ([ECKeyPair isValidHexEncodedPublicKeyWithCandidate:envelope.source] && dataMessage.publicChatInfo == nil) { // Handled in LokiPublicChatPoller for open group messages
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
        dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
        [[LKMultiDeviceProtocol updateDeviceLinksIfNeededForHexEncodedPublicKey:envelope.source in:transaction].ensureOn(queue, ^() {
            dispatch_semaphore_signal(semaphore);
        }).catchOn(queue, ^(NSError *error) {
            dispatch_semaphore_signal(semaphore);
        }) retainUntilComplete];
        dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
    }
    // FIXME: ========

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

        NSString *senderMasterHexEncodedPublicKey = ([LKDatabaseUtilities getMasterHexEncodedPublicKeyFor:envelope.source in:transaction] ?: envelope.source);
        NSString *userHexEncodedPublicKey = OWSIdentityManager.sharedManager.identityKeyPair.hexEncodedPublicKey;
        NSString *userMasterHexEncodedPublicKey = ([LKDatabaseUtilities getMasterHexEncodedPublicKeyFor:userHexEncodedPublicKey in:transaction] ?: userHexEncodedPublicKey);

        // Group messages create the group if it doesn't already exist.
        //
        // We distinguish between the old group state (if any) and the new group state.
        TSGroupThread *_Nullable oldGroupThread = [TSGroupThread threadWithGroupId:groupId transaction:transaction];
        if (oldGroupThread) {
            // Loki: Determine removed members
            removedMemberIds = [NSMutableSet setWithArray:oldGroupThread.groupModel.groupMemberIds];
            [removedMemberIds minusSet:newMemberIds];
            // TODO: Below is the original code. Is it safe that we modified it like this?
            // ========
            // Don't trust other clients; ensure all known group members remain in the
            // group unless it is a "quit" message in which case we should only remove
            // the quiting member below.
//            [newMemberIds addObjectsFromArray:oldGroupThread.groupModel.groupMemberIds];
            // ========
        }

        // Loki: Handle profile key update if needed
        [LKSessionMetaProtocol updateProfileKeyIfNeededForHexEncodedPublicKey:senderMasterHexEncodedPublicKey using:dataMessage];

        // Loki: Handle display name update if needed
        [LKSessionMetaProtocol updateDisplayNameIfNeededForHexEncodedPublicKey:senderMasterHexEncodedPublicKey using:dataMessage appendingShortID:NO in:transaction];

        switch (dataMessage.group.type) {
            case SSKProtoGroupContextTypeUpdate: {
                // Loki: Ignore updates from non-admins
                if ([LKClosedGroupsProtocol shouldIgnoreClosedGroupUpdateMessage:envelope in:oldGroupThread using:transaction]) {
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

                [newGroupThread setGroupModel:newGroupModel withTransaction:transaction];

                BOOL wasCurrentUserRemovedFromGroup = [removedMemberIds containsObject:userMasterHexEncodedPublicKey];
                if (!wasCurrentUserRemovedFromGroup) {
                    // Loki: Try to establish sessions with all members when a group is created or updated
                    [LKClosedGroupsProtocol establishSessionsIfNeededWithClosedGroupMembers:newMemberIds.allObjects in:newGroupThread using:transaction];
                }

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

                // If we were the one that was removed then we need to leave the group
                if (wasCurrentUserRemovedFromGroup) {
                    [newGroupThread leaveGroupWithTransaction:transaction];
                }

                return nil;
            }
            case SSKProtoGroupContextTypeQuit: {
                if (!oldGroupThread) {
                    OWSLogWarn(@"Ignoring quit group message from unknown group.");
                    return nil;
                }
                newMemberIds = [NSMutableSet setWithArray:oldGroupThread.groupModel.groupMemberIds];
                [newMemberIds removeObject:senderMasterHexEncodedPublicKey];
                oldGroupThread.groupModel.groupMemberIds = [newMemberIds.allObjects mutableCopy];
                [oldGroupThread saveWithTransaction:transaction];

                NSString *nameString =
                    [self.contactsManager displayNameForPhoneIdentifier:senderMasterHexEncodedPublicKey transaction:transaction];
                NSString *updateGroupInfo =
                    [NSString stringWithFormat:NSLocalizedString(@"GROUP_MEMBER_LEFT", @""), nameString];
                // MJK TODO - should be safe to remove senderTimestamp
                [[[TSInfoMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                 inThread:oldGroupThread
                                              messageType:TSInfoMessageTypeGroupUpdate
                                            customMessage:updateGroupInfo] saveWithTransaction:transaction];

                // If we were the one that quit then we need to leave the group (only relevant for slave
                // devices in a multi device context)
                // TODO: This needs more documentation
                if (![newMemberIds containsObject:userMasterHexEncodedPublicKey]) {
                    [oldGroupThread leaveGroupWithTransaction:transaction];
                }
                
                return nil;
            }
            case SSKProtoGroupContextTypeDeliver: {
                if (!oldGroupThread) {
                    OWSFailDebug(@"ignoring deliver group message from unknown group.");
                    return nil;
                }

                [[OWSDisappearingMessagesJob sharedJob] becomeConsistentWithDisappearingDuration:dataMessage.expireTimer
                                                                                          thread:oldGroupThread
                                                                      createdByRemoteRecipientId:senderMasterHexEncodedPublicKey
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
                                                                       authorId:senderMasterHexEncodedPublicKey
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
                /*
                if (envelope.isPtpMessage) { incomingMessage.isP2P = YES; }
                 */
                if (dataMessage.publicChatInfo != nil && dataMessage.publicChatInfo.hasServerID) { incomingMessage.openGroupServerMessageID = dataMessage.publicChatInfo.serverID; }

                NSArray<TSAttachmentPointer *> *attachmentPointers =
                    [TSAttachmentPointer attachmentPointersFromProtos:dataMessage.attachments
                                                         albumMessage:incomingMessage];
                for (TSAttachmentPointer *pointer in attachmentPointers) {
                    [pointer saveWithTransaction:transaction];
                    [incomingMessage.attachmentIds addObject:pointer.uniqueId];
                }

                if (body.length == 0 && attachmentPointers.count < 1 && !contact) {
                    OWSLogWarn(@"Ignoring empty incoming message from: %@ for group: %@ with timestamp: %lu.",
                        senderMasterHexEncodedPublicKey,
                        groupId,
                        (unsigned long)timestamp);
                    return nil;
                }
                
                // Loki: Cache the user hex encoded public key (for mentions)
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
                        [LKMentionsManager populateUserPublicKeyCacheIfNeededFor:oldGroupThread.uniqueId in:transaction];
                        [LKMentionsManager cache:incomingMessage.authorId for:oldGroupThread.uniqueId];
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

        // TODO: Are we sure this works correctly with multi device?
        [LKSessionMetaProtocol updateDisplayNameIfNeededForHexEncodedPublicKey:incomingMessage.authorId using:dataMessage appendingShortID:YES in:transaction];
        [LKSessionMetaProtocol updateProfileKeyIfNeededForHexEncodedPublicKey:thread.contactIdentifier using:dataMessage];

        // Loki: Parse Loki specific properties if needed
        /*
        if (envelope.isPtpMessage) { incomingMessage.isP2P = YES; }
         */
        
        NSArray<TSAttachmentPointer *> *attachmentPointers =
            [TSAttachmentPointer attachmentPointersFromProtos:dataMessage.attachments albumMessage:incomingMessage];
        for (TSAttachmentPointer *pointer in attachmentPointers) {
            [pointer saveWithTransaction:transaction];
            [incomingMessage.attachmentIds addObject:pointer.uniqueId];
        }

        // Loki: Do this before the check below
        [LKFriendRequestProtocol handleFriendRequestMessageIfNeededFromEnvelope:envelope using:transaction];
        
        if (body.length == 0 && attachmentPointers.count < 1 && !contact) {
            OWSLogWarn(@"Ignoring empty incoming message from: %@ with timestamp: %lu.",
                hexEncodedPublicKey,
                (unsigned long)timestamp);
            return nil;
        }
        
        // Loki: If we received a message from a contact in the last 2 minutes that wasn't P2P, then we need to ping them.
        // We assume this occurred because they don't have our P2P details.
        /*
        if (!envelope.isPtpMessage && hexEncodedPublicKey != nil) {
            uint64_t timestamp = envelope.timestamp;
            uint64_t now = NSDate.ows_millisecondTimeStamp;
            uint64_t ageInSeconds = (now - timestamp) / 1000;
            if (ageInSeconds <= 120) { [LKP2PAPI pingContact:hexEncodedPublicKey]; }
        }
         */

        [self finalizeIncomingMessage:incomingMessage
                               thread:thread
                         masterThread:thread
                             envelope:envelope
                          transaction:transaction];
        
        return incomingMessage;
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
                [LKStorage writeSyncWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
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
                } error:nil];
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
