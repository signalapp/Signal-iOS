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
                                     callMessage:contentProto.callMessage
                         serverDeliveryTimestamp:request.serverDeliveryTimestamp
                                              tx:transaction];
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
                          receiptMessage:contentProto.receiptMessage
                                 context:context
                                      tx:transaction];
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

#pragma mark - Group ID Mapping

- (void)ensureGroupIdMapping:(NSData *)groupId transaction:(SDSAnyWriteTransaction *)transaction
{
    // We might be learning of a v1 group id for the first time that
    // corresponds to a v2 group without a v1-to-v2 group id mapping.
    [TSGroupThread ensureGroupIdMappingForGroupId:groupId transaction:transaction];
}

@end

NS_ASSUME_NONNULL_END
