//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <SignalServiceKit/OWSMessageHandler.h>

NS_ASSUME_NONNULL_BEGIN

@protocol DeliveryReceiptContext;

@class IdentifiedIncomingEnvelope;
@class MessageManagerRequest;
@class SDSAnyWriteTransaction;
@class SSKProtoDataMessage;
@class SSKProtoEnvelope;
@class SSKProtoSyncMessage;
@class TSThread;

typedef NS_CLOSED_ENUM(NSUInteger, OWSMessageManagerMessageType)
{
    OWSMessageManagerMessageTypeSyncMessage,
    OWSMessageManagerMessageTypeDataMessage,
    OWSMessageManagerMessageTypeCallMessage,
    OWSMessageManagerMessageTypeTypingMessage,
    OWSMessageManagerMessageTypeNullMessage,
    OWSMessageManagerMessageTypeReceiptMessage,
    OWSMessageManagerMessageTypeDecryptionErrorMessage,
    OWSMessageManagerMessageTypeStoryMessage,
    OWSMessageManagerMessageTypeHasSenderKeyDistributionMessage,
    OWSMessageManagerMessageTypeEditMessage,
    OWSMessageManagerMessageTypeUnknown
};

@interface OWSMessageManager : OWSMessageHandler

- (void)handleRequest:(MessageManagerRequest *)request
              context:(id<DeliveryReceiptContext>)context
          transaction:(SDSAnyWriteTransaction *)transaction;

- (TSThread *_Nullable)preprocessDataMessage:(SSKProtoDataMessage *)dataMessage
                                    envelope:(SSKProtoEnvelope *)envelope
                                 transaction:(SDSAnyWriteTransaction *)transaction;

- (void)logUnactionablePayload:(SSKProtoEnvelope *)envelope;

- (void)handleDeliveryReceipt:(IdentifiedIncomingEnvelope *)identifiedEnvelope
                      context:(id<DeliveryReceiptContext>)context
                  transaction:(SDSAnyWriteTransaction *)transaction;

// exposed for testing
- (void)handleIncomingEnvelope:(SSKProtoEnvelope *)envelope
               withSyncMessage:(SSKProtoSyncMessage *)syncMessage
                 plaintextData:(NSData *)plaintextData
               wasReceivedByUD:(BOOL)wasReceivedByUD
       serverDeliveryTimestamp:(uint64_t)serverDeliveryTimestamp
                   transaction:(SDSAnyWriteTransaction *)transaction;

// exposed for testing
- (void)handleIncomingEnvelope:(IdentifiedIncomingEnvelope *)identifiedEnvelope
                 withDataMessage:(SSKProtoDataMessage *)dataMessage
                   plaintextData:(NSData *)plaintextData
                 wasReceivedByUD:(BOOL)wasReceivedByUD
         serverDeliveryTimestamp:(uint64_t)serverDeliveryTimestamp
    shouldDiscardVisibleMessages:(BOOL)shouldDiscardVisibleMessages
                     transaction:(SDSAnyWriteTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
