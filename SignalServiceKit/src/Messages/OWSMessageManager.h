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
@class ServerReceiptEnvelope;
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

- (void)handleDeliveryReceipt:(ServerReceiptEnvelope *)envelope
                      context:(id<DeliveryReceiptContext>)context
                  transaction:(SDSAnyWriteTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
