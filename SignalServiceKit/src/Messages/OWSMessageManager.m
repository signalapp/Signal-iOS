//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSMessageManager.h"
#import "AppContext.h"
#import "AppReadiness.h"
#import "ContactsManagerProtocol.h"
#import "HTTPUtils.h"
#import "MIMETypeUtil.h"
#import "MessageSender.h"
#import "NSData+Image.h"
#import "NotificationsProtocol.h"
#import "OWSCallMessageHandler.h"
#import "OWSContact.h"
#import "OWSDisappearingConfigurationUpdateInfoMessage.h"
#import "OWSDisappearingMessagesConfiguration.h"
#import "OWSDisappearingMessagesJob.h"
#import "OWSIdentityManager.h"
#import "OWSIncomingSentMessageTranscript.h"
#import "OWSOutgoingReceiptManager.h"
#import "OWSReceiptManager.h"
#import "OWSRecordTranscriptJob.h"
#import "OWSUnknownProtocolVersionMessage.h"
#import "ProfileManagerProtocol.h"
#import "TSAccountManager.h"
#import "TSAttachment.h"
#import "TSAttachmentPointer.h"
#import "TSAttachmentStream.h"
#import "TSContactThread.h"
#import "TSGroupModel.h"
#import "TSGroupThread.h"
#import "TSIncomingMessage.h"
#import "TSInfoMessage.h"
#import "TSOutgoingMessage.h"
#import "TSQuotedMessage.h"
#import <SignalCoreKit/Cryptography.h>
#import <SignalCoreKit/NSData+OWS.h>
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalCoreKit/NSString+OWS.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark -

@implementation OWSMessageManager

- (instancetype)init
{
    self = [super init];

    if (!self) {
        return self;
    }

    OWSSingletonAssert();

    return self;
}

#pragma mark - message handling

// This code path is for server-generated receipts only.
- (void)handleDeliveryReceipt:(ServerReceiptEnvelope *)envelope
                      context:(id<DeliveryReceiptContext>)context
                  transaction:(SDSAnyWriteTransaction *)transaction
{
    if (!envelope) {
        OWSFailDebug(@"Missing envelope.");
        return;
    }
    if (!transaction) {
        OWSFail(@"Missing transaction.");
        return;
    }
    // Server-generated delivery receipts don't include a "delivery timestamp".
    // The envelope's timestamp gives the timestamp of the message this receipt
    // is for. Unlike UD receipts, it is not meant to be the time the message
    // was delivered. We use the current time as a good-enough guess. We could
    // also use the envelope's serverTimestamp.
    const uint64_t deliveryTimestamp = [NSDate ows_millisecondTimeStamp];
    if (![SDS fitsInInt64:deliveryTimestamp]) {
        OWSFailDebug(@"Invalid timestamp.");
        return;
    }

    NSArray<NSNumber *> *earlyReceiptTimestamps =
        [self.receiptManager processDeliveryReceiptsFrom:envelope.sourceServiceIdObjC
                                       recipientDeviceId:envelope.sourceDeviceId
                                          sentTimestamps:@[ @(envelope.timestamp) ]
                                       deliveryTimestamp:deliveryTimestamp
                                                 context:context
                                                      tx:transaction];

    [self recordEarlyReceiptOfType:SSKProtoReceiptMessageTypeDelivery
                   senderServiceId:envelope.sourceServiceIdObjC
                    senderDeviceId:envelope.sourceDeviceId
                        timestamps:earlyReceiptTimestamps
                   remoteTimestamp:deliveryTimestamp
                       transaction:transaction];
}

- (void)logUnactionablePayload:(SSKProtoEnvelope *)envelope
{
    OWSProdInfoWEnvelope([OWSAnalyticsEvents messageManagerErrorEnvelopeNoActionablePayload], envelope);
}

- (void)handleRequest:(MessageManagerRequest *)request
              context:(id<DeliveryReceiptContext>)context
          transaction:(SDSAnyWriteTransaction *)transaction
{
    SSKProtoContent *contentProto = request.protoContent;
    OWSLogInfo(@"handling content: <Content: %@>", [self descriptionForContent:contentProto]);

    switch (request.messageType) {
        case OWSMessageManagerMessageTypeSyncMessage:
            [self handleIncomingEnvelope:request.decryptedEnvelope
                             syncMessage:contentProto.syncMessage
                           plaintextData:request.plaintextData
                         wasReceivedByUD:request.wasReceivedByUD
                 serverDeliveryTimestamp:request.serverDeliveryTimestamp
                                      tx:transaction];

            [OWSDeviceManagerObjcBridge setHasReceivedSyncMessageWithTransaction:transaction];
            break;
        case OWSMessageManagerMessageTypeDataMessage:
            [self handleIncomingEnvelope:request.decryptedEnvelope
                             withDataMessage:contentProto.dataMessage
                               plaintextData:request.plaintextData
                             wasReceivedByUD:request.wasReceivedByUD
                     serverDeliveryTimestamp:request.serverDeliveryTimestamp
                shouldDiscardVisibleMessages:request.shouldDiscardVisibleMessages
                                 transaction:transaction];
            break;
        case OWSMessageManagerMessageTypeCallMessage:
            OWSAssertDebug(!request.shouldDiscardVisibleMessages);
            OWSCallMessageAction action = [self.callMessageHandler actionForEnvelope:request.envelope
                                                                         callMessage:contentProto.callMessage
                                                             serverDeliveryTimestamp:request.serverDeliveryTimestamp];
            switch (action) {
                case OWSCallMessageActionIgnore:
                    OWSLogInfo(@"Ignoring call message with timestamp: %llu", request.envelope.timestamp);
                    break;
                case OWSCallMessageActionHandoff:
                    [self.callMessageHandler externallyHandleCallMessageWithEnvelope:request.envelope
                                                                       plaintextData:request.plaintextData
                                                                     wasReceivedByUD:request.wasReceivedByUD
                                                             serverDeliveryTimestamp:request.serverDeliveryTimestamp
                                                                         transaction:transaction];
                    break;
                case OWSCallMessageActionProcess:
                    [self handleIncomingEnvelope:request.decryptedEnvelope
                                 withCallMessage:contentProto.callMessage
                         serverDeliveryTimestamp:request.serverDeliveryTimestamp
                                     transaction:transaction];
                    break;
            }
            break;
        case OWSMessageManagerMessageTypeTypingMessage:
            [self handleIncomingEnvelope:request.decryptedEnvelope
                       withTypingMessage:contentProto.typingMessage
                 serverDeliveryTimestamp:request.serverDeliveryTimestamp
                             transaction:transaction];
            break;
        case OWSMessageManagerMessageTypeNullMessage:
            OWSLogInfo(@"Received null message.");
            break;
        case OWSMessageManagerMessageTypeReceiptMessage:
            [self handleIncomingEnvelope:request.decryptedEnvelope
                      withReceiptMessage:contentProto.receiptMessage
                                 context:context
                             transaction:transaction];
            break;
        case OWSMessageManagerMessageTypeDecryptionErrorMessage:
            [self handleIncomingEnvelope:request.decryptedEnvelope
                withDecryptionErrorMessage:contentProto.decryptionErrorMessage
                               transaction:transaction];
            break;
        case OWSMessageManagerMessageTypeStoryMessage:
            [self handleIncomingEnvelope:request.decryptedEnvelope
                        withStoryMessage:contentProto.storyMessage
                                      tx:transaction];
            break;
        case OWSMessageManagerMessageTypeHasSenderKeyDistributionMessage:
            // Sender key distribution messages are not mutually exclusive. They can be
            // included with any message type. However, they're not processed here. They're
            // processed in the -preprocess phase that occurs post-decryption.
            //
            // See: OWSMessageManager.preprocessEnvelope(envelope:plaintext:transaction:)
            break;
        case OWSMessageManagerMessageTypeEditMessage: {
            OWSEditProcessingResult result = [self handleIncomingEnvelope:request.decryptedEnvelope
                                                          withEditMessage:contentProto.editMessage
                                                          wasReceivedByUD:request.wasReceivedByUD
                                                              transaction:transaction];

            switch (result) {
                case OWSEditProcessingResultSuccess:
                case OWSEditProcessingResultInvalidEdit:
                    break;
                case OWSEditProcessingResultEditedMessageMissing: {
                    [self.earlyMessageManager recordEarlyEnvelope:request.envelope
                                                    plainTextData:request.plaintextData
                                                  wasReceivedByUD:request.wasReceivedByUD
                                          serverDeliveryTimestamp:request.serverDeliveryTimestamp
                                       associatedMessageTimestamp:contentProto.editMessage.targetSentTimestamp
                                          associatedMessageAuthor:request.decryptedEnvelope.sourceAciObjC
                                                      transaction:transaction];
                }
            }
            break;
        }
        case OWSMessageManagerMessageTypeUnknown:
            OWSLogWarn(@"Ignoring envelope. Content with no known payload");
            break;
    }
    if (SSKDebugFlags.internalLogging || CurrentAppContext().isNSE) {
        OWSLogInfo(@"Done timestamp: %llu, serviceTimestamp: %llu, ",
            request.envelope.timestamp,
            request.envelope.serverTimestamp);
    }
}

- (void)handleIncomingEnvelope:(DecryptedIncomingEnvelope *)decryptedEnvelope
                 withDataMessage:(SSKProtoDataMessage *)dataMessage
                   plaintextData:(NSData *)plaintextData
                 wasReceivedByUD:(BOOL)wasReceivedByUD
         serverDeliveryTimestamp:(uint64_t)serverDeliveryTimestamp
    shouldDiscardVisibleMessages:(BOOL)shouldDiscardVisibleMessages
                     transaction:(SDSAnyWriteTransaction *)transaction
{
    if (!decryptedEnvelope) {
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
    SSKProtoEnvelope *_Nonnull envelope = decryptedEnvelope.envelope;

    if (SSKDebugFlags.internalLogging || CurrentAppContext().isNSE) {
        OWSLogInfo(@"timestamp: %llu, serviceTimestamp: %llu, %@",
            decryptedEnvelope.timestamp,
            decryptedEnvelope.serverTimestamp,
            [OWSMessageManager descriptionForDataMessageContents:dataMessage]);
    }

    NSData *groupId = [self groupIdForDataMessage:dataMessage];

    if (groupId != nil) {
        [self ensureGroupIdMapping:groupId transaction:transaction];

        if ([self.blockingManager isGroupIdBlocked:groupId transaction:transaction]) {
            OWSLogError(
                @"Ignoring blocked message from %@ in group %@", decryptedEnvelope.sourceServiceIdObjC, groupId);
            return;
        }
    }

    if (dataMessage.hasTimestamp) {
        if (dataMessage.timestamp <= 0) {
            OWSFailDebug(
                @"Ignoring message with invalid data message timestamp: %@", decryptedEnvelope.sourceServiceIdObjC);
            return;
        }
        if (![SDS fitsInInt64:dataMessage.timestamp]) {
            OWSFailDebug(@"Invalid timestamp.");
            return;
        }
        // This prevents replay attacks by the service.
        if (dataMessage.timestamp != decryptedEnvelope.timestamp) {
            OWSFailDebug(@"Ignoring message with non-matching data message timestamp: %@",
                decryptedEnvelope.sourceServiceIdObjC);
            return;
        }
    }

    if ([dataMessage hasProfileKey]) {
        NSData *profileKey = [dataMessage profileKey];
        SignalServiceAddress *address = decryptedEnvelope.envelope.sourceAddress;
        if (address.isLocalAddress && self.tsAccountManager.isPrimaryDevice) {
            OWSLogVerbose(@"Ignoring profile key for local device on primary.");
        } else if (profileKey.length != kAES256_KeyByteLength) {
            OWSFailDebug(
                @"Unexpected profile key length: %lu on message from: %@", (unsigned long)profileKey.length, address);
        } else {
            [self.profileManager setProfileKeyData:profileKey
                                        forAddress:address
                                 userProfileWriter:UserProfileWriter_LocalUser
                                     authedAccount:AuthedAccount.implicit
                                       transaction:transaction];
        }
    }

    if (!RemoteConfig.stories && dataMessage.storyContext != nil) {
        OWSLogInfo(@"Ignoring message (author: %@, timestamp: %llu) related to story (author: %@, timestamp: %llu)",
            decryptedEnvelope.sourceServiceIdObjC,
            dataMessage.timestamp,
            dataMessage.storyContext.authorAci,
            dataMessage.storyContext.sentTimestamp);
        return;
    }

    // Pre-process the data message. For v1 and v2 group messages this involves
    // checking group state, possibly creating the group thread, possibly
    // responding to group info requests, etc.
    //
    // If we can and should try to "process" (e.g. generate user-visible
    // interactions) for the data message, preprocessDataMessage will return a
    // thread. If not, we should abort immediately.
    TSThread *_Nullable thread = [self preprocessDataMessage:dataMessage envelope:envelope transaction:transaction];
    if (thread == nil) {
        return;
    }

    TSIncomingMessage *_Nullable message = nil;
    if ((dataMessage.flags & SSKProtoDataMessageFlagsEndSession) != 0) {
        [self handleEndSessionMessageWithEnvelope:envelope dataMessage:dataMessage transaction:transaction];
    } else if ((dataMessage.flags & SSKProtoDataMessageFlagsExpirationTimerUpdate) != 0) {
        [self handleExpirationTimerUpdateMessageWithEnvelope:decryptedEnvelope
                                                 dataMessage:dataMessage
                                                      thread:thread
                                                 transaction:transaction];
    } else if ((dataMessage.flags & SSKProtoDataMessageFlagsProfileKeyUpdate) != 0) {
        // Do nothing, we handle profile keys on all incoming messages above.
    } else {
        message = [self handleReceivedEnvelope:decryptedEnvelope
                               withDataMessage:dataMessage
                                        thread:thread
                                 plaintextData:plaintextData
                               wasReceivedByUD:wasReceivedByUD
                       serverDeliveryTimestamp:serverDeliveryTimestamp
                  shouldDiscardVisibleMessages:shouldDiscardVisibleMessages
                                   transaction:transaction];
        if (message != nil) {
            OWSAssertDebug([TSMessage anyFetchWithUniqueId:message.uniqueId transaction:transaction] != nil);

            OWSLogDebug(@"Incoming message: %@", message.debugDescription);
        }
    }

    // Send delivery receipts for "valid data" messages received via UD.
    if (wasReceivedByUD) {
        [self.outgoingReceiptManager enqueueDeliveryReceiptFor:decryptedEnvelope
                                               messageUniqueId:message.uniqueId
                                                            tx:transaction];
    }
}

// Returns a thread reference if message processing should proceed.
// Message processing is generating user-visible interactions, etc.
// We don't want to do that if:
//
// * The data message is malformed.
// * The local user is not in the group.
- (nullable TSThread *)preprocessDataMessage:(SSKProtoDataMessage *)dataMessage
                                    envelope:(SSKProtoEnvelope *)envelope
                                 transaction:(SDSAnyWriteTransaction *)transaction
{
    if (dataMessage.groupV2 != nil) {
        // V2 Group.
        SSKProtoGroupContextV2 *groupV2 = dataMessage.groupV2;
        if (!groupV2.hasMasterKey) {
            OWSFailDebug(@"Missing masterKey.");
            return nil;
        }
        if (!groupV2.hasRevision) {
            OWSFailDebug(@"Missing revision.");
            return nil;
        }

        NSError *_Nullable error;
        GroupV2ContextInfo *_Nullable groupContextInfo =
            [self.groupsV2 groupV2ContextInfoForMasterKeyData:groupV2.masterKey error:&error];
        if (error != nil || groupContextInfo == nil) {
            OWSFailDebug(@"Invalid group context.");
            return nil;
        }
        NSData *groupId = groupContextInfo.groupId;
        uint32_t revision = groupV2.revision;

        TSGroupThread *_Nullable groupThread = [TSGroupThread fetchWithGroupId:groupId transaction:transaction];
        if (groupThread == nil) {
            OWSFailDebug(@"Unknown v2 group.");
            return nil;
        }
        if (![groupThread.groupModel isKindOfClass:TSGroupModelV2.class]) {
            OWSFailDebug(@"Invalid group model.");
            return nil;
        }
        TSGroupModelV2 *groupModel = (TSGroupModelV2 *)groupThread.groupModel;

        if (groupModel.revision < revision) {
            OWSFailDebug(@"Invalid v2 group revision[%@]: %lu < %lu",
                groupModel.groupId.hexadecimalString,
                (unsigned long)groupModel.revision,
                (unsigned long)revision);
            return nil;
        }

        if (!envelope.sourceAddress) {
            OWSFailDebug(@"Missing sender address.");
            return nil;
        }
        if (!groupThread.isLocalUserFullMember) {
            // We don't want to process messages for groups in which we are a pending member.
            OWSLogInfo(@"Ignoring messages for left group.");
            return nil;
        }
        if (![groupModel.groupMembership isFullMember:envelope.sourceAddress]) {
            // We don't want to process group messages for non-members.
            OWSLogInfo(@"Ignoring messages for user not in group: %@.", envelope.sourceAddress);
            return nil;
        }

        return groupThread;
    } else {
        // No group context.
        TSContactThread *thread = [TSContactThread getOrCreateThreadWithContactAddress:envelope.sourceAddress
                                                                           transaction:transaction];
        return thread;
    }
}

- (void)updateDisappearingMessageConfigurationWithEnvelope:(DecryptedIncomingEnvelope *)decryptedEnvelope
                                               dataMessage:(SSKProtoDataMessage *)dataMessage
                                                    thread:(TSThread *)thread
                                               transaction:(SDSAnyWriteTransaction *)transaction
{
    if (!decryptedEnvelope) {
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
    if (!thread) {
        OWSFail(@"Missing thread.");
        return;
    }
    if (![thread isKindOfClass:[TSContactThread class]]) {
        return;
    }
    LocalIdentifiersObjC *localIdentifiers = [self.tsAccountManager localIdentifiersObjCWithTx:transaction];
    if (localIdentifiers == nil) {
        OWSFailDebug(@"Not registered.");
        return;
    }

    AciObjC *authorAci = decryptedEnvelope.sourceAciObjC;
    DisappearingMessageToken *disappearingMessageToken =
        [DisappearingMessageToken tokenForProtoExpireTimer:dataMessage.expireTimer];
    [GroupManager remoteUpdateDisappearingMessagesWithContactThread:(TSContactThread *)thread
                                           disappearingMessageToken:disappearingMessageToken
                                                       changeAuthor:authorAci
                                                   localIdentifiers:localIdentifiers
                                                        transaction:transaction];
}

// This code path is for UD receipts.
- (void)handleIncomingEnvelope:(DecryptedIncomingEnvelope *)decryptedEnvelope
            withReceiptMessage:(SSKProtoReceiptMessage *)receiptMessage
                       context:(id<DeliveryReceiptContext>)context
                   transaction:(SDSAnyWriteTransaction *)transaction
{
    if (!decryptedEnvelope) {
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
    if (!receiptMessage.hasType) {
        OWSFailDebug(@"Missing type for receipt message, ignoring.");
        return;
    }

    NSArray<NSNumber *> *sentTimestamps = receiptMessage.timestamp;
    for (NSNumber *sentTimestamp in sentTimestamps) {
        if (![SDS fitsInInt64:sentTimestamp.unsignedLongLongValue]) {
            OWSFailDebug(@"Invalid timestamp.");
            return;
        }
    }

    NSArray<NSNumber *> *earlyTimestamps;

    switch (receiptMessage.unwrappedType) {
        case SSKProtoReceiptMessageTypeDelivery:
            earlyTimestamps = [self.receiptManager processDeliveryReceiptsFrom:decryptedEnvelope.sourceAciObjC
                                                             recipientDeviceId:decryptedEnvelope.sourceDeviceId
                                                                sentTimestamps:sentTimestamps
                                                             deliveryTimestamp:decryptedEnvelope.timestamp
                                                                       context:context
                                                                            tx:transaction];
            break;
        case SSKProtoReceiptMessageTypeRead:
            earlyTimestamps = [self.receiptManager processReadReceiptsFrom:decryptedEnvelope.sourceAciObjC
                                                         recipientDeviceId:decryptedEnvelope.sourceDeviceId
                                                            sentTimestamps:sentTimestamps
                                                             readTimestamp:decryptedEnvelope.timestamp
                                                                        tx:transaction];
            break;
        case SSKProtoReceiptMessageTypeViewed:
            earlyTimestamps = [self.receiptManager processViewedReceiptsFrom:decryptedEnvelope.sourceAciObjC
                                                           recipientDeviceId:decryptedEnvelope.sourceDeviceId
                                                              sentTimestamps:sentTimestamps
                                                             viewedTimestamp:decryptedEnvelope.timestamp
                                                                          tx:transaction];
            break;
        default:
            OWSLogInfo(@"Ignoring receipt message of unknown type: %d.", (int)receiptMessage.unwrappedType);
            return;
    }

    [self recordEarlyReceiptOfType:receiptMessage.unwrappedType
                   senderServiceId:decryptedEnvelope.sourceAciObjC
                    senderDeviceId:decryptedEnvelope.sourceDeviceId
                        timestamps:earlyTimestamps
                   remoteTimestamp:decryptedEnvelope.timestamp
                       transaction:transaction];
}

// remoteTimestamp is the time the message was delivered, read, or viewed.
// earlyTimestamps contains the collection of outgoing messages referred to by the receipt.
- (void)recordEarlyReceiptOfType:(SSKProtoReceiptMessageType)receiptType
                 senderServiceId:(ServiceIdObjC *)senderServiceId
                  senderDeviceId:(uint32_t)senderDeviceId
                      timestamps:(NSArray<NSNumber *> *)earlyTimestamps
                 remoteTimestamp:(uint64_t)remoteTimestamp
                     transaction:(SDSAnyWriteTransaction *)transaction
{
    for (NSNumber *nsEarlyTimestamp in earlyTimestamps) {
        OWSLogInfo(@"Record early receipt for %@", nsEarlyTimestamp);
        const UInt64 earlyTimestamp = [nsEarlyTimestamp unsignedLongLongValue];
        [self.earlyMessageManager recordEarlyReceiptForOutgoingMessageWithType:receiptType
                                                               senderServiceId:senderServiceId
                                                                senderDeviceId:senderDeviceId
                                                                     timestamp:remoteTimestamp
                                                    associatedMessageTimestamp:earlyTimestamp
                                                                            tx:transaction];
    }
}

- (void)handleIncomingEnvelope:(DecryptedIncomingEnvelope *)decryptedEnvelope
               withCallMessage:(SSKProtoCallMessage *)callMessage
       serverDeliveryTimestamp:(uint64_t)serverDeliveryTimestamp
                   transaction:(SDSAnyWriteTransaction *)transaction
{
    if (!decryptedEnvelope) {
        OWSFailDebug(@"Missing envelope.");
        return;
    }
    if (!callMessage) {
        OWSFailDebug(@"Missing callMessage.");
        return;
    }
    SSKProtoEnvelope *_Nonnull envelope = decryptedEnvelope.envelope;

    [self ensureGroupIdMapping:envelope withCallMessage:callMessage transaction:transaction];

    // If destinationDevice is defined, ignore messages not addressed to this device.
    if ([callMessage hasDestinationDeviceID]) {
        if ([callMessage destinationDeviceID] != self.tsAccountManager.storedDeviceId) {
            OWSLogInfo(@"Ignoring call message that is not for this device! intended: %u this: %u", [callMessage destinationDeviceID], self.tsAccountManager.storedDeviceId);
            return;
        }
    }

    if ([callMessage hasProfileKey]) {
        NSData *profileKey = [callMessage profileKey];
        SignalServiceAddress *address = envelope.sourceAddress;
        if (address.isLocalAddress && self.tsAccountManager.isPrimaryDevice) {
            OWSLogVerbose(@"Ignoring profile key for local device on primary.");
        } else if (profileKey.length != kAES256_KeyByteLength) {
            OWSFailDebug(
                @"Unexpected profile key length: %lu on message from: %@", (unsigned long)profileKey.length, address);
        } else {
            [self.profileManager setProfileKeyData:profileKey
                                        forAddress:address
                                 userProfileWriter:UserProfileWriter_LocalUser
                                     authedAccount:AuthedAccount.implicit
                                       transaction:transaction];
        }
    }

    BOOL supportsMultiRing = false;
    if ([callMessage hasSupportsMultiRing]) {
        supportsMultiRing = callMessage.supportsMultiRing;
    }

    // Any call message which will result in the posting a new incoming call to CallKit
    // must be handled sync if we're already on the main thread.  This includes "offer"
    // and "urgent opaque" call messages.  Otherwise we violate this constraint:
    //
    // (PushKit) Apps receiving VoIP pushes must post an incoming call via CallKit in the same run loop as
    // pushRegistry:didReceiveIncomingPushWithPayload:forType:[withCompletionHandler:] without delay.
    //
    // Which can result in the main app being terminated with 0xBAADCA11:
    //
    // The exception code "0xbaadca11" indicates that your app was killed for failing to
    // report a CallKit call in response to a PushKit notification.
    //
    // Or this form of crash:
    //
    // [PKPushRegistry _terminateAppIfThereAreUnhandledVoIPPushes].
    if (NSThread.isMainThread && callMessage.offer) {
        OWSLogInfo(@"Handling 'offer' call message offer sync.");
        [self.callMessageHandler receivedOffer:callMessage.offer
                                    fromCaller:envelope.sourceAddress
                                  sourceDevice:envelope.sourceDevice
                               sentAtTimestamp:envelope.timestamp
                       serverReceivedTimestamp:envelope.serverTimestamp
                       serverDeliveryTimestamp:serverDeliveryTimestamp
                             supportsMultiRing:supportsMultiRing
                                   transaction:transaction];
        return;
    } else if (NSThread.isMainThread && callMessage.opaque && callMessage.opaque.hasUrgency
        && callMessage.opaque.unwrappedUrgency == SSKProtoCallMessageOpaqueUrgencyHandleImmediately) {
        OWSLogInfo(@"Handling 'urgent opaque' call message offer sync.");
        [self.callMessageHandler receivedOpaque:callMessage.opaque
                                     fromCaller:envelope.sourceAddress
                                   sourceDevice:envelope.sourceDevice
                        serverReceivedTimestamp:envelope.serverTimestamp
                        serverDeliveryTimestamp:serverDeliveryTimestamp
                                    transaction:transaction];
        return;
    }

    // By dispatching async, we introduce the possibility that these messages might be lost
    // if the app exits before this block is executed.  This is fine, since the call by
    // definition will end if the app exits.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (callMessage.offer) {
            DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *sdsWriteBlockTransaction) {
                [self.callMessageHandler receivedOffer:callMessage.offer
                                            fromCaller:envelope.sourceAddress
                                          sourceDevice:envelope.sourceDevice
                                       sentAtTimestamp:envelope.timestamp
                               serverReceivedTimestamp:envelope.serverTimestamp
                               serverDeliveryTimestamp:serverDeliveryTimestamp
                                     supportsMultiRing:supportsMultiRing
                                           transaction:sdsWriteBlockTransaction];
            });
        } else if (callMessage.answer) {
            [self.callMessageHandler receivedAnswer:callMessage.answer
                                         fromCaller:envelope.sourceAddress
                                       sourceDevice:envelope.sourceDevice
                                  supportsMultiRing:supportsMultiRing];
        } else if (callMessage.iceUpdate.count > 0) {
            [self.callMessageHandler receivedIceUpdate:callMessage.iceUpdate
                                            fromCaller:envelope.sourceAddress
                                          sourceDevice:envelope.sourceDevice];
        } else if (callMessage.legacyHangup) {
            OWSLogVerbose(@"Received CallMessage with Legacy Hangup.");
            [self.callMessageHandler receivedHangup:callMessage.legacyHangup
                                         fromCaller:envelope.sourceAddress
                                       sourceDevice:envelope.sourceDevice];
        } else if (callMessage.hangup) {
            OWSLogVerbose(@"Received CallMessage with Hangup.");
            [self.callMessageHandler receivedHangup:callMessage.hangup
                                         fromCaller:envelope.sourceAddress
                                       sourceDevice:envelope.sourceDevice];
        } else if (callMessage.busy) {
            [self.callMessageHandler receivedBusy:callMessage.busy
                                       fromCaller:envelope.sourceAddress
                                     sourceDevice:envelope.sourceDevice];
        } else if (callMessage.opaque) {
            [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *sdsWriteBlockTransaction) {
                [self.callMessageHandler receivedOpaque:callMessage.opaque
                                             fromCaller:envelope.sourceAddress
                                           sourceDevice:envelope.sourceDevice
                                serverReceivedTimestamp:envelope.serverTimestamp
                                serverDeliveryTimestamp:serverDeliveryTimestamp
                                            transaction:sdsWriteBlockTransaction];
            }];
        } else {
            OWSProdInfoWEnvelope([OWSAnalyticsEvents messageManagerErrorCallMessageNoActionablePayload], envelope);
        }
    });
}

- (void)handleIncomingEnvelope:(DecryptedIncomingEnvelope *)decryptedEnvelope
             withTypingMessage:(SSKProtoTypingMessage *)typingMessage
       serverDeliveryTimestamp:(uint64_t)serverDeliveryTimestamp
                   transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(transaction);

    if (!decryptedEnvelope) {
        OWSFailDebug(@"Missing envelope.");
        return;
    }
    if (!typingMessage) {
        OWSFailDebug(@"Missing typingMessage.");
        return;
    }
    if (typingMessage.timestamp != decryptedEnvelope.timestamp) {
        OWSFailDebug(@"typingMessage has invalid timestamp.");
        return;
    }
    SSKProtoEnvelope *_Nonnull envelope = decryptedEnvelope.envelope;

    NSData *groupId = typingMessage.groupID;
    if (groupId != nil) {
        [self ensureGroupIdMapping:groupId transaction:transaction];
    }

    if (envelope.sourceAddress.isLocalAddress) {
        OWSLogVerbose(@"Ignoring typing indicators from self or linked device.");
        return;
    }

    TSThread *_Nullable thread;
    if (groupId != nil) {
        if ([self.blockingManager isGroupIdBlocked:groupId transaction:transaction]) {
            OWSLogError(
                @"Ignoring blocked message from %@ in group %@", decryptedEnvelope.sourceServiceIdObjC, groupId);
            return;
        }
        TSGroupThread *_Nullable groupThread = [TSGroupThread fetchWithGroupId:groupId transaction:transaction];
        if (groupThread != nil && !groupThread.isLocalUserFullOrInvitedMember) {
            OWSLogInfo(@"Ignoring messages for left group.");
            return;
        }
        if ([groupThread.groupModel isKindOfClass:TSGroupModelV2.class]) {
            TSGroupModelV2 *groupModel = (TSGroupModelV2 *)groupThread.groupModel;
            if (groupModel.isAnnouncementsOnly
                && ![groupModel.groupMembership isFullMemberAndAdministrator:envelope.sourceAddress]) {
                return;
            }
        }
        thread = groupThread;
    } else {
        thread = [TSContactThread getThreadWithContactAddress:envelope.sourceAddress transaction:transaction];
    }

    if (!thread) {
        // This isn't necessarily an error.  We might not yet know about the thread,
        // in which case we don't need to display the typing indicators.
        OWSLogWarn(@"Could not locate thread for typingMessage.");
        return;
    }

    if (!typingMessage.hasAction) {
        OWSFailDebug(@"Type message is missing action.");
        return;
    }

    // We should ignore typing indicator messages.
    if (envelope.hasServerTimestamp && envelope.serverTimestamp > 0 && serverDeliveryTimestamp > 0) {
        uint64_t relevancyCutoff = serverDeliveryTimestamp - (uint64_t)(5 * kMinuteInterval);
        if (envelope.serverTimestamp < relevancyCutoff) {
            OWSLogInfo(@"Discarding obsolete typing indicator message.");
            return;
        }
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        switch (typingMessage.unwrappedAction) {
            case SSKProtoTypingMessageActionStarted:
                [self.typingIndicatorsImpl
                    didReceiveTypingStartedMessageInThread:thread
                                                   address:decryptedEnvelope.envelope.sourceAddress
                                                  deviceId:decryptedEnvelope.sourceDeviceId];
                break;
            case SSKProtoTypingMessageActionStopped:
                [self.typingIndicatorsImpl
                    didReceiveTypingStoppedMessageInThread:thread
                                                   address:decryptedEnvelope.envelope.sourceAddress
                                                  deviceId:decryptedEnvelope.sourceDeviceId];
                break;
            default:
                OWSFailDebug(@"Typing message has unexpected action.");
                break;
        }
    });
}

- (void)handleEndSessionMessageWithEnvelope:(SSKProtoEnvelope *)envelope
                                dataMessage:(SSKProtoDataMessage *)dataMessage
                                transaction:(SDSAnyWriteTransaction *)transaction
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

    TSContactThread *thread = [TSContactThread getOrCreateThreadWithContactAddress:envelope.sourceAddress
                                                                       transaction:transaction];

    [[[TSInfoMessage alloc] initWithThread:thread
                               messageType:TSInfoMessageTypeSessionDidEnd] anyInsertWithTransaction:transaction];

    // PNI TODO: this should end the PNI session if it was sent to our PNI.
    [self archiveSessionsFor:envelope.sourceAddress transaction:transaction];
}

- (void)handleExpirationTimerUpdateMessageWithEnvelope:(DecryptedIncomingEnvelope *)decryptedEnvelope
                                           dataMessage:(SSKProtoDataMessage *)dataMessage
                                                thread:(TSThread *)thread
                                           transaction:(SDSAnyWriteTransaction *)transaction
{
    if (thread.isGroupV2Thread) {
        OWSFailDebug(@"Unexpected dm timer update for v2 group.");
        return;
    }

    [self updateDisappearingMessageConfigurationWithEnvelope:decryptedEnvelope
                                                 dataMessage:dataMessage
                                                      thread:thread
                                                 transaction:transaction];
}

- (TSIncomingMessage *_Nullable)handleReceivedEnvelope:(DecryptedIncomingEnvelope *)decryptedEnvelope
                                       withDataMessage:(SSKProtoDataMessage *)dataMessage
                                                thread:(TSThread *)thread
                                         plaintextData:(NSData *)plaintextData
                                       wasReceivedByUD:(BOOL)wasReceivedByUD
                               serverDeliveryTimestamp:(uint64_t)serverDeliveryTimestamp
                          shouldDiscardVisibleMessages:(BOOL)shouldDiscardVisibleMessages
                                           transaction:(SDSAnyWriteTransaction *)transaction
{
    if (!decryptedEnvelope) {
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
    if (!thread) {
        OWSFail(@"Missing thread.");
        return nil;
    }
    SSKProtoEnvelope *envelope = decryptedEnvelope.envelope;

    if (dataMessage.hasRequiredProtocolVersion
        && dataMessage.requiredProtocolVersion > SSKProtos.currentProtocolVersion) {
        [self insertUnknownProtocolVersionErrorInThread:thread
                                        protocolVersion:dataMessage.requiredProtocolVersion
                                                 sender:envelope.sourceAddress
                                            transaction:transaction];
        return nil;
    }

    uint64_t timestamp = envelope.timestamp;
    NSString *messageDescription;
    if (thread.isGroupThread) {
        TSGroupThread *groupThread = (TSGroupThread *)thread;
        messageDescription = [NSString
            stringWithFormat:@"Incoming message from: %@ for group: %@ with timestamp: %llu, serviceTimestamp: %llu",
            envelopeAddress(envelope),
            groupThread.groupModel.groupId,
            timestamp,
            envelope.serverTimestamp];
    } else {
        messageDescription =
            [NSString stringWithFormat:@"Incoming 1:1 message from: %@ with timestamp: %llu, serviceTimestamp: %llu",
                      envelopeAddress(envelope),
                      timestamp,
                      envelope.serverTimestamp];
    }

    if (SSKDebugFlags.internalLogging || CurrentAppContext().isNSE) {
        OWSLogInfo(@"%@", messageDescription);
    } else {
        OWSLogDebug(@"%@", messageDescription);
    }

    if (dataMessage.reaction) {
        if (SSKDebugFlags.internalLogging || CurrentAppContext().isNSE) {
            OWSLogInfo(@"Reaction: %@", messageDescription);
        }
        OWSReactionProcessingResult result =
            [OWSReactionManager processIncomingReaction:dataMessage.reaction
                                                 thread:thread
                                                reactor:decryptedEnvelope.sourceAciObjC
                                              timestamp:timestamp
                                        serverTimestamp:decryptedEnvelope.serverTimestamp
                                       expiresInSeconds:dataMessage.expireTimer
                                         sentTranscript:nil
                                            transaction:transaction];

        switch (result) {
            case OWSReactionProcessingResultSuccess:
            case OWSReactionProcessingResultInvalidReaction:
                break;
            case OWSReactionProcessingResultAssociatedMessageMissing: {
                AciObjC *messageAuthor = [[AciObjC alloc] initWithAciString:dataMessage.reaction.targetAuthorAci];
                [self.earlyMessageManager recordEarlyEnvelope:envelope
                                                plainTextData:plaintextData
                                              wasReceivedByUD:wasReceivedByUD
                                      serverDeliveryTimestamp:serverDeliveryTimestamp
                                   associatedMessageTimestamp:dataMessage.reaction.timestamp
                                      associatedMessageAuthor:messageAuthor
                                                  transaction:transaction];
                break;
            }
        }

        return nil;
    }

    if (dataMessage.delete) {
        OWSRemoteDeleteProcessingResult result =
            [TSMessage tryToRemotelyDeleteMessageFromAuthor:decryptedEnvelope.sourceAciObjC
                                            sentAtTimestamp:dataMessage.delete.targetSentTimestamp
                                             threadUniqueId:thread.uniqueId
                                            serverTimestamp:envelope.serverTimestamp
                                                transaction:transaction];

        switch (result) {
            case OWSRemoteDeleteProcessingResultSuccess:
                break;
            case OWSRemoteDeleteProcessingResultInvalidDelete:
                OWSLogError(@"Failed to remotely delete message: %llu", dataMessage.delete.targetSentTimestamp);
                break;
            case OWSRemoteDeleteProcessingResultDeletedMessageMissing:
                [self.earlyMessageManager recordEarlyEnvelope:envelope
                                                plainTextData:plaintextData
                                              wasReceivedByUD:wasReceivedByUD
                                      serverDeliveryTimestamp:serverDeliveryTimestamp
                                   associatedMessageTimestamp:dataMessage.delete.targetSentTimestamp
                                      associatedMessageAuthor:decryptedEnvelope.sourceAciObjC
                                                  transaction:transaction];
                break;
        }
        return nil;
    }

    if (shouldDiscardVisibleMessages) {
        // Now that "reactions" and "delete for everyone" have been processed,
        // the only possible outcome of further processing is a visible message
        // or group call update, both of which should be discarded.
        OWSLogInfo(@"Discarding message with timestamp: %llu", envelope.timestamp);
        return nil;
    }

    if (dataMessage.groupCallUpdate) {
        if (!thread.isGroupThread) {
            OWSLogError(@"Invalid thread for GroupUpdateMessage: %@", thread);
            return nil;
        }
        TSGroupThread *groupThread = (TSGroupThread *)thread;
        PendingTask *pendingTask = [OWSMessageManager buildPendingTaskWithLabel:@"GroupCallUpdate"];
        [self.callMessageHandler receivedGroupCallUpdateMessage:dataMessage.groupCallUpdate
                                                      forThread:groupThread
                                        serverReceivedTimestamp:envelope.timestamp
                                                     completion:^{ [pendingTask complete]; }];
        return nil;
    }

    NSString *_Nullable body = dataMessage.body;
    MessageBodyRanges *_Nullable bodyRanges;
    if (dataMessage.bodyRanges.count > 0) {
        bodyRanges = [[MessageBodyRanges alloc] initWithProtos:dataMessage.bodyRanges];
    }

    NSNumber *_Nullable serverTimestamp = (envelope.hasServerTimestamp ? @(envelope.serverTimestamp) : nil);
    if (serverTimestamp != nil && ![SDS fitsInInt64WithNSNumber:serverTimestamp]) {
        OWSFailDebug(@"Invalid timestamp.");
        return nil;
    }

    NSString *_Nullable serverGuid = (envelope.hasServerGuid ? envelope.serverGuid : nil);
    if (serverGuid != nil && [[NSUUID alloc] initWithUUIDString:serverGuid] == nil) {
        OWSFailDebug(@"Invalid server guid.");
        serverGuid = nil;
    }

    TSQuotedMessage *_Nullable quotedMessage = [TSQuotedMessage quotedMessageForDataMessage:dataMessage
                                                                                     thread:thread
                                                                                transaction:transaction];

    OWSContact *_Nullable contact;
    OWSLinkPreview *_Nullable linkPreview;

    contact = [OWSContacts contactForDataMessage:dataMessage transaction:transaction];

    NSError *linkPreviewError;
    linkPreview = [OWSLinkPreview buildValidatedLinkPreviewWithDataMessage:dataMessage
                                                                      body:body
                                                               transaction:transaction
                                                                     error:&linkPreviewError];
    if (linkPreviewError && ![OWSLinkPreview isNoPreviewError:linkPreviewError]) {
        OWSLogError(@"linkPreviewError: %@", linkPreviewError);
    }

    NSError *stickerError;
    MessageSticker *_Nullable messageSticker =
        [MessageSticker buildValidatedMessageStickerWithDataMessage:dataMessage
                                                        transaction:transaction
                                                              error:&stickerError];
    if (stickerError && ![MessageSticker isNoStickerError:stickerError]) {
        OWSFailDebug(@"stickerError: %@", stickerError);
    }

    OWSGiftBadge *_Nullable giftBadge = [OWSGiftBadge maybeBuildFromDataMessage:dataMessage];

    BOOL isViewOnceMessage = dataMessage.hasIsViewOnce && dataMessage.isViewOnce;

    TSPaymentModels *_Nullable paymentModels = [TSPaymentModels parsePaymentProtosInDataMessage:dataMessage
                                                                                         thread:thread];
    if (paymentModels.request != nil) {
        OWSLogInfo(@"Processing payment request.");
        [self.paymentsHelper processIncomingPaymentRequestWithThread:thread
                                                      paymentRequest:paymentModels.request
                                                         transaction:transaction];
        return nil;
    } else if (paymentModels.notification != nil) {
        OWSLogInfo(@"Processing payment notification.");
        [self.paymentsHelper processIncomingPaymentNotificationWithThread:thread
                                                      paymentNotification:paymentModels.notification
                                                            senderAddress:envelope.sourceAddress
                                                              transaction:transaction];
        return nil;
    } else if (paymentModels.cancellation != nil) {
        OWSLogInfo(@"Processing payment cancellation.");
        [self.paymentsHelper processIncomingPaymentCancellationWithThread:thread
                                                      paymentCancellation:paymentModels.cancellation
                                                              transaction:transaction];
        return nil;
    } else if (paymentModels != nil) {
        OWSFailDebug(@"Unexpected payment model.");
    }

    [self updateDisappearingMessageConfigurationWithEnvelope:decryptedEnvelope
                                                 dataMessage:dataMessage
                                                      thread:thread
                                                 transaction:transaction];

    NSNumber *_Nullable storyTimestamp;
    SignalServiceAddress *_Nullable storyAuthorAddress;
    if (dataMessage.storyContext != nil && dataMessage.storyContext.hasSentTimestamp
        && dataMessage.storyContext.hasAuthorAci) {
        OWSLogInfo(
            @"Processing storyContext for message with timestamp: %llu, storyTimestamp: %llu, and author uuid: %@",
            envelope.timestamp,
            dataMessage.storyContext.sentTimestamp,
            dataMessage.storyContext.authorAci);

        storyTimestamp = @(dataMessage.storyContext.sentTimestamp);
        storyAuthorAddress = [[SignalServiceAddress alloc] initWithAciString:dataMessage.storyContext.authorAci];

        if (!storyAuthorAddress.isValid) {
            OWSFailDebug(@"Discarding story reply with invalid address %@", storyAuthorAddress);
            return nil;
        }
    }

    // Legit usage of senderTimestamp when creating an incoming group message record
    //
    // The builder() factory method requires us to specify every
    // property so that this will break if we add any new properties.
    TSIncomingMessageBuilder *incomingMessageBuilder =
        [TSIncomingMessageBuilder builderWithThread:thread
                                          timestamp:timestamp
                                          authorAci:decryptedEnvelope.sourceAciObjC
                                     sourceDeviceId:envelope.sourceDevice
                                        messageBody:body
                                         bodyRanges:bodyRanges
                                      attachmentIds:@[]
                                          editState:0
                                   expiresInSeconds:dataMessage.expireTimer
                                      quotedMessage:quotedMessage
                                       contactShare:contact
                                        linkPreview:linkPreview
                                     messageSticker:messageSticker
                                    serverTimestamp:serverTimestamp
                            serverDeliveryTimestamp:serverDeliveryTimestamp
                                         serverGuid:serverGuid
                                    wasReceivedByUD:wasReceivedByUD
                                  isViewOnceMessage:isViewOnceMessage
                                 storyAuthorAddress:storyAuthorAddress
                                     storyTimestamp:storyTimestamp
                                 storyReactionEmoji:nil
                                          giftBadge:giftBadge];
    TSIncomingMessage *message = [incomingMessageBuilder build];
    if (!message) {
        OWSFailDebug(@"Missing incomingMessage.");
        return nil;
    }
    if (!message.shouldBeSaved) {
        OWSFailDebug(@"Incoming message should not be saved.");
        return nil;
    }

    // Typically `hasRenderableContent` will depend on whether or not the message has any attachmentIds
    // But since the message is partially built and doesn't have the attachments yet, we check
    // for attachments explicitly. Story replies cannot have attachments, so we can bail on them here immediately.
    if (!message.hasRenderableContent && (dataMessage.attachments.count == 0 || message.isStoryReply)) {
        OWSLogWarn(@"Ignoring empty: %@", messageDescription);
        OWSLogVerbose(@"Ignoring empty message(envelope): %@", envelope.debugDescription);
        OWSLogVerbose(@"Ignoring empty message(dataMessage): %@", dataMessage.debugDescription);
        return nil;
    }

    if ((message.giftBadge != nil) && thread.isGroupThread) {
        OWSFailDebug(@"Ignoring gift sent to group");
        return nil;
    }

    if (SSKDebugFlags.internalLogging || CurrentAppContext().isNSE) {
        OWSLogInfo(@"Inserting: %@", messageDescription);
    }

    // Check for any placeholders inserted because of a previously undecryptable message
    // The sender may have resent the message. If so, we should swap it in place of the placeholder
    [message insertOrReplacePlaceholderFrom:[[SignalServiceAddress alloc]
                                                initWithUntypedServiceIdObjC:decryptedEnvelope.sourceServiceIdObjC]
                                transaction:transaction];

    // Inserting the message may have modified the thread on disk, so reload it.
    // For example, we may have marked the thread as visible.
    [thread anyReloadWithTransaction:transaction];

    NSArray<TSAttachmentPointer *> *attachmentPointers =
        [TSAttachmentPointer attachmentPointersFromProtos:dataMessage.attachments albumMessage:message];

    NSMutableArray<NSString *> *attachmentIds = [message.attachmentIds mutableCopy];
    for (TSAttachmentPointer *pointer in attachmentPointers) {
        [pointer anyInsertWithTransaction:transaction];
        [attachmentIds addObject:pointer.uniqueId];
    }
    if (message.attachmentIds.count != attachmentIds.count) {
        [message anyUpdateIncomingMessageWithTransaction:transaction
                                                   block:^(TSIncomingMessage *blockParamMessage) {
                                                       blockParamMessage.attachmentIds = [attachmentIds copy];
                                                   }];
    }
    OWSAssertDebug(message.hasRenderableContent);

    [self.earlyMessageManager applyPendingMessagesFor:message transaction:transaction];

    // Any messages sent from the current user - from this device or another - should be automatically marked as read.
    if (envelope.sourceAddress.isLocalAddress) {
        BOOL hasPendingMessageRequest = [thread hasPendingMessageRequestWithTransaction:transaction.unwrapGrdbRead];
        OWSFailDebug(@"Incoming messages from yourself are not supported.");
        // Don't send a read receipt for messages sent by ourselves.
        [message markAsReadAtTimestamp:envelope.timestamp
                                thread:thread
                          circumstance:hasPendingMessageRequest
                              ? OWSReceiptCircumstanceOnLinkedDeviceWhilePendingMessageRequest
                              : OWSReceiptCircumstanceOnLinkedDevice
              shouldClearNotifications:NO // not required, since no notifications if sent by local
                           transaction:transaction];
    }

    [self.attachmentDownloads enqueueDownloadOfAttachmentsForNewMessage:message transaction:transaction];

    [self.notificationsManager notifyUserForIncomingMessage:message thread:thread transaction:transaction];

    if (CurrentAppContext().isMainApp) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.typingIndicatorsImpl didReceiveIncomingMessageInThread:thread
                                                                 address:envelope.sourceAddress
                                                                deviceId:envelope.sourceDevice];
        });
    }

    return message;
}

- (void)insertUnknownProtocolVersionErrorInThread:(TSThread *)thread
                                  protocolVersion:(NSUInteger)protocolVersion
                                           sender:(SignalServiceAddress *)sender
                                      transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(thread);
    OWSAssertDebug(transaction);

    OWSFailDebug(@"Unknown protocol version: %lu", (unsigned long)protocolVersion);

    if (!sender.isValid) {
        OWSFailDebug(@"Missing sender.");
        return;
    }

    TSInteraction *message = [[OWSUnknownProtocolVersionMessage alloc] initWithThread:thread
                                                                               sender:sender
                                                                      protocolVersion:protocolVersion];
    [message anyInsertWithTransaction:transaction];
}

#pragma mark - Group ID Mapping

- (void)ensureGroupIdMapping:(SSKProtoEnvelope *)envelope
             withCallMessage:(SSKProtoCallMessage *)callMessage
                 transaction:(SDSAnyWriteTransaction *)transaction
{
    // TODO: Update this to reflect group calls.
}

- (void)ensureGroupIdMapping:(NSData *)groupId transaction:(SDSAnyWriteTransaction *)transaction
{
    // We might be learning of a v1 group id for the first time that
    // corresponds to a v2 group without a v1-to-v2 group id mapping.
    [TSGroupThread ensureGroupIdMappingForGroupId:groupId transaction:transaction];
}

@end

NS_ASSUME_NONNULL_END
