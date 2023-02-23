//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <SignalServiceKit/OWSMessageHandler.h>

NS_ASSUME_NONNULL_BEGIN

@protocol DeliveryReceiptContext;

@class MessageManagerRequest;
@class SDSAnyWriteTransaction;
@class SSKProtoEnvelope;

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

// processEnvelope: can be called from any thread.
//
// Returns YES on success.
- (BOOL)processEnvelope:(SSKProtoEnvelope *)envelope
                   plaintextData:(NSData *_Nullable)plaintextData
                 wasReceivedByUD:(BOOL)wasReceivedByUD
         serverDeliveryTimestamp:(uint64_t)serverDeliveryTimestamp
    shouldDiscardVisibleMessages:(BOOL)shouldDiscardVisibleMessages
                     transaction:(SDSAnyWriteTransaction *)transaction;

- (BOOL)handleRequest:(MessageManagerRequest *)request
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

@end

NS_ASSUME_NONNULL_END
