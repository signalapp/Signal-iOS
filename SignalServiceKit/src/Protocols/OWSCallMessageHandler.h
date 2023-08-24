//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

NS_ASSUME_NONNULL_BEGIN

@class AciObjC;
@class SDSAnyReadTransaction;
@class SDSAnyWriteTransaction;
@class SSKProtoCallMessage;
@class SSKProtoCallMessageAnswer;
@class SSKProtoCallMessageBusy;
@class SSKProtoCallMessageHangup;
@class SSKProtoCallMessageIceUpdate;
@class SSKProtoCallMessageOffer;
@class SSKProtoCallMessageOpaque;
@class SSKProtoDataMessageGroupCallUpdate;
@class SSKProtoEnvelope;
@class SignalServiceAddress;
@class TSGroupThread;

typedef NS_ENUM(NSUInteger, OWSCallMessageAction) {
    // This message should not be processed
    OWSCallMessageActionIgnore,
    // Process the message by deferring to -externallyHandleCallMessage...
    OWSCallMessageActionHandoff,
    // Process the message normally
    OWSCallMessageActionProcess,
};

@protocol OWSCallMessageHandler <NSObject>

/// Informs caller of how the handler would like to handle this message
- (OWSCallMessageAction)actionForEnvelope:(SSKProtoEnvelope *)envelope
                              callMessage:(SSKProtoCallMessage *)message
                  serverDeliveryTimestamp:(uint64_t)serverDeliveryTimestamp;

- (void)receivedOffer:(SSKProtoCallMessageOffer *)offer
                 fromCaller:(SignalServiceAddress *)caller
               sourceDevice:(uint32_t)device
            sentAtTimestamp:(uint64_t)sentAtTimestamp
    serverReceivedTimestamp:(uint64_t)serverReceivedTimestamp
    serverDeliveryTimestamp:(uint64_t)serverDeliveryTimestamp
          supportsMultiRing:(BOOL)supportsMultiRing
                transaction:(SDSAnyWriteTransaction *)transaction
    NS_SWIFT_NAME(receivedOffer(_:from:sourceDevice:sentAtTimestamp:serverReceivedTimestamp:serverDeliveryTimestamp:supportsMultiRing:transaction:));

- (void)receivedAnswer:(SSKProtoCallMessageAnswer *)answer
            fromCaller:(SignalServiceAddress *)caller
          sourceDevice:(uint32_t)device
     supportsMultiRing:(BOOL)supportsMultiRing NS_SWIFT_NAME(receivedAnswer(_:from:sourceDevice:supportsMultiRing:));

- (void)receivedIceUpdate:(NSArray<SSKProtoCallMessageIceUpdate *> *)iceUpdate
               fromCaller:(SignalServiceAddress *)caller
             sourceDevice:(uint32_t)device NS_SWIFT_NAME(receivedIceUpdate(_:from:sourceDevice:));

- (void)receivedHangup:(SSKProtoCallMessageHangup *)hangup
            fromCaller:(SignalServiceAddress *)caller
          sourceDevice:(uint32_t)device NS_SWIFT_NAME(receivedHangup(_:from:sourceDevice:));

- (void)receivedBusy:(SSKProtoCallMessageBusy *)busy
          fromCaller:(SignalServiceAddress *)caller
        sourceDevice:(uint32_t)device NS_SWIFT_NAME(receivedBusy(_:from:sourceDevice:));

- (void)receivedOpaque:(SSKProtoCallMessageOpaque *)opaque
                 fromCaller:(AciObjC *)callerAci
               sourceDevice:(uint32_t)device
    serverReceivedTimestamp:(uint64_t)serverReceivedTimestamp
    serverDeliveryTimestamp:(uint64_t)serverDeliveryTimestamp
                transaction:(SDSAnyReadTransaction *)transaction
    NS_SWIFT_NAME(receivedOpaque(_:from:sourceDevice:serverReceivedTimestamp:serverDeliveryTimestamp:transaction:));

- (void)receivedGroupCallUpdateMessage:(SSKProtoDataMessageGroupCallUpdate *)updateMessage
                             forThread:(TSGroupThread *)groupThread
               serverReceivedTimestamp:(uint64_t)serverReceivedTimestamp
                            completion:(dispatch_block_t)completionHandler
    NS_SWIFT_NAME(receivedGroupCallUpdateMessage(_:for:serverReceivedTimestamp:completion:));

- (void)externallyHandleCallMessageWithEnvelope:(SSKProtoEnvelope *)envelope
                                  plaintextData:(NSData *)plaintextData
                                wasReceivedByUD:(BOOL)wasReceivedByUD
                        serverDeliveryTimestamp:(uint64_t)serverDeliveryTimestamp
                                    transaction:(SDSAnyWriteTransaction *)transaction
    NS_SWIFT_NAME(externallyHandleCallMessage(envelope:plaintextData:wasReceivedByUD:serverDeliveryTimestamp:transaction:));

@end

NS_ASSUME_NONNULL_END
