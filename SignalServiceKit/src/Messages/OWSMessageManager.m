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
#import "NSData+Image.h"
#import "NotificationsProtocol.h"
#import "OWSCallMessageHandler.h"
#import "OWSDisappearingConfigurationUpdateInfoMessage.h"
#import "OWSDisappearingMessagesConfiguration.h"
#import "OWSDisappearingMessagesJob.h"
#import "OWSIncomingSentMessageTranscript.h"
#import "OWSOutgoingReceiptManager.h"
#import "OWSReceiptManager.h"
#import "OWSRecordTranscriptJob.h"
#import "OWSUnknownProtocolVersionMessage.h"
#import "ProfileManagerProtocol.h"
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
                                 dataMessage:contentProto.dataMessage
                               plaintextData:request.plaintextData
                             wasReceivedByUD:request.wasReceivedByUD
                     serverDeliveryTimestamp:request.serverDeliveryTimestamp
                shouldDiscardVisibleMessages:request.shouldDiscardVisibleMessages
                                          tx:transaction];
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
                           typingMessage:contentProto.typingMessage
                                      tx:transaction];
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
    uint32_t deviceId = [TSAccountManagerObjcBridge storedDeviceIdWith:transaction];
    if ([callMessage hasDestinationDeviceID]) {
        if ([callMessage destinationDeviceID] != deviceId) {
            OWSLogInfo(@"Ignoring call message that is not for this device! intended: %u this: %u",
                [callMessage destinationDeviceID],
                deviceId);
            return;
        }
    }

    if ([callMessage hasProfileKey]) {
        NSData *profileKey = [callMessage profileKey];
        SignalServiceAddress *address = envelope.sourceAddress;
        if (address.isLocalAddress && [TSAccountManagerObjcBridge isPrimaryDeviceWith:transaction]) {
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
                                     fromCaller:decryptedEnvelope.sourceAciObjC
                                   sourceDevice:decryptedEnvelope.sourceDeviceId
                        serverReceivedTimestamp:decryptedEnvelope.serverTimestamp
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
                                             fromCaller:decryptedEnvelope.sourceAciObjC
                                           sourceDevice:decryptedEnvelope.sourceDeviceId
                                serverReceivedTimestamp:decryptedEnvelope.serverTimestamp
                                serverDeliveryTimestamp:serverDeliveryTimestamp
                                            transaction:sdsWriteBlockTransaction];
            }];
        } else {
            OWSLogWarn(@"Call message with no actionable payload.");
        }
    });
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
