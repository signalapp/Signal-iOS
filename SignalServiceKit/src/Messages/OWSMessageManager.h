//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <SignalServiceKit/OWSMessageHandler.h>

NS_ASSUME_NONNULL_BEGIN

@protocol DeliveryReceiptContext;

@class MessageManagerRequest;
@class SDSAnyWriteTransaction;
@class SSKProtoDataMessage;
@class SSKProtoEnvelope;
@class SSKProtoSyncMessage;

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
    OWSMessageManagerMessageTypeUnknown
};

@interface OWSMessageManager : OWSMessageHandler

- (void)processEnvelope:(SSKProtoEnvelope *)envelope
                   plaintextData:(NSData *_Nullable)plaintextData
                 wasReceivedByUD:(BOOL)wasReceivedByUD
         serverDeliveryTimestamp:(uint64_t)serverDeliveryTimestamp
    shouldDiscardVisibleMessages:(BOOL)shouldDiscardVisibleMessages
                     transaction:(SDSAnyWriteTransaction *)transaction;

- (void)handleRequest:(MessageManagerRequest *)request
              context:(id<DeliveryReceiptContext>)context
          transaction:(SDSAnyWriteTransaction *)transaction;

- (BOOL)canProcessEnvelope:(SSKProtoEnvelope *)envelope transaction:(SDSAnyWriteTransaction *)transaction;

- (void)finishProcessingEnvelope:(SSKProtoEnvelope *)envelope transaction:(SDSAnyWriteTransaction *)transaction;

- (MessageManagerRequest *_Nullable)requestForEnvelope:(SSKProtoEnvelope *)envelope
                                         plaintextData:(NSData *)plaintextData
                                       wasReceivedByUD:(BOOL)wasReceivedByUD
                               serverDeliveryTimestamp:(uint64_t)serverDeliveryTimestamp
                          shouldDiscardVisibleMessages:(BOOL)shouldDiscardVisibleMessages
                                           transaction:(SDSAnyWriteTransaction *)transaction;

- (void)logUnactionablePayload:(SSKProtoEnvelope *)envelope;

- (void)handleDeliveryReceipt:(SSKProtoEnvelope *)envelope
                      context:(id<DeliveryReceiptContext>)context
                  transaction:(SDSAnyWriteTransaction *)transaction;

#if TESTABLE_BUILD
// exposed for testing
- (void)handleIncomingEnvelope:(SSKProtoEnvelope *)envelope
               withSyncMessage:(SSKProtoSyncMessage *)syncMessage
                 plaintextData:(NSData *)plaintextData
               wasReceivedByUD:(BOOL)wasReceivedByUD
       serverDeliveryTimestamp:(uint64_t)serverDeliveryTimestamp
                   transaction:(SDSAnyWriteTransaction *)transaction;

// exposed for testing
- (void)handleIncomingEnvelope:(SSKProtoEnvelope *)envelope
                 withDataMessage:(SSKProtoDataMessage *)dataMessage
                   plaintextData:(NSData *)plaintextData
                 wasReceivedByUD:(BOOL)wasReceivedByUD
         serverDeliveryTimestamp:(uint64_t)serverDeliveryTimestamp
    shouldDiscardVisibleMessages:(BOOL)shouldDiscardVisibleMessages
                     transaction:(SDSAnyWriteTransaction *)transaction;
#endif

@end

NS_ASSUME_NONNULL_END
